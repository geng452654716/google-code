import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/platform/security/device_secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/device_secret_store');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('uses namespaced native methods and copies returned bytes', () async {
    MethodCall? captured;
    final nativeBytes = Uint8List.fromList([1, 2, 3]);
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return nativeBytes;
    });
    final store = MethodChannelDeviceSecretStore(
      channel: channel,
      platformSupportedOverride: true,
    );

    final result = await store.read('cloud.github.session.v1');

    expect(captured?.method, 'readSecret');
    expect(captured?.arguments, {'key': 'cloud.github.session.v1'});
    expect(result, [1, 2, 3]);
    nativeBytes[0] = 9;
    expect(result, [1, 2, 3]);
  });

  test(
    'validates key and value before crossing the platform channel',
    () async {
      final store = MethodChannelDeviceSecretStore(
        channel: channel,
        platformSupportedOverride: true,
      );

      await expectLater(store.read('../token'), throwsFormatException);
      await expectLater(
        store.write('cloud.github.session.v1', Uint8List(0)),
        throwsFormatException,
      );
      await expectLater(
        store.write('cloud.github.session.v1', Uint8List(4097)),
        throwsFormatException,
      );
    },
  );

  test('desktop runners retain quick unlock and add cloud secret storage', () {
    final swift = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    final windows = File(
      'windows/runner/secure_key_store.cpp',
    ).readAsStringSync();

    for (final method in ['readSecret', 'writeSecret', 'deleteSecret']) {
      expect(swift, contains(method));
      expect(windows, contains(method));
    }
    expect(swift, contains('com.gengyujian.google-code.cloud-secrets'));
    expect(swift, contains('kSecAttrAccessibleWhenUnlockedThisDeviceOnly'));
    expect(windows, contains('com.gengyujian.google-code.cloud-secret.'));
    expect(windows, contains('CRED_PERSIST_LOCAL_MACHINE'));
    expect(swift, contains('quickUnlockKeychainQuery'));
    expect(windows, contains('kQuickUnlockKeyLength = 32'));
  });

  test('macOS cloud backup entitlements allow selected writes and HTTPS', () {
    for (final path in [
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('com.apple.security.files.user-selected.read-write'),
      );
      expect(source, contains('com.apple.security.network.client'));
      expect(
        source,
        isNot(contains('com.apple.security.files.user-selected.read-only')),
      );
    }
  });
}
