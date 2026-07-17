import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// User-controlled destination boundary for a sensitive account QR image.
abstract interface class AccountShareFileSaver {
  /// Saves [pngBytes] only after the user explicitly chooses a destination.
  Future<bool> savePng(Uint8List pngBytes, {required String suggestedName});
}

/// Desktop implementation backed by the operating system save dialog.
class FileSelectorAccountShareFileSaver implements AccountShareFileSaver {
  static const _pngType = XTypeGroup(
    label: 'PNG 二维码图片',
    extensions: ['png'],
    mimeTypes: ['image/png'],
  );

  @override
  Future<bool> savePng(
    Uint8List pngBytes, {
    required String suggestedName,
  }) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: const [_pngType],
      suggestedName: suggestedName,
      confirmButtonText: '保存二维码',
    );
    if (location == null) return false;
    await File(location.path).writeAsBytes(pngBytes, flush: true);
    return true;
  }
}
