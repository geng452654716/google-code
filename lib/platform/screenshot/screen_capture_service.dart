import 'package:flutter/services.dart';

/// Stable categories for failures raised by the native screen-capture layer.
enum ScreenCaptureFailureKind { permissionDenied, unavailable, failed }

/// Safe user-facing screen-capture failure without native diagnostic details.
class ScreenCaptureException implements Exception {
  const ScreenCaptureException(this.kind, this.message);

  final ScreenCaptureFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Testable platform boundary for an interactive desktop region screenshot.
abstract interface class ScreenCaptureService {
  /// Returns encoded image bytes, or `null` when the user cancels selection.
  Future<Uint8List?> captureRegion();

  /// Opens the operating system screen-recording permission settings page.
  Future<void> openPermissionSettings();

  /// Fully exits and reopens the installed desktop application.
  Future<void> restartApplication();
}

/// Method-channel implementation backed by the desktop runner.
class PlatformScreenCaptureService implements ScreenCaptureService {
  const PlatformScreenCaptureService({
    this.channel = const MethodChannel('google_code/screen_capture'),
  });

  final MethodChannel channel;

  @override
  Future<Uint8List?> captureRegion() async {
    try {
      final bytes = await channel.invokeMethod<Uint8List>('captureRegion');
      return bytes == null || bytes.isEmpty ? null : bytes;
    } on MissingPluginException {
      throw const ScreenCaptureException(
        ScreenCaptureFailureKind.unavailable,
        '当前平台暂不支持区域截图，请改用二维码图片或剪贴板导入。',
      );
    } on PlatformException catch (error) {
      throw _mapPlatformError(error);
    }
  }

  @override
  Future<void> openPermissionSettings() async {
    try {
      await channel.invokeMethod<void>('openScreenRecordingSettings');
    } on MissingPluginException {
      throw const ScreenCaptureException(
        ScreenCaptureFailureKind.unavailable,
        '无法打开系统设置，请手动进入隐私与安全性中的屏幕录制设置。',
      );
    } on PlatformException {
      throw const ScreenCaptureException(
        ScreenCaptureFailureKind.failed,
        '无法打开系统设置，请手动进入隐私与安全性中的屏幕录制设置。',
      );
    }
  }

  @override
  Future<void> restartApplication() async {
    try {
      await channel.invokeMethod<void>('restartApplication');
    } on MissingPluginException {
      throw const ScreenCaptureException(
        ScreenCaptureFailureKind.unavailable,
        '无法自动重新打开应用，请手动完全退出 Google Code 后再次打开。',
      );
    } on PlatformException {
      throw const ScreenCaptureException(
        ScreenCaptureFailureKind.failed,
        '无法自动重新打开应用，请手动完全退出 Google Code 后再次打开。',
      );
    }
  }

  ScreenCaptureException _mapPlatformError(PlatformException error) {
    return switch (error.code) {
      'permission_denied' => const ScreenCaptureException(
        ScreenCaptureFailureKind.permissionDenied,
        '当前进程尚未获得屏幕录制权限。若系统设置中的 Google Code 已经开启，请完全退出并重新打开应用；否则请先开启权限。',
      ),
      'unavailable' || 'unsupported' => const ScreenCaptureException(
        ScreenCaptureFailureKind.unavailable,
        '当前平台暂不支持区域截图，请改用二维码图片或剪贴板导入。',
      ),
      _ => const ScreenCaptureException(
        ScreenCaptureFailureKind.failed,
        '区域截图失败，请重试或改用二维码图片导入。',
      ),
    };
  }
}
