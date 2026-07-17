import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Native operating-system events that require the decrypted Vault to close.
enum SystemSessionEvent { screenLocked, sessionDisconnected, systemSleeping }

/// Platform boundary for lock-screen, session-disconnect, and sleep events.
abstract interface class SystemSessionEventService {
  Stream<SystemSessionEvent> get events;

  /// Installs the native-to-Dart event handler once for the application scope.
  Future<void> start();

  /// Releases the platform handler and closes the application event stream.
  Future<void> dispose();
}

/// Receives native desktop session events through a dedicated MethodChannel.
class MethodChannelSystemSessionEventService
    implements SystemSessionEventService {
  MethodChannelSystemSessionEventService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'google_code/system_session_events';
  static const _eventMethod = 'systemSessionEvent';

  final MethodChannel _channel;
  final StreamController<SystemSessionEvent> _events =
      StreamController<SystemSessionEvent>.broadcast(sync: true);
  bool _isStarted = false;
  bool _isDisposed = false;

  @override
  Stream<SystemSessionEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    if (_isStarted || _isDisposed || !_supportsCurrentPlatform) return;
    _isStarted = true;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    if (_isStarted && _supportsCurrentPlatform) {
      _channel.setMethodCallHandler(null);
    }
    await _events.close();
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != _eventMethod || _isDisposed) return;
    final event = switch (call.arguments) {
      'screenLocked' => SystemSessionEvent.screenLocked,
      'sessionDisconnected' => SystemSessionEvent.sessionDisconnected,
      'systemSleeping' => SystemSessionEvent.systemSleeping,
      _ => null,
    };
    if (event != null) _events.add(event);
  }

  bool get _supportsCurrentPlatform => Platform.isMacOS || Platform.isWindows;
}
