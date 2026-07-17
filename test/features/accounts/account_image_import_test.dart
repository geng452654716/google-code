import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/state/providers.dart';
import 'package:google_code/application/import/otp_import_service.dart';
import 'package:google_code/domain/entities/entities.dart';
import 'package:google_code/domain/import/otp_import_candidate.dart';
import 'package:google_code/domain/repositories/vault_repository.dart';
import 'package:google_code/domain/totp/totp.dart';
import 'package:google_code/features/accounts/accounts_page.dart';
import 'package:google_code/platform/files/image_import_picker.dart';
import 'package:google_code/platform/qr/qr_code_service.dart';

void main() {
  testWidgets('imports a selected QR image after confirmation', (tester) async {
    const uri =
        'otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example';
    final repository = _UnlockedRepository();
    final picker = _MemoryImagePicker(QrCodeService().encodePng(uri));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultRepositoryProvider.overrideWithValue(repository),
          vaultSessionProvider.overrideWith(_UnlockedController.new),
          imageImportPickerProvider.overrideWithValue(picker),
          otpImportServiceProvider.overrideWithValue(
            const _ImmediateImportService(),
          ),
        ],
        child: MaterialApp(home: AccountsPage(onToggleTheme: () {})),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从二维码图片导入'));

    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('确认导入账号').evaluate().isNotEmpty) break;
    }

    expect(find.text('确认导入账号'), findsOneWidget);
    expect(find.text('Example'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(repository.storedPayload.accounts, hasLength(1));
    expect(repository.storedPayload.accounts.single.issuer, 'Example');
    expect(find.text('二维码账号已加密保存'), findsOneWidget);
  });
}

/// Deterministic parser fake; QR decoding itself is covered by service tests.
class _ImmediateImportService extends OtpImportService {
  const _ImmediateImportService();

  @override
  Future<OtpImportResult> decodeImageBytes(
    Uint8List bytes, {
    OtpImportSource source = OtpImportSource.imageFile,
  }) async {
    return SingleOtpImportResult(
      OtpImportCandidate(
        source: source,
        draft: const AccountDraft(
          issuer: 'Example',
          accountName: 'alice@example.com',
          secret: 'JBSWY3DPEHPK3PXP',
          algorithm: TotpAlgorithm.sha1,
          digits: 6,
          periodSeconds: 30,
        ),
      ),
    );
  }
}

/// Session controller seeded directly into an unlocked widget-test state.
class _UnlockedController extends VaultSessionController {
  @override
  VaultSessionState build() => VaultSessionState(
    phase: VaultSessionPhase.unlocked,
    payload: VaultPayload.empty(DateTime.utc(2026, 7, 16)),
  );
}

/// In-memory picker that avoids opening a native file dialog in widget tests.
class _MemoryImagePicker implements ImageImportPicker {
  const _MemoryImagePicker(this.bytes);

  final Uint8List bytes;

  @override
  Future<PickedImageData?> pickImage() async =>
      PickedImageData(bytes: bytes, name: 'account.png');
}

/// Already-unlocked persistence fake used by the import confirmation flow.
class _UnlockedRepository implements VaultRepository {
  VaultPayload storedPayload = VaultPayload.empty(DateTime.utc(2026, 7, 16));

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
  }

  @override
  void lock() {}
}
