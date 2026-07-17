import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/application/share/account_share_service.dart';
import 'package:google_code/domain/entities/account.dart';
import 'package:google_code/domain/totp/totp.dart';
import 'package:google_code/platform/qr/qr_code_service.dart';

void main() {
  final account = Account(
    id: 'account-1',
    issuer: 'Example Service',
    accountName: 'alice+desktop@example.com',
    secret: 'JBSWY3DPEHPK3PXP',
    algorithm: TotpAlgorithm.sha256,
    digits: 8,
    periodSeconds: 45,
    sortOrder: 0,
    isPinned: false,
    createdAt: DateTime.utc(2026, 7, 16),
    updatedAt: DateTime.utc(2026, 7, 16),
  );

  test('creates a complete standards-compatible share package in memory', () {
    final material = AccountShareService().create(account);

    expect(material.secret, account.secret);

    final parsed = OtpAuthUriCodec().parse(material.otpAuthUri);
    expect(parsed.secret, account.secret);
    expect(parsed.issuer, account.issuer);
    expect(parsed.accountName, account.accountName);
    expect(parsed.algorithm, account.algorithm);
    expect(parsed.digits, account.digits);
    expect(parsed.period, account.periodSeconds);

    final uri = Uri.parse(material.otpAuthUri);
    expect(uri.queryParameters['algorithm'], 'SHA256');
    expect(uri.queryParameters['digits'], '8');
    expect(uri.queryParameters['period'], '45');
    expect(QrCodeService().decodeImage(material.qrPng), material.otpAuthUri);
  });
}
