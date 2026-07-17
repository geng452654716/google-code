import 'dart:typed_data';

import '../entities/vault_payload.dart';

/// Whether an encrypted Vault already exists on the current device.
enum VaultAvailability { missing, present }

/// Persistence boundary for the currently unlocked encrypted Vault.
abstract interface class VaultRepository {
  Future<VaultAvailability> inspect();

  Future<VaultPayload> create(String password);

  Future<VaultPayload> unlock(String password);

  /// Unlocks the current Vault with a device-protected DEK copy.
  Future<VaultPayload> unlockWithQuickUnlockKey(Uint8List keyBytes);

  /// Exports a short-lived copy of the active DEK for device secure storage.
  Future<Uint8List> exportQuickUnlockKey();

  /// Verifies [password] without replacing the current unlocked Vault session.
  Future<bool> verifyPassword(String password);

  Future<void> save(VaultPayload payload);

  void lock();
}
