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

void main() {
  testWidgets('shows configured device authentication and unlocks the Vault', (
    tester,
  ) async {
    final repository = _LockedQuickUnlockRepository();
    final authentication = _QuickUnlockAuthentication();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultRepositoryProvider.overrideWithValue(repository),
          localAuthenticationServiceProvider.overrideWithValue(authentication),
          secureKeyStoreProvider.overrideWithValue(_ConfiguredKeyStore()),
        ],
        child: const GoogleCodeApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TOTP Vault 已锁定'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-unlock-button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quick-unlock-button')));
    await tester.pumpAndSettle();

    expect(find.text('还没有验证码账号'), findsOneWidget);
    expect(repository.quickUnlockCount, 1);
    expect(authentication.authenticateCount, 1);
  });
}

class _LockedQuickUnlockRepository implements VaultRepository {
  final payload = VaultPayload.empty(DateTime.utc(2026, 7, 16));
  int quickUnlockCount = 0;

  @override
  Future<VaultAvailability> inspect() async => VaultAvailability.present;

  @override
  Future<VaultPayload> create(String password) async => payload;

  @override
  Future<VaultPayload> unlock(String password) async => payload;

  @override
  Future<VaultPayload> unlockWithQuickUnlockKey(Uint8List keyBytes) async {
    quickUnlockCount += 1;
    return payload;
  }

  @override
  Future<Uint8List> exportQuickUnlockKey() async => Uint8List(32);

  @override
  Future<bool> verifyPassword(String password) async => true;

  @override
  Future<void> save(VaultPayload payload) async {}

  @override
  void lock() {}
}

class _QuickUnlockAuthentication implements LocalAuthenticationService {
  int authenticateCount = 0;

  @override
  String get displayName => 'Test Device Auth';

  @override
  Future<DeviceAuthenticationAvailability> inspect() async =>
      DeviceAuthenticationAvailability.available;

  @override
  Future<DeviceAuthenticationResult> authenticate({
    required String reason,
  }) async {
    authenticateCount += 1;
    return DeviceAuthenticationResult.authenticated;
  }
}

class _ConfiguredKeyStore implements SecureKeyStore {
  @override
  Future<bool> containsQuickUnlockKey() async => true;

  @override
  Future<Uint8List?> readQuickUnlockKey() async => Uint8List(32);

  @override
  Future<void> writeQuickUnlockKey(Uint8List keyBytes) async {}

  @override
  Future<void> deleteQuickUnlockKey() async {}
}
