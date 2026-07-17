/// Stable failure categories for encrypted backup operations.
enum BackupFailureKind {
  invalidFormat,
  unsupportedVersion,
  invalidPasswordOrCorrupted,
  invalidPayload,
  fileTooLarge,
}

/// User-safe backup exception that never contains passwords or decrypted data.
class BackupException implements Exception {
  const BackupException(this.kind, this.message);

  final BackupFailureKind kind;
  final String message;

  @override
  String toString() => 'BackupException($kind): $message';
}
