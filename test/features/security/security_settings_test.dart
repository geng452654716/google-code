import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/state/providers.dart';
import 'package:google_code/domain/entities/vault_payload.dart';
import 'package:google_code/domain/repositories/vault_repository.dart';
import 'package:google_code/features/security/security_settings_dialog.dart';
import 'package:google_code/platform/auth/local_authentication_service.dart';
import 'package:google_code/platform/security/secure_key_store.dart';

void main() {
  testWidgets(
    'requires the master password, enables quick unlock, and can disable it',
    (tester) async {
      final repository = _SecurityRepository();
      final authentication = _SecurityAuthentication();
      final keyStore = _SecurityKeyStore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultRepositoryProvider.overrideWithValue(repository),
            localAuthenticationServiceProvider.overrideWithValue(
              authentication,
            ),
            secureKeyStoreProvider.overrideWithValue(keyStore),
          ],
          child: const MaterialApp(home: _SecuritySettingsLauncher()),
        ),
      );

      await tester.tap(find.text('打开安全设置'));
      await tester.pumpAndSettle();

      expect(find.text('快速解锁未启用'), findsOneWidget);
      expect(find.byKey(const ValueKey('enable-quick-unlock')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('quick-unlock-master-password')),
        'wrong-password',
      );
      await tester.tap(find.byKey(const ValueKey('enable-quick-unlock')));
      await tester.pumpAndSettle();

      expect(find.text('主密码错误，未启用快速解锁。'), findsOneWidget);
      expect(authentication.authenticateCount, 0);
      expect(keyStore.stored, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('quick-unlock-master-password')),
        'password123',
      );
      await tester.tap(find.byKey(const ValueKey('enable-quick-unlock')));
      await tester.pumpAndSettle();

      expect(find.text('快速解锁已启用'), findsOneWidget);
      expect(find.text('快速解锁已在当前设备启用。'), findsOneWidget);
      expect(authentication.authenticateCount, 1);
      expect(keyStore.stored, repository.expectedKey);
      expect(repository.exportedReference, everyElement(0));

      await tester.tap(find.byKey(const ValueKey('disable-quick-unlock')));
      await tester.pumpAndSettle();

      expect(find.text('快速解锁未启用'), findsOneWidget);
      expect(find.text('当前设备的快速解锁材料已删除。'), findsOneWidget);
      expect(keyStore.stored, isNull);
      expect(keyStore.deleteCount, 1);
    },
  );
}

/// Opens the production dialog through a real modal route.
class _SecuritySettingsLauncher extends StatelessWidget {
  const _SecuritySettingsLauncher();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const SecuritySettingsDialog(),
          ),
          child: const Text('打开安全设置'),
        ),
      ),
    );
  }
}

/// Vault boundary that exposes one deterministic DEK for enablement tests.
class _SecurityRepository implements VaultRepository {
  final payload = VaultPayload.empty(DateTime.utc(2026, 7, 16));
  final expectedKey = List<int>.generate(32, (index) => index);

  Uint8List? exportedReference;

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
  Future<Uint8List> exportQuickUnlockKey() async =>
      exportedReference = Uint8List.fromList(expectedKey);

  @override
  Future<bool> verifyPassword(String password) async =>
      password == 'password123';

  @override
  Future<void> save(VaultPayload payload) async {}

  @override
  void lock() {}
}

/// Device authentication fake that records whether a challenge was presented.
class _SecurityAuthentication implements LocalAuthenticationService {
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

/// In-memory secure store that copies bytes before the service clears its DEK.
class _SecurityKeyStore implements SecureKeyStore {
  Uint8List? stored;
  int deleteCount = 0;

  @override
  Future<bool> containsQuickUnlockKey() async => stored != null;

  @override
  Future<Uint8List?> readQuickUnlockKey() async =>
      stored == null ? null : Uint8List.fromList(stored!);

  @override
  Future<void> writeQuickUnlockKey(Uint8List keyBytes) async {
    stored = Uint8List.fromList(keyBytes);
  }

  @override
  Future<void> deleteQuickUnlockKey() async {
    stored?.fillRange(0, stored!.length, 0);
    stored = null;
    deleteCount += 1;
  }
}
