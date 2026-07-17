import 'dart:io';
import 'package:flutter/services.dart';

/// Device-local secure storage boundary for the quick-unlock DEK copy.
abstract interface class SecureKeyStore {
  Future<bool> containsQuickUnlockKey();

  Future<Uint8List?> readQuickUnlockKey();

  Future<void> writeQuickUnlockKey(Uint8List keyBytes);

  Future<void> deleteQuickUnlockKey();
}

/// Keychain/Credential Manager implementation exposed by the desktop runner.
class MethodChannelSecureKeyStore implements SecureKeyStore {
  /// Creates a secure key store backed by the desktop method channel.
  ///
  /// [platformSupportedOverride] overrides host detection for deterministic
  /// cross-platform tests.
  MethodChannelSecureKeyStore({
    MethodChannel? channel,
    this.platformSupportedOverride,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'google_code/secure_key_store';
  static const _keyLength = 32;

  final MethodChannel _channel;

  /// Optional platform support override used by cross-platform tests.
  final bool? platformSupportedOverride;

  @override
  Future<bool> containsQuickUnlockKey() async {
    if (!_supportsCurrentPlatform) return false;
    return await _channel.invokeMethod<bool>('contains') ?? false;
  }

  @override
  Future<Uint8List?> readQuickUnlockKey() async {
    if (!_supportsCurrentPlatform) return null;
    Uint8List? value;
    try {
      value = await _channel.invokeMethod<Uint8List>('read');
    } on PlatformException catch (error) {
      if (error.code == 'invalid_key') {
        throw const FormatException('Stored quick unlock key is invalid.');
      }
      rethrow;
    }
    if (value == null) return null;
    if (value.length != _keyLength) {
      final invalid = Uint8List.fromList(value);
      invalid.fillRange(0, invalid.length, 0);
      throw const FormatException('Stored quick unlock key is invalid.');
    }
    return Uint8List.fromList(value);
  }

  @override
  Future<void> writeQuickUnlockKey(Uint8List keyBytes) async {
    if (!_supportsCurrentPlatform) {
      throw UnsupportedError('Secure key storage is unavailable.');
    }
    if (keyBytes.length != _keyLength) {
      throw const FormatException('Quick unlock key must contain 32 bytes.');
    }
    await _channel.invokeMethod<void>('write', keyBytes);
  }

  @override
  Future<void> deleteQuickUnlockKey() async {
    if (!_supportsCurrentPlatform) return;
    await _channel.invokeMethod<void>('delete');
  }

  bool get _supportsCurrentPlatform =>
      platformSupportedOverride ?? Platform.isMacOS || Platform.isWindows;
}
