import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/state/providers.dart';
import 'package:google_code/core/errors/vault_exception.dart';
import 'package:google_code/domain/entities/entities.dart';
import 'package:google_code/domain/repositories/vault_repository.dart';
import 'package:google_code/domain/totp/totp.dart';

void main() {
  test('creates a Vault and manages account CRUD and search', () async {
    final repository = _FakeVaultRepository();
    final container = ProviderContainer(
      overrides: [vaultRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(vaultSessionProvider.notifier);

    await controller.initialize();
    expect(
      container.read(vaultSessionProvider).phase,
      VaultSessionPhase.needsSetup,
    );

    expect(await controller.createVault('short', 'short'), isFalse);
    expect(container.read(vaultSessionProvider).message, '主密码至少需要 8 个字符');

    expect(await controller.createVault('password123', 'password123'), isTrue);
    expect(container.read(vaultSessionProvider).isUnlocked, isTrue);

    const draft = AccountDraft(
      issuer: ' Example ',
      accountName: ' alice@example.com ',
      secret: 'jbsw y3dp-ehpk3pxp',
      algorithm: TotpAlgorithm.sha1,
      digits: 6,
      periodSeconds: 30,
    );
    expect(await controller.addAccount(draft), isTrue);

    var state = container.read(vaultSessionProvider);
    expect(state.payload!.accounts, hasLength(1));
    final accountId = state.payload!.accounts.single.id;
    expect(state.payload!.accounts.single.issuer, 'Example');
    expect(state.payload!.accounts.single.secret, 'JBSWY3DPEHPK3PXP');

    controller.setSearchQuery('alice');
    expect(container.read(vaultSessionProvider).visibleAccounts, hasLength(1));
    controller.setSearchQuery('missing');
    expect(container.read(vaultSessionProvider).visibleAccounts, isEmpty);

    const updatedDraft = AccountDraft(
      issuer: 'Updated',
      accountName: 'bob@example.com',
      secret: 'JBSWY3DPEHPK3PXP',
      algorithm: TotpAlgorithm.sha256,
      digits: 8,
      periodSeconds: 45,
    );
    expect(await controller.updateAccount(accountId, updatedDraft), isTrue);
    state = container.read(vaultSessionProvider);
    expect(state.payload!.accounts.single.issuer, 'Updated');
    expect(state.payload!.accounts.single.algorithm, TotpAlgorithm.sha256);

    expect(await controller.deleteAccount(accountId), isTrue);
    expect(container.read(vaultSessionProvider).payload!.accounts, isEmpty);
    expect(repository.saveCount, 3);

    controller.lock();
    state = container.read(vaultSessionProvider);
    expect(state.phase, VaultSessionPhase.locked);
    expect(state.payload, isNull);
    expect(repository.isLocked, isTrue);
  });

  test('requires explicit permission to keep an exact duplicate', () async {
    final repository = _FakeVaultRepository();
    final container = ProviderContainer(
      overrides: [vaultRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(vaultSessionProvider.notifier);
    await controller.initialize();
    await controller.createVault('password123', 'password123');

    const draft = AccountDraft(
      issuer: 'Example',
      accountName: 'alice@example.com',
      secret: 'JBSWY3DPEHPK3PXP',
      algorithm: TotpAlgorithm.sha1,
      digits: 6,
      periodSeconds: 30,
    );
    expect(await controller.addAccount(draft), isTrue);
    expect(await controller.addAccount(draft), isFalse);
    expect(await controller.addAccount(draft, allowDuplicate: true), isTrue);
    expect(
      container.read(vaultSessionProvider).payload!.accounts,
      hasLength(2),
    );
  });

  test('persists a normalized account batch in one transaction', () async {
    final repository = _FakeVaultRepository();
    final container = ProviderContainer(
      overrides: [vaultRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(vaultSessionProvider.notifier);
    await controller.initialize();
    await controller.createVault('password123', 'password123');

    const drafts = [
      AccountDraft(
        issuer: ' Example ',
        accountName: ' alice@example.com ',
        secret: 'jbsw y3dp-ehpk3pxp',
        algorithm: TotpAlgorithm.sha1,
        digits: 6,
        periodSeconds: 30,
      ),
      AccountDraft(
        issuer: 'Work',
        accountName: 'bob@example.com',
        secret: 'GEZDGNBVGY3TQOJQ',
        algorithm: TotpAlgorithm.sha256,
        digits: 8,
        periodSeconds: 30,
      ),
    ];

    expect(await controller.addAccounts(drafts), isTrue);

    final accounts = container.read(vaultSessionProvider).payload!.accounts;
    expect(accounts, hasLength(2));
    expect(accounts.first.issuer, 'Example');
    expect(accounts.first.secret, 'JBSWY3DPEHPK3PXP');
    expect(accounts.last.sortOrder, 1);
    expect(repository.saveCount, 1);
  });

  test('schedules one automatic backup per successful account add', () async {
    final repository = _FakeVaultRepository();
    final scheduler = _FakeAccountAdditionBackupScheduler();
    final container = ProviderContainer(
      overrides: [
        vaultRepositoryProvider.overrideWithValue(repository),
        accountAdditionBackupSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(vaultSessionProvider.notifier);
    await controller.initialize();
    await controller.createVault('password123', 'password123');

    const first = AccountDraft(
      issuer: 'Example',
      accountName: 'alice@example.com',
      secret: 'JBSWY3DPEHPK3PXP',
      algorithm: TotpAlgorithm.sha1,
      digits: 6,
      periodSeconds: 30,
    );
    const second = AccountDraft(
      issuer: 'Work',
      accountName: 'bob@example.com',
      secret: 'GEZDGNBVGY3TQOJQ',
      algorithm: TotpAlgorithm.sha1,
      digits: 6,
      periodSeconds: 30,
    );

    expect(await controller.addAccount(first), isTrue);
    expect(await controller.addAccounts([second]), isTrue);
    expect(scheduler.payloads, hasLength(2));
    expect(scheduler.payloads.first.accounts, hasLength(1));
    expect(scheduler.payloads.last.accounts, hasLength(2));

    final accountId = scheduler.payloads.last.accounts.first.id;
    expect(await controller.updateAccount(accountId, first), isTrue);
    expect(await controller.deleteAccount(accountId), isTrue);
    expect(scheduler.payloads, hasLength(2));
  });

  test(
    'creates, renames, assigns, and deletes account groups atomically',
    () async {
      final repository = _FakeVaultRepository();
      final container = ProviderContainer(
        overrides: [vaultRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(vaultSessionProvider.notifier);
      await controller.initialize();
      await controller.createVault('password123', 'password123');

      const draft = AccountDraft(
        issuer: 'Example',
        accountName: 'alice@example.com',
        secret: 'JBSWY3DPEHPK3PXP',
        algorithm: TotpAlgorithm.sha1,
        digits: 6,
        periodSeconds: 30,
      );
      expect(await controller.addAccount(draft), isTrue);
      final accountId = container
          .read(vaultSessionProvider)
          .payload!
          .accounts
          .single
          .id;

      expect(await controller.createGroup(' Work '), isTrue);
      var payload = container.read(vaultSessionProvider).payload!;
      expect(payload.groups, hasLength(1));
      expect(payload.groups.single['name'], 'Work');
      final groupId = payload.groups.single['id']! as String;

      expect(await controller.createGroup('work'), isFalse);
      expect(container.read(vaultSessionProvider).message, '该分组名称已经存在');
      expect(await controller.renameGroup(groupId, 'Servers'), isTrue);
      expect(
        container.read(vaultSessionProvider).payload!.groups.single['name'],
        'Servers',
      );

      expect(
        await controller.moveAccountToGroup(accountId, 'missing'),
        isFalse,
      );
      expect(container.read(vaultSessionProvider).message, '目标分组不存在');
      expect(await controller.moveAccountToGroup(accountId, groupId), isTrue);
      payload = container.read(vaultSessionProvider).payload!;
      expect(payload.accounts.single.groupId, groupId);

      expect(await controller.deleteGroup(groupId), isTrue);
      payload = container.read(vaultSessionProvider).payload!;
      expect(payload.groups, isEmpty);
      expect(payload.accounts, hasLength(1));
      expect(payload.accounts.single.groupId, isNull);
      expect(repository.saveCount, 5);
    },
  );

  test(
    'reauthenticates only while unlocked and preserves session data',
    () async {
      final repository = _FakeVaultRepository();
      final container = ProviderContainer(
        overrides: [vaultRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(vaultSessionProvider.notifier);
      await controller.initialize();
      await controller.createVault('password123', 'password123');
      final payloadBefore = container.read(vaultSessionProvider).payload;

      expect(await controller.reauthenticate('password123'), isTrue);
      expect(container.read(vaultSessionProvider).isUnlocked, isTrue);
      expect(container.read(vaultSessionProvider).payload, same(payloadBefore));
    },
  );

  test(
    'failed reauthentication does not lock or clear unlocked payload',
    () async {
      final repository = _FakeVaultRepository();
      final container = ProviderContainer(
        overrides: [vaultRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(vaultSessionProvider.notifier);
      await controller.initialize();
      await controller.createVault('password123', 'password123');
      final payloadBefore = container.read(vaultSessionProvider).payload;

      expect(await controller.reauthenticate('wrong-password'), isFalse);
      final state = container.read(vaultSessionProvider);
      expect(state.isUnlocked, isTrue);
      expect(state.payload, same(payloadBefore));
      expect(state.message, isNull);
    },
  );

  test('does not reauthenticate a locked Vault', () async {
    final repository = _FakeVaultRepository(
      availability: VaultAvailability.present,
      storedPayload: VaultPayload.empty(DateTime.utc(2026, 7, 16)),
    );
    final container = ProviderContainer(
      overrides: [vaultRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(vaultSessionProvider.notifier);
    await controller.initialize();

    expect(await controller.reauthenticate('password123'), isFalse);
    expect(
      container.read(vaultSessionProvider).phase,
      VaultSessionPhase.locked,
    );
  });

  test('reports a wrong password without exposing decrypted payload', () async {
    final repository = _FakeVaultRepository(
      availability: VaultAvailability.present,
      storedPayload: VaultPayload.empty(DateTime.utc(2026, 7, 16)),
    );
    final container = ProviderContainer(
      overrides: [vaultRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(vaultSessionProvider.notifier);

    await controller.initialize();
    expect(
      container.read(vaultSessionProvider).phase,
      VaultSessionPhase.locked,
    );
    expect(await controller.unlock('wrong-password'), isFalse);

    final state = container.read(vaultSessionProvider);
    expect(state.phase, VaultSessionPhase.locked);
    expect(state.payload, isNull);
    expect(state.message, '主密码不正确，或密钥包装数据已损坏。请检查输入后重试。');
  });
}

/// In-memory repository fake that models locked and unlocked Vault behavior.
class _FakeVaultRepository implements VaultRepository {
  _FakeVaultRepository({
    this.availability = VaultAvailability.missing,
    this.storedPayload,
  });

  VaultAvailability availability;
  VaultPayload? storedPayload;
  bool isLocked = true;
  int saveCount = 0;
  String password = 'password123';

  @override
  Future<VaultAvailability> inspect() async => availability;

  @override
  Future<VaultPayload> create(String password) async {
    if (availability == VaultAvailability.present) {
      throw const VaultUnlockException('Vault already exists.');
    }
    this.password = password;
    storedPayload = VaultPayload.empty(DateTime.utc(2026, 7, 16));
    availability = VaultAvailability.present;
    isLocked = false;
    return storedPayload!;
  }

  @override
  Future<VaultPayload> unlock(String password) async {
    if (password != this.password || storedPayload == null) {
      throw const VaultUnlockException(
        'Invalid credential.',
        VaultUnlockFailureKind.invalidCredential,
      );
    }
    isLocked = false;
    return storedPayload!;
  }

  @override
  Future<VaultPayload> unlockWithQuickUnlockKey(Uint8List keyBytes) async =>
      throw UnsupportedError('Quick unlock is not used by this test fake.');

  @override
  Future<Uint8List> exportQuickUnlockKey() async =>
      throw UnsupportedError('Quick unlock is not used by this test fake.');

  @override
  Future<bool> verifyPassword(String password) async =>
      password == this.password && storedPayload != null;

  @override
  Future<void> save(VaultPayload payload) async {
    if (isLocked) throw const VaultUnlockException('Vault is locked.');
    storedPayload = payload;
    saveCount += 1;
  }

  @override
  void lock() {
    isLocked = true;
  }
}

class _FakeAccountAdditionBackupScheduler
    implements AccountAdditionBackupScheduler {
  final payloads = <VaultPayload>[];

  @override
  Future<void> scheduleAfterAccountAddition(VaultPayload payload) async {
    payloads.add(payload);
  }
}
