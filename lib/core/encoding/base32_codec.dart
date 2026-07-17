import 'dart:typed_data';

/// RFC 4648 Base32 codec used by OTP secrets.
class Base32Codec {
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Removes user-friendly separators and validates the encoded secret.
  String normalize(String input) {
    final normalized = input
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceFirst(RegExp(r'=+$'), '');
    if (normalized.isEmpty) {
      throw const FormatException('Base32 secret must not be empty.');
    }
    if (!RegExp(r'^[A-Z2-7]+$').hasMatch(normalized)) {
      throw const FormatException('Base32 secret contains invalid characters.');
    }
    return normalized;
  }

  /// Decodes a padded or unpadded RFC 4648 Base32 string.
  Uint8List decode(String input) {
    final normalized = normalize(input);
    final output = BytesBuilder(copy: false);
    var buffer = 0;
    var bitsInBuffer = 0;

    for (final codeUnit in normalized.codeUnits) {
      final value = _alphabet.indexOf(String.fromCharCode(codeUnit));
      buffer = (buffer << 5) | value;
      bitsInBuffer += 5;
      if (bitsInBuffer >= 8) {
        bitsInBuffer -= 8;
        output.addByte((buffer >> bitsInBuffer) & 0xff);
        buffer &= (1 << bitsInBuffer) - 1;
      }
    }
    return output.toBytes();
  }

  /// Encodes bytes without `=` padding, matching common authenticator apps.
  String encode(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('Secret bytes must not be empty.');
    }
    final output = StringBuffer();
    var buffer = 0;
    var bitsInBuffer = 0;

    for (final byte in bytes) {
      buffer = (buffer << 8) | (byte & 0xff);
      bitsInBuffer += 8;
      while (bitsInBuffer >= 5) {
        bitsInBuffer -= 5;
        output.write(_alphabet[(buffer >> bitsInBuffer) & 0x1f]);
        buffer &= (1 << bitsInBuffer) - 1;
      }
    }
    if (bitsInBuffer > 0) {
      output.write(_alphabet[(buffer << (5 - bitsInBuffer)) & 0x1f]);
    }
    return output.toString();
  }
}
