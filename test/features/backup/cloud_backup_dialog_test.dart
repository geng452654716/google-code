import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/state/providers.dart';
import 'package:google_code/domain/entities/vault_payload.dart';
import 'package:google_code/features/backup/cloud_backup_dialog.dart';
import 'package:google_code/platform/cloud_backup/cloud_backup_provider.dart';
import 'package:google_code/platform/cloud_backup/external_url_launcher.dart';
import 'package:google_code/platform/cloud_backup/github_api_backup_provider.dart';
import 'package:google_code/platform/files/backup_file_service.dart';
import 'package:google_code/platform/security/device_secret_store.dart';

void main() {
  testWidgets('shows all providers and disables an unconfigured GitHub app', (
    tester,
  ) async {
    final github = _FakeGitHubProvider(configured: false);
    await _pumpDialog(tester, github: github);

    expect(find.text('iCloud Drive'), findsOneWidget);
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(
      find.textContaining('当前安装包未配置 GitHub App Client ID'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('github-connect')), findsNothing);
  });

  testWidgets('authorizes a GitHub account and selects a private repository', (
    tester,
  ) async {
    final github = _FakeGitHubProvider(configured: true);
    final launcher = _FakeLauncher();
    await _pumpDialog(tester, github: github, launcher: launcher);

    await tester.tap(find.byKey(const ValueKey('github-connect')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('github-device-code')), findsOneWidget);
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    expect(launcher.opened, [Uri.parse('https://github.com/login/device')]);

    github.authorization.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('owner/totp-backup'), findsOneWidget);
    await tester.tap(find.text('owner/totp-backup'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(github.selectedRepository, 'owner/totp-backup');
    expect(find.textContaining('当前仓库：owner/totp-backup'), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud-upload-github')), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud-restore-github')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('github-auto-backup-switch')),
      findsOneWidget,
    );
  });

  testWidgets('Vault lock closes and cancels GitHub authorization', (
    tester,
  ) async {
    final github = _FakeGitHubProvider(configured: true);
    final container = await _pumpDialog(tester, github: github);

    await tester.tap(find.byKey(const ValueKey('github-connect')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('github-device-code')), findsOneWidget);

    _lockVault(container);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(github.authorizationCancellation?.isCancelled, isTrue);
    expect(find.byKey(const ValueKey('github-device-code')), findsNothing);
    expect(find.byType(CloudBackupDialog), findsNothing);
    github.authorization.complete();
    await tester.pump();
  });

  testWidgets('auto-backup switch requests and validates a device password', (
    tester,
  ) async {
    final github = _FakeGitHubProvider(configured: true)
      ..connected = true
      ..selectedRepository = 'owner/totp-backup';
    await _pumpDialog(tester, github: github);

    await tester.tap(find.byKey(const ValueKey('github-auto-backup-switch')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('github-auto-backup-password')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('github-auto-backup-password')),
      'short',
    );
    await tester.enterText(
      find.byKey(const ValueKey('github-auto-backup-password-confirmation')),
      'short',
    );
    await tester.tap(
      find.byKey(const ValueKey('github-auto-backup-enable-submit')),
    );
    await tester.pump();

    expect(find.text('自动备份密码至少需要 8 个字符。'), findsOneWidget);
  });

  testWidgets('Vault lock clears and closes the backup password dialog', (
    tester,
  ) async {
    final github = _FakeGitHubProvider(configured: false);
    final container = await _pumpDialog(tester, github: github);

    await tester.tap(find.byKey(const ValueKey('cloud-upload-iCloudDrive')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('cloud-backup-password')),
      'backup-password',
    );
    await tester.enterText(
      find.byKey(const ValueKey('cloud-backup-password-confirmation')),
      'backup-password',
    );

    _lockVault(container);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('cloud-backup-password')), findsNothing);
    expect(find.byType(CloudBackupDialog), findsNothing);
  });

  testWidgets('Vault lock closes the GitHub repository selector', (
    tester,
  ) async {
    final github = _FakeGitHubProvider(configured: true)..connected = true;
    final container = await _pumpDialog(tester, github: github);

    await tester.tap(find.byKey(const ValueKey('github-select-repository')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('选择 GitHub 私有仓库'), findsOneWidget);

    _lockVault(container);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('选择 GitHub 私有仓库'), findsNothing);
    expect(find.byType(CloudBackupDialog), findsNothing);
  });
}

