import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/state/providers.dart';
import 'package:google_code/application/import/otp_import_service.dart';
import 'package:google_code/domain/entities/entities.dart';
import 'package:google_code/domain/import/google_authenticator_migration.dart';
import 'package:google_code/domain/import/otp_import_candidate.dart';
import 'package:google_code/domain/repositories/vault_repository.dart';
import 'package:google_code/domain/totp/totp.dart';
import 'package:google_code/features/accounts/accounts_page.dart';
import 'package:google_code/platform/files/image_import_picker.dart';

void main() {
  testWidgets(
    'collects a multi-QR migration batch and saves selected accounts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _UnlockedRepository();
      final service = _MigrationImportService([
        GoogleMigrationPart(
          version: 1,
          batchSize: 2,
          batchIndex: 0,
          batchId: 88,
          entries: [
            _validEntry('Example', 'alice@example.com', 'JBSWY3DPEHPK3PXP'),
            GoogleMigrationEntry.invalid(
              issuer: 'Legacy',
              accountName: 'counter-account',
              issue: 'HOTP 暂不支持',
            ),
          ],
        ),
        GoogleMigrationPart(
          version: 1,
          batchSize: 2,
          batchIndex: 1,
          batchId: 88,
          entries: [_validEntry('Work', 'bob@example.com', 'GEZDGNBVGY3TQOJQ')],
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultRepositoryProvider.overrideWithValue(repository),
            vaultSessionProvider.overrideWith(_UnlockedController.new),
            imageImportPickerProvider.overrideWithValue(
              const _MemoryImagePicker(),
            ),
            otpImportServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(home: AccountsPage(onToggleTheme: () {})),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('add-account-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从二维码图片导入'));
      await _pumpUntilFound(tester, find.textContaining('已读取 1/2 张'));

      expect(find.textContaining('已读取 1/2 张'), findsOneWidget);
      expect(repository.storedPayload.accounts, isEmpty);
      await tester.tap(find.text('继续选择图片'));
      await _pumpUntilFound(tester, find.text('确认批量导入'));

      expect(find.text('确认批量导入'), findsOneWidget);
      expect(find.textContaining('有效 2 个，无效 1 个'), findsOneWidget);
      expect(find.text('无法导入：HOTP 暂不支持'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '导入 2 个账号'));
      await tester.pumpAndSettle();

      expect(repository.storedPayload.accounts, hasLength(2));
      expect(repository.saveCount, 1);
      expect(find.text('批量导入完成：成功 2，跳过 0，无效 1'), findsOneWidget);
    },
  );
}

GoogleMigrationEntry _validEntry(
  String issuer,
  String accountName,
  String secret,
) => GoogleMigrationEntry.valid(
  issuer: issuer,
  accountName: accountName,
  draft: AccountDraft(
    issuer: issuer,
    accountName: accountName,
    secret: secret,
    algorithm: TotpAlgorithm.sha1,
    digits: 6,
    periodSeconds: 30,
  ),
);

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
}

class _MigrationImportService extends OtpImportService {
  _MigrationImportService(this.parts);

  final List<GoogleMigrationPart> parts;
  int _nextPart = 0;

  @override
  Future<OtpImportResult> decodeImageBytes(
    Uint8List bytes, {
    OtpImportSource source = OtpImportSource.imageFile,
  }) async => GoogleMigrationOtpImportResult(parts[_nextPart++]);
}

class _MemoryImagePicker implements ImageImportPicker {
  const _MemoryImagePicker();

  @override
  Future<PickedImageData?> pickImage() async => PickedImageData(
    bytes: Uint8List.fromList([1, 2, 3]),
    name: 'migration.png',
  );
}

class _UnlockedController extends VaultSessionController {
  @override
  VaultSessionState build() => VaultSessionState(
    phase: VaultSessionPhase.unlocked,
    payload: VaultPayload.empty(DateTime.utc(2026, 7, 16)),
  );
}

class _UnlockedRepository implements VaultRepository {
  VaultPayload storedPayload = VaultPayload.empty(DateTime.utc(2026, 7, 16));
  int saveCount = 0;

  @override
  Future<VaultAvailability> inspect() async => VaultAvailability.present;

  @override
  Future<VaultPayload> create(String password) async => storedPayload;

  @override
  Future<VaultPayload> unlock(String password) async => storedPayload;

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
    storedPayload = payload;
    saveCount += 1;
  }

  @override
  void lock() {}
}
