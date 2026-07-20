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
import 'package:google_code/platform/screenshot/screen_capture_service.dart';

void main() {
  testWidgets('imports a selected screenshot through the shared confirmation', (
    tester,
  ) async {
    final repository = _UnlockedRepository();
    final capture = _FakeScreenCaptureService(Uint8List.fromList([1, 2, 3]));
    await _pumpAccountsPage(tester, repository, capture);

    await _chooseScreenshot(tester);
    await _startScreenshotSelection(tester);
    await _pumpUntilFound(tester, find.text('确认导入账号'));

    expect(find.textContaining('已从区域截图识别账号'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(capture.captureCount, 1);
    expect(repository.storedPayload.accounts, hasLength(1));
    expect(repository.storedPayload.accounts.single.issuer, 'Example');
    expect(find.text('区域截图账号已加密保存'), findsOneWidget);
  });

  testWidgets('silently stops when region selection is cancelled', (
    tester,
  ) async {
    final repository = _UnlockedRepository();
    final capture = _FakeScreenCaptureService(null);
    await _pumpAccountsPage(tester, repository, capture);

    await _chooseScreenshot(tester);
    await _startScreenshotSelection(tester);
    await tester.pumpAndSettle();

    expect(capture.captureCount, 1);
    expect(repository.storedPayload.accounts, isEmpty);
    expect(find.text('确认导入账号'), findsNothing);
    expect(find.text('正在解析…'), findsNothing);
    expect(find.text('已取消屏幕二维码扫描，应用窗口已恢复。'), findsOneWidget);
  });

  testWidgets('explains native selector and can stop before minimizing', (
    tester,
  ) async {
    final repository = _UnlockedRepository();
    final capture = _FakeScreenCaptureService(Uint8List.fromList([1, 2, 3]));
    await _pumpAccountsPage(tester, repository, capture);

    await _chooseScreenshot(tester);
    await tester.pumpAndSettle();

    expect(find.text('扫描屏幕二维码'), findsOneWidget);
    expect(find.textContaining('鼠标会变成系统截图的十字光标'), findsOneWidget);
    expect(find.textContaining('按 Esc'), findsOneWidget);
    expect(capture.captureCount, 0);

    await tester.tap(find.widgetWithText(TextButton, '暂不扫描'));
    await tester.pumpAndSettle();

    expect(capture.captureCount, 0);
    expect(find.textContaining('十字光标'), findsNothing);
  });

  testWidgets('permission denial can open system settings', (tester) async {
    final repository = _UnlockedRepository();
    final capture = _FakeScreenCaptureService(
      null,
      failure: const ScreenCaptureException(
        ScreenCaptureFailureKind.permissionDenied,
        '需要屏幕录制权限才能框选并识别二维码。',
      ),
    );
    await _pumpAccountsPage(tester, repository, capture);

    await _chooseScreenshot(tester);
    await _startScreenshotSelection(tester);
    await _pumpUntilFound(tester, find.text('屏幕录制权限尚未生效'));

    expect(find.text('退出并重新打开'), findsOneWidget);
    expect(find.text('打开系统设置'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '打开系统设置'));
    await tester.pumpAndSettle();

    expect(capture.openSettingsCount, 1);
    expect(find.text('正在解析…'), findsNothing);
  });

  testWidgets('permission denial can restart after permission is enabled', (
    tester,
  ) async {
    final repository = _UnlockedRepository();
    final capture = _FakeScreenCaptureService(
      null,
      failure: const ScreenCaptureException(
        ScreenCaptureFailureKind.permissionDenied,
        '当前进程尚未获得屏幕录制权限。',
      ),
    );
    await _pumpAccountsPage(tester, repository, capture);

    await _chooseScreenshot(tester);
    await _startScreenshotSelection(tester);
    await _pumpUntilFound(tester, find.text('屏幕录制权限尚未生效'));

    expect(find.textContaining('彻底重启应用'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '退出并重新打开'));
    await tester.pumpAndSettle();

    expect(capture.restartCount, 1);
    expect(capture.openSettingsCount, 0);
  });
}

/// Opens the add-account menu and selects the screenshot import action.
Future<void> _chooseScreenshot(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  await tester.tap(find.text('扫描屏幕二维码'));
}

/// Confirms the documented minimize-and-select native screenshot lifecycle.
Future<void> _startScreenshotSelection(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '开始框选'));
}

/// Advances asynchronous import work without waiting on the one-second ticker.
Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
}

/// Builds an unlocked account page with deterministic platform boundaries.
Future<void> _pumpAccountsPage(
  WidgetTester tester,
  _UnlockedRepository repository,
  ScreenCaptureService capture,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vaultRepositoryProvider.overrideWithValue(repository),
        vaultSessionProvider.overrideWith(_UnlockedController.new),
        screenCaptureServiceProvider.overrideWithValue(capture),
        otpImportServiceProvider.overrideWithValue(
          const _ImmediateImportService(),
        ),
      ],
      child: MaterialApp(home: AccountsPage(onToggleTheme: () {})),
    ),
  );
  await tester.pump();
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

/// In-memory screenshot implementation used by widget tests.
class _FakeScreenCaptureService implements ScreenCaptureService {
  _FakeScreenCaptureService(this.bytes, {this.failure});

  final Uint8List? bytes;
  final ScreenCaptureException? failure;
  int captureCount = 0;
  int openSettingsCount = 0;
  int restartCount = 0;

  @override
  Future<Uint8List?> captureRegion() async {
    captureCount += 1;
    if (failure case final error?) throw error;
    return bytes;
  }

  @override
  Future<void> openPermissionSettings() async {
    openSettingsCount += 1;
  }

  @override
  Future<void> restartApplication() async {
    restartCount += 1;
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

/// Already-unlocked persistence fake used by screenshot import tests.
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
