import 'totp_algorithm.dart';

/// Immutable configuration for one TOTP account.
class TotpConfig {
  const TotpConfig({
    required this.secret,
    required this.accountName,
    this.issuer,
    this.algorithm = TotpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
  }) : assert(digits == 6 || digits == 8),
       assert(period > 0);

  /// Base32-encoded shared secret.
  final String secret;

  /// Human-readable account label, usually an email or username.
  final String accountName;

  /// Optional service/provider name.
  final String? issuer;

  /// HMAC hash algorithm.
  final TotpAlgorithm algorithm;

  /// Number of displayed digits. RFC-compatible values are 6 and 8.
  final int digits;

  /// Validity window in seconds.
  final int period;
}
