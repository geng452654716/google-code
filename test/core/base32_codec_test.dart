import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/core/encoding/base32_codec.dart';

void main() {
  final codec = Base32Codec();

  test('decodes padded, lowercase, spaced and hyphenated input', () {
    expect(codec.decode('jbsw y3dp-ehpk3pxp===='), <int>[
      72,
      101,
      108,
      108,
      111,
      33,
      222,
      173,
      190,
      239,
    ]);
  });

  test('round-trips bytes without padding', () {
    final bytes = utf8.encode('12345678901234567890');
    expect(codec.decode(codec.encode(bytes)), bytes);
  });

  test('rejects invalid characters and empty input', () {
    expect(() => codec.decode('ABC018'), throwsFormatException);
    expect(() => codec.decode('   '), throwsFormatException);
  });
}
