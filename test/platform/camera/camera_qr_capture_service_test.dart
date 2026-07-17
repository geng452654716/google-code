import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/platform/camera/camera_qr_capture_service.dart';

void main() {
  test('rejects unsupported platforms before touching the camera plugin', () {
    const service = DesktopCameraQrCaptureService(
      platformSupportedOverride: false,
    );

    expect(
      service.listDevices(),
      throwsA(
        isA<CameraQrCaptureException>().having(
          (error) => error.kind,
          'kind',
          CameraQrCaptureFailureKind.unsupported,
        ),
      ),
    );
  });
}
