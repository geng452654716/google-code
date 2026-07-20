import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../core/errors/vault_exception.dart';
import 'vault_envelope.dart';

/// Decrypted Vault material retained only while the application is unlocked.
class OpenedVault {
  const OpenedVault({
    required this.envelope,
    required this.dataEncryptionKey,
    required this.payload,
  });

  final VaultEnvelope envelope;
  final SecretKey dataEncryptionKey;
  final Map<String, Object?> payload;
}

/// Encrypts and decrypts the versioned local vault envelope.
class VaultCryptoService {
  VaultCryptoService({AesGcm? cipher})
    : _cipher = cipher ?? AesGcm.with256bits();

  static final _wrapAad = utf8.encode('google-code:v1:wrapped-dek');
  static final _payloadAad = utf8.encode('google-code:v1:payload');
  static final _legacyPayloadAads = <List<int>>[
    const <int>[],
    utf8.encode('google-code:v1:wrapped-dek'),
    utf8.encode('google-code-backup:payload:v1'),
    utf8.encode('google-code-vault:v1:payload'),
  ];

  final AesGcm _cipher;

  /// Creates a new envelope using a random data-encryption key (DEK).
  Future<VaultEnvelope> create(
    Map<String, Object?> clearPayload,
    String password, {
    VaultKdfParameters kdf = const VaultKdfParameters(),
  }) async {
    return (await createOpened(clearPayload, password, kdf: kdf)).envelope;
  }

  /// Creates a new envelope and returns its unlocked in-memory key material.
  Future<OpenedVault> createOpened(
    Map<String, Object?> clearPayload,
    String password, {
    VaultKdfParameters kdf = const VaultKdfParameters(),
  }) async {
    _validatePassword(password);
    final salt = _randomBytes(16);
    final keyEncryptionKey = await _deriveKey(password, salt, kdf);
    final dataEncryptionKey = await _cipher.newSecretKey();
    final dataEncryptionKeyBytes = await dataEncryptionKey.extractBytes();

    final wrappedDek = await _cipher.encrypt(
      dataEncryptionKeyBytes,
      secretKey: keyEncryptionKey,
      aad: _wrapAad,
    );
    final encryptedPayload = await _encryptPayload(
      clearPayload,
      dataEncryptionKey,
    );
    final envelope = VaultEnvelope(
      kdf: kdf,
      salt: salt,
      wrappedDek: VaultCipherBox.fromSecretBox(wrappedDek),
      payload: VaultCipherBox.fromSecretBox(encryptedPayload),
    );
    return OpenedVault(
      envelope: envelope,
      dataEncryptionKey: dataEncryptionKey,
      payload: clearPayload,
    );
  }

  /// Unlocks and authenticates an envelope while retaining its DEK in memory.
  Future<OpenedVault> open(VaultEnvelope envelope, String password) async {
    _validatePassword(password);
    late final List<int> dekBytes;
    try {
      final keyEncryptionKey = await _deriveKey(
        password,
        envelope.salt,
        envelope.kdf,
      );
      dekBytes = await _cipher.decrypt(
        envelope.wrappedDek.toSecretBox(),
        secretKey: keyEncryptionKey,
        aad: _wrapAad,
      );
    } on SecretBoxAuthenticationError catch (_) {
      throw const VaultUnlockException(
        'Master password or wrapped Vault key is invalid.',
        VaultUnlockFailureKind.invalidCredential,
      );
    }

    final dataEncryptionKey = SecretKey(dekBytes);
    return _openPayloadWithCompatibleAuthentication(
      envelope,
      dataEncryptionKey,
    );
  }

  /// Opens an envelope with a previously device-protected DEK copy.
  ///
  /// The supplied bytes are never retained directly; the returned [OpenedVault]
  /// owns the in-memory [SecretKey] used by the active unlocked session.
  Future<OpenedVault> openWithDataEncryptionKey(
    VaultEnvelope envelope,
    List<int> dataEncryptionKeyBytes,
  ) async {
    if (dataEncryptionKeyBytes.length != 32) {
      throw const VaultUnlockException('Quick unlock key is invalid.');
    }
    final dataEncryptionKey = SecretKey(dataEncryptionKeyBytes);
    return _openPayloadWithCompatibleAuthentication(
      envelope,
      dataEncryptionKey,
    );
  }

