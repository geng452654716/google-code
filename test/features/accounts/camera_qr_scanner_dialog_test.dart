import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/state/import_providers.dart';
import 'package:google_code/application/import/otp_import_service.dart';
import 'package:google_code/domain/import/otp_import_candidate.dart';
import 'package:google_code/features/accounts/camera_qr_scanner_dialog.dart';
import 'package:google_code/platform/camera/camera_qr_capture_service.dart';
import 'package:google_code/platform/qr/qr_code_service.dart';

void main() {
  const uri =
      'otpauth://totp/Camera:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Camera';

  testWidgets(
    'returns the first supported QR and disposes the camera session',
    (tester) async {
      final session = _FakeCameraSession(QrCodeService().encodePng(uri));
      final service = _FakeCameraService(session: session);
      OtpImportResult? scannedResult;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cameraQrCaptureServiceProvider.overrideWithValue(service),
            otpImportServiceProvider.overrideWithValue(
              _FakeOtpImportService(
                const OtpImportService().decodeQrText(
                  uri,
                  source: OtpImportSource.camera,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    scannedResult = await showDialog<OtpImportResult>(
                      context: context,
                      builder: (_) => const CameraQrScannerDialog(
                        scanInterval: Duration.zero,
                      ),
                    );
                  },
                  child: const Text('scan'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('scan'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(scannedResult, isA<SingleOtpImportResult>());
      final candidate = (scannedResult! as SingleOtpImportResult).candidate;
      expect(candidate.draft.issuer, 'Camera');
      expect(session.captureCount, 1);
      expect(session.disposed, isTrue);
    },
  );

  testWidgets('shows a retry state when no camera is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cameraQrCaptureServiceProvider.overrideWithValue(
            const _NoCameraService(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: CameraQrScannerDialog())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('未检测到可用摄像头'), findsWidgets);
    expect(find.byKey(const ValueKey('retry-camera-scan')), findsOneWidget);
  });
}

class _FakeOtpImportService extends OtpImportService {
  const _FakeOtpImportService(this.result);

  final OtpImportResult result;

  @override
  Future<OtpImportResult?> tryDecodeCameraFrame(Uint8List bytes) async =>
      result;
}

class _FakeCameraService implements CameraQrCaptureService {
  const _FakeCameraService({required this.session});

  final CameraQrCaptureSession session;

  static const device = CameraQrCaptureDevice(
    id: 'camera-1',
    name: 'Test Camera',
    lensDirection: CameraLensDirection.front,
  );

  @override
  Future<List<CameraQrCaptureDevice>> listDevices() async => const [device];

  @override
  Future<CameraQrCaptureSession> open(CameraQrCaptureDevice device) async =>
      session;
}

class _NoCameraService implements CameraQrCaptureService {
  const _NoCameraService();

  @override
  Future<List<CameraQrCaptureDevice>> listDevices() async {
    throw const CameraQrCaptureException(
      CameraQrCaptureFailureKind.noDevice,
      '未检测到可用摄像头，请连接摄像头后重试。',
    );
  }

  @override
  Future<CameraQrCaptureSession> open(CameraQrCaptureDevice device) =>
      throw UnimplementedError();
}

class _FakeCameraSession implements CameraQrCaptureSession {
  _FakeCameraSession(this.frame);

  final Uint8List frame;
  int captureCount = 0;
  bool disposed = false;

  @override
  double get aspectRatio => 4 / 3;

  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);

  @override
  Future<Uint8List> captureFrame() async {
    captureCount++;
    return frame;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
