import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/state/providers.dart';
import 'package:google_code/domain/entities/entities.dart';
import 'package:google_code/domain/repositories/vault_repository.dart';
import 'package:google_code/features/accounts/accounts_page.dart';
import 'package:google_code/platform/clipboard/clipboard_import_reader.dart';

void main() {
  const uri =
      'otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example';

  testWidgets('imports an otpauth URI selected from the clipboard menu', (
    tester,
  ) async {
    final repository = _UnlockedRepository();
    final clipboard = _MemoryClipboardReader(const ClipboardTextData(uri));
    await _pumpAccountsPage(tester, repository, clipboard);

    await tester.tap(find.byKey(const ValueKey('add-account-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从剪贴板导入'));
    await _pumpUntilFound(tester, find.text('确认导入账号'));

    expect(find.text('确认导入账号'), findsOneWidget);
    expect(find.textContaining('剪贴板链接'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(repository.storedPayload.accounts, hasLength(1));
    expect(repository.storedPayload.accounts.single.issuer, 'Example');
    expect(find.text('剪贴板账号已加密保存'), findsOneWidget);
  });

  testWidgets('Ctrl+V opens clipboard import confirmation', (tester) async {
    final repository = _UnlockedRepository();
    final clipboard = _MemoryClipboardReader(const ClipboardTextData(uri));
    await _pumpAccountsPage(tester, repository, clipboard);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await _pumpUntilFound(tester, find.text('确认导入账号'));

    expect(clipboard.readCount, 1);
    expect(find.text('确认导入账号'), findsOneWidget);
    expect(find.textContaining('剪贴板链接'), findsOneWidget);
  });
}

/// Advances asynchronous import work without waiting on the one-second ticker.
Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
}

/// Builds an unlocked accounts surface with deterministic local dependencies.
Future<void> _pumpAccountsPage(
  WidgetTester tester,
  _UnlockedRepository repository,
  ClipboardImportReader clipboard,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vaultRepositoryProvider.overrideWithValue(repository),
        vaultSessionProvider.overrideWith(_UnlockedController.new),
        clipboardImportReaderProvider.overrideWithValue(clipboard),
      ],
      child: MaterialApp(home: AccountsPage(onToggleTheme: () {})),
    ),
  );
  await tester.pump();
}

/// In-memory clipboard source used without touching the host clipboard.
class _MemoryClipboardReader implements ClipboardImportReader {
  _MemoryClipboardReader(this.data);

  final ClipboardImportData? data;
  int readCount = 0;

  @override
  Future<ClipboardImportData?> read() async {
    readCount += 1;
    return data;
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

/// Already-unlocked persistence fake used by clipboard import tests.
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