  /// Re-encrypts an updated payload with the active DEK and a fresh nonce.
  Future<OpenedVault> updatePayload(
    OpenedVault openedVault,
    Map<String, Object?> clearPayload,
  ) async {
    final encryptedPayload = await _encryptPayload(
      clearPayload,
      openedVault.dataEncryptionKey,
    );
    final envelope = VaultEnvelope(
      version: openedVault.envelope.version,
      kdf: openedVault.envelope.kdf,
      salt: openedVault.envelope.salt,
      wrappedDek: openedVault.envelope.wrappedDek,
      payload: VaultCipherBox.fromSecretBox(encryptedPayload),
    );
    return OpenedVault(
      envelope: envelope,
      dataEncryptionKey: openedVault.dataEncryptionKey,
      payload: clearPayload,
    );
  }

  /// Unlocks and returns only the clear payload for one-shot callers.
  Future<Map<String, Object?>> decrypt(
    VaultEnvelope envelope,
    String password,
  ) async {
    return (await open(envelope, password)).payload;
  }

  Future<OpenedVault> _openPayloadWithCompatibleAuthentication(
    VaultEnvelope envelope,
    SecretKey dataEncryptionKey,
  ) async {
    final aadCandidates = <List<int>>[_payloadAad, ..._legacyPayloadAads];
    for (final aad in aadCandidates) {
      late final List<int> clearBytes;
      try {
        clearBytes = await _cipher.decrypt(
          envelope.payload.toSecretBox(),
          secretKey: dataEncryptionKey,
          aad: aad,
        );
      } on SecretBoxAuthenticationError {
        continue;
      }

      return _decodeAuthenticatedPayload(
        envelope,
        dataEncryptionKey,
        clearBytes,
      );
    }

    throw const VaultUnlockException(
      'Vault payload authentication failed for every supported format.',
      VaultUnlockFailureKind.payloadAuthenticationFailed,
    );
  }

  OpenedVault _decodeAuthenticatedPayload(
    VaultEnvelope envelope,
    SecretKey dataEncryptionKey,
    List<int> clearBytes,
  ) {
    try {
      final decoded = jsonDecode(utf8.decode(clearBytes));
      if (decoded is! Map) {
        throw const FormatException('Vault payload must be an object.');
      }
      return OpenedVault(
        envelope: envelope,
        dataEncryptionKey: dataEncryptionKey,
        payload: decoded.cast<String, Object?>(),
      );
    } on FormatException {
      throw const VaultUnlockException(
        'Authenticated Vault payload is not valid JSON.',
        VaultUnlockFailureKind.payloadJsonInvalid,
      );
    } on TypeError {
      throw const VaultUnlockException(
        'Authenticated Vault payload JSON has invalid key types.',
        VaultUnlockFailureKind.payloadJsonInvalid,
      );
    }
  }

  Future<SecretBox> _encryptPayload(
    Map<String, Object?> clearPayload,
    SecretKey dataEncryptionKey,
  ) {
    return _cipher.encrypt(
      utf8.encode(jsonEncode(clearPayload)),
      secretKey: dataEncryptionKey,
      aad: _payloadAad,
    );
  }

  Future<SecretKey> _deriveKey(
    String password,
    List<int> salt,
    VaultKdfParameters parameters,
  ) {
    final algorithm = Argon2id(
      parallelism: parameters.parallelism,
      memory: parameters.memory,
      iterations: parameters.iterations,
      hashLength: parameters.hashLength,
    );
    return algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  void _validatePassword(String password) {
    if (password.isEmpty) {
      throw const VaultUnlockException(
        'Master password must not be empty.',
        VaultUnlockFailureKind.invalidCredential,
      );
    }
  }
}
