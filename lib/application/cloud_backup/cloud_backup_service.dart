import '../../domain/entities/vault_payload.dart';
import '../../platform/cloud_backup/cloud_backup_provider.dart';
import '../../platform/files/backup_file_service.dart';
import '../backup/backup_service.dart';

/// Encrypts Vault data before delegating transport to a cloud provider.
class CloudBackupService {
  const CloudBackupService(this._backupService);

  final BackupService _backupService;

  Future<CloudBackupUploadResult?> upload({
    required CloudBackupProvider provider,
    required VaultPayload payload,
    required String password,
  }) async {
    final bytes = await _backupService.export(payload, password);
    try {
      final now = DateTime.now().toUtc();
      String two(int value) => value.toString().padLeft(2, '0');
      final name =
          'TOTP-Vault-${now.year}${two(now.month)}${two(now.day)}-'
          '${two(now.hour)}${two(now.minute)}${two(now.second)}.gcbak';
      return await provider.upload(bytes, suggestedName: name);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<PickedBackupFile?> downloadLatest(CloudBackupProvider provider) =>
      provider.downloadLatest();
}
