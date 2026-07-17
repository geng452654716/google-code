import 'dart:async';

import 'package:flutter/services.dart';

/// Reads the current plain-text clipboard value.
typedef ClipboardTextReader = Future<String?> Function();

/// Replaces the current plain-text clipboard value.
typedef ClipboardTextWriter = Future<void> Function(String text);

/// Writes sensitive text and clears it only if the clipboard is still unchanged.
class SensitiveClipboardService {
  SensitiveClipboardService({
    ClipboardTextReader? readText,
    ClipboardTextWriter? writeText,
  }) : _readText = readText ?? _readSystemClipboard,
       _writeText = writeText ?? _writeSystemClipboard;

  final ClipboardTextReader _readText;
  final ClipboardTextWriter _writeText;
  Timer? _clearTimer;

  /// Copies [text] and schedules a best-effort conditional clear after [ttl].
  Future<void> writeText(
    String text, {
    Duration ttl = const Duration(minutes: 1),
  }) async {
    _clearTimer?.cancel();
    await _writeText(text);
    _clearTimer = Timer(ttl, () async {
      final current = await _readText();
      if (current == text) {
        await _writeText('');
      }
    });
  }

  /// Cancels pending work when the application-level provider is destroyed.
  void dispose() {
    _clearTimer?.cancel();
    _clearTimer = null;
  }

  static Future<String?> _readSystemClipboard() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  static Future<void> _writeSystemClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
