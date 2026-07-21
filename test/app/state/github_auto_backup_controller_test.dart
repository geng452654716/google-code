import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/state/providers.dart';
import 'package:google_code/application/backup/backup_service.dart';
import 'package:google_code/application/cloud_backup/cloud_backup_service.dart';
import 'package:google_code/domain/entities/vault_payload.dart';
import 'package:google_code/platform/cloud_backup/cloud_backup_provider.dart';
import 'package:google_code/platform/cloud_backup/github_api_backup_provider.dart';
import 'package:google_code/platform/files/backup_file_service.dart';
import 'package:google_code/platform/security/device_secret_store.dart';

void main() {
  test(
    'enable verifies an upload and stores the password only on device',
    () async {
      final secrets = _MemorySecretStore();
      final github = _FakeGitHubProvider();
      final cloud = _FakeCloudBackupService();
      final container = _container(
        secrets: secrets,
        github: github,
        cloud: cloud,
      );
      addTearDown(container.dispose);
      final controller = container.read(githubAutoBackupProvider.notifier);
      final payload = VaultPayload.empty(DateTime.utc(2026, 7, 21));

      expect(
        await controller.enable(password: 'backup-password', payload: payload),
        isTrue,
      );

      final state = container.read(githubAutoBackupProvider);
      expect(state.isEnabled, isTrue);
      expect(state.lastSuccessfulAt, isNotNull);
      expect(cloud.payloads, [same(payload)]);
      expect(secrets.values, hasLength(1));

      await controller.disable();
      expect(container.read(githubAutoBackupProvider).isEnabled, isFalse);
      expect(secrets.values, isEmpty);
    },
  );

  test(
    'failed verification rolls back the stored auto-backup password',
    () async {
      final secrets = _MemorySecretStore();
      final cloud = _FakeCloudBackupService()..failureMessage = 'upload failed';
      final container = _container(
        secrets: secrets,
        github: _FakeGitHubProvider(),
        cloud: cloud,
      );
      addTearDown(container.dispose);

      final enabled = await container
          .read(githubAutoBackupProvider.notifier)
          .enable(
            password: 'backup-password',
            payload: VaultPayload.empty(DateTime.utc(2026, 7, 21)),
          );

      expect(enabled, isFalse);
      expect(container.read(githubAutoBackupProvider).isEnabled, isFalse);
      expect(secrets.values, isEmpty);
    },
  );

  test(
    'rapid additions are serialized and finish with the newest payload',
    () async {
      final secrets = _MemorySecretStore();
      final cloud = _FakeCloudBackupService();
      final container = _container(
        secrets: secrets,
        github: _FakeGitHubProvider(),
        cloud: cloud,
      );
      addTearDown(container.dispose);
      final controller = container.read(githubAutoBackupProvider.notifier);
      final initial = VaultPayload.empty(DateTime.utc(2026, 7, 21));
      expect(
        await controller.enable(password: 'backup-password', payload: initial),
        isTrue,
      );

      final firstGate = Completer<void>();
      cloud.gates.add(firstGate);
      final first = initial.copyWith(updatedAt: DateTime.utc(2026, 7, 21, 1));
      final newest = initial.copyWith(updatedAt: DateTime.utc(2026, 7, 21, 2));
      final firstRun = controller.scheduleAfterAccountAddition(first);
      await cloud.waitForUploadCount(2);
      await controller.scheduleAfterAccountAddition(newest);
      firstGate.complete();
      await firstRun;

      expect(cloud.payloads, hasLength(3));
      expect(cloud.payloads.last, same(newest));
      expect(cloud.maxConcurrentUploads, 1);
      expect(
        container.read(githubAutoBackupProvider).notification,
        '新增账号已自动备份到 GitHub。',
      );
    },
  );

  test('account addition waits for startup reconciliation', () async {
    final secrets = _MemorySecretStore()
      ..seed('cloud.github.auto-backup-password.v1', 'backup-password');
    final readGate = Completer<void>();
    secrets.readGate = readGate;
    final cloud = _FakeCloudBackupService();
    final container = _container(
      secrets: secrets,
      github: _FakeGitHubProvider(),
      cloud: cloud,
    );
    addTearDown(container.dispose);
    final controller = container.read(githubAutoBackupProvider.notifier);
    final payload = VaultPayload.empty(DateTime.utc(2026, 7, 21));

    final initialization = controller.initialize();
    await secrets.waitForRead();
    final scheduled = controller.scheduleAfterAccountAddition(payload);
    readGate.complete();
    await Future.wait([initialization, scheduled]);

    expect(cloud.payloads, [same(payload)]);
    expect(container.read(githubAutoBackupProvider).isEnabled, isTrue);
  });
}

