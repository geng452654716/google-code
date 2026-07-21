import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/platform/cloud_backup/cloud_backup_provider.dart';
import 'package:google_code/platform/cloud_backup/synced_folder_cloud_backup_provider.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('totp-cloud-folder-');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('writes a timestamped version and latest copy', () async {
    final provider = _provider(
      directory.path,
      now: () => DateTime.utc(2026, 7, 21, 8, 9, 10),
    );
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    final result = await provider.upload(bytes, suggestedName: 'ignored.gcbak');

    expect(result?.destination, directory.path);
    expect(
      File(
        '${directory.path}/TOTP-Vault-20260721-080910.gcbak',
      ).readAsBytesSync(),
      bytes,
    );
    expect(
      File(
        '${directory.path}/${SyncedFolderCloudBackupProvider.latestFileName}',
      ).readAsBytesSync(),
      bytes,
    );
    expect(
      directory.listSync().whereType<File>().any(
        (file) => file.path.endsWith('.uploading'),
      ),
      isFalse,
    );
  });

  test('keeps only the configured number of timestamped versions', () async {
    for (var index = 0; index < 5; index++) {
      File(
        '${directory.path}/TOTP-Vault-20260721-08090$index.gcbak',
      ).writeAsBytesSync([index]);
    }
    final provider = _provider(
      directory.path,
      maxVersions: 3,
      now: () => DateTime.utc(2026, 7, 21, 8, 10),
    );

    await provider.upload(Uint8List.fromList([9]), suggestedName: 'new.gcbak');

    final versions = directory
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where(
          (name) =>
              name.startsWith('TOTP-Vault-') &&
              name != SyncedFolderCloudBackupProvider.latestFileName,
        )
        .toList();
    expect(versions, hasLength(3));
    expect(versions, contains('TOTP-Vault-20260721-081000.gcbak'));
  });

  test('downloads the most recently modified encrypted backup', () async {
    final older = File('${directory.path}/older.gcbak')
      ..writeAsBytesSync([1, 2]);
    final newest = File('${directory.path}/newest.gcbak')
      ..writeAsBytesSync([3, 4]);
    older.setLastModifiedSync(DateTime.utc(2026, 7, 20));
    newest.setLastModifiedSync(DateTime.utc(2026, 7, 21));

    final backup = await _provider(directory.path).downloadLatest();

    expect(backup?.name, 'iCloud Drive / newest.gcbak');
    expect(backup?.bytes, [3, 4]);
  });

  test('returns null when directory selection is cancelled', () async {
    final provider = SyncedFolderCloudBackupProvider(
      info: _info,
      directoryPicker: ({confirmButtonText}) async => null,
    );

    expect(
      await provider.upload(Uint8List.fromList([1]), suggestedName: 'x'),
      isNull,
    );
    expect(await provider.downloadLatest(), isNull);
  });

  test('reports an empty selected directory', () async {
    await expectLater(
      _provider(directory.path).downloadLatest(),
      throwsA(
        isA<CloudBackupException>().having(
          (error) => error.message,
          'message',
          contains('没有找到加密备份'),
        ),
      ),
    );
  });
}

const _info = CloudBackupProviderInfo(
  type: CloudBackupProviderType.iCloudDrive,
  title: 'iCloud Drive',
  description: 'test',
  iconName: 'cloud',
);

SyncedFolderCloudBackupProvider _provider(
  String path, {
  DateTime Function()? now,
  int maxVersions = 30,
}) => SyncedFolderCloudBackupProvider(
  info: _info,
  directoryPicker: ({confirmButtonText}) async => path,
  now: now,
  maxVersions: maxVersions,
);
