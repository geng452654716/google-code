import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS region capture minimizes and always restores the app window', () {
    final source = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    expect(source, contains('miniaturize(nil)'));
    expect(source, contains('DispatchQueue.main.asyncAfter'));
    expect(source, contains('runInteractiveScreenCapture'));
    expect(source, contains('restoreAfterScreenCapture()'));
    expect(source, contains('if isMiniaturized'));
    expect(source, contains('deminiaturize(nil)'));
    expect(source, isNot(contains('orderOut(nil)')));
  });
}
