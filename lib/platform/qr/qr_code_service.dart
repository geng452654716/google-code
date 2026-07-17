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

  /// Decodes the first QR code using bounded rotation and inversion attempts.
  String decodeImage(Uint8List bytes, {int maxPixels = 40 * 1000 * 1000}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Unsupported or damaged image.');
    }
    if (decoded.width * decoded.height > maxPixels) {
      throw const FormatException('Image pixel count exceeds the limit.');
    }

    final base = _resizeForDecoding(decoded);
    final candidates = <img.Image>[
      base,
      img.copyRotate(base, angle: 90),
      img.copyRotate(base, angle: 180),
      img.copyRotate(base, angle: 270),
      img.invert(img.Image.from(base)),
    ];
    for (final candidate in candidates) {
      try {
        return _decodeCandidate(candidate);
      } on ReaderException {
        // Continue with the next bounded preprocessing strategy.
      }
    }
    throw const FormatException('No QR code found in image.');
  }

  img.Image _resizeForDecoding(img.Image source) {
    const maxDimension = 2400;
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

  String _decodeCandidate(img.Image image) {
    final pixels = Int32List(image.width * image.height);
    var offset = 0;
    for (final pixel in image) {
      pixels[offset++] =
          ((pixel.a.toInt() & 0xff) << 24) |
          ((pixel.r.toInt() & 0xff) << 16) |
          ((pixel.g.toInt() & 0xff) << 8) |
          (pixel.b.toInt() & 0xff);
    }
    final source = RGBLuminanceSource(image.width, image.height, pixels);
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    final hints = DecodeHints()..put(DecodeHintType.tryHarder);
    return QRCodeReader().decode(bitmap, hints: hints).text;
  }
}
