import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/application/import/otp_import_service.dart';
import 'package:google_code/domain/import/otp_import_candidate.dart';
import 'package:google_code/domain/totp/totp.dart';
import 'package:google_code/platform/qr/qr_code_service.dart';

void main() {
  const uri =
      'otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&algorithm=SHA256&digits=8&period=45';

  test('decodes an image into a validated TOTP import candidate', () async {
    final png = QrCodeService().encodePng(uri);

    final candidate = await const OtpImportService().fromImageBytes(png);

    expect(candidate.source, OtpImportSource.imageFile);
    expect(candidate.draft.issuer, 'Example');
    expect(candidate.draft.accountName, 'alice@example.com');
    expect(candidate.draft.secret, 'JBSWY3DPEHPK3PXP');
    expect(candidate.draft.algorithm, TotpAlgorithm.sha256);
    expect(candidate.draft.digits, 8);
    expect(candidate.draft.periodSeconds, 45);
  });

  test('rejects images above the configured byte limit', () async {
    const service = OtpImportService(maxImageBytes: 4);

    expect(
      service.fromImageBytes(Uint8List(5)),
      throwsA(
        isA<OtpImportException>().having(
          (error) => error.message,
          'message',
          contains('超过'),
        ),
      ),
    );
  });

  test('rejects QR payloads that are not standard TOTP URIs', () {
    const service = OtpImportService();

    expect(
      () => service.fromQrText(
        'https://example.com',
        source: OtpImportSource.imageFile,
      ),
      throwsA(isA<OtpImportException>()),
    );
  });

  test('parses clipboard text with a clipboard-specific source', () {
    const service = OtpImportService();

    final candidate = service.fromQrText(
      uri,
      source: OtpImportSource.clipboardText,
    );

    expect(candidate.source, OtpImportSource.clipboardText);
    expect(candidate.draft.accountName, 'alice@example.com');
  });
}
