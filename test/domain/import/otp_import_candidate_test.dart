import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/domain/entities/entities.dart';
import 'package:google_code/domain/import/otp_import_candidate.dart';
import 'package:google_code/domain/totp/totp.dart';

void main() {
  test('detects exact duplicates without exposing source paths', () {
    const draft = AccountDraft(
      issuer: 'Example',
      accountName: 'Alice@example.com',
      secret: 'JBSWY3DPEHPK3PXP',
      algorithm: TotpAlgorithm.sha1,
      digits: 6,
      periodSeconds: 30,
    );
    const candidate = OtpImportCandidate(
      draft: draft,
      source: OtpImportSource.imageFile,
    );
    final now = DateTime.utc(2026, 7, 16);
    final account = Account(
      id: 'account-1',
      issuer: 'example',
      accountName: 'alice@EXAMPLE.COM',
      secret: 'JBSWY3DPEHPK3PXP',
      algorithm: TotpAlgorithm.sha256,
      digits: 8,
      periodSeconds: 60,
      sortOrder: 0,
      isPinned: false,
      createdAt: now,
      updatedAt: now,
    );

    expect(candidate.isDuplicateOf(account), isTrue);
    expect(candidate.sourceLabel, '本地二维码图片');
  });

  test('uses safe labels for both clipboard input types', () {
    const draft = AccountDraft(
      issuer: 'Example',
      accountName: 'alice@example.com',
      secret: 'JBSWY3DPEHPK3PXP',
      algorithm: TotpAlgorithm.sha1,
      digits: 6,
      periodSeconds: 30,
    );

    expect(
      const OtpImportCandidate(
        draft: draft,
        source: OtpImportSource.clipboardImage,
      ).sourceLabel,
      '剪贴板图片',
    );
    expect(
      const OtpImportCandidate(
        draft: draft,
        source: OtpImportSource.clipboardText,
      ).sourceLabel,
      '剪贴板链接',
    );
  });
}
