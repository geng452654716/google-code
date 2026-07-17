import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/state/providers.dart';
import 'package:google_code/domain/entities/vault_payload.dart';
import 'package:google_code/domain/repositories/vault_repository.dart';

void main() {
  test(
    'restore replaces visible payload only after repository save succeeds',
    () async {
      final original = VaultPayload.empty(DateTime.utc(2026, 7, 16));
      final replacement = original.copyWith(
        preferences: const {'autoLockMinutes': 30},
        updatedAt: DateTime.utc(2026, 7, 16, 1),
      );
      final repository = _RestoreRepository(original);
      final container = ProviderContainer(
        overrides: [
          vaultRepositoryProvider.overrideWithValue(repository),
          vaultSessionProvider.overrideWith(
            () => _UnlockedController(original),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(vaultSessionProvider.notifier);
      expect(await controller.applyRestoredPayload(replacement), isTrue);
      expect(container.read(vaultSessionProvider).payload, same(replacement));
      expect(repository.saved, same(replacement));
    },
  );

  test('failed restore keeps current Vault payload unchanged', () async {
    final original = VaultPayload.empty(DateTime.utc(2026, 7, 16));
    final replacement = original.copyWith(
      preferences: const {'autoLockMinutes': 30},
    );
    final repository = _RestoreRepository(original)..failSave = true;
    final container = ProviderContainer(
      overrides: [
        vaultRepositoryProvider.overrideWithValue(repository),
        vaultSessionProvider.overrideWith(() => _UnlockedController(original)),
      ],
    );
    addTearDown(container.dispose);

    final success = await container
        .read(vaultSessionProvider.notifier)
        .applyRestoredPayload(replacement);
    expect(success, isFalse);
    expect(container.read(vaultSessionProvider).payload, same(original));
    expect(container.read(vaultSessionProvider).message, contains('未被修改'));
  });
}

class _UnlockedController extends VaultSessionController {
  _UnlockedController(this.payload);

  final VaultPayload payload;

  @override
  VaultSessionState build() =>
      VaultSessionState(phase: VaultSessionPhase.unlocked, payload: payload);
}

class _RestoreRepository implements VaultRepository {
  _RestoreRepository(this.payload);

  VaultPayload payload;
  VaultPayload? saved;
  bool failSave = false;

  @override
  Future<VaultAvailability> inspect() async => VaultAvailability.present;

  @override
  Future<VaultPayload> create(String password) async => payload;

  @override
  Future<VaultPayload> unlock(String password) async => payload;

  @override
  Future<VaultPayload> unlockWithQuickUnlockKey(Uint8List keyBytes) async =>
      throw UnsupportedError('Quick unlock is not used by this test fake.');

  @override
  Future<Uint8List> exportQuickUnlockKey() async =>
      throw UnsupportedError('Quick unlock is not used by this test fake.');

  @override
  Future<bool> verifyPassword(String password) async => true;

  @override
  Future<void> save(VaultPayload payload) async {
    if (failSave) throw StateError('simulated failure');
    saved = payload;
    this.payload = payload;
  }

  @override
  void lock() {}
}
