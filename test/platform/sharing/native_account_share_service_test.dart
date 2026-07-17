import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/platform/sharing/native_account_share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/native_account_share');
  final payload = NativeAccountSharePayload(
    title: 'Example account TOTP',
    text: 'Base32 Secret: JBSWY3DPEHPK3PXP',
    qrPng: Uint8List.fromList([137, 80, 78, 71]),
  );

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'sends the complete in-memory package and maps presented result',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return 'presented';
          });

      final result = await MethodChannelNativeAccountShareService(
        channel: channel,
        isSupportedPlatform: true,
      ).share(payload);

      expect(result, NativeAccountShareResult.presented);
      expect(received!.method, 'shareAccount');
      final arguments = received!.arguments as Map<Object?, Object?>;
      expect(arguments['title'], payload.title);
      expect(arguments['text'], payload.text);
      expect(arguments['qrPng'], payload.qrPng);
    },
  );

  test(
    'maps cancellation and missing plugin without exposing material',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 'cancelled');
      final service = MethodChannelNativeAccountShareService(
        channel: channel,
        isSupportedPlatform: true,
      );
      expect(await service.share(payload), NativeAccountShareResult.cancelled);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(
        await service.share(payload),
        NativeAccountShareResult.unavailable,
      );
    },
  );

  test('does not invoke the channel on an unsupported platform', () async {
    var invoked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          invoked = true;
          return 'presented';
        });

    final result = await MethodChannelNativeAccountShareService(
      channel: channel,
      isSupportedPlatform: false,
    ).share(payload);

    expect(result, NativeAccountShareResult.unavailable);
    expect(invoked, isFalse);
  });

  test(
    'rejects empty or oversized sensitive payloads before native code',
    () async {
      final service = MethodChannelNativeAccountShareService(
        channel: channel,
        isSupportedPlatform: true,
      );
      expect(
        () => service.share(
          NativeAccountSharePayload(
            title: '',
            text: payload.text,
            qrPng: payload.qrPng,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => service.share(
          NativeAccountSharePayload(
            title: payload.title,
            text: payload.text,
            qrPng: Uint8List(5 * 1024 * 1024 + 1),
          ),
        ),
        throwsArgumentError,
      );
    },
  );
}
