import '../../core/encoding/base32_codec.dart';
import 'totp_algorithm.dart';
import 'totp_config.dart';

/// Parses and serializes Key URI Format (`otpauth://`) TOTP entries.
class OtpAuthUriCodec {
  OtpAuthUriCodec({Base32Codec? base32Codec})
    : _base32Codec = base32Codec ?? Base32Codec();

  final Base32Codec _base32Codec;

  /// Parses a TOTP URI and rejects HOTP or ambiguous issuer metadata.
  TotpConfig parse(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'otpauth') {
      throw const FormatException('Expected an otpauth:// URI.');
    }
    if (uri.host.toLowerCase() != 'totp') {
      throw FormatException('Only TOTP is supported, received: ${uri.host}.');
    }
    if (uri.pathSegments.isEmpty || uri.pathSegments.last.trim().isEmpty) {
      throw const FormatException('TOTP account label is missing.');
    }

    final label = uri.pathSegments.join('/');
    final separator = label.indexOf(':');
    final labelIssuer = separator < 0
        ? null
        : label.substring(0, separator).trim();
    final accountName = (separator < 0 ? label : label.substring(separator + 1))
        .trim();
    if (accountName.isEmpty) {
      throw const FormatException('TOTP account name is missing.');
    }

    final queryIssuer = uri.queryParameters['issuer']?.trim();
    if (labelIssuer != null &&
        labelIssuer.isNotEmpty &&
        queryIssuer != null &&
        queryIssuer.isNotEmpty &&
        labelIssuer != queryIssuer) {
      throw const FormatException('Issuer in label and query must match.');
    }
    final issuer = (queryIssuer?.isNotEmpty ?? false)
        ? queryIssuer
        : (labelIssuer?.isNotEmpty ?? false)
        ? labelIssuer
        : null;

    final secret = _base32Codec.normalize(uri.queryParameters['secret'] ?? '');
    final digits = _parseInt(uri.queryParameters['digits'], fallback: 6);
    if (digits != 6 && digits != 8) {
      throw FormatException('Unsupported TOTP digit count: $digits.');
    }
    final period = _parseInt(uri.queryParameters['period'], fallback: 30);
    if (period <= 0) {
      throw const FormatException('TOTP period must be positive.');
    }

    return TotpConfig(
      secret: secret,
      accountName: accountName,
      issuer: issuer,
      algorithm: TotpAlgorithm.parse(uri.queryParameters['algorithm']),
      digits: digits,
      period: period,
    );
  }

  /// Serializes [config] to a standards-compatible TOTP URI.
  String encode(TotpConfig config) {
    final secret = _base32Codec.normalize(config.secret);
    final encodedAccount = Uri.encodeComponent(config.accountName);
    final encodedLabel = config.issuer == null || config.issuer!.isEmpty
        ? encodedAccount
        : '${Uri.encodeComponent(config.issuer!)}:$encodedAccount';
    final parameters = <String, String>{
      'secret': secret,
      if (config.issuer != null && config.issuer!.isNotEmpty)
        'issuer': config.issuer!,
      'algorithm': config.algorithm.otpAuthName,
      'digits': config.digits.toString(),
      'period': config.period.toString(),
    };
    final query = Uri(queryParameters: parameters).query;
    return 'otpauth://totp/$encodedLabel?$query';
  }

  int _parseInt(String? value, {required int fallback}) {
    if (value == null || value.isEmpty) return fallback;
    return int.tryParse(value) ??
        (throw FormatException('Expected an integer, received: $value.'));
  }
}
