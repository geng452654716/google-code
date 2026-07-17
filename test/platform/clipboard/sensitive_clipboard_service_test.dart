import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/platform/clipboard/sensitive_clipboard_service.dart';

void main() {
  test('clears sensitive text after the configured lifetime', () async {
    String? clipboard;
    final service = SensitiveClipboardService(
      readText: () async => clipboard,
      writeText: (text) async => clipboard = text,
    );
    addTearDown(service.dispose);

    await service.writeText('SECRET', ttl: const Duration(milliseconds: 10));
    expect(clipboard, 'SECRET');

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(clipboard, isEmpty);
  });

  test('does not erase clipboard content replaced by the user', () async {
    String? clipboard;
    final service = SensitiveClipboardService(
      readText: () async => clipboard,
      writeText: (text) async => clipboard = text,
    );
    addTearDown(service.dispose);

    await service.writeText('SECRET', ttl: const Duration(milliseconds: 10));
    clipboard = 'new user content';

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(clipboard, 'new user content');
  });

  test('a newer sensitive copy replaces the previous cleanup task', () async {
    String? clipboard;
    final service = SensitiveClipboardService(
      readText: () async => clipboard,
      writeText: (text) async => clipboard = text,
    );
    addTearDown(service.dispose);

    await service.writeText('FIRST', ttl: const Duration(milliseconds: 10));
    await service.writeText('SECOND', ttl: const Duration(milliseconds: 40));

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(clipboard, 'SECOND');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(clipboard, isEmpty);
  });
}
