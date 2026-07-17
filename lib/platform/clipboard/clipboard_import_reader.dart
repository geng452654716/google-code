import 'package:flutter/services.dart';

typedef ClipboardTextReader = Future<String?> Function();

/// Reads and trims plain text through Flutter's standard clipboard channel.
Future<String?> _readClipboardText() async {
  final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
  return clipboard?.text?.trim();
}

/// Clipboard payload that can be converted into one TOTP import candidate.
sealed class ClipboardImportData {
  const ClipboardImportData();
}

/// QR image bytes read directly from the operating-system clipboard.
final class ClipboardImageData extends ClipboardImportData {
  const ClipboardImageData(this.bytes);

  final Uint8List bytes;
}

/// Plain text read from the clipboard, expected to contain an otpauth URI.
final class ClipboardTextData extends ClipboardImportData {
  const ClipboardTextData(this.text);

  final String text;
}

/// Safe, user-facing failure raised when the clipboard cannot be read.
class ClipboardImportReadException implements Exception {
  const ClipboardImportReadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Testable boundary for reading image or text data from the clipboard.
abstract interface class ClipboardImportReader {
  Future<ClipboardImportData?> read();
}

/// Reads clipboard images through native desktop code and text through Flutter.
class PlatformClipboardImportReader implements ClipboardImportReader {
  const PlatformClipboardImportReader({
    this.channel = const MethodChannel('google_code/clipboard_import'),
    this.readText = _readClipboardText,
  });

  final MethodChannel channel;
  final ClipboardTextReader readText;

  @override
  Future<ClipboardImportData?> read() async {
    Object? imageFailure;
    try {
      final bytes = await channel.invokeMethod<Uint8List>('readImage');
      if (bytes != null && bytes.isNotEmpty) {
        return ClipboardImageData(bytes);
      }
    } on MissingPluginException catch (error) {
      imageFailure = error;
    } on PlatformException catch (error) {
      imageFailure = error;
    }

    try {
      final text = (await readText())?.trim();
      if (text != null && text.isNotEmpty) {
        return ClipboardTextData(text);
      }
    } on Object {
      throw const ClipboardImportReadException('无法读取剪贴板，请检查系统权限后重试。');
    }

    if (imageFailure != null) {
      throw const ClipboardImportReadException('无法读取剪贴板图片，请重新复制后重试。');
    }
    return null;
  }
}
