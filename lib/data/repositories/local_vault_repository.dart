import 'dart:io';
import 'dart:typed_data';

import '../../core/errors/vault_exception.dart';
import '../../domain/entities/vault_payload.dart';
import '../../domain/repositories/vault_repository.dart';
import '../vault/vault.dart';

/// File-backed Vault repository that retains the DEK only while unlocked.
class LocalVaultRepository implements VaultRepository {
  LocalVaultRepository(
    this._fileResolver, {
    VaultCryptoService? cryptoService,
    this.kdfParameters = const VaultKdfParameters(),
  }) : _cryptoService = cryptoService ?? VaultCryptoService();

  final Future<File> Function() _fileResolver;
  final VaultCryptoService _cryptoService;
  final VaultKdfParameters kdfParameters;

  VaultFileStore? _store;
  OpenedVault? _openedVault;
  bool _openedFromBackup = false;

  Future<VaultFileStore> _resolveStore() async {
    return _store ??= VaultFileStore(await _fileResolver());
  }

  @override
  Future<VaultAvailability> inspect() async {
    final store = await _resolveStore();
    return await store.exists()
        ? VaultAvailability.present
        : VaultAvailability.missing;
  }

  @override
  Future<VaultPayload> create(String password) async {
    final store = await _resolveStore();
    if (await store.exists()) {
      throw const VaultUnlockException('Vault already exists.');
    }
    final payload = VaultPayload.empty(DateTime.now());
    final openedVault = await _cryptoService.createOpened(
      payload.toJson(),
      password,
      kdf: kdfParameters,
    );
    await store.write(openedVault.envelope);
    _openedVault = openedVault;
    _openedFromBackup = false;
    return payload;
  }

  @override
  Future<VaultPayload> unlock(String password) async {
    final store = await _resolveStore();
    if (!await store.exists()) {
      throw const VaultUnlockException('Vault does not exist.');
    }
    final openedResult = await _openAvailableCopies(
      store,
      (envelope) => _cryptoService.open(envelope, password),
    );
    final result = await _repairRecoveredPayload(store, openedResult);
    _openedVault = result.openedVault;
    _openedFromBackup = result.fromBackup;
    return result.payload;
  }

  @override
  Future<VaultPayload> unlockWithQuickUnlockKey(Uint8List keyBytes) async {
    final store = await _resolveStore();
    if (!await store.exists()) {
      throw const VaultUnlockException('Vault does not exist.');
    }
    final openedResult = await _openAvailableCopies(
      store,
      (envelope) =>
          _cryptoService.openWithDataEncryptionKey(envelope, keyBytes),
    );
    final result = await _repairRecoveredPayload(store, openedResult);
    _openedVault = result.openedVault;
    _openedFromBackup = result.fromBackup;
    return result.payload;
  }

