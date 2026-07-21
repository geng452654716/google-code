import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../../data/backup/backup_crypto_service.dart';
import '../files/backup_file_service.dart';
import 'cloud_backup_provider.dart';

typedef DirectoryPicker = Future<String?> Function({String? confirmButtonText});

/// Stores encrypted backups in a user-selected cloud-synced directory.
///
/// iCloud Drive and Google Drive desktop clients remain responsible for account
/// login and synchronization; TOTP Vault never receives their credentials.
class SyncedFolderCloudBackupProvider implements CloudBackupProvider {
  SyncedFolderCloudBackupProvider({
    required this.info,
    DirectoryPicker? directoryPicker,
    DateTime Function()? now,
    this.maxVersions = 30,
  }) : _directoryPicker = directoryPicker ?? getDirectoryPath,
       _now = now ?? (() => DateTime.now().toUtc());

  @override
  final CloudBackupProviderInfo info;

  final DirectoryPicker _directoryPicker;
  final DateTime Function() _now;
  final int maxVersions;

  static const latestFileName = 'TOTP-Vault-latest.gcbak';
  static const _versionPrefix = 'TOTP-Vault-';
  static const _temporarySuffix = '.uploading';

  @override
  Future<CloudBackupUploadResult?> upload(
    Uint8List encryptedBackup, {
    required String suggestedName,
  }) async {
    final path = await _directoryPicker(confirmButtonText: '选择云备份目录');
    if (path == null) return null;
    final directory = Directory(path);
    try {
      if (!await directory.exists()) {
        throw const CloudBackupException('所选同步目录不存在。');
      }
      final now = _now().toUtc();
      final versionName = _versionFileName(now);
      await _atomicWrite(
        File('${directory.path}/$versionName'),
        encryptedBackup,
      );
      await _atomicWrite(
        File('${directory.path}/$latestFileName'),
        encryptedBackup,
      );
      await _pruneVersions(directory);
      return CloudBackupUploadResult(
        provider: info.type,
        destination: directory.path,
        createdAt: now,
      );
    } on CloudBackupException {
      rethrow;
    } on FileSystemException {
      throw CloudBackupException('无法写入 ${info.title} 同步目录，请确认目录已下载到本机且具有写入权限。');
    }
  }

  @override
  Future<PickedBackupFile?> downloadLatest() async {
    final path = await _directoryPicker(confirmButtonText: '选择云备份目录');
    if (path == null) return null;
    final directory = Directory(path);
    try {
      final candidates = await _backupFiles(directory);
      if (candidates.isEmpty) {
        throw CloudBackupException('${info.title} 目录中没有找到加密备份。');
      }
      candidates.sort((left, right) {
        final modified = right.modified.compareTo(left.modified);
        return modified != 0 ? modified : right.name.compareTo(left.name);
      });
      final selected = candidates.first;
      if (selected.length > BackupCryptoService.maxBackupBytes) {
        throw const CloudBackupException('云端备份超过 32 MiB 限制。');
      }
      return PickedBackupFile(
        bytes: await File(selected.path).readAsBytes(),
        name: '${info.title} / ${selected.name}',
      );
    } on CloudBackupException {
      rethrow;
    } on FileSystemException {
      throw CloudBackupException('无法读取 ${info.title} 同步目录，请确认云盘客户端已经完成同步。');
    }
  }

  Future<void> _atomicWrite(File target, Uint8List bytes) async {
    final temporary = File('${target.path}$_temporarySuffix');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  Future<List<_BackupFileMetadata>> _backupFiles(Directory directory) async {
    if (!await directory.exists()) return const [];
    final files = <_BackupFileMetadata>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.gcbak')) continue;
      final stat = await entity.stat();
      files.add(
        _BackupFileMetadata(
          path: entity.path,
          name: name,
          length: stat.size,
          modified: stat.modified.toUtc(),
        ),
      );
    }
    return files;
  }

  Future<void> _pruneVersions(Directory directory) async {
    if (maxVersions < 1) return;
    final files =
        (await _backupFiles(directory))
            .where(
              (file) =>
                  file.name.startsWith(_versionPrefix) &&
                  file.name != latestFileName,
            )
            .toList()
          ..sort((left, right) => right.name.compareTo(left.name));
    for (final expired in files.skip(maxVersions)) {
      await File(expired.path).delete();
    }
  }

  String _versionFileName(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '$_versionPrefix${value.year}${two(value.month)}${two(value.day)}-'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}.gcbak';
  }
}

class _BackupFileMetadata {
  const _BackupFileMetadata({
    required this.path,
    required this.name,
    required this.length,
    required this.modified,
  });

  final String path;
  final String name;
  final int length;
  final DateTime modified;
}
