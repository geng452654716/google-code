import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/state/providers.dart';
import 'package:google_code/core/errors/vault_exception.dart';
import 'package:google_code/domain/entities/entities.dart';
import 'package:google_code/domain/repositories/vault_repository.dart';
import 'package:google_code/domain/totp/totp.dart';
import 'package:google_code/features/accounts/accounts_page.dart';

void main() {
  testWidgets('creates a group and drags an account into and out of it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _GroupVaultRepository(_initialPayload());
    final container = ProviderContainer(
      overrides: [vaultRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(vaultSessionProvider.notifier);
    await controller.initialize();
    await controller.unlock('password123');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: AccountsPage(onToggleTheme: () {}),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('create-group-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('group-name-field')),
      '工作',
    );
    await tester.tap(find.byKey(const ValueKey('save-group-name')));
    await tester.pumpAndSettle();

    expect(find.text('工作'), findsOneWidget);
    expect(repository.storedPayload.groups, hasLength(1));
    final groupId = repository.storedPayload.groups.single['id']! as String;
    final accountId = repository.storedPayload.accounts.single.id;

    await _dragTo(
      tester,
      find.byKey(ValueKey('account-drag-handle-$accountId')),
      find.byKey(ValueKey('group-drop-$groupId')),
    );
    expect(repository.storedPayload.accounts.single.groupId, groupId);
    expect(find.text('已移动到「工作」'), findsOneWidget);

    await _dragTo(
      tester,
      find.byKey(ValueKey('account-drag-handle-$accountId')),
      find.byKey(const ValueKey('group-drop-ungrouped')),
    );
    expect(repository.storedPayload.accounts.single.groupId, isNull);
    expect(find.text('已移到未分组'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _dragTo(WidgetTester tester, Finder source, Finder target) async {
  final gesture = await tester.startGesture(tester.getCenter(source));
  await tester.pump();
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.up();
  await tester.pumpAndSettle();
}

VaultPayload _initialPayload() {
  final now = DateTime.utc(2026, 7, 20);
  return VaultPayload.empty(now).copyWith(
    accounts: [
      Account(
        id: 'account-1',
        issuer: 'Example',
        accountName: 'alice@example.com',
        secret: 'JBSWY3DPEHPK3PXP',
        algorithm: TotpAlgorithm.sha1,
        digits: 6,
        periodSeconds: 30,
        sortOrder: 0,
        isPinned: false,
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

class _GroupVaultRepository implements VaultRepository {
  _GroupVaultRepository(this.storedPayload);

  VaultPayload storedPayload;
  bool isLocked = true;

  @override
  Future<VaultAvailability> inspect() async => VaultAvailability.present;

  @override
  Future<VaultPayload> create(String password) async => storedPayload;

  @override
  Future<VaultPayload> unlock(String password) async {
    if (password != 'password123') {
      throw VaultUnlockException();
    }
    isLocked = false;
    return storedPayload;
  }

  @override
  Future<void> save(VaultPayload payload) async {
    if (isLocked) throw VaultUnlockException();
    storedPayload = payload;
  }

  @override
  Future<bool> verifyPassword(String password) async =>
      password == 'password123';

  @override
  Future<Uint8List> exportQuickUnlockKey() async => Uint8List(32);

  @override
  Future<VaultPayload> unlockWithQuickUnlockKey(Uint8List keyBytes) async {
    isLocked = false;
    return storedPayload;
  }

  @override
  void lock() => isLocked = true;
}
