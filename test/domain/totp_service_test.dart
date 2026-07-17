import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/core/encoding/base32_codec.dart';
import 'package:google_code/domain/totp/totp.dart';

void main() {
  final codec = Base32Codec();
  final service = TotpService(base32Codec: codec);
  const times = <int>[
    59,
    1111111109,
    1111111111,
    1234567890,
    2000000000,
    20000000000,
  ];

  Future<void> verifyVectors(
    TotpAlgorithm algorithm,
    String asciiSecret,
    List<String> expected,
  ) async {
    final config = TotpConfig(
      secret: codec.encode(ascii.encode(asciiSecret)),
      accountName: 'rfc@example.com',
      algorithm: algorithm,
      digits: 8,
    );
    for (var index = 0; index < times.length; index++) {
      final code = await service.generate(
        config,
        DateTime.fromMillisecondsSinceEpoch(times[index] * 1000, isUtc: true),
      );
      expect(
        code,
        expected[index],
        reason: '${algorithm.name} at ${times[index]}',
      );
    }
  }

  test('matches RFC 6238 SHA-1 vectors', () async {
    await verifyVectors(TotpAlgorithm.sha1, '12345678901234567890', [
      '94287082',
      '07081804',
      '14050471',
      '89005924',
      '69279037',
      '65353130',
    ]);
  });

  test('matches RFC 6238 SHA-256 vectors', () async {
    await verifyVectors(
      TotpAlgorithm.sha256,
      '12345678901234567890123456789012',
      ['46119246', '68084774', '67062674', '91819424', '90698825', '77737706'],
    );
  });

  test('matches RFC 6238 SHA-512 vectors', () async {
    await verifyVectors(
      TotpAlgorithm.sha512,
      '1234567890123456789012345678901234567890123456789012345678901234',
      ['90693936', '25091201', '99943326', '93441116', '38618901', '47863826'],
    );
  });

  test('reports remaining seconds in the current period', () {
    const config = TotpConfig(secret: 'JBSWY3DPEHPK3PXP', accountName: 'demo');
    expect(
      service.remainingSeconds(
        config,
        DateTime.fromMillisecondsSinceEpoch(31000, isUtc: true),
      ),
      29,
    );
  });
}
