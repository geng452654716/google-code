import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Argon2id parameters stored with each vault for deterministic unlocking.
class VaultKdfParameters {
  const VaultKdfParameters({
    this.memory = 19456,
    this.iterations = 2,
    this.parallelism = 1,
    this.hashLength = 32,
  });

  final int memory;
  final int iterations;
  final int parallelism;
  final int hashLength;

  Map<String, Object> toJson() => {
    'name': 'argon2id',
    'memory': memory,
    'iterations': iterations,
    'parallelism': parallelism,
    'hashLength': hashLength,
  };

  factory VaultKdfParameters.fromJson(Map<String, Object?> json) {
    if (json['name'] != 'argon2id') {
      throw const FormatException('Unsupported vault KDF.');
    }
    return VaultKdfParameters(
      memory: json['memory'] as int,
      iterations: json['iterations'] as int,
      parallelism: json['parallelism'] as int,
      hashLength: json['hashLength'] as int,
    );
  }
}

/// JSON-friendly representation of one AES-GCM secret box.
class VaultCipherBox {
  const VaultCipherBox({
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;

  factory VaultCipherBox.fromSecretBox(SecretBox box) => VaultCipherBox(
    nonce: box.nonce,
    cipherText: box.cipherText,
    mac: box.mac.bytes,
  );

  SecretBox toSecretBox() => SecretBox(cipherText, nonce: nonce, mac: Mac(mac));

  Map<String, String> toJson() => {
    'nonce': base64Encode(nonce),
    'cipherText': base64Encode(cipherText),
    'mac': base64Encode(mac),
  };

  factory VaultCipherBox.fromJson(Map<String, Object?> json) => VaultCipherBox(
    nonce: base64Decode(json['nonce'] as String),
    cipherText: base64Decode(json['cipherText'] as String),
    mac: base64Decode(json['mac'] as String),
  );
}

/// Versioned encrypted vault file envelope.
class VaultEnvelope {
  const VaultEnvelope({
    required this.kdf,
    required this.salt,
    required this.wrappedDek,
    required this.payload,
    this.version = 1,
  });

  final int version;
  final VaultKdfParameters kdf;
  final List<int> salt;
  final VaultCipherBox wrappedDek;
  final VaultCipherBox payload;

  Map<String, Object> toJson() => {
    'version': version,
    'kdf': kdf.toJson(),
    'salt': base64Encode(salt),
    'wrappedDek': wrappedDek.toJson(),
    'payload': payload.toJson(),
  };

  String encode() => jsonEncode(toJson());

  factory VaultEnvelope.decode(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, Object?>) {
      throw const FormatException('Vault root must be an object.');
    }
    final version = value['version'];
    if (version != 1) {
      throw FormatException('Unsupported vault version: $version.');
    }
    return VaultEnvelope(
      version: version as int,
      kdf: VaultKdfParameters.fromJson(
        (value['kdf'] as Map).cast<String, Object?>(),
      ),
      salt: base64Decode(value['salt'] as String),
      wrappedDek: VaultCipherBox.fromJson(
        (value['wrappedDek'] as Map).cast<String, Object?>(),
      ),
      payload: VaultCipherBox.fromJson(
        (value['payload'] as Map).cast<String, Object?>(),
      ),
    );
  }
}
