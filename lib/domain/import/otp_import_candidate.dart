import '../entities/entities.dart';

/// Entry point that supplied an OTP import candidate.
enum OtpImportSource {
  imageFile,
  clipboardImage,
  clipboardText,
  screenshot,
  camera,
  googleMigration,
}

/// A validated TOTP account awaiting user confirmation before persistence.
class OtpImportCandidate {
  const OtpImportCandidate({required this.draft, required this.source});

  final AccountDraft draft;
  final OtpImportSource source;

  /// Whether this candidate exactly matches an account already in the Vault.
  bool isDuplicateOf(Account account) {
    return account.issuer.toLowerCase() == draft.issuer.toLowerCase() &&
        account.accountName.toLowerCase() == draft.accountName.toLowerCase() &&
        account.secret == draft.secret;
  }

  /// Human-readable source name that never contains a local file path.
  String get sourceLabel => switch (source) {
    OtpImportSource.imageFile => '本地二维码图片',
    OtpImportSource.clipboardImage => '剪贴板图片',
    OtpImportSource.clipboardText => '剪贴板链接',
    OtpImportSource.screenshot => '区域截图',
    OtpImportSource.camera => '摄像头',
    OtpImportSource.googleMigration => 'Google Authenticator 迁移二维码',
  };
}
