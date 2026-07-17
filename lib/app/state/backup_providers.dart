import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/backup/backup_service.dart';
import '../../platform/files/backup_file_service.dart';

/// In-memory encrypted backup and restore coordinator.
final backupServiceProvider = Provider<BackupService>((ref) => BackupService());

/// Native file picker and saver isolated behind a testable boundary.
final backupFileServiceProvider = Provider<BackupFileService>(
  (ref) => FileSelectorBackupFileService(),
);
