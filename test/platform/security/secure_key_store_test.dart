import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/platform/security/secure_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/secure_key_store');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'maps a native invalid credential to a removable format error',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'read') {
          throw PlatformException(
            code: 'invalid_key',
            message: 'Stored quick unlock material is invalid.',
          );
        }
        return null;
      });

      final keyStore = MethodChannelSecureKeyStore(channel: channel);

      await expectLater(
        keyStore.readQuickUnlockKey(),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
