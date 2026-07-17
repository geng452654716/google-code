import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../application/backup/backup_exception.dart';
import '../../domain/entities/vault_payload.dart';
import 'backup_envelope.dart';

/// Decrypted backup contents retained only for the active restore preview.
class OpenedBackup {
  const OpenedBackup({required this.createdAt, required this.payload});

  final DateTime createdAt;
  final VaultPayload payload;
}

/// Creates and opens the independent `.gcbak` encrypted backup format.
class BackupCryptoService {
  BackupCryptoService({AesGcm? cipher})
    : _cipher = cipher ?? AesGcm.with256bits();

  static const maxBackupBytes = 32 * 1024 * 1024;
  static final _wrapAad = utf8.encode('google-code-backup:dek:v1');
  static final _payloadAad = utf8.encode('google-code-backup:payload:v1');

  final AesGcm _cipher;

  /// Encrypts [payload] under a fresh DEK and password-derived wrapping key.
  Future<Uint8List> create(
    VaultPayload payload,
    String password, {
    DateTime? createdAt,
    BackupKdfParameters kdf = const BackupKdfParameters(),
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
    final encryptedPayload = await _cipher.encrypt(
      utf8.encode(jsonEncode(payload.toJson())),
      secretKey: dataEncryptionKey,
      aad: _payloadAad,
    );
    return BackupEnvelope(
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
      kdf: kdf,
      salt: salt,
      wrappedDek: BackupCipherBox.fromSecretBox(wrappedDek),
      payload: BackupCipherBox.fromSecretBox(encryptedPayload),
    ).encodeBytes();
  }

  /// Authenticates and decrypts a bounded backup entirely in memory.
  Future<OpenedBackup> open(Uint8List bytes, String password) async {
    _validatePassword(password);
    if (bytes.length > maxBackupBytes) {
      throw const BackupException(
        BackupFailureKind.fileTooLarge,
        '备份文件超过 32 MiB 限制。',
      );
    }

    late final BackupEnvelope envelope;
    try {
      envelope = BackupEnvelope.decodeBytes(bytes);
    } on BackupEnvelopeException catch (error) {
      if (error.failure == BackupEnvelopeFailure.unsupportedVersion) {
        throw const BackupException(
          BackupFailureKind.unsupportedVersion,
          '该备份由更高版本的 Google Code 创建，当前版本无法恢复。',
        );
      }
      throw const BackupException(
        BackupFailureKind.invalidFormat,
        '所选文件不是有效的 Google Code 加密备份。',
      );
    }

    try {
      final keyEncryptionKey = await _deriveKey(
        password,
        envelope.salt,
        envelope.kdf,
      );
      final dekBytes = await _cipher.decrypt(
        envelope.wrappedDek.toSecretBox(),
        secretKey: keyEncryptionKey,
        aad: _wrapAad,
      );
      final clearBytes = await _cipher.decrypt(
        envelope.payload.toSecretBox(),
        secretKey: SecretKey(dekBytes),
        aad: _payloadAad,
      );
      final decoded = jsonDecode(utf8.decode(clearBytes));
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Backup payload must be an object.');
      }
      return OpenedBackup(
        createdAt: envelope.createdAt,
        payload: VaultPayload.fromJson(decoded),
      );
    } on SecretBoxAuthenticationError {
      throw const BackupException(
        BackupFailureKind.invalidPasswordOrCorrupted,
        '备份密码错误，或备份文件已损坏。',
      );
    } on BackupException {
      rethrow;
    } on Object {
      throw const BackupException(
        BackupFailureKind.invalidPayload,
        '备份内容无法读取或不受当前版本支持。',
      );
    }
  }

  Future<SecretKey> _deriveKey(
    String password,
    List<int> salt,
    BackupKdfParameters parameters,
  ) {
    return Argon2id(
      parallelism: parameters.parallelism,
      memory: parameters.memoryKiB,
      iterations: parameters.iterations,
      hashLength: parameters.hashLength,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  void _validatePassword(String password) {
    if (password.isEmpty) {
      throw const BackupException(
        BackupFailureKind.invalidPasswordOrCorrupted,
        '请输入备份密码。',
      );
    }
  }
}
