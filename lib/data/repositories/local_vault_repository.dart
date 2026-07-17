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
    return payload;
  }

  @override
  Future<VaultPayload> unlock(String password) async {
    final store = await _resolveStore();
    if (!await store.exists()) {
      throw const VaultUnlockException('Vault does not exist.');
    }
    final openedVault = await _cryptoService.open(await store.read(), password);
    final payload = VaultPayload.fromJson(openedVault.payload);
    _openedVault = openedVault;
    return payload;
  }

  @override
  Future<VaultPayload> unlockWithQuickUnlockKey(Uint8List keyBytes) async {
    final store = await _resolveStore();
    if (!await store.exists()) {
      throw const VaultUnlockException('Vault does not exist.');
    }
    final openedVault = await _cryptoService.openWithDataEncryptionKey(
      await store.read(),
      keyBytes,
    );
    final payload = VaultPayload.fromJson(openedVault.payload);
    _openedVault = openedVault;
    return payload;
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
      await _cryptoService.open(await store.read(), password);
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
    await (await _resolveStore()).write(updated.envelope);
    _openedVault = updated;
  }

  @override
  void lock() {
    _openedVault = null;
  }
}
