import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../../application/backup/backup_exception.dart';
import '../../data/backup/backup_crypto_service.dart';

/// Backup bytes selected by the user and retained only in memory.
class PickedBackupFile {
  const PickedBackupFile({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// Display-only result for a user-approved encrypted backup destination.
class SavedBackupFile {
  const SavedBackupFile({required this.path});

  final String path;
}

/// Platform boundary for `.gcbak` import and export dialogs.
abstract interface class BackupFileService {
  Future<SavedBackupFile?> saveBackup(
    Uint8List bytes, {
    required String suggestedName,
  });

  Future<PickedBackupFile?> pickBackup();
}

/// Desktop implementation that never creates a clear or temporary backup file.
class FileSelectorBackupFileService implements BackupFileService {
  static const _backupType = XTypeGroup(
    label: 'TOTP Vault 加密备份',
    extensions: ['gcbak'],
    mimeTypes: ['application/octet-stream'],
  );

  @override
  Future<SavedBackupFile?> saveBackup(
    Uint8List bytes, {
    required String suggestedName,
  }) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: const [_backupType],
      suggestedName: suggestedName,
      confirmButtonText: '保存加密备份',
    );
    if (location == null) return null;
    await File(location.path).writeAsBytes(bytes, flush: true);
    return SavedBackupFile(path: location.path);
  }

  @override
  Future<PickedBackupFile?> pickBackup() async {
    final file = await openFile(
      acceptedTypeGroups: const [_backupType],
      confirmButtonText: '选择备份',
    );
    if (file == null) return null;
    if (await file.length() > BackupCryptoService.maxBackupBytes) {
      throw const BackupException(
        BackupFailureKind.fileTooLarge,
        '备份文件超过 32 MiB 限制。',
      );
    }
    return PickedBackupFile(bytes: await file.readAsBytes(), name: file.name);
  }
}
