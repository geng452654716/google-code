import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/google_code_app.dart';
import 'package:google_code/app/state/providers.dart';
import 'package:google_code/domain/entities/vault_payload.dart';
import 'package:google_code/domain/repositories/vault_repository.dart';
import 'package:google_code/platform/auth/local_authentication_service.dart';
import 'package:google_code/platform/security/secure_key_store.dart';
import 'package:google_code/platform/session/system_session_event_service.dart';

void main() {
  testWidgets(
    'system lock removes an open sensitive dialog and locks only once',
    (tester) async {
      final repository = _SystemLockRepository();
      final sessionEvents = _FakeSystemSessionEventService();
      addTearDown(sessionEvents.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultRepositoryProvider.overrideWithValue(repository),
            systemSessionEventServiceProvider.overrideWithValue(sessionEvents),
            localAuthenticationServiceProvider.overrideWithValue(
              _UnavailableAuthentication(),
            ),
            secureKeyStoreProvider.overrideWithValue(_EmptySecureKeyStore()),
          ],
          child: const GoogleCodeApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TOTP Vault 已锁定'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'password123');
      await tester.tap(find.widgetWithText(FilledButton, '解锁'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-security-settings')));
      await tester.pump();
      expect(find.text('安全设置'), findsOneWidget);

      sessionEvents.emit(SystemSessionEvent.screenLocked);
      await tester.pump();

      expect(find.text('安全设置'), findsNothing);
      expect(find.text('TOTP Vault 已锁定'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('open-security-settings')),
        findsNothing,
      );
      expect(repository.lockCount, 1);

      sessionEvents.emit(SystemSessionEvent.systemSleeping);
      await tester.pump();
      expect(repository.lockCount, 1);
    },
  );
}

/// In-memory unlocked Vault used to verify repository key cleanup is requested.
class _SystemLockRepository implements VaultRepository {
  final payload = VaultPayload.empty(DateTime.utc(2026, 7, 17));
  int lockCount = 0;

  @override
  Future<VaultAvailability> inspect() async => VaultAvailability.present;

  @override
  Future<VaultPayload> create(String password) async => payload;

  @override
  Future<VaultPayload> unlock(String password) async => payload;

  @override
  Future<VaultPayload> unlockWithQuickUnlockKey(Uint8List keyBytes) async =>
      payload;

  @override
  Future<Uint8List> exportQuickUnlockKey() async => Uint8List(32);

  @override
  Future<bool> verifyPassword(String password) async => true;

  @override
  Future<void> save(VaultPayload payload) async {}

  @override
  void lock() {
    lockCount += 1;
  }
}

/// Native event fake that emits synchronously like the production service.
class _FakeSystemSessionEventService implements SystemSessionEventService {
  final _controller = StreamController<SystemSessionEvent>.broadcast(
    sync: true,
  );
  bool _isDisposed = false;

  @override
  Stream<SystemSessionEvent> get events => _controller.stream;

  @override
  Future<void> start() async {}

  /// Publishes a system event without invoking a desktop platform channel.
  void emit(SystemSessionEvent event) {
    if (!_isDisposed) _controller.add(event);
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _controller.close();
  }
}

/// Keeps the security dialog off local_auth platform channels in widget tests.
class _UnavailableAuthentication implements LocalAuthenticationService {
  @override
  String get displayName => '设备认证';

  @override
  Future<DeviceAuthenticationAvailability> inspect() async =>
      DeviceAuthenticationAvailability.unavailable;

  @override
  Future<DeviceAuthenticationResult> authenticate({
    required String reason,
  }) async => DeviceAuthenticationResult.unavailable;
}

/// Empty device store used while the security settings dialog inspects status.
class _EmptySecureKeyStore implements SecureKeyStore {
  @override
  Future<bool> containsQuickUnlockKey() async => false;

  @override
  Future<Uint8List?> readQuickUnlockKey() async => null;

  @override
  Future<void> writeQuickUnlockKey(Uint8List keyBytes) async {}

  @override
  Future<void> deleteQuickUnlockKey() async {}
}
