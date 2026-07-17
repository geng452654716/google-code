import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:google_code/platform/qr/qr_code_service.dart';

void main() {
  test('generates a PNG and decodes the otpauth URI back', () {
    const uri =
        'otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example';
    final service = QrCodeService();
    final png = service.encodePng(uri);
    expect(png, isNotEmpty);
    expect(service.decodeImage(png), uri);
  });

  test('decodes BMP bytes produced by native Windows capture', () {
    const uri =
        'otpauth://totp/Windows:user?secret=JBSWY3DPEHPK3PXP&issuer=Windows';
    final service = QrCodeService();
    final source = img.decodePng(service.encodePng(uri))!;
    final bmp = img.encodeBmp(source);

    expect(service.decodeImage(bmp), uri);
  });

  test('decodes rotated and inverted QR images', () {
    const uri =
        'otpauth://totp/Rotated:user?secret=JBSWY3DPEHPK3PXP&issuer=Rotated';
    final service = QrCodeService();
    final source = img.decodePng(service.encodePng(uri))!;
    final rotated = img.encodePng(img.copyRotate(source, angle: 90));
    final inverted = img.encodePng(img.invert(img.Image.from(source)));

    expect(service.decodeImage(rotated), uri);
    expect(service.decodeImage(inverted), uri);
  });
}
