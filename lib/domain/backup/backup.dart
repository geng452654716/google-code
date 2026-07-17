import '../entities/vault_payload.dart';

/// How decrypted backup contents should be applied to the current Vault.
enum BackupRestoreMode { merge, replace }

/// Non-sensitive aggregate information shown before restore is committed.
class BackupRestoreSummary {
  const BackupRestoreSummary({
    required this.accountCount,
    required this.groupCount,
    required this.newAccountCount,
    required this.exactDuplicateCount,
    required this.conflictCount,
  });

  final int accountCount;
  final int groupCount;
  final int newAccountCount;
  final int exactDuplicateCount;
  final int conflictCount;
}

/// Temporary decrypted restore model; callers must release it after use.
class BackupRestorePreview {
  const BackupRestorePreview({
    required this.backupCreatedAt,
    required this.payload,
    required this.summary,
  });

  final DateTime backupCreatedAt;

  /// Sensitive payload held only while the restore preview remains visible.
  final VaultPayload payload;

  final BackupRestoreSummary summary;
}

/// Result prepared for one atomic save through the active Vault repository.
class BackupRestoreResult {
  const BackupRestoreResult({
    required this.payload,
    required this.mode,
    required this.addedAccountCount,
    required this.skippedDuplicateCount,
    required this.conflictCount,
  });

  final VaultPayload payload;
  final BackupRestoreMode mode;
  final int addedAccountCount;
  final int skippedDuplicateCount;
  final int conflictCount;
}
