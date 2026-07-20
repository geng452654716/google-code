import 'dart:io';

import 'vault_envelope.dart';

/// Persists the encrypted vault with atomic replacement and backup recovery.
class VaultFileStore {
  const VaultFileStore(this.file);

  final File file;

  File get _temporaryFile => File('${file.path}.tmp');
  File get _backupFile => File('${file.path}.bak');

  /// Whether the primary encrypted file exists.
  Future<bool> primaryExists() => file.exists();

  /// Whether the automatic encrypted recovery copy exists.
  Future<bool> backupExists() => _backupFile.exists();

  /// Whether either the primary Vault or its recovery backup exists.
  Future<bool> exists() async =>
      await file.exists() || await _backupFile.exists();

  /// Writes a complete envelope, retaining the previous valid file as `.bak`.
  Future<void> write(VaultEnvelope envelope) async {
    await file.parent.create(recursive: true);
    final temporary = _temporaryFile;
    await temporary.writeAsString(envelope.encode(), flush: true);

    if (await file.exists()) {
      await file.copy(_backupFile.path);
    }
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }

  /// Writes a Vault opened from `.bak` without replacing that known-good copy.
  ///
  /// The existing primary may be corrupt, so rotating it into `.bak` here would
  /// destroy the recovery source that made the current session possible.
  Future<void> writeRecovered(VaultEnvelope envelope) async {
    await file.parent.create(recursive: true);
    final temporary = _temporaryFile;
    await temporary.writeAsString(envelope.encode(), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }

  /// Decodes only the primary encrypted Vault.
  Future<VaultEnvelope> readPrimary() async {
    return VaultEnvelope.decode(await file.readAsString());
  }

  /// Decodes only the automatic encrypted recovery copy.
  Future<VaultEnvelope> readBackup() async {
    return VaultEnvelope.decode(await _backupFile.readAsString());
  }

  /// Reads the primary vault and falls back to `.bak` if it is malformed.
  Future<VaultEnvelope> read() async {
    try {
      return VaultEnvelope.decode(await file.readAsString());
    } on Object {
      if (await _backupFile.exists()) {
        return VaultEnvelope.decode(await _backupFile.readAsString());
      }
      rethrow;
    }
  }
}
