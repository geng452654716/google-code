import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/state/providers.dart';
import 'package:google_code/application/backup/backup_service.dart';
import 'package:google_code/domain/backup/backup.dart';
import 'package:google_code/domain/entities/vault_payload.dart';
import 'package:google_code/domain/repositories/vault_repository.dart';
import 'package:google_code/features/backup/backup_export_dialog.dart';
import 'package:google_code/features/backup/backup_restore_dialog.dart';
import 'package:google_code/platform/files/backup_file_service.dart';

void main() {
  testWidgets('export validates a separate password and shows saved location', (
    tester,
  ) async {
    final current = VaultPayload.empty(DateTime.utc(2026, 7, 16));
    final repository = _BackupRepository(current);
    final service = _FakeBackupService(current);
    final files = _MemoryBackupFiles();
    await _pumpDialog(
      tester,
      dialog: const BackupExportDialog(),
      payload: current,
      repository: repository,
      service: service,
      files: files,
    );

    await tester.enterText(
      find.byKey(const ValueKey('backup-export-password')),
      'backup-password',
    );
    await tester.enterText(
      find.byKey(const ValueKey('backup-export-confirmation')),
      'backup-password',
    );
    await tester.tap(find.byKey(const ValueKey('backup-export-submit')));
    await tester.pumpAndSettle();

    expect(service.exportPassword, 'backup-password');
    expect(files.savedBytes, [1, 2, 3, 4]);
    expect(files.suggestedName, endsWith('.gcbak'));
    expect(find.textContaining('/safe/google-code.gcbak'), findsOneWidget);
    final passwordField = tester.widget<TextField>(
      find.byKey(const ValueKey('backup-export-password')),
    );
    expect(passwordField.controller!.text, isEmpty);
  });

  testWidgets('restore previews aggregate counts and merges in one save', (
    tester,
  ) async {
    final current = VaultPayload.empty(DateTime.utc(2026, 7, 16));
    final restored = current.copyWith(
      preferences: const {'autoLockMinutes': 20},
      updatedAt: DateTime.utc(2026, 7, 16, 1),
    );
    final repository = _BackupRepository(current);
    final service = _FakeBackupService(restored);
    final files = _MemoryBackupFiles(
      picked: PickedBackupFile(
        bytes: Uint8List.fromList([9, 8, 7]),
        name: 'selected.gcbak',
      ),
    );
    final container = await _pumpDialog(
      tester,
      dialog: const BackupRestoreDialog(),
      payload: current,
      repository: repository,
      service: service,
      files: files,
    );

    await tester.tap(find.byKey(const ValueKey('backup-restore-pick-file')));
    await tester.pumpAndSettle();
    expect(find.text('selected.gcbak'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('backup-restore-password')),
      'backup-password',
    );
    await tester.tap(find.byKey(const ValueKey('backup-restore-preview')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('backup-restore-summary')),
      findsOneWidget,
    );
    expect(find.textContaining('账号：2'), findsOneWidget);
    expect(service.previewPassword, 'backup-password');

    await tester.tap(find.byKey(const ValueKey('backup-restore-apply')));
    await tester.pumpAndSettle();

    expect(repository.saved, same(restored));
    expect(container.read(vaultSessionProvider).payload, same(restored));
    expect(find.textContaining('已新增 2 个账号'), findsOneWidget);
  });

  testWidgets('replace requires confirmation and lock closes restore route', (
    tester,
  ) async {
    final current = VaultPayload.empty(DateTime.utc(2026, 7, 16));
    final restored = current.copyWith(
      preferences: const {'autoLockMinutes': 20},
    );
    final repository = _BackupRepository(current);
    final service = _FakeBackupService(restored);
    final files = _MemoryBackupFiles(
      picked: PickedBackupFile(
        bytes: Uint8List.fromList([1]),
        name: 'selected.gcbak',
      ),
    );
    final container = await _pumpDialog(
      tester,
      dialog: const BackupRestoreDialog(),
      payload: current,
      repository: repository,
      service: service,
      files: files,
    );

    await tester.tap(find.byKey(const ValueKey('backup-restore-pick-file')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('backup-restore-password')),
      'backup-password',
    );
    await tester.tap(find.byKey(const ValueKey('backup-restore-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('替换'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('backup-restore-apply')));
    await tester.pumpAndSettle();

    expect(find.text('确认替换当前 Vault？'), findsOneWidget);
    expect(repository.saved, isNull);
    await tester.tap(
      find.byKey(const ValueKey('backup-restore-confirm-replace')),
    );
    await tester.pumpAndSettle();
    expect(repository.saved, same(restored));

    container.read(vaultSessionProvider.notifier).lock();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('从加密备份恢复'), findsNothing);
  });
}

Future<ProviderContainer> _pumpDialog(
  WidgetTester tester, {
  required Widget dialog,
  required VaultPayload payload,
  required _BackupRepository repository,
  required BackupService service,
  required BackupFileService files,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vaultRepositoryProvider.overrideWithValue(repository),
        vaultSessionProvider.overrideWith(
          () => _UnlockedBackupController(payload),
        ),
        backupServiceProvider.overrideWithValue(service),
        backupFileServiceProvider.overrideWithValue(files),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => dialog,
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
  return container;
}

class _UnlockedBackupController extends VaultSessionController {
  _UnlockedBackupController(this.payload);

  final VaultPayload payload;

  @override
  VaultSessionState build() =>
      VaultSessionState(phase: VaultSessionPhase.unlocked, payload: payload);
}

class _FakeBackupService extends BackupService {
  _FakeBackupService(this.restoredPayload);

  final VaultPayload restoredPayload;
  String? exportPassword;
  String? previewPassword;

  @override
  Future<Uint8List> export(VaultPayload payload, String password) async {
    exportPassword = password;
    return Uint8List.fromList([1, 2, 3, 4]);
  }

  @override
  Future<BackupRestorePreview> preview(
    Uint8List bytes,
    String password,
    VaultPayload current,
  ) async {
    previewPassword = password;
    return BackupRestorePreview(
      backupCreatedAt: DateTime.utc(2026, 7, 16),
      payload: restoredPayload,
      summary: const BackupRestoreSummary(
        accountCount: 2,
        groupCount: 1,
        newAccountCount: 2,
        exactDuplicateCount: 0,
        conflictCount: 1,
      ),
    );
  }

  @override
  BackupRestoreResult prepareRestore({
    required VaultPayload current,
    required BackupRestorePreview preview,
    required BackupRestoreMode mode,
  }) => BackupRestoreResult(
    payload: restoredPayload,
    mode: mode,
    addedAccountCount: 2,
    skippedDuplicateCount: 0,
    conflictCount: 1,
  );
}

class _MemoryBackupFiles implements BackupFileService {
  _MemoryBackupFiles({this.picked});

  final PickedBackupFile? picked;
  List<int>? savedBytes;
  String? suggestedName;

  @override
  Future<PickedBackupFile?> pickBackup() async => picked;

  @override
  Future<SavedBackupFile?> saveBackup(
    Uint8List bytes, {
    required String suggestedName,
  }) async {
    savedBytes = List<int>.from(bytes);
    this.suggestedName = suggestedName;
    return const SavedBackupFile(path: '/safe/google-code.gcbak');
  }
}

class _BackupRepository implements VaultRepository {
  _BackupRepository(this.payload);

  VaultPayload payload;
  VaultPayload? saved;

  @override
  Future<VaultAvailability> inspect() async => VaultAvailability.present;

  @override
  Future<VaultPayload> create(String password) async => payload;

  @override
  Future<VaultPayload> unlock(String password) async => payload;

  @override
  Future<VaultPayload> unlockWithQuickUnlockKey(Uint8List keyBytes) async =>
      throw UnsupportedError('Quick unlock is not used by this test fake.');

  @override
  Future<Uint8List> exportQuickUnlockKey() async =>
      throw UnsupportedError('Quick unlock is not used by this test fake.');

  @override
  Future<bool> verifyPassword(String password) async => true;

  @override
  Future<void> save(VaultPayload payload) async {
    saved = payload;
    this.payload = payload;
  }

  @override
  void lock() {}
}
