import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/platform/clipboard/clipboard_import_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_code/clipboard_import_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('prefers clipboard image bytes over text', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readImage');
      return Uint8List.fromList([1, 2, 3]);
    });
    final reader = PlatformClipboardImportReader(
      channel: channel,
      readText: () async => 'otpauth://totp/unused',
    );

    final result = await reader.read();

    expect(result, isA<ClipboardImageData>());
    expect((result! as ClipboardImageData).bytes, [1, 2, 3]);
  });

  test('falls back to trimmed clipboard text when no image exists', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final reader = PlatformClipboardImportReader(
      channel: channel,
      readText: () async => '  otpauth://totp/Example  ',
    );

    final result = await reader.read();

    expect(result, isA<ClipboardTextData>());
    expect((result! as ClipboardTextData).text, 'otpauth://totp/Example');
  });

  test('returns null when neither image nor text exists', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final reader = PlatformClipboardImportReader(
      channel: channel,
      readText: () async => '   ',
    );

    expect(await reader.read(), isNull);
  });
}
