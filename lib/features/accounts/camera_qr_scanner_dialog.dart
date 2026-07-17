import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/import_providers.dart';
import '../../application/import/otp_import_service.dart';
import '../../platform/camera/camera_qr_capture_service.dart';

/// Modal desktop camera scanner that returns one validated import result.
class CameraQrScannerDialog extends ConsumerStatefulWidget {
  const CameraQrScannerDialog({
    this.scanInterval = const Duration(milliseconds: 650),
    super.key,
  });

  /// Delay between still captures; configurable to keep widget tests fast.
  final Duration scanInterval;

  @override
  ConsumerState<CameraQrScannerDialog> createState() =>
      _CameraQrScannerDialogState();
}

class _CameraQrScannerDialogState extends ConsumerState<CameraQrScannerDialog> {
  List<CameraQrCaptureDevice> _devices = const [];
  CameraQrCaptureDevice? _selectedDevice;
  CameraQrCaptureSession? _session;
  CameraQrCaptureException? _fatalError;
  String _scanMessage = '正在启动摄像头…';
  bool _isOpening = true;
  bool _isSwitchingDevice = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDevices());
  }

  @override
  void dispose() {
    _generation++;
    final session = _session;
    _session = null;
    if (session != null) unawaited(session.dispose());
    super.dispose();
  }

  /// Enumerates cameras and opens the first available device.
  Future<void> _loadDevices() async {
    final generation = ++_generation;
    setState(() {
      _isOpening = true;
      _fatalError = null;
      _scanMessage = '正在检测摄像头…';
    });
    try {
      final devices = await ref
          .read(cameraQrCaptureServiceProvider)
          .listDevices();
      if (!mounted || generation != _generation) return;
      _devices = devices;
      await _openDevice(devices.first, generation: generation);
    } on CameraQrCaptureException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _isOpening = false;
        _fatalError = error;
        _scanMessage = error.message;
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _isOpening = false;
        _fatalError = const CameraQrCaptureException(
          CameraQrCaptureFailureKind.unavailable,
          '摄像头初始化失败，请检查设备和系统权限后重试。',
        );
      });
    }
  }

  /// Replaces the current native session without allowing stale scan loops to win.
  Future<void> _selectDevice(CameraQrCaptureDevice device) async {
    if (_isSwitchingDevice || device.id == _selectedDevice?.id) return;
    final generation = ++_generation;
    setState(() {
      _isSwitchingDevice = true;
      _fatalError = null;
      _scanMessage = '正在切换摄像头…';
    });
    await _openDevice(device, generation: generation);
  }

  Future<void> _openDevice(
    CameraQrCaptureDevice device, {
    required int generation,
  }) async {
    final previous = _session;
    _session = null;
    if (previous != null) await previous.dispose();
    if (!mounted || generation != _generation) return;

    try {
      final session = await ref
          .read(cameraQrCaptureServiceProvider)
          .open(device);
      if (!mounted || generation != _generation) {
        await session.dispose();
        return;
      }
      setState(() {
        _session = session;
        _selectedDevice = device;
        _isOpening = false;
        _isSwitchingDevice = false;
        _fatalError = null;
        _scanMessage = '请将二维码完整放入取景框';
      });
      unawaited(_scanLoop(session, generation));
    } on CameraQrCaptureException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _isOpening = false;
        _isSwitchingDevice = false;
        _fatalError = error;
        _scanMessage = error.message;
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _isOpening = false;
        _isSwitchingDevice = false;
        _fatalError = const CameraQrCaptureException(
          CameraQrCaptureFailureKind.unavailable,
          '摄像头启动失败，请关闭占用摄像头的其他应用后重试。',
        );
      });
    }
  }

  /// Captures bounded still frames until one supported OTP QR is recognized.
  Future<void> _scanLoop(CameraQrCaptureSession session, int generation) async {
    while (mounted && generation == _generation && _session == session) {
      await Future<void>.delayed(widget.scanInterval);
      if (!mounted || generation != _generation || _session != session) return;

      try {
        final frame = await session.captureFrame();
        if (!mounted || generation != _generation || _session != session) {
          return;
        }
        final result = await ref
            .read(otpImportServiceProvider)
            .tryDecodeCameraFrame(frame);
        if (!mounted || generation != _generation || _session != session) {
          return;
        }
        if (result == null) {
          _updateScanMessage('正在扫描，请保持二维码清晰稳定');
          continue;
        }

        _generation++;
        Navigator.of(context).pop(result);
        return;
      } on OtpImportException catch (error) {
        if (!mounted || generation != _generation) return;
        _updateScanMessage(error.message);
      } on CameraQrCaptureException catch (error) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _fatalError = error;
          _scanMessage = error.message;
        });
        return;
      } on Object {
        if (!mounted || generation != _generation) return;
        setState(() {
          _fatalError = const CameraQrCaptureException(
            CameraQrCaptureFailureKind.captureFailed,
            '摄像头扫描异常，请关闭窗口后重试。',
          );
        });
        return;
      }
    }
  }

  void _updateScanMessage(String message) {
    if (_scanMessage == message) return;
    setState(() => _scanMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      scrollable: true,
      title: const Row(
        children: [
          Icon(Icons.qr_code_scanner_rounded),
          SizedBox(width: 10),
          Text('摄像头扫描'),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_devices.length > 1) ...[
              DropdownButtonFormField<String>(
                key: const ValueKey('camera-device-selector'),
                initialValue: _selectedDevice?.id,
                decoration: const InputDecoration(
                  labelText: '摄像头',
                  prefixIcon: Icon(Icons.videocam_outlined),
                ),
                items: _devices
                    .map(
                      (device) => DropdownMenuItem(
                        value: device.id,
                        child: Text(
                          device.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _isSwitchingDevice
                    ? null
                    : (id) {
                        final device = _devices
                            .where((candidate) => candidate.id == id)
                            .firstOrNull;
                        if (device != null) unawaited(_selectDevice(device));
                      },
              ),
              const SizedBox(height: 14),
            ],
            AspectRatio(
              aspectRatio: _session?.aspectRatio ?? 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_session case final session?) session.buildPreview(),
                      if (_isOpening || _isSwitchingDevice)
                        const Center(child: CircularProgressIndicator()),
                      if (_fatalError != null)
                        _CameraErrorPanel(
                          error: _fatalError!,
                          onRetry: _loadDevices,
                        ),
                      if (_session != null && _fatalError == null)
                        const _QrTargetOverlay(),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  _fatalError == null
                      ? Icons.center_focus_strong_rounded
                      : Icons.error_outline_rounded,
                  size: 20,
                  color: _fatalError == null ? colors.primary : colors.error,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_fatalError?.message ?? _scanMessage)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '摄像头画面仅在本机内存中解析；临时截图会在读取后立即删除。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _CameraErrorPanel extends StatelessWidget {
  const _CameraErrorPanel({required this.error, required this.onRetry});

  final CameraQrCaptureException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                error.message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const ValueKey('retry-camera-scan'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrTargetOverlay extends StatelessWidget {
  const _QrTargetOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.58,
          child: AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
