import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/google_code_app.dart';
import 'package:google_code/app/state/providers.dart';
import 'package:google_code/domain/entities/vault_payload.dart';
import 'package:google_code/domain/repositories/vault_repository.dart';

void main() {
  testWidgets('renders first-run Vault onboarding', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultRepositoryProvider.overrideWithValue(_MissingVaultRepository()),
        ],
        child: const GoogleCodeApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('创建本地保险库'), findsOneWidget);
    expect(find.text('主密码'), findsOneWidget);
    expect(find.text('创建并进入'), findsOneWidget);
  });
}

/// Minimal first-run repository used to keep widget tests off platform storage.
class _MissingVaultRepository implements VaultRepository {
  @override
  Future<VaultAvailability> inspect() async => VaultAvailability.missing;

  @override
  Future<VaultPayload> create(String password) async =>
      VaultPayload.empty(DateTime.utc(2026, 7, 16));

  @override
  Future<VaultPayload> unlock(String password) async =>
      VaultPayload.empty(DateTime.utc(2026, 7, 16));

  @override
  Future<VaultPayload> unlockWithQuickUnlockKey(Uint8List keyBytes) async =>
      throw UnsupportedError('Quick unlock is not used by this test fake.');

  @override
  Future<Uint8List> exportQuickUnlockKey() async =>
      throw UnsupportedError('Quick unlock is not used by this test fake.');

  @override
  Future<bool> verifyPassword(String password) async => false;

  @override
  Future<void> save(VaultPayload payload) async {}

  @override
  void lock() {}
}
