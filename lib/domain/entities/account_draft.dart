import '../totp/totp.dart';

/// Validated user-editable values used to create or update an account.
class AccountDraft {
  const AccountDraft({
    required this.issuer,
    required this.accountName,
    required this.secret,
    required this.algorithm,
    required this.digits,
    required this.periodSeconds,
  });

  final String issuer;
  final String accountName;
  final String secret;
  final TotpAlgorithm algorithm;
  final int digits;
  final int periodSeconds;

  factory AccountDraft.fromConfig(TotpConfig config) => AccountDraft(
    issuer: config.issuer ?? '',
    accountName: config.accountName,
    secret: config.secret,
    algorithm: config.algorithm,
    digits: config.digits,
    periodSeconds: config.period,
  );
}
