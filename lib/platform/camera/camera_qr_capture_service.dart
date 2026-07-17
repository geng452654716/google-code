import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Stable camera identifier and display metadata exposed to the scanner UI.
class CameraQrCaptureDevice {
  const CameraQrCaptureDevice({
    required this.id,
    required this.name,
    required this.lensDirection,
  });

  /// Platform camera name used to reopen the same device.
  final String id;

  /// Human-readable camera name supplied by the operating system.
  final String name;

  /// Physical direction used only for preview presentation.
  final CameraLensDirection lensDirection;
}

/// User-safe categories for desktop camera failures.
enum CameraQrCaptureFailureKind {
  unsupported,
  noDevice,
  permissionDenied,
  unavailable,
  captureFailed,
}

/// Camera failure that never exposes native paths or raw platform diagnostics.
class CameraQrCaptureException implements Exception {
  const CameraQrCaptureException(this.kind, this.message);

  final CameraQrCaptureFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

/// One initialized camera whose frames are held only long enough for QR parsing.
abstract interface class CameraQrCaptureSession {
  /// Preview aspect ratio reported by the initialized native camera.
  double get aspectRatio;

  /// Builds the native texture preview without copying frames into application state.
  Widget buildPreview();

  /// Captures one still frame into memory and removes the plugin temporary file.
  Future<Uint8List> captureFrame();

  /// Stops capture and releases the operating-system camera handle.
  Future<void> dispose();
}

/// Testable boundary around desktop camera enumeration and session creation.
abstract interface class CameraQrCaptureService {
  /// Lists cameras available to the current desktop process.
  Future<List<CameraQrCaptureDevice>> listDevices();

  /// Opens [device] with a QR-friendly medium resolution and audio disabled.
  Future<CameraQrCaptureSession> open(CameraQrCaptureDevice device);
}

/// `camera` + `camera_desktop` implementation for macOS and Windows.
class DesktopCameraQrCaptureService implements CameraQrCaptureService {
  const DesktopCameraQrCaptureService({this.platformSupportedOverride});

  /// Test-only platform override; production uses the real operating system.
  final bool? platformSupportedOverride;

  bool get _isSupportedPlatform =>
      platformSupportedOverride ?? (Platform.isMacOS || Platform.isWindows);

  @override
  Future<List<CameraQrCaptureDevice>> listDevices() async {
    if (!_isSupportedPlatform) {
      throw const CameraQrCaptureException(
        CameraQrCaptureFailureKind.unsupported,
        '当前平台暂不支持摄像头二维码扫描。',
      );
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw const CameraQrCaptureException(
          CameraQrCaptureFailureKind.noDevice,
          '未检测到可用摄像头，请连接摄像头后重试。',
        );
      }
      return cameras
          .map(
            (camera) => CameraQrCaptureDevice(
              id: camera.name,
              name: camera.name,
              lensDirection: camera.lensDirection,
            ),
          )
          .toList(growable: false);
    } on CameraQrCaptureException {
      rethrow;
    } on CameraException catch (error) {
      throw _mapCameraException(error, opening: true);
    } on Object {
      throw const CameraQrCaptureException(
        CameraQrCaptureFailureKind.unavailable,
        '无法读取摄像头列表，请检查系统权限和设备连接状态。',
      );
    }
  }

  @override
  Future<CameraQrCaptureSession> open(CameraQrCaptureDevice device) async {
    if (!_isSupportedPlatform) {
      throw const CameraQrCaptureException(
        CameraQrCaptureFailureKind.unsupported,
        '当前平台暂不支持摄像头二维码扫描。',
      );
    }

    CameraController? controller;
    try {
      final descriptions = await availableCameras();
      final description = descriptions
          .where((candidate) => candidate.name == device.id)
          .firstOrNull;
      if (description == null) {
        throw const CameraQrCaptureException(
          CameraQrCaptureFailureKind.unavailable,
          '所选摄像头已断开，请重新选择设备。',
        );
      }

      controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      return _CameraControllerQrCaptureSession(
        controller: controller,
        mirrorWindowsPreview:
            Platform.isWindows &&
            description.lensDirection == CameraLensDirection.front,
      );
    } on CameraQrCaptureException {
      await controller?.dispose();
      rethrow;
    } on CameraException catch (error) {
      await controller?.dispose();
      throw _mapCameraException(error, opening: true);
    } on Object {
      await controller?.dispose();
      throw const CameraQrCaptureException(
        CameraQrCaptureFailureKind.unavailable,
        '摄像头启动失败，请关闭占用摄像头的其他应用后重试。',
      );
    }
  }

  CameraQrCaptureException _mapCameraException(
    CameraException error, {
    required bool opening,
  }) {
    final code = error.code.toLowerCase();
    if (code.contains('denied') ||
        code.contains('permission') ||
        code.contains('restricted')) {
      return const CameraQrCaptureException(
        CameraQrCaptureFailureKind.permissionDenied,
        '没有摄像头访问权限，请在系统隐私设置中允许 Google Code 使用摄像头。',
      );
    }
    return CameraQrCaptureException(
      opening
          ? CameraQrCaptureFailureKind.unavailable
          : CameraQrCaptureFailureKind.captureFailed,
      opening ? '摄像头启动失败，请检查设备是否被其他应用占用。' : '摄像头画面读取失败，请重新打开扫描窗口。',
    );
  }
}

class _CameraControllerQrCaptureSession implements CameraQrCaptureSession {
  _CameraControllerQrCaptureSession({
    required this._controller,
    required this._mirrorWindowsPreview,
  });

  final CameraController _controller;
  final bool _mirrorWindowsPreview;
  bool _disposed = false;

  @override
  double get aspectRatio {
    final ratio = _controller.value.aspectRatio;
    return ratio.isFinite && ratio > 0 ? ratio : 4 / 3;
  }

  @override
  Widget buildPreview() {
    final preview = CameraPreview(_controller);
    if (!_mirrorWindowsPreview) return preview;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(-1, 1, 1),
      child: preview,
    );
  }

  @override
  Future<Uint8List> captureFrame() async {
    if (_disposed || !_controller.value.isInitialized) {
      throw const CameraQrCaptureException(
        CameraQrCaptureFailureKind.captureFailed,
        '摄像头会话已结束，请重新打开扫描窗口。',
      );
    }

    XFile? picture;
    try {
      picture = await _controller.takePicture();
      return await picture.readAsBytes();
    } on CameraException catch (error) {
      final code = error.code.toLowerCase();
      if (code.contains('denied') || code.contains('permission')) {
        throw const CameraQrCaptureException(
          CameraQrCaptureFailureKind.permissionDenied,
          '摄像头权限已被关闭，请在系统隐私设置中重新允许访问。',
        );
      }
      throw const CameraQrCaptureException(
        CameraQrCaptureFailureKind.captureFailed,
        '摄像头画面读取失败，请重新打开扫描窗口。',
      );
    } on CameraQrCaptureException {
      rethrow;
    } on Object {
      throw const CameraQrCaptureException(
        CameraQrCaptureFailureKind.captureFailed,
        '摄像头画面读取失败，请重新打开扫描窗口。',
      );
    } finally {
      final path = picture?.path;
      if (path != null && path.isNotEmpty) {
        try {
          final temporaryFile = File(path);
          if (await temporaryFile.exists()) await temporaryFile.delete();
        } on FileSystemException {
          // Best-effort cleanup: the plugin or OS may already remove the file.
        }
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _controller.dispose();
  }
}
