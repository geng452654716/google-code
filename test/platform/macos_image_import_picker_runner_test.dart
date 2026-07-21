import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS sandbox allows access to selected QR images and sync folders', () {
    for (final path in <String>[
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      final entitlements = File(path).readAsStringSync();

      expect(
        entitlements,
        contains('com.apple.security.files.user-selected.read-write'),
        reason:
            '$path must allow NSOpenPanel to expose selected images and cloud backup folders.',
      );
    }
  });

  test('macOS image picker reports a panel display abort as an error', () {
    final source = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    expect(source, contains('panel.beginSheetModal(for: self)'));
    expect(source, contains('if response == .abort'));
    expect(source, contains('code: "image_picker_unavailable"'));
  });
}
