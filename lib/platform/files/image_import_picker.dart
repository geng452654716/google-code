import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

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
  const FileSelectorImageImportPicker({
    this.macosChannel = const MethodChannel('google_code/image_import_picker'),
  });

  final MethodChannel macosChannel;

  static const _imageTypes = XTypeGroup(
    label: '二维码图片',
    extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', 'tif', 'tiff'],
  );

  @override
  Future<PickedImageData?> pickImage() async {
    if (Platform.isMacOS) return _pickMacosImage();

    final file = await openFile(
      acceptedTypeGroups: const [_imageTypes],
      confirmButtonText: '选择图片',
    );
    if (file == null) return null;
    return PickedImageData(bytes: await file.readAsBytes(), name: file.name);
  }

  Future<PickedImageData?> _pickMacosImage() async {
    final response = await macosChannel.invokeMapMethod<String, Object?>(
      'pickQrImage',
    );
    if (response == null) return null;
    final bytes = response['bytes'];
    final name = response['name'];
    if (bytes is! Uint8List || name is! String || name.isEmpty) {
      throw const FormatException('Invalid image picker response.');
    }
    return PickedImageData(bytes: bytes, name: name);
  }
}
