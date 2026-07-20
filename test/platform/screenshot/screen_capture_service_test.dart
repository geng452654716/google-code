import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/platform/screenshot/screen_capture_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_code/screen_capture_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('returns captured image bytes', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'captureRegion');
      return Uint8List.fromList([1, 2, 3]);
    });

    final bytes = await const PlatformScreenCaptureService(
      channel: channel,
    ).captureRegion();

    expect(bytes, [1, 2, 3]);
  });

  test('returns null when selection is cancelled', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);

    expect(
      await const PlatformScreenCaptureService(
        channel: channel,
      ).captureRegion(),
      isNull,
    );
  });

  test('maps native permission denial', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'permission_denied');
    });

    await expectLater(
      const PlatformScreenCaptureService(channel: channel).captureRegion(),
      throwsA(
        isA<ScreenCaptureException>()
            .having(
              (error) => error.kind,
              'kind',
              ScreenCaptureFailureKind.permissionDenied,
            )
            .having((error) => error.message, 'message', contains('屏幕录制权限')),
      ),
    );
  });

  test('maps native capture failures to a safe message', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'capture_failed',
        message: 'sensitive native diagnostic',
      );
    });

    await expectLater(
      const PlatformScreenCaptureService(channel: channel).captureRegion(),
      throwsA(
        isA<ScreenCaptureException>()
            .having(
              (error) => error.kind,
              'kind',
              ScreenCaptureFailureKind.failed,
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('sensitive')),
            ),
      ),
    );
  });

  test('opens native screen-recording settings', () async {
    var opened = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openScreenRecordingSettings');
      opened = true;
      return null;
    });

    await const PlatformScreenCaptureService(
      channel: channel,
    ).openPermissionSettings();

    expect(opened, isTrue);
  });

  test('requests a full native application restart', () async {
    var restarted = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'restartApplication');
      restarted = true;
      return null;
    });

    await const PlatformScreenCaptureService(
      channel: channel,
    ).restartApplication();

    expect(restarted, isTrue);
  });
}
