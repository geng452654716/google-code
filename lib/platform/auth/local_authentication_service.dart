import 'dart:io';

import 'package:local_auth/local_auth.dart';

/// Whether the current desktop can present a device-owner authentication UI.
enum DeviceAuthenticationAvailability { available, notEnrolled, unavailable }

/// Result of one local device authentication request.
enum DeviceAuthenticationResult {
  authenticated,
  cancelled,
  unavailable,
  failed,
}

/// Boundary for Touch ID, Windows Hello, or equivalent device credentials.
abstract interface class LocalAuthenticationService {
  Future<DeviceAuthenticationAvailability> inspect();

  /// Requests fresh local authentication without exposing credential details.
  Future<DeviceAuthenticationResult> authenticate({required String reason});

  /// Platform-appropriate label used in buttons and security explanations.
  String get displayName;
}

/// Official local_auth-backed desktop authentication implementation.
class SystemLocalAuthenticationService implements LocalAuthenticationService {
  SystemLocalAuthenticationService({LocalAuthentication? authentication})
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  String get displayName {
    if (Platform.isMacOS) return 'Touch ID 或设备密码';
    if (Platform.isWindows) return 'Windows Hello';
    return '设备认证';
  }

  @override
  Future<DeviceAuthenticationAvailability> inspect() async {
    if (!Platform.isMacOS && !Platform.isWindows) {
      return DeviceAuthenticationAvailability.unavailable;
    }
    try {
      return await _authentication.isDeviceSupported()
          ? DeviceAuthenticationAvailability.available
          : DeviceAuthenticationAvailability.unavailable;
    } on LocalAuthException catch (error) {
      return _availabilityFor(error.code);
    } on Object {
      return DeviceAuthenticationAvailability.unavailable;
    }
  }

  @override
  Future<DeviceAuthenticationResult> authenticate({
    required String reason,
  }) async {
    try {
      final authenticated = await _authentication.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        sensitiveTransaction: true,
      );
      return authenticated
          ? DeviceAuthenticationResult.authenticated
          : DeviceAuthenticationResult.failed;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.userRequestedFallback =>
          DeviceAuthenticationResult.cancelled,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.uiUnavailable =>
          DeviceAuthenticationResult.unavailable,
        _ => DeviceAuthenticationResult.failed,
      };
    } on Object {
      return DeviceAuthenticationResult.failed;
    }
  }

  DeviceAuthenticationAvailability _availabilityFor(
    LocalAuthExceptionCode code,
  ) {
    return switch (code) {
      LocalAuthExceptionCode.noCredentialsSet ||
      LocalAuthExceptionCode.noBiometricsEnrolled =>
        DeviceAuthenticationAvailability.notEnrolled,
      _ => DeviceAuthenticationAvailability.unavailable,
    };
  }
}
