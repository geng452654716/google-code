import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/encoding/base32_codec.dart';
import 'totp_algorithm.dart';
import 'totp_config.dart';

/// Generates RFC 6238 time-based one-time passwords.
class TotpService {
  TotpService({Base32Codec? base32Codec})
    : _base32Codec = base32Codec ?? Base32Codec();

  final Base32Codec _base32Codec;

  /// Generates a code for [time] using the account [config].
  Future<String> generate(TotpConfig config, DateTime time) async {
    final unixSeconds = time.toUtc().millisecondsSinceEpoch ~/ 1000;
    final counter = unixSeconds ~/ config.period;
    return generateForCounter(config, counter);
  }

  /// Generates a code for an explicit moving counter, useful for RFC vectors.
  Future<String> generateForCounter(TotpConfig config, int counter) async {
    if (counter < 0) {
      throw ArgumentError.value(counter, 'counter', 'Must not be negative.');
    }
    final secret = _base32Codec.decode(config.secret);
    final counterBytes = ByteData(8)..setUint64(0, counter, Endian.big);
    final mac = await _hmac(config.algorithm).calculateMac(
      counterBytes.buffer.asUint8List(),
      secretKey: SecretKey(secret),
    );
    final offset = mac.bytes.last & 0x0f;
    final binary =
        ((mac.bytes[offset] & 0x7f) << 24) |
        ((mac.bytes[offset + 1] & 0xff) << 16) |
        ((mac.bytes[offset + 2] & 0xff) << 8) |
        (mac.bytes[offset + 3] & 0xff);
    final modulus = config.digits == 8 ? 100000000 : 1000000;
    return (binary % modulus).toString().padLeft(config.digits, '0');
  }

  /// Returns seconds remaining in the current validity window.
  int remainingSeconds(TotpConfig config, DateTime time) {
    final unixSeconds = time.toUtc().millisecondsSinceEpoch ~/ 1000;
    final elapsed = unixSeconds % config.period;
    return config.period - elapsed;
  }

  Hmac _hmac(TotpAlgorithm algorithm) => switch (algorithm) {
    TotpAlgorithm.sha1 => Hmac.sha1(),
    TotpAlgorithm.sha256 => Hmac.sha256(),
    TotpAlgorithm.sha512 => Hmac.sha512(),
  };
}
