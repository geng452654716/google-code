import 'dart:io';
import 'package:flutter/services.dart';

/// Result returned after the operating system accepts or declines a share request.
enum NativeAccountShareResult { presented, unavailable, cancelled }

/// Sensitive in-memory package sent to the native desktop share surface.
class NativeAccountSharePayload {
  const NativeAccountSharePayload({
    required this.title,
    required this.text,
    required this.qrPng,
  });

  /// Human-readable title shown by share targets when the platform supports it.
  final String title;

  /// Account label, Base32 Secret, and otpauth URI shared as plain text.
  final String text;

  /// QR PNG bytes shared directly from memory without a plaintext temp file.
  final Uint8List qrPng;
}

/// Platform boundary for presenting the native macOS or Windows share surface.
abstract interface class NativeAccountShareService {
  /// Presents [payload] to the operating system after application reauthentication.
  Future<NativeAccountShareResult> share(NativeAccountSharePayload payload);
}

/// MethodChannel implementation backed by NSSharingServicePicker or Windows share UI.
class MethodChannelNativeAccountShareService
    implements NativeAccountShareService {
  /// [isSupportedPlatform] overrides platform detection only for deterministic tests.
  MethodChannelNativeAccountShareService({
    MethodChannel? channel,
    bool? isSupportedPlatform,
  }) : _channel = channel ?? const MethodChannel(_channelName),
       _isSupportedPlatform =
           isSupportedPlatform ?? (Platform.isMacOS || Platform.isWindows);

  static const _channelName = 'google_code/native_account_share';
  static const _shareMethod = 'shareAccount';
  static const _maxQrBytes = 5 * 1024 * 1024;

  final MethodChannel _channel;
  final bool _isSupportedPlatform;

  @override
  Future<NativeAccountShareResult> share(
    NativeAccountSharePayload payload,
  ) async {
    if (!_isSupportedPlatform) {
      return NativeAccountShareResult.unavailable;
    }
    if (payload.title.trim().isEmpty || payload.text.trim().isEmpty) {
      throw ArgumentError('Native share title and text must not be empty.');
    }
    if (payload.qrPng.isEmpty || payload.qrPng.length > _maxQrBytes) {
      throw ArgumentError(
        'Native share QR PNG must be between 1 byte and 5 MiB.',
      );
    }

    try {
      final result = await _channel.invokeMethod<String>(_shareMethod, {
        'title': payload.title,
        'text': payload.text,
        'qrPng': payload.qrPng,
      });
      return switch (result) {
        'presented' => NativeAccountShareResult.presented,
        'cancelled' => NativeAccountShareResult.cancelled,
        'unavailable' => NativeAccountShareResult.unavailable,
        _ => throw PlatformException(
          code: 'invalid_share_result',
          message: 'Native share returned an unsupported result.',
          details: result,
        ),
      };
    } on MissingPluginException {
      return NativeAccountShareResult.unavailable;
    }
  }
}
