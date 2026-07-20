import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';
import 'package:zxing2/qrcode.dart';

/// Platform-independent QR PNG generator and decoder.
class QrCodeService {
  /// Renders [content] as a high-contrast PNG with a four-module quiet zone.
  Uint8List encodePng(
    String content, {
    int moduleSize = 8,
    int quietZoneModules = 4,
  }) {
    if (content.isEmpty) {
      throw const FormatException('QR content must not be empty.');
    }
    final code = QrCode(
      payload: QrPayload.fromString(content),
      errorCorrectLevel: QrErrorCorrectLevel.medium,
    );
    final qrImage = QrImage(code);
    final totalModules = qrImage.moduleCount + quietZoneModules * 2;
    final output = img.Image(
      width: totalModules * moduleSize,
      height: totalModules * moduleSize,
    );
    img.fill(output, color: img.ColorRgb8(255, 255, 255));

    for (var row = 0; row < qrImage.moduleCount; row++) {
      for (var column = 0; column < qrImage.moduleCount; column++) {
        if (!qrImage.isDark(row, column)) continue;
        final left = (column + quietZoneModules) * moduleSize;
        final top = (row + quietZoneModules) * moduleSize;
        img.fillRect(
          output,
          x1: left,
          y1: top,
          x2: left + moduleSize - 1,
          y2: top + moduleSize - 1,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
    }
    return Uint8List.fromList(img.encodePng(output));
  }

  /// Decodes the first QR code using bounded, lazy preprocessing attempts.
  String decodeImage(Uint8List bytes, {int maxPixels = 40 * 1000 * 1000}) {
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (decoder == null || info == null) {
      throw const FormatException('Unsupported or damaged image.');
    }
    if (info.width <= 0 ||
        info.height <= 0 ||
        info.width > maxPixels ~/ info.height) {
      throw const FormatException('Image pixel count exceeds the limit.');
    }

    final decoded = decoder.decode(bytes, frame: 0);
    if (decoded == null) {
      throw const FormatException('Unsupported or damaged image.');
    }
    final base = _resizeForDecoding(decoded);

    for (final attempt in const <({bool inverted, bool tryHarder})>[
      (inverted: false, tryHarder: false),
      (inverted: false, tryHarder: true),
      (inverted: true, tryHarder: false),
      (inverted: true, tryHarder: true),
    ]) {
      try {
        return _decodeCandidate(
          base,
          inverted: attempt.inverted,
          tryHarder: attempt.tryHarder,
        );
      } on ReaderException {
        // Continue with the next bounded preprocessing strategy.
      }
    }
    throw const FormatException('No QR code found in image.');
  }

  img.Image _resizeForDecoding(img.Image source) {
    const maxDimension = 1600;
    final longest = source.width > source.height ? source.width : source.height;
    if (longest <= maxDimension) return source;
    final scale = maxDimension / longest;
    return img.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  String _decodeCandidate(
    img.Image image, {
    required bool inverted,
    required bool tryHarder,
  }) {
    final pixels = Int32List(image.width * image.height);
    var offset = 0;
    for (final pixel in image) {
      var red = pixel.r.toInt() & 0xff;
      var green = pixel.g.toInt() & 0xff;
      var blue = pixel.b.toInt() & 0xff;
      if (inverted) {
        red = 0xff - red;
        green = 0xff - green;
        blue = 0xff - blue;
      }
      pixels[offset++] =
          ((pixel.a.toInt() & 0xff) << 24) | (red << 16) | (green << 8) | blue;
    }
    final source = RGBLuminanceSource(image.width, image.height, pixels);
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    final hints = DecodeHints();
    if (tryHarder) hints.put(DecodeHintType.tryHarder);
    return QRCodeReader().decode(bitmap, hints: hints).text;
  }
}