Future<ProviderContainer> _pumpDialog(
  WidgetTester tester, {
  required _FakeGitHubProvider github,
  ExternalUrlLauncher? launcher,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 960));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final iCloud = _FakeCloudProvider(
    const CloudBackupProviderInfo(
      type: CloudBackupProviderType.iCloudDrive,
      title: 'iCloud Drive',
      description: 'iCloud test',
      iconName: 'cloud',
    ),
  );
  final google = _FakeCloudProvider(
    const CloudBackupProviderInfo(
      type: CloudBackupProviderType.googleDrive,
      title: 'Google Drive',
      description: 'Google test',
      iconName: 'drive',
    ),
  );
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vaultSessionProvider.overrideWith(
          () => _UnlockedCloudBackupController(
            VaultPayload.empty(DateTime.utc(2026, 7, 21)),
          ),
        ),
        githubBackupProvider.overrideWithValue(github),
        deviceSecretStoreProvider.overrideWithValue(_EmptySecretStore()),
        externalUrlLauncherProvider.overrideWithValue(
          launcher ?? _FakeLauncher(),
        ),
        cloudBackupProvidersProvider.overrideWithValue([
          iCloud,
          google,
          github,
        ]),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  key: const ValueKey('open-cloud-backup'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const CloudBackupDialog(),
                  ),
                  child: const Text('打开云备份'),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-cloud-backup')));
  await tester.pumpAndSettle();
  return container;
}

void _lockVault(ProviderContainer container) {
  final controller =
      container.read(vaultSessionProvider.notifier)
          as _UnlockedCloudBackupController;
  controller.forceLock();
}

class _UnlockedCloudBackupController extends VaultSessionController {
  _UnlockedCloudBackupController(this.payload);

  final VaultPayload payload;

  @override
  VaultSessionState build() =>
      VaultSessionState(phase: VaultSessionPhase.unlocked, payload: payload);

  /// Simulates auto-lock without invoking a repository in widget tests.
  void forceLock() {
    state = const VaultSessionState(phase: VaultSessionPhase.locked);
  }
}

class _FakeCloudProvider implements CloudBackupProvider {
  const _FakeCloudProvider(this.info);

  @override
  final CloudBackupProviderInfo info;

  @override
  Future<PickedBackupFile?> downloadLatest() async => null;

  @override
  Future<CloudBackupUploadResult?> upload(
    Uint8List encryptedBackup, {
    required String suggestedName,
  }) async => null;
}

class _FakeGitHubProvider implements GitHubCloudBackupProvider {
  _FakeGitHubProvider({required this.configured});

  final bool configured;
  final authorization = Completer<void>();
  GitHubAuthorizationCancellation? authorizationCancellation;
  bool connected = false;
  String? selectedRepository;

  @override
  bool get isConfigured => configured;

  @override
  CloudBackupProviderInfo get info => const CloudBackupProviderInfo(
    type: CloudBackupProviderType.github,
    title: 'GitHub',
    description: 'GitHub test',
    iconName: 'code',
  );

  @override
  Future<GitHubConnectionState> connectionState() async =>
      GitHubConnectionState(
        isConnected: connected,
        repository: selectedRepository,
      );

  @override
  Future<void> disconnect() async {
    connected = false;
    selectedRepository = null;
  }

  @override
  Future<PickedBackupFile?> downloadLatest() async => null;

  @override
  Future<void> finishAuthorization(
    GitHubDeviceCode code, {
    GitHubAuthorizationCancellation? cancellation,
  }) async {
    authorizationCancellation = cancellation;
    await authorization.future;
    if (cancellation?.isCancelled ?? false) {
      throw const CloudBackupException('cancelled');
    }
    connected = true;
  }

  @override
  Future<List<GitHubBackupRepository>> listRepositories() async => const [
    GitHubBackupRepository(
      id: 1,
      fullName: 'owner/totp-backup',
      isPrivate: true,
    ),
  ];

  @override
  Future<void> selectRepository(GitHubBackupRepository repository) async {
    selectedRepository = repository.fullName;
  }

  @override
  Future<GitHubDeviceCode> startAuthorization() async => GitHubDeviceCode(
    deviceCode: 'device-code',
    userCode: 'ABCD-EFGH',
    verificationUri: Uri.parse('https://github.com/login/device'),
    expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    interval: const Duration(seconds: 5),
  );

  @override
  Future<CloudBackupUploadResult?> upload(
    Uint8List encryptedBackup, {
    required String suggestedName,
  }) async => null;
}

class _FakeLauncher implements ExternalUrlLauncher {
  final opened = <Uri>[];

  @override
  Future<void> open(Uri uri) async => opened.add(uri);
}

class _EmptySecretStore implements DeviceSecretStore {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<Uint8List?> read(String key) async => null;

  @override
  Future<void> write(String key, Uint8List value) async {}
}
