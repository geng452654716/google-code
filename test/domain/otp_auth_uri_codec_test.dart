import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/domain/totp/totp.dart';

void main() {
  final codec = OtpAuthUriCodec();

  test('uses standard defaults and decodes percent-encoded labels', () {
    final config = codec.parse(
      'otpauth://totp/Example%20Co:alice%2Bdev%40example.com?secret=jbsw-y3dp ehpk3pxp&issuer=Example%20Co',
    );
    expect(config.issuer, 'Example Co');
    expect(config.accountName, 'alice+dev@example.com');
    expect(config.secret, 'JBSWY3DPEHPK3PXP');
    expect(config.algorithm, TotpAlgorithm.sha1);
    expect(config.digits, 6);
    expect(config.period, 30);
  });

  test('accepts matching issuer-only labels from compatible generators', () {
    final config = codec.parse(
      'otpauth://totp/Example%20Service:?secret=JBSWY3DPEHPK3PXP&issuer=%20Example%20Service%20',
    );

    expect(config.issuer, 'Example Service');
    expect(config.accountName, 'Example Service');
    expect(config.secret, 'JBSWY3DPEHPK3PXP');
  });

  test('still rejects empty accounts without two matching issuer fields', () {
    expect(
      () => codec.parse(
        'otpauth://totp/Example%20Service:?secret=JBSWY3DPEHPK3PXP',
      ),
      throwsFormatException,
    );
    expect(
      () => codec.parse(
        'otpauth://totp/Example%20Service:?secret=JBSWY3DPEHPK3PXP&issuer=Other',
      ),
      throwsFormatException,
    );
  });

  test('round-trips non-default configuration', () {
    const original = TotpConfig(
      secret: 'JBSWY3DPEHPK3PXP',
      accountName: '张三+dev@example.com',
      issuer: '团队 A',
      algorithm: TotpAlgorithm.sha512,
      digits: 8,
      period: 60,
    );
    final decoded = codec.parse(codec.encode(original));
    expect(decoded.secret, original.secret);
    expect(decoded.accountName, original.accountName);
    expect(decoded.issuer, original.issuer);
    expect(decoded.algorithm, original.algorithm);
    expect(decoded.digits, original.digits);
    expect(decoded.period, original.period);
  });

  test('rejects HOTP and conflicting issuers', () {
    expect(
      () =>
          codec.parse('otpauth://hotp/test?secret=JBSWY3DPEHPK3PXP&counter=1'),
      throwsFormatException,
    );
    expect(
      () => codec.parse(
        'otpauth://totp/IssuerA:test?secret=JBSWY3DPEHPK3PXP&issuer=IssuerB',
      ),
      throwsFormatException,
    );
  });
}
