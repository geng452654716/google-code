import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Selected image bytes plus a display-only file name.
class PickedImageData {
  const PickedImageData({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// Platform boundary for selecting a user-owned QR image.
abstract interface class ImageImportPicker {
  Future<PickedImageData?> pickImage();
}

/// Official `file_selector` implementation for macOS and Windows.
class FileSelectorImageImportPicker implements ImageImportPicker {
  static const _imageTypes = XTypeGroup(
    label: '二维码图片',
    extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', 'tif', 'tiff'],
  );

  @override
  Future<PickedImageData?> pickImage() async {
    final file = await openFile(
      acceptedTypeGroups: const [_imageTypes],
      confirmButtonText: '选择图片',
    );
    if (file == null) return null;
    return PickedImageData(bytes: await file.readAsBytes(), name: file.name);
  }
}
