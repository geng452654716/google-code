import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/state/providers.dart';
import 'package:google_code/domain/entities/entities.dart';
import 'package:google_code/domain/repositories/vault_repository.dart';
import 'package:google_code/domain/totp/totp.dart';
import 'package:google_code/features/accounts/account_share_dialog.dart';
import 'package:google_code/platform/files/account_share_file_saver.dart';
import 'package:google_code/platform/auth/local_authentication_service.dart';
import 'package:google_code/platform/security/secure_key_store.dart';
import 'package:google_code/platform/sharing/native_account_share_service.dart';

void main() {
  final account = Account(
    id: 'account-1',
    issuer: 'Example Service',
    accountName: 'alice@example.com',
    secret: 'JBSWY3DPEHPK3PXP',
    algorithm: TotpAlgorithm.sha256,
    digits: 8,
    periodSeconds: 45,
    sortOrder: 0,
    isPinned: false,
    createdAt: DateTime.utc(2026, 7, 16),
    updatedAt: DateTime.utc(2026, 7, 16),
  );

  testWidgets('requires a fresh password and shares every supported format', (
    tester,
  ) async {
    final repository = _ShareRepository(account);
    final saver = _MemoryShareFileSaver();
    final nativeShare = _MemoryNativeAccountShareService();
    final copied = <({String text, Duration ttl})>[];
    await _pumpShareDialog(
      tester,
      account: account,
      repository: repository,
      saver: saver,
      nativeShareService: nativeShare,
      writeSensitiveText: (text, ttl) async {
        copied.add((text: text, ttl: ttl));
      },
    );

    expect(find.text('分享账号凭据'), findsOneWidget);
    expect(find.textContaining('获得 Secret、链接或二维码的人'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-share-qr')), findsNothing);
    expect(find.textContaining(account.secret), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('share-master-password')),
      'wrong-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, '验证并继续'));
    await tester.pump();
    await tester.pump();
    expect(find.text('主密码错误，验证失败。'), findsOneWidget);
    expect(repository.verifyCount, 1);

    await _authenticate(tester, 'password123');
    expect(find.text('Secret'), findsOneWidget);
    expect(find.text('链接'), findsOneWidget);
    expect(find.text('二维码'), findsOneWidget);
    expect(_shareText(tester, 'secret'), '•••• •••• •••• ••••');

    await tester.tap(find.widgetWithText(OutlinedButton, '显示内容'));
    await tester.pump();
    expect(_shareText(tester, 'secret'), 'JBSW Y3DP EHPK 3PXP');
    await tester.tap(find.widgetWithText(FilledButton, '复制 Secret'));
    await tester.pump();
    expect(copied.single.text, account.secret);
    expect(copied.single.ttl, const Duration(seconds: 30));
    expect(find.textContaining('Secret 已复制'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-master-password')), findsOneWidget);

    await _authenticate(tester, 'password123');
    await tester.tap(find.text('链接'));
    await tester.pump();
    expect(_shareText(tester, 'uri'), 'otpauth://totp/••••••••••••');
    await tester.tap(find.widgetWithText(OutlinedButton, '显示内容'));
    await tester.pump();
    final uri = _shareText(tester, 'uri');
    final parsed = OtpAuthUriCodec().parse(uri);
    expect(parsed.secret, account.secret);
    expect(parsed.issuer, account.issuer);
    expect(parsed.algorithm, account.algorithm);
    expect(parsed.digits, account.digits);
    expect(parsed.period, account.periodSeconds);
    await tester.tap(find.widgetWithText(FilledButton, '复制链接'));
    await tester.pump();
    expect(copied.last.text, uri);
    expect(copied.last.ttl, const Duration(seconds: 30));

    await _authenticate(tester, 'password123');
    await tester.tap(find.text('二维码'));
    await tester.pump();
    expect(find.byKey(const ValueKey('account-share-qr')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '保存二维码 PNG'));
    await tester.pump();
    await tester.pump();
    expect(saver.savedBytes, isNotEmpty);
    expect(saver.suggestedName, 'Example-Service-alice@example.com-totp.png');
    expect(find.textContaining('二维码已保存'), findsOneWidget);

    await _authenticate(tester, 'password123');
    await tester.ensureVisible(
      find.byKey(const ValueKey('share-native-account')),
    );
    await tester.tap(find.byKey(const ValueKey('share-native-account')));
    await tester.pump();
    await tester.pump();
    expect(nativeShare.payload, isNotNull);
    expect(nativeShare.payload!.title, contains('Example Service'));
    expect(nativeShare.payload!.text, contains(account.secret));
    expect(nativeShare.payload!.text, contains('otpauth://totp/'));
    expect(nativeShare.payload!.qrPng, isNotEmpty);
    expect(find.textContaining('系统分享面板已打开'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-master-password')), findsOneWidget);
  });

  testWidgets(
    'allows configured device authentication without master password',
    (tester) async {
      final repository = _ShareRepository(account);
      final authentication = _ShareAuthentication();
      final keyStore = _ShareKeyStore();
      await _pumpShareDialog(
        tester,
        account: account,
        repository: repository,
        saver: _MemoryShareFileSaver(),
        authentication: authentication,
        keyStore: keyStore,
        writeSensitiveText: (_, _) async {},
      );

      expect(
        find.byKey(const ValueKey('share-device-authentication')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('share-device-authentication')),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Secret'), findsOneWidget);
      expect(repository.verifyCount, 0);
      expect(authentication.authenticateCount, 1);
      expect(keyStore.deleteCount, 0);
    },
  );

  testWidgets(
    'device authentication cancellation preserves password fallback',
    (tester) async {
      final authentication = _ShareAuthentication(
        result: DeviceAuthenticationResult.cancelled,
      );
      final keyStore = _ShareKeyStore();
      await _pumpShareDialog(
        tester,
        account: account,
        repository: _ShareRepository(account),
        saver: _MemoryShareFileSaver(),
        authentication: authentication,
        keyStore: keyStore,
        writeSensitiveText: (_, _) async {},
      );

      await tester.tap(
        find.byKey(const ValueKey('share-device-authentication')),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('已取消设备认证。'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('share-master-password')),
        findsOneWidget,
      );
      expect(keyStore.deleteCount, 0);
    },
  );

  testWidgets('conceals material after timeout and application focus loss', (
    tester,
  ) async {
    final repository = _ShareRepository(account);
    await _pumpShareDialog(
      tester,
      account: account,
      repository: repository,
      saver: _MemoryShareFileSaver(),
      revealDuration: const Duration(seconds: 2),
      writeSensitiveText: (_, _) async {},
    );

    await _authenticate(tester, 'password123');
    expect(find.text('Secret'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('分享内容已超时隐藏'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-master-password')), findsOneWidget);

    await _authenticate(tester, 'password123');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.textContaining('窗口已失焦'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-master-password')), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('closes the dialog immediately when the Vault locks', (
    tester,
  ) async {
    final repository = _ShareRepository(account);
    final container = await _pumpShareDialog(
      tester,
      account: account,
      repository: repository,
      saver: _MemoryShareFileSaver(),
      writeSensitiveText: (_, _) async {},
    );
    await _authenticate(tester, 'password123');

    final dialogContainer = ProviderScope.containerOf(
      tester.element(find.byType(AccountShareDialog)),
    );
    expect(dialogContainer, same(container));
    dialogContainer.read(vaultSessionProvider.notifier).lock();
    expect(dialogContainer.read(vaultSessionProvider).isUnlocked, isFalse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('share-master-password')),
      findsNothing,
      reason:
          'locked dialogs must close instead of returning to reauthentication',
    );
    expect(find.text('分享账号凭据'), findsNothing);
    expect(container.read(vaultSessionProvider).isUnlocked, isFalse);
  });
}

/// Opens the real modal route with deterministic in-memory dependencies.
Future<ProviderContainer> _pumpShareDialog(
  WidgetTester tester, {
  required Account account,
  required _ShareRepository repository,
  required AccountShareFileSaver saver,
  required SensitiveShareTextWriter writeSensitiveText,
  NativeAccountShareService? nativeShareService,
  Duration revealDuration = const Duration(seconds: 60),
  LocalAuthenticationService? authentication,
  SecureKeyStore? keyStore,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vaultRepositoryProvider.overrideWithValue(repository),
        vaultSessionProvider.overrideWith(
          () => _UnlockedShareController(repository.payload),
        ),
        accountShareFileSaverProvider.overrideWithValue(saver),
        if (nativeShareService != null)
          nativeAccountShareServiceProvider.overrideWithValue(
            nativeShareService,
          ),
        if (authentication != null)
          localAuthenticationServiceProvider.overrideWithValue(authentication),
        if (keyStore != null)
          secureKeyStoreProvider.overrideWithValue(keyStore),
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
                    builder: (context) => AccountShareDialog(
                      account: account,
                      revealDuration: revealDuration,
                      writeSensitiveText: writeSensitiveText,
                    ),
                  ),
                  child: const Text('打开分享'),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('打开分享'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

/// Completes one master-password challenge without waiting for periodic timers.
Future<void> _authenticate(WidgetTester tester, String password) async {
  await tester.enterText(
    find.byKey(const ValueKey('share-master-password')),
    password,
  );
  await tester.tap(find.widgetWithText(FilledButton, '验证并继续'));
  await tester.pump();
  await tester.pump();
}

/// Returns the currently rendered concealed or revealed sensitive text.
String _shareText(WidgetTester tester, String format) => tester
    .widget<SelectableText>(find.byKey(ValueKey('share-sensitive-$format')))
    .data!;

/// Session controller seeded with one unlocked account for modal tests.
class _UnlockedShareController extends VaultSessionController {
  _UnlockedShareController(this.payload);

  final VaultPayload payload;

  @override
  VaultSessionState build() =>
      VaultSessionState(phase: VaultSessionPhase.unlocked, payload: payload);
}

/// Repository fake that records fresh master-password verification attempts.
class _ShareRepository implements VaultRepository {
  _ShareRepository(Account account)
    : payload = VaultPayload.empty(
        DateTime.utc(2026, 7, 16),
      ).copyWith(accounts: [account]);

  final VaultPayload payload;
  int verifyCount = 0;

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
  Future<bool> verifyPassword(String password) async {
    verifyCount += 1;
    return password == 'password123';
  }

  @override
  Future<void> save(VaultPayload payload) async {}

  @override
  void lock() {}
}

class _ShareAuthentication implements LocalAuthenticationService {
  _ShareAuthentication({
    this.result = DeviceAuthenticationResult.authenticated,
  });

  final DeviceAuthenticationResult result;
  int authenticateCount = 0;

  @override
  String get displayName => 'Test Device Auth';

  @override
  Future<DeviceAuthenticationAvailability> inspect() async =>
      DeviceAuthenticationAvailability.available;

  @override
  Future<DeviceAuthenticationResult> authenticate({
    required String reason,
  }) async {
    authenticateCount += 1;
    return result;
  }
}

class _ShareKeyStore implements SecureKeyStore {
  int deleteCount = 0;

  @override
  Future<bool> containsQuickUnlockKey() async => true;

  @override
  Future<Uint8List?> readQuickUnlockKey() async => Uint8List(32);

  @override
  Future<void> writeQuickUnlockKey(Uint8List keyBytes) async {}

  @override
  Future<void> deleteQuickUnlockKey() async => deleteCount += 1;
}

/// Captures a user-approved QR save without opening a native save dialog.
class _MemoryShareFileSaver implements AccountShareFileSaver {
  Uint8List? savedBytes;
  String? suggestedName;

  @override
  Future<bool> savePng(
    Uint8List pngBytes, {
    required String suggestedName,
  }) async {
    savedBytes = Uint8List.fromList(pngBytes);
    this.suggestedName = suggestedName;
    return true;
  }
}

/// Captures the complete native share request without opening an OS surface.
class _MemoryNativeAccountShareService implements NativeAccountShareService {
  NativeAccountSharePayload? payload;

  @override
  Future<NativeAccountShareResult> share(
    NativeAccountSharePayload payload,
  ) async {
    this.payload = payload;
    return NativeAccountShareResult.presented;
  }
}
