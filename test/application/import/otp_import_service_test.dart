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

  test('decodes camera frames with a camera-specific source', () async {
    final png = QrCodeService().encodePng(uri);

    final result = await const OtpImportService().tryDecodeCameraFrame(png);

    expect(result, isA<SingleOtpImportResult>());
    final candidate = (result! as SingleOtpImportResult).candidate;
    expect(candidate.source, OtpImportSource.camera);
    expect(candidate.draft.accountName, 'alice@example.com');
  });

  test('keeps scanning when a camera frame has no QR code', () async {
    final result = await const OtpImportService().tryDecodeCameraFrame(
      Uint8List.fromList([1, 2, 3, 4]),
    );

    expect(result, isNull);
  });

  test('rejects a visible camera QR that is not an OTP payload', () async {
    final png = QrCodeService().encodePng('https://example.com/not-an-otp');

    expect(
      const OtpImportService().tryDecodeCameraFrame(png),
      throwsA(isA<OtpImportException>()),
    );
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

  test('imports a QR with a matching issuer-only label', () async {
    const compatibleUri =
        'otpauth://totp/Example%20Service:?secret=JBSWY3DPEHPK3PXP&issuer=%20Example%20Service%20';
    final png = QrCodeService().encodePng(compatibleUri);

    final candidate = await const OtpImportService().fromImageBytes(png);

    expect(candidate.draft.issuer, 'Example Service');
    expect(candidate.draft.accountName, 'Example Service');
    expect(candidate.draft.secret, 'JBSWY3DPEHPK3PXP');
  });

  test('reports a specific error for conflicting issuer metadata', () {
    const service = OtpImportService();

    expect(
      () => service.fromQrText(
        'otpauth://totp/Example:user?secret=JBSWY3DPEHPK3PXP&issuer=Other',
        source: OtpImportSource.imageFile,
      ),
      throwsA(
        isA<OtpImportException>().having(
          (error) => error.message,
          'message',
          contains('发行方信息互相冲突'),
        ),
      ),
    );
  });

  test('reports a specific error for an invalid TOTP secret', () {
    const service = OtpImportService();

    expect(
      () => service.fromQrText(
        'otpauth://totp/Example:user?secret=INVALID1&issuer=Example',
        source: OtpImportSource.imageFile,
      ),
      throwsA(
        isA<OtpImportException>().having(
          (error) => error.message,
          'message',
          contains('密钥为空或格式无效'),
        ),
      ),
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
