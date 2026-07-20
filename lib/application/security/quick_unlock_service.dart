import 'dart:typed_data';

import '../../core/errors/vault_exception.dart';
import '../../domain/entities/vault_payload.dart';
import '../../domain/repositories/vault_repository.dart';
import '../../platform/auth/local_authentication_service.dart';
import '../../platform/security/secure_key_store.dart';

/// Current quick-unlock capability and device-local configuration state.
class QuickUnlockStatus {
  const QuickUnlockStatus({
    required this.authenticationAvailability,
    required this.isConfigured,
    required this.authenticationName,
  });

  final DeviceAuthenticationAvailability authenticationAvailability;
  final bool isConfigured;
  final String authenticationName;

  bool get canUse =>
      authenticationAvailability ==
          DeviceAuthenticationAvailability.available &&
      isConfigured;

  bool get canEnable =>
      authenticationAvailability == DeviceAuthenticationAvailability.available;
}

/// Outcome of a quick-unlock attempt that may carry a decrypted Vault payload.
enum QuickUnlockAttemptStatus {
  success,
  cancelled,
  unavailable,
  notConfigured,
  invalidKey,
  failed,
}

/// Result wrapper that never carries the device-protected key itself.
class QuickUnlockAttempt {
  const QuickUnlockAttempt(this.status, {this.payload});

  final QuickUnlockAttemptStatus status;
  final VaultPayload? payload;
}

/// Outcome of enabling quick unlock on the current device.
enum QuickUnlockEnableResult {
  enabled,
  wrongPassword,
  cancelled,
  unavailable,
  failed,
}

/// Coordinates authentication, secure storage, and Vault DEK operations.
class QuickUnlockService {
  const QuickUnlockService({
    required this.repository,
    required this.authentication,
    required this.keyStore,
  });

  /// Active Vault boundary used for password verification and DEK operations.
  final VaultRepository repository;

  /// Current platform device-owner authentication boundary.
  final LocalAuthenticationService authentication;

  /// Current platform secure storage boundary.
  final SecureKeyStore keyStore;

  /// Inspects device authentication and secure-storage configuration.
  Future<QuickUnlockStatus> inspect() async {
    final availability = await authentication.inspect();
    var configured = false;
    try {
      configured = await keyStore.containsQuickUnlockKey();
    } on Object {
      configured = false;
    }
    return QuickUnlockStatus(
      authenticationAvailability: availability,
      isConfigured: configured,
      authenticationName: authentication.displayName,
    );
  }

  /// Enables quick unlock only after master-password and device authentication.
  Future<QuickUnlockEnableResult> enable(String masterPassword) async {
    if (masterPassword.isEmpty ||
        !await _verifyPasswordSafely(masterPassword)) {
      return QuickUnlockEnableResult.wrongPassword;
    }
    final authResult = await authentication.authenticate(
      reason: '启用 TOTP Vault 快速解锁',
    );
    final mapped = _mapEnableAuthentication(authResult);
    if (mapped != null) return mapped;

    Uint8List? keyBytes;
    try {
      final exportedKey = await repository.exportQuickUnlockKey();
      keyBytes = exportedKey;
      await keyStore.writeQuickUnlockKey(exportedKey);
      return QuickUnlockEnableResult.enabled;
    } on Object {
      return QuickUnlockEnableResult.failed;
    } finally {
      _clearBytes(keyBytes);
    }
  }

  /// Authenticates locally and opens the Vault with the protected DEK copy.
  Future<QuickUnlockAttempt> unlock() async {
    final configured = await _containsKeySafely();
    if (!configured) {
      return const QuickUnlockAttempt(QuickUnlockAttemptStatus.notConfigured);
    }
    final authResult = await authentication.authenticate(
      reason: '解锁 TOTP Vault',
    );
    final mapped = _mapAttemptAuthentication(authResult);
    if (mapped != null) return QuickUnlockAttempt(mapped);

    Uint8List? keyBytes;
    try {
      keyBytes = await keyStore.readQuickUnlockKey();
      if (keyBytes == null) {
        return const QuickUnlockAttempt(QuickUnlockAttemptStatus.notConfigured);
      }
      final payload = await repository.unlockWithQuickUnlockKey(keyBytes);
      return QuickUnlockAttempt(
        QuickUnlockAttemptStatus.success,
        payload: payload,
      );
    } on VaultUnlockException {
      // A Vault failure may be caused by damaged encrypted data rather than a
      // stale device key. Keep the only password-independent recovery material.
      return const QuickUnlockAttempt(QuickUnlockAttemptStatus.invalidKey);
    } on FormatException {
      // Automatic deletion is irreversible; only explicit disable may remove
      // device recovery material.
      return const QuickUnlockAttempt(QuickUnlockAttemptStatus.invalidKey);
    } on Object {
      return const QuickUnlockAttempt(QuickUnlockAttemptStatus.failed);
    } finally {
      _clearBytes(keyBytes);
    }
  }

  /// Reauthenticates a sensitive operation without reading or exporting the DEK.
  Future<DeviceAuthenticationResult> reauthenticate({
    required String reason,
  }) async {
    if (!await _containsKeySafely()) {
      return DeviceAuthenticationResult.unavailable;
    }
    return authentication.authenticate(reason: reason);
  }

  /// Removes the device-only quick-unlock material.
  Future<bool> disable() async {
    try {
      await keyStore.deleteQuickUnlockKey();
      return true;
    } on Object {
      return false;
    }
  }

  Future<bool> _verifyPasswordSafely(String password) async {
    try {
      return await repository.verifyPassword(password);
    } on Object {
      return false;
    }
  }

  Future<bool> _containsKeySafely() async {
    try {
      return await keyStore.containsQuickUnlockKey();
    } on Object {
      return false;
    }
  }

  QuickUnlockEnableResult? _mapEnableAuthentication(
    DeviceAuthenticationResult result,
  ) {
    return switch (result) {
      DeviceAuthenticationResult.authenticated => null,
      DeviceAuthenticationResult.cancelled => QuickUnlockEnableResult.cancelled,
      DeviceAuthenticationResult.unavailable =>
        QuickUnlockEnableResult.unavailable,
      DeviceAuthenticationResult.failed => QuickUnlockEnableResult.failed,
    };
  }

  QuickUnlockAttemptStatus? _mapAttemptAuthentication(
    DeviceAuthenticationResult result,
  ) {
    return switch (result) {
      DeviceAuthenticationResult.authenticated => null,
      DeviceAuthenticationResult.cancelled =>
        QuickUnlockAttemptStatus.cancelled,
      DeviceAuthenticationResult.unavailable =>
        QuickUnlockAttemptStatus.unavailable,
      DeviceAuthenticationResult.failed => QuickUnlockAttemptStatus.failed,
    };
  }

  void _clearBytes(Uint8List? bytes) {
    if (bytes == null) return;
    bytes.fillRange(0, bytes.length, 0);
  }
}
