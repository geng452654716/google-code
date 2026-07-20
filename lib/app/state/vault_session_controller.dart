import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/encoding/base32_codec.dart';
import '../../core/errors/vault_exception.dart';
import '../../core/security/password_policy.dart';
import '../../application/security/quick_unlock_service.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/vault_repository.dart';
import 'security_providers.dart';
import 'vault_session_state.dart';

/// Coordinates Vault lifecycle and all mutations of unlocked account data.
class VaultSessionController extends Notifier<VaultSessionState> {
  final _base32Codec = Base32Codec();
  final _passwordPolicy = const PasswordPolicy();
  final _uuid = const Uuid();
  bool _initialized = false;

  VaultRepository get _repository => ref.read(vaultRepositoryProvider);

  QuickUnlockService get _quickUnlockService =>
      ref.read(quickUnlockServiceProvider);

  @override
  VaultSessionState build() => const VaultSessionState.loading();

  /// Inspects local storage once and selects onboarding or unlock flow.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final availability = await _repository.inspect();
      state = VaultSessionState(
        phase: availability == VaultAvailability.missing
            ? VaultSessionPhase.needsSetup
            : VaultSessionPhase.locked,
      );
    } on Object {
      state = const VaultSessionState(
        phase: VaultSessionPhase.error,
        message: '无法读取本地 Vault，请检查应用数据目录权限。',
      );
    }
  }

  /// Retries storage inspection after a recoverable startup error.
  Future<void> retryInitialize() async {
    _initialized = false;
    state = const VaultSessionState.loading();
    await initialize();
  }

  /// Creates the first encrypted Vault after local password validation.
  Future<bool> createVault(String password, String confirmation) async {
    final validation = _passwordPolicy.validate(password);
    if (validation != null) {
      state = state.copyWith(message: validation);
      return false;
    }
    if (password != confirmation) {
      state = state.copyWith(message: '两次输入的主密码不一致');
      return false;
    }
    state = state.copyWith(isProcessing: true, clearMessage: true);
    try {
      final payload = await _repository.create(password);
      state = VaultSessionState(
        phase: VaultSessionPhase.unlocked,
        payload: payload,
      );
      return true;
    } on Object {
      state = state.copyWith(
        isProcessing: false,
        message: '创建加密 Vault 失败，请重试。',
      );
      return false;
    }
  }

  /// Unlocks an existing Vault without retaining [password] in state.
  Future<bool> unlock(String password) async {
    if (password.isEmpty) {
      state = state.copyWith(message: '请输入主密码');
      return false;
    }
    state = state.copyWith(isProcessing: true, clearMessage: true);
    try {
      final payload = await _repository.unlock(password);
      state = VaultSessionState(
        phase: VaultSessionPhase.unlocked,
        payload: payload,
      );
      return true;
    } on VaultUnlockException {
      state = state.copyWith(
        isProcessing: false,
        message: '主密码错误，或 Vault 数据已损坏。',
      );
      return false;
    } on Object {
      state = state.copyWith(isProcessing: false, message: '解锁失败，请稍后重试。');
      return false;
    }
  }

  /// Unlocks through fresh device authentication and its protected DEK copy.
  Future<QuickUnlockAttemptStatus> unlockWithQuickUnlock() async {
    if (state.isProcessing) return QuickUnlockAttemptStatus.failed;
    state = state.copyWith(isProcessing: true, clearMessage: true);
    final attempt = await _quickUnlockService.unlock();
    if (attempt.status == QuickUnlockAttemptStatus.success &&
        attempt.payload != null) {
      state = VaultSessionState(
        phase: VaultSessionPhase.unlocked,
        payload: attempt.payload,
      );
      return attempt.status;
    }
    state = state.copyWith(
      isProcessing: false,
      message: switch (attempt.status) {
        QuickUnlockAttemptStatus.cancelled => null,
        QuickUnlockAttemptStatus.notConfigured => '快速解锁尚未启用，请输入主密码。',
        QuickUnlockAttemptStatus.unavailable => '设备认证当前不可用，请输入主密码。',
        QuickUnlockAttemptStatus.invalidKey => '快速解锁材料已失效，请使用主密码解锁后重新启用。',
        QuickUnlockAttemptStatus.failed => '快速解锁失败，请输入主密码。',
        QuickUnlockAttemptStatus.success => null,
      },
      clearMessage: attempt.status == QuickUnlockAttemptStatus.cancelled,
    );
    return attempt.status;
  }

  /// Revalidates the master password for a sensitive unlocked operation.
  ///
  /// The password and decrypted verification payload are not retained in state.
  Future<bool> reauthenticate(String password) async {
    if (!state.isUnlocked || state.isProcessing || password.isEmpty) {
      return false;
    }
    try {
      return await _repository.verifyPassword(password);
    } on Object {
      return false;
    }
  }

  /// Drops all decrypted account references and returns to the lock screen.
  void lock() {
    _repository.lock();
    state = const VaultSessionState(phase: VaultSessionPhase.locked);
  }

  /// Updates the in-memory search query without writing sensitive data to disk.
  void setSearchQuery(String query) {
    if (!state.isUnlocked) return;
    state = state.copyWith(searchQuery: query);
  }

  /// Adds a validated account and persists the complete encrypted payload.
  Future<bool> addAccount(
    AccountDraft draft, {
    bool allowDuplicate = false,
  }) async {
    final normalized = _normalizeDraft(draft);
    if (normalized == null) return false;
    final payload = state.payload;
    if (payload == null) return false;
    if (!allowDuplicate && _isDuplicate(payload.accounts, normalized)) {
      state = state.copyWith(message: '该账号已经存在');
      return false;
    }
    final now = DateTime.now().toUtc();
    final account = Account(
      id: _uuid.v4(),
      issuer: normalized.issuer,
      accountName: normalized.accountName,
      secret: normalized.secret,
      algorithm: normalized.algorithm,
      digits: normalized.digits,
      periodSeconds: normalized.periodSeconds,
      sortOrder: payload.accounts.length,
      isPinned: false,
      createdAt: now,
      updatedAt: now,
    );
    return _persistAccounts([...payload.accounts, account]);
  }

  /// Adds a user-confirmed batch in one encrypted Vault transaction.
  ///
  /// Batch confirmation is responsible for deciding which duplicates to keep;
  /// this method still normalizes every draft before mutating persisted state.
  Future<bool> addAccounts(
    List<AccountDraft> drafts, {
    bool allowDuplicates = false,
  }) async {
    if (drafts.isEmpty) return false;
    final payload = state.payload;
    if (payload == null) return false;

    final normalizedDrafts = <AccountDraft>[];
    for (final draft in drafts) {
      final normalized = _normalizeDraft(draft);
      if (normalized == null) return false;
      if (!allowDuplicates &&
          _isDuplicate(
            payload.accounts,
            normalized,
            additionalDrafts: normalizedDrafts,
          )) {
        continue;
      }
      normalizedDrafts.add(normalized);
    }
    if (normalizedDrafts.isEmpty) {
      state = state.copyWith(message: '所选账号均已存在');
      return false;
    }

    final now = DateTime.now().toUtc();
    final firstSortOrder = payload.accounts.length;
    final newAccounts = <Account>[
      for (var index = 0; index < normalizedDrafts.length; index++)
        Account(
          id: _uuid.v4(),
          issuer: normalizedDrafts[index].issuer,
          accountName: normalizedDrafts[index].accountName,
          secret: normalizedDrafts[index].secret,
          algorithm: normalizedDrafts[index].algorithm,
          digits: normalizedDrafts[index].digits,
          periodSeconds: normalizedDrafts[index].periodSeconds,
          sortOrder: firstSortOrder + index,
          isPinned: false,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    return _persistAccounts([...payload.accounts, ...newAccounts]);
  }

  /// Replaces editable fields while preserving identity and creation metadata.
  Future<bool> updateAccount(String id, AccountDraft draft) async {
    final normalized = _normalizeDraft(draft);
    if (normalized == null) return false;
    final payload = state.payload;
    if (payload == null) return false;
    final index = payload.accounts.indexWhere((account) => account.id == id);
    if (index < 0) {
      state = state.copyWith(message: '找不到要编辑的账号');
      return false;
    }
    if (_isDuplicate(payload.accounts, normalized, excludingId: id)) {
      state = state.copyWith(message: '该账号已经存在');
      return false;
    }
    final current = payload.accounts[index];
    final updated = current.copyWith(
      issuer: normalized.issuer,
      accountName: normalized.accountName,
      secret: normalized.secret,
      algorithm: normalized.algorithm,
      digits: normalized.digits,
      periodSeconds: normalized.periodSeconds,
      updatedAt: DateTime.now().toUtc(),
    );
    final accounts = payload.accounts.toList()..[index] = updated;
    return _persistAccounts(accounts);
  }

  /// Persists a fully prepared restore payload in one encrypted transaction.
  ///
  /// The visible session is replaced only after the repository save succeeds,
  /// so an invalid or interrupted restore cannot modify the current UI state.
  Future<bool> applyRestoredPayload(VaultPayload restoredPayload) async {
    if (!state.isUnlocked || state.isProcessing) return false;
    if (restoredPayload.schemaVersion != VaultPayload.currentSchemaVersion) {
      state = state.copyWith(message: '备份数据版本不受支持。');
      return false;
    }
    state = state.copyWith(isProcessing: true, clearMessage: true);
    try {
      await _repository.save(restoredPayload);
      state = state.copyWith(
        payload: restoredPayload,
        searchQuery: '',
        isProcessing: false,
        clearMessage: true,
      );
      return true;
    } on Object {
      state = state.copyWith(
        isProcessing: false,
        message: '恢复失败，当前 Vault 未被修改。',
      );
      return false;
    }
  }

  /// Creates a locally encrypted account group.
  Future<bool> createGroup(String name) async {
    final payload = state.payload;
    if (payload == null || state.isProcessing) return false;
    final normalizedName = _normalizeGroupName(name);
    if (normalizedName == null) return false;
    if (_hasGroupName(payload.groups, normalizedName)) {
      state = state.copyWith(message: '该分组名称已经存在');
      return false;
    }

    final now = DateTime.now().toUtc();
    final group = <String, Object?>{
      'id': _uuid.v4(),
      'name': normalizedName,
      'sortOrder': payload.groups.length,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    };
    return _persistPayload(
      payload.copyWith(groups: List.unmodifiable([...payload.groups, group])),
    );
  }

  /// Renames a group without changing its identity or account assignments.
  Future<bool> renameGroup(String id, String name) async {
    final payload = state.payload;
    if (payload == null || state.isProcessing) return false;
    final normalizedName = _normalizeGroupName(name);
    if (normalizedName == null) return false;
    final index = payload.groups.indexWhere((group) => group['id'] == id);
    if (index < 0) {
      state = state.copyWith(message: '找不到要编辑的分组');
      return false;
    }
    if (_hasGroupName(payload.groups, normalizedName, excludingId: id)) {
      state = state.copyWith(message: '该分组名称已经存在');
      return false;
    }

    final groups = payload.groups.map(Map<String, Object?>.of).toList();
    groups[index]
      ..['name'] = normalizedName
      ..['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    return _persistPayload(payload.copyWith(groups: List.unmodifiable(groups)));
  }

  /// Deletes a group and atomically moves its accounts to "ungrouped".
  Future<bool> deleteGroup(String id) async {
    final payload = state.payload;
    if (payload == null || state.isProcessing) return false;
    if (!payload.groups.any((group) => group['id'] == id)) {
      state = state.copyWith(message: '找不到要删除的分组');
      return false;
    }

    final now = DateTime.now().toUtc();
    final groups = payload.groups
        .where((group) => group['id'] != id)
        .map(Map<String, Object?>.of)
        .toList(growable: false);
    final accounts = payload.accounts
        .map(
          (account) => account.groupId == id
              ? account.copyWith(clearGroup: true, updatedAt: now)
              : account,
        )
        .toList(growable: false);
    return _persistPayload(
      payload.copyWith(
        groups: List.unmodifiable(groups),
        accounts: List.unmodifiable(accounts),
      ),
    );
  }

  /// Moves an account into a group, or clears its group when [groupId] is null.
  Future<bool> moveAccountToGroup(String accountId, String? groupId) async {
    final payload = state.payload;
    if (payload == null || state.isProcessing) return false;
    if (groupId != null &&
        !payload.groups.any((group) => group['id'] == groupId)) {
      state = state.copyWith(message: '目标分组不存在');
      return false;
    }
    final index = payload.accounts.indexWhere(
      (account) => account.id == accountId,
    );
    if (index < 0) {
      state = state.copyWith(message: '找不到要移动的账号');
      return false;
    }
    final current = payload.accounts[index];
    if (current.groupId == groupId) return true;

    final accounts = payload.accounts.toList();
    accounts[index] = current.copyWith(
      groupId: groupId,
      clearGroup: groupId == null,
      updatedAt: DateTime.now().toUtc(),
    );
    return _persistAccounts(accounts);
  }

  /// Permanently removes one account from the encrypted payload.
  Future<bool> deleteAccount(String id) async {
    final payload = state.payload;
    if (payload == null) return false;
    final accounts = payload.accounts
        .where((account) => account.id != id)
        .toList(growable: false);
    if (accounts.length == payload.accounts.length) return false;
    return _persistAccounts(accounts);
  }

  String? _normalizeGroupName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      state = state.copyWith(message: '请输入分组名称');
      return null;
    }
    if (normalized.runes.length > 40) {
      state = state.copyWith(message: '分组名称最多 40 个字符');
      return null;
    }
    return normalized;
  }

  bool _hasGroupName(
    List<Map<String, Object?>> groups,
    String name, {
    String? excludingId,
  }) {
    final normalized = name.toLowerCase();
    return groups.any(
      (group) =>
          group['id'] != excludingId &&
          (group['name'] as String?)?.trim().toLowerCase() == normalized,
    );
  }

  AccountDraft? _normalizeDraft(AccountDraft draft) {
    final accountName = draft.accountName.trim();
    if (accountName.isEmpty) {
      state = state.copyWith(message: '请输入账号名称');
      return null;
    }
    if (draft.digits != 6 && draft.digits != 8) {
      state = state.copyWith(message: '验证码位数只能是 6 或 8');
      return null;
    }
    if (draft.periodSeconds < 5 || draft.periodSeconds > 300) {
      state = state.copyWith(message: '验证码周期必须在 5 到 300 秒之间');
      return null;
    }
    try {
      return AccountDraft(
        issuer: draft.issuer.trim(),
        accountName: accountName,
        secret: _base32Codec.normalize(draft.secret),
        algorithm: draft.algorithm,
        digits: draft.digits,
        periodSeconds: draft.periodSeconds,
      );
    } on FormatException {
      state = state.copyWith(message: 'Secret 不是有效的 Base32 字符串');
      return null;
    }
  }

  bool _isDuplicate(
    List<Account> accounts,
    AccountDraft draft, {
    String? excludingId,
    List<AccountDraft> additionalDrafts = const [],
  }) {
    bool matchesDraft(String issuer, String accountName, String secret) =>
        issuer.toLowerCase() == draft.issuer.toLowerCase() &&
        accountName.toLowerCase() == draft.accountName.toLowerCase() &&
        secret == draft.secret;
    return accounts.any(
          (account) =>
              account.id != excludingId &&
              matchesDraft(account.issuer, account.accountName, account.secret),
        ) ||
        additionalDrafts.any(
          (candidate) => matchesDraft(
            candidate.issuer,
            candidate.accountName,
            candidate.secret,
          ),
        );
  }

  Future<bool> _persistAccounts(List<Account> accounts) async {
    final payload = state.payload;
    if (payload == null) return false;
    return _persistPayload(
      payload.copyWith(accounts: List.unmodifiable(accounts)),
    );
  }

  Future<bool> _persistPayload(VaultPayload updatedPayload) async {
    if (!state.isUnlocked || state.isProcessing) return false;
    state = state.copyWith(isProcessing: true, clearMessage: true);
    final persistedPayload = updatedPayload.copyWith(
      updatedAt: DateTime.now().toUtc(),
    );
    try {
      await _repository.save(persistedPayload);
      state = state.copyWith(
        payload: persistedPayload,
        isProcessing: false,
        clearMessage: true,
      );
      return true;
    } on Object {
      state = state.copyWith(isProcessing: false, message: '保存失败，原数据未被修改。');
      return false;
    }
  }
}

/// Local Vault persistence implementation used by the session controller.
final vaultRepositoryProvider = Provider<VaultRepository>(
  (ref) => throw UnimplementedError('Vault repository must be overridden.'),
);

final vaultSessionProvider =
    NotifierProvider<VaultSessionController, VaultSessionState>(
      VaultSessionController.new,
    );