ProviderContainer _container({
  required _MemorySecretStore secrets,
  required _FakeGitHubProvider github,
  required _FakeCloudBackupService cloud,
}) => ProviderContainer(
  overrides: [
    deviceSecretStoreProvider.overrideWithValue(secrets),
    githubBackupProvider.overrideWithValue(github),
    cloudBackupServiceProvider.overrideWithValue(cloud),
  ],
);

class _MemorySecretStore implements DeviceSecretStore {
  final values = <String, Uint8List>{};
  final _readStarted = Completer<void>();
  Completer<void>? readGate;

  void seed(String key, String value) {
    values[key] = Uint8List.fromList(value.codeUnits);
  }

  Future<void> waitForRead() => _readStarted.future;

  @override
  Future<void> delete(String key) async {
    final value = values.remove(key);
    value?.fillRange(0, value.length, 0);
  }

  @override
  Future<Uint8List?> read(String key) async {
    if (!_readStarted.isCompleted) _readStarted.complete();
    await readGate?.future;
    final value = values[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> write(String key, Uint8List value) async {
    values[key] = Uint8List.fromList(value);
  }
}

class _FakeCloudBackupService extends CloudBackupService {
  _FakeCloudBackupService() : super(BackupService());

  final payloads = <VaultPayload>[];
  final gates = Queue<Completer<void>>();
  final _uploadCountChanged = StreamController<int>.broadcast();
  String? failureMessage;
  int _activeUploads = 0;
  int maxConcurrentUploads = 0;

  @override
  Future<CloudBackupUploadResult?> upload({
    required CloudBackupProvider provider,
    required VaultPayload payload,
    required String password,
  }) async {
    _activeUploads += 1;
    if (_activeUploads > maxConcurrentUploads) {
      maxConcurrentUploads = _activeUploads;
    }
    payloads.add(payload);
    _uploadCountChanged.add(payloads.length);
    try {
      if (gates.isNotEmpty) await gates.removeFirst().future;
      if (failureMessage case final message?) {
        throw CloudBackupException(message);
      }
      return CloudBackupUploadResult(
        provider: CloudBackupProviderType.github,
        destination: 'owner/totp-backup',
        createdAt: DateTime.utc(2026, 7, 21, payloads.length),
      );
    } finally {
      _activeUploads -= 1;
    }
  }

  Future<void> waitForUploadCount(int count) async {
    if (payloads.length >= count) return;
    await _uploadCountChanged.stream.firstWhere((value) => value >= count);
  }
}

class _FakeGitHubProvider implements GitHubCloudBackupProvider {
  @override
  bool get isConfigured => true;

  @override
  CloudBackupProviderInfo get info => const CloudBackupProviderInfo(
    type: CloudBackupProviderType.github,
    title: 'GitHub',
    description: 'test',
    iconName: 'code',
  );

  @override
  Future<GitHubConnectionState> connectionState() async =>
      const GitHubConnectionState(
        isConnected: true,
        repository: 'owner/totp-backup',
      );

  @override
  Future<void> disconnect() async {}

  @override
  Future<PickedBackupFile?> downloadLatest() async => null;

  @override
  Future<void> finishAuthorization(
    GitHubDeviceCode code, {
    GitHubAuthorizationCancellation? cancellation,
  }) async {}

  @override
  Future<List<GitHubBackupRepository>> listRepositories() async => const [];

  @override
  Future<void> selectRepository(GitHubBackupRepository repository) async {}

  @override
  Future<GitHubDeviceCode> startAuthorization() => throw UnimplementedError();

  @override
  Future<CloudBackupUploadResult?> upload(
    Uint8List encryptedBackup, {
    required String suggestedName,
  }) async => null;
}
