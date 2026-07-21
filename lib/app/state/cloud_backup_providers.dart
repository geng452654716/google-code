import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/cloud_backup/cloud_backup_service.dart';
import '../../platform/cloud_backup/cloud_backup_provider.dart';
import '../../platform/cloud_backup/external_url_launcher.dart';
import '../../platform/cloud_backup/github_api_backup_provider.dart';
import '../../platform/cloud_backup/synced_folder_cloud_backup_provider.dart';
import '../../platform/security/device_secret_store.dart';
import 'backup_providers.dart';

final cloudBackupServiceProvider = Provider<CloudBackupService>(
  (ref) => CloudBackupService(ref.watch(backupServiceProvider)),
);

final deviceSecretStoreProvider = Provider<DeviceSecretStore>(
  (ref) => const MethodChannelDeviceSecretStore(),
);

final externalUrlLauncherProvider = Provider<ExternalUrlLauncher>(
  (ref) => const DesktopExternalUrlLauncher(),
);

final iCloudDriveBackupProvider = Provider<CloudBackupProvider>(
  (ref) => SyncedFolderCloudBackupProvider(
    info: const CloudBackupProviderInfo(
      type: CloudBackupProviderType.iCloudDrive,
      title: 'iCloud Drive',
      description: '选择 iCloud Drive 中的目录，由 macOS 或 iCloud 客户端同步',
      iconName: 'cloud',
    ),
  ),
);

final googleDriveBackupProvider = Provider<CloudBackupProvider>(
  (ref) => SyncedFolderCloudBackupProvider(
    info: const CloudBackupProviderInfo(
      type: CloudBackupProviderType.googleDrive,
      title: 'Google Drive',
      description: '选择 Google Drive 桌面版同步目录，不向应用提供 Google 密码',
      iconName: 'drive',
    ),
  ),
);

final githubBackupProvider = Provider<GitHubCloudBackupProvider>(
  (ref) => GitHubApiBackupProvider(
    secretStore: ref.watch(deviceSecretStoreProvider),
  ),
);

final cloudBackupProvidersProvider = Provider<List<CloudBackupProvider>>(
  (ref) => [
    ref.watch(iCloudDriveBackupProvider),
    ref.watch(googleDriveBackupProvider),
    ref.watch(githubBackupProvider),
  ],
);
