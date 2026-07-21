import 'dart:io';
import 'package:flutter/services.dart';

/// Device-only storage for cloud authorization tokens and provider settings.
abstract interface class DeviceSecretStore {
  Future<Uint8List?> read(String key);

  Future<void> write(String key, Uint8List value);

  Future<void> delete(String key);
}

/// Keychain/Credential Manager implementation exposed by the desktop runner.
class MethodChannelDeviceSecretStore implements DeviceSecretStore {
  const MethodChannelDeviceSecretStore({
    this.channel = const MethodChannel('google_code/secure_key_store'),
    this.platformSupportedOverride,
  });

  final MethodChannel channel;
  final bool? platformSupportedOverride;

  bool get _isSupported =>
      platformSupportedOverride ?? Platform.isMacOS || Platform.isWindows;

  @override
  Future<Uint8List?> read(String key) async {
    _validateKey(key);
    if (!_isSupported) return null;
    final value = await channel.invokeMethod<Uint8List>('readSecret', {
      'key': key,
    });
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> write(String key, Uint8List value) async {
    _validateKey(key);
    if (!_isSupported) {
      throw UnsupportedError('Device secret storage is unavailable.');
    }
    if (value.isEmpty || value.length > 4096) {
      throw const FormatException('Device secret is invalid.');
    }
    await channel.invokeMethod<void>('writeSecret', {
      'key': key,
      'value': value,
    });
  }

  @override
  Future<void> delete(String key) async {
    _validateKey(key);
    if (!_isSupported) return;
    await channel.invokeMethod<void>('deleteSecret', {'key': key});
  }

  /// Restricts native credential identifiers to an application-owned namespace.
  void _validateKey(String key) {
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{0,127}$').hasMatch(key)) {
      throw const FormatException('Device secret key is invalid.');
    }
  }
}
