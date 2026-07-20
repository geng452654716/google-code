import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Structural failure reported while parsing an untrusted backup envelope.
enum BackupEnvelopeFailure { invalidFormat, unsupportedVersion }

/// Typed parser error that lets the UI distinguish future backup versions.
class BackupEnvelopeException implements Exception {
  const BackupEnvelopeException(this.failure, this.message);

  final BackupEnvelopeFailure failure;
  final String message;

  @override
  String toString() => 'BackupEnvelopeException: $message';
}

/// Bounded Argon2id parameters stored in an independent backup file.
class BackupKdfParameters {
  const BackupKdfParameters({
    this.memoryKiB = 19456,
    this.iterations = 2,
    this.parallelism = 1,
    this.hashLength = 32,
  });

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int hashLength;

  Map<String, Object> toJson() => {
    'name': 'argon2id',
    'memoryKiB': memoryKiB,
    'iterations': iterations,
    'parallelism': parallelism,
    'hashLength': hashLength,
  };

  factory BackupKdfParameters.fromJson(Map<String, Object?> json) {
    if (json['name'] != 'argon2id') {
      throw const BackupEnvelopeException(
        BackupEnvelopeFailure.invalidFormat,
        'Unsupported backup KDF.',
      );
    }
    final memoryKiB = json['memoryKiB'];
    final iterations = json['iterations'];
    final parallelism = json['parallelism'];
    final hashLength = json['hashLength'];
    if (memoryKiB is! int ||
        memoryKiB < 8192 ||
        memoryKiB > 262144 ||
        iterations is! int ||
        iterations < 1 ||
        iterations > 10 ||
        parallelism is! int ||
        parallelism < 1 ||
        parallelism > 8 ||
        hashLength != 32) {
      throw const BackupEnvelopeException(
        BackupEnvelopeFailure.invalidFormat,
        'Unsafe or invalid backup KDF parameters.',
      );
    }
    return BackupKdfParameters(
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: hashLength as int,
    );
  }
}

/// JSON representation of one authenticated AES-256-GCM ciphertext.
class BackupCipherBox {
  const BackupCipherBox({
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;

  factory BackupCipherBox.fromSecretBox(SecretBox box) => BackupCipherBox(
    nonce: box.nonce,
    cipherText: box.cipherText,
    mac: box.mac.bytes,
  );

  SecretBox toSecretBox() => SecretBox(cipherText, nonce: nonce, mac: Mac(mac));

  Map<String, String> toJson() => {
    'algorithm': 'aes-256-gcm',
    'nonce': base64Encode(nonce),
    'cipherText': base64Encode(cipherText),
    'mac': base64Encode(mac),
  };

  factory BackupCipherBox.fromJson(Map<String, Object?> json) {
    try {
      if (json['algorithm'] != 'aes-256-gcm') {
        throw const FormatException('Unsupported cipher.');
      }
      final nonce = base64Decode(json['nonce'] as String);
      final cipherText = base64Decode(json['cipherText'] as String);
      final mac = base64Decode(json['mac'] as String);
      if (nonce.length != 12 || mac.length != 16 || cipherText.isEmpty) {
        throw const FormatException('Invalid cipher box lengths.');
      }
      return BackupCipherBox(nonce: nonce, cipherText: cipherText, mac: mac);
    } on Object {
      throw const BackupEnvelopeException(
        BackupEnvelopeFailure.invalidFormat,
        'Invalid backup cipher box.',
      );
    }
  }
}

/// Versioned format that is intentionally distinct from the device Vault.
class BackupEnvelope {
  const BackupEnvelope({
    required this.createdAt,
    required this.kdf,
    required this.salt,
    required this.wrappedDek,
    required this.payload,
    this.formatVersion = currentFormatVersion,
  });

  static const formatName = 'google-code-backup';
  static const currentFormatVersion = 1;

  final int formatVersion;
  final DateTime createdAt;
  final BackupKdfParameters kdf;
  final List<int> salt;
  final BackupCipherBox wrappedDek;
  final BackupCipherBox payload;

  Map<String, Object> toJson() => {
    'format': formatName,
    'formatVersion': formatVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'kdf': kdf.toJson(),
    'salt': base64Encode(salt),
    'wrappedDek': wrappedDek.toJson(),
    'payload': payload.toJson(),
  };

  Uint8List encodeBytes() =>
      Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  factory BackupEnvelope.decodeBytes(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, Object?> || decoded['format'] != formatName) {
        throw const BackupEnvelopeException(
          BackupEnvelopeFailure.invalidFormat,
          'Not a TOTP Vault backup.',
        );
      }
      final version = decoded['formatVersion'];
      if (version != currentFormatVersion) {
        throw BackupEnvelopeException(
          BackupEnvelopeFailure.unsupportedVersion,
          'Unsupported backup version: $version.',
        );
      }
      final salt = base64Decode(decoded['salt'] as String);
      if (salt.length < 16 || salt.length > 64) {
        throw const FormatException('Invalid salt length.');
      }
      return BackupEnvelope(
        formatVersion: version as int,
        createdAt: DateTime.parse(decoded['createdAt'] as String).toUtc(),
        kdf: BackupKdfParameters.fromJson(
          (decoded['kdf'] as Map).cast<String, Object?>(),
        ),
        salt: salt,
        wrappedDek: BackupCipherBox.fromJson(
          (decoded['wrappedDek'] as Map).cast<String, Object?>(),
        ),
        payload: BackupCipherBox.fromJson(
          (decoded['payload'] as Map).cast<String, Object?>(),
        ),
      );
    } on BackupEnvelopeException {
      rethrow;
    } on Object {
      throw const BackupEnvelopeException(
        BackupEnvelopeFailure.invalidFormat,
        'Backup envelope is malformed.',
      );
    }
  }
}