  @override
  Future<Uint8List> exportQuickUnlockKey() async {
    final current = _openedVault;
    if (current == null) {
      throw const VaultUnlockException('Vault is locked.');
    }
    final bytes = await current.dataEncryptionKey.extractBytes();
    if (bytes.length != 32) {
      throw const VaultUnlockException('Vault DEK length is invalid.');
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<bool> verifyPassword(String password) async {
    final store = await _resolveStore();
    if (!await store.exists()) return false;
    try {
      await _openAvailableCopies(
        store,
        (envelope) => _cryptoService.open(envelope, password),
      );
      return true;
    } on VaultUnlockException {
      return false;
    }
  }

  @override
  Future<void> save(VaultPayload payload) async {
    final current = _openedVault;
    if (current == null) {
      throw const VaultUnlockException('Vault is locked.');
    }
    final updated = await _cryptoService.updatePayload(
      current,
      payload.toJson(),
    );
    final store = await _resolveStore();
    if (_openedFromBackup) {
      await store.writeRecovered(updated.envelope);
    } else {
      await store.write(updated.envelope);
    }
    _openedVault = updated;
    _openedFromBackup = false;
  }

  @override
  void lock() {
    _openedVault = null;
    _openedFromBackup = false;
  }

  /// Re-encrypts payloads written by the historical zeroed quick-unlock DEK.
  ///
  /// The master password has already unwrapped the canonical DEK before this
  /// path is reachable. Preserve the existing backup while the
  /// primary copy is atomically repaired with that canonical DEK.
  Future<_OpenedVaultResult> _repairRecoveredPayload(
    VaultFileStore store,
    _OpenedVaultResult result,
  ) async {
    if (!result.openedVault.payloadRequiresReencryption) return result;

    final repaired = await _cryptoService.updatePayload(
      result.openedVault,
      result.payload.toJson(),
    );
    await store.writeRecovered(repaired.envelope);
    return _OpenedVaultResult(
      openedVault: repaired,
      payload: result.payload,
      fromBackup: false,
    );
  }

  Future<_OpenedVaultResult> _openAvailableCopies(
    VaultFileStore store,
    Future<OpenedVault> Function(VaultEnvelope envelope) opener,
  ) async {
    final failures = <VaultUnlockException>[];

    if (await store.primaryExists()) {
      final result = await _tryOpenCopy(
        read: store.readPrimary,
        opener: opener,
        fromBackup: false,
        failures: failures,
      );
      if (result != null) return result;
    }

    if (await store.backupExists()) {
      final result = await _tryOpenCopy(
        read: store.readBackup,
        opener: opener,
        fromBackup: true,
        failures: failures,
      );
      if (result != null) return result;
    }

    for (final kind in const [
      VaultUnlockFailureKind.payloadSchemaIncompatible,
      VaultUnlockFailureKind.payloadJsonInvalid,
      VaultUnlockFailureKind.payloadAuthenticationFailed,
      VaultUnlockFailureKind.corruptedPayload,
    ]) {
      if (failures.any((failure) => failure.kind == kind)) {
        throw VaultUnlockException(
          'The Vault key was accepted, but every available payload failed.',
          kind,
        );
      }
    }
    if (failures.any(
      (failure) => failure.kind == VaultUnlockFailureKind.invalidCredential,
    )) {
      throw const VaultUnlockException(
        'The credential could not unlock any available Vault copy.',
        VaultUnlockFailureKind.invalidCredential,
      );
    }
    throw const VaultUnlockException(
      'No readable Vault copy is available.',
      VaultUnlockFailureKind.unreadableVault,
    );
  }

  Future<_OpenedVaultResult?> _tryOpenCopy({
    required Future<VaultEnvelope> Function() read,
    required Future<OpenedVault> Function(VaultEnvelope envelope) opener,
    required bool fromBackup,
    required List<VaultUnlockException> failures,
  }) async {
    late final VaultEnvelope envelope;
    try {
      envelope = await read();
    } on Object {
      failures.add(
        const VaultUnlockException(
          'Vault envelope is unreadable.',
          VaultUnlockFailureKind.unreadableVault,
        ),
      );
      return null;
    }

    late final OpenedVault openedVault;
    try {
      openedVault = await opener(envelope);
    } on VaultUnlockException catch (error) {
      failures.add(error);
      return null;
    } on Object {
      failures.add(
        const VaultUnlockException(
          'Vault could not be opened.',
          VaultUnlockFailureKind.unreadableVault,
        ),
      );
      return null;
    }

    try {
      final payload = VaultPayload.fromJson(openedVault.payload);
      return _OpenedVaultResult(
        openedVault: openedVault,
        payload: payload,
        fromBackup: fromBackup,
      );
    } on Object {
      failures.add(
        const VaultUnlockException(
          'Vault payload schema is incompatible.',
          VaultUnlockFailureKind.payloadSchemaIncompatible,
        ),
      );
      return null;
    }
  }
}

class _OpenedVaultResult {
  const _OpenedVaultResult({
    required this.openedVault,
    required this.payload,
    required this.fromBackup,
  });

  final OpenedVault openedVault;
  final VaultPayload payload;
  final bool fromBackup;
}
