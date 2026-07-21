import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/vault_payload.dart';
import '../../platform/cloud_backup/cloud_backup_provider.dart';
import 'cloud_backup_providers.dart';

const _githubAutoBackupPasswordKey = 'cloud.github.auto-backup-password.v1';

/// Distinguishes account-addition feedback from configuration feedback.
enum GitHubAutoBackupNotificationSource { configuration, accountAddition }

/// Device-local state for GitHub automatic encrypted backups.
class GitHubAutoBackupState {
  const GitHubAutoBackupState({
    this.isInitialized = false,
    this.isEnabled = false,
    this.isProcessing = false,
    this.lastSuccessfulAt,
    this.notification,
    this.notificationId = 0,
    this.notificationIsError = false,
    this.notificationSource = GitHubAutoBackupNotificationSource.configuration,
  });

  final bool isInitialized;
  final bool isEnabled;
  final bool isProcessing;
  final DateTime? lastSuccessfulAt;
  final String? notification;
  final int notificationId;
  final bool notificationIsError;
  final GitHubAutoBackupNotificationSource notificationSource;

  GitHubAutoBackupState copyWith({
    bool? isInitialized,
    bool? isEnabled,
    bool? isProcessing,
    DateTime? lastSuccessfulAt,
    String? notification,
    int? notificationId,
    bool? notificationIsError,
    GitHubAutoBackupNotificationSource? notificationSource,
    bool clearLastSuccessfulAt = false,
    bool clearNotification = false,
  }) => GitHubAutoBackupState(
    isInitialized: isInitialized ?? this.isInitialized,
    isEnabled: isEnabled ?? this.isEnabled,
    isProcessing: isProcessing ?? this.isProcessing,
    lastSuccessfulAt: clearLastSuccessfulAt
        ? null
        : lastSuccessfulAt ?? this.lastSuccessfulAt,
    notification: clearNotification ? null : notification ?? this.notification,
    notificationId: notificationId ?? this.notificationId,
    notificationIsError: notificationIsError ?? this.notificationIsError,
    notificationSource: notificationSource ?? this.notificationSource,
  );
}

/// Boundary used by account mutations so tests can replace cloud scheduling.
abstract interface class AccountAdditionBackupScheduler {
  Future<void> scheduleAfterAccountAddition(VaultPayload payload);
}

final githubAutoBackupProvider =
    NotifierProvider<GitHubAutoBackupController, GitHubAutoBackupState>(
      GitHubAutoBackupController.new,
    );

final accountAdditionBackupSchedulerProvider =
    Provider<AccountAdditionBackupScheduler>(
      (ref) => ref.watch(githubAutoBackupProvider.notifier),
    );

/// Stores an independent backup password in device secure storage and queues
/// GitHub uploads after successful account additions.
class GitHubAutoBackupController extends Notifier<GitHubAutoBackupState>
    implements AccountAdditionBackupScheduler {
  bool _initialized = false;
  Future<void>? _initializeFuture;
  bool _isDraining = false;
  VaultPayload? _pendingPayload;

  @override
  GitHubAutoBackupState build() => const GitHubAutoBackupState();

  /// Reconciles the secure password with the locally stored GitHub session.
  Future<void> initialize({bool force = false}) async {
    final activeInitialization = _initializeFuture;
    if (activeInitialization != null) {
      await activeInitialization;
      if (!force) return;
    }
    if (_initialized && !force) return;

    final operation = _reconcileStoredConfiguration();
    _initializeFuture = operation;
    try {
      await operation;
      _initialized = true;
    } finally {
      if (identical(_initializeFuture, operation)) {
        _initializeFuture = null;
      }
    }
  }

  Future<void> _reconcileStoredConfiguration() async {
    Uint8List? passwordBytes;
    try {
      passwordBytes = await ref
          .read(deviceSecretStoreProvider)
          .read(_githubAutoBackupPasswordKey);
      final connection = await ref.read(githubBackupProvider).connectionState();
      final canRun =
          passwordBytes != null &&
          passwordBytes.isNotEmpty &&
          connection.isConnected &&
          connection.repository != null;
      if (!canRun && passwordBytes != null) {
        await ref
            .read(deviceSecretStoreProvider)
            .delete(_githubAutoBackupPasswordKey);
      }
      state = state.copyWith(
        isInitialized: true,
        isEnabled: canRun,
        isProcessing: false,
        clearNotification: true,
        clearLastSuccessfulAt: !canRun,
      );
    } on Object {
      state = state.copyWith(
        isInitialized: true,
        isEnabled: false,
        isProcessing: false,
        clearLastSuccessfulAt: true,
      );
    } finally {
      passwordBytes?.fillRange(0, passwordBytes.length, 0);
    }
  }

  /// Enables automatic backup and verifies the configuration with an upload.
  Future<bool> enable({
    required String password,
    required VaultPayload payload,
  }) async {
    if (state.isProcessing) return false;
    if (password.length < 8) {
      _notify(
        '备份密码至少需要 8 个字符。',
        isError: true,
        source: GitHubAutoBackupNotificationSource.configuration,
      );
      return false;
    }
    state = state.copyWith(isProcessing: true, clearNotification: true);
    Uint8List? passwordBytes;
    try {
      final connection = await ref.read(githubBackupProvider).connectionState();
      if (!connection.isConnected || connection.repository == null) {
        throw const CloudBackupException('请先连接 GitHub 并选择用于备份的私有仓库。');
      }
      passwordBytes = Uint8List.fromList(utf8.encode(password));
      await ref
          .read(deviceSecretStoreProvider)
          .write(_githubAutoBackupPasswordKey, passwordBytes);
      final result = await ref
          .read(cloudBackupServiceProvider)
          .upload(
            provider: ref.read(githubBackupProvider),
            payload: payload,
            password: password,
          );
      if (result == null) {
        throw const CloudBackupException('GitHub 自动备份未完成，请重试。');
      }
      state = state.copyWith(
        isInitialized: true,
        isEnabled: true,
        isProcessing: false,
        lastSuccessfulAt: result.createdAt,
      );
      _notify(
        'GitHub 自动备份已开启，并已备份当前 Vault。',
        source: GitHubAutoBackupNotificationSource.configuration,
      );
      return true;
    } on CloudBackupException catch (error) {
      await _deletePasswordIgnoringErrors();
      state = state.copyWith(
        isInitialized: true,
        isEnabled: false,
        isProcessing: false,
        clearLastSuccessfulAt: true,
      );
      _notify(
        error.message,
        isError: true,
        source: GitHubAutoBackupNotificationSource.configuration,
      );
      return false;
    } on Object {
      await _deletePasswordIgnoringErrors();
      state = state.copyWith(
        isInitialized: true,
        isEnabled: false,
        isProcessing: false,
        clearLastSuccessfulAt: true,
      );
      _notify(
        '无法开启 GitHub 自动备份，请稍后重试。',
        isError: true,
        source: GitHubAutoBackupNotificationSource.configuration,
      );
      return false;
    } finally {
      passwordBytes?.fillRange(0, passwordBytes.length, 0);
    }
  }

  /// Disables automatic backup without removing GitHub authorization or files.
  Future<void> disable() async {
    _pendingPayload = null;
    await _deletePasswordIgnoringErrors();
    state = state.copyWith(
      isInitialized: true,
      isEnabled: false,
      isProcessing: false,
      clearLastSuccessfulAt: true,
    );
    _notify(
      'GitHub 自动备份已关闭。',
      source: GitHubAutoBackupNotificationSource.configuration,
    );
  }

  /// Coalesces rapid imports and uploads only the newest persisted payload.
  @override
  Future<void> scheduleAfterAccountAddition(VaultPayload payload) async {
    try {
      await initialize();
      if (!state.isEnabled) return;
      _pendingPayload = payload;
      if (_isDraining) return;
      _isDraining = true;
      while (true) {
        final pending = _pendingPayload;
        if (pending == null) break;
        _pendingPayload = null;
        await _uploadAddedAccounts(pending);
      }
    } on Object {
      _notify(
        '账号已保存，但 GitHub 自动备份失败，请稍后重试。',
        isError: true,
        source: GitHubAutoBackupNotificationSource.accountAddition,
      );
    } finally {
      _isDraining = false;
    }
  }

  Future<void> _uploadAddedAccounts(VaultPayload payload) async {
    state = state.copyWith(isProcessing: true, clearNotification: true);
    Uint8List? passwordBytes;
    try {
      passwordBytes = await ref
          .read(deviceSecretStoreProvider)
          .read(_githubAutoBackupPasswordKey);
      if (passwordBytes == null || passwordBytes.isEmpty) {
        state = state.copyWith(isEnabled: false, isProcessing: false);
        _notify(
          '账号已保存，但自动备份密码已丢失，GitHub 自动备份已关闭。',
          isError: true,
          source: GitHubAutoBackupNotificationSource.accountAddition,
        );
        return;
      }
      final password = utf8.decode(passwordBytes);
      final result = await ref
          .read(cloudBackupServiceProvider)
          .upload(
            provider: ref.read(githubBackupProvider),
            payload: payload,
            password: password,
          );
      if (result == null) {
        throw const CloudBackupException('GitHub 未返回备份结果。');
      }
      state = state.copyWith(
        isProcessing: false,
        lastSuccessfulAt: result.createdAt,
      );
      _notify(
        '新增账号已自动备份到 GitHub。',
        source: GitHubAutoBackupNotificationSource.accountAddition,
      );
    } on CloudBackupException catch (error) {
      state = state.copyWith(isProcessing: false);
      _notify(
        '账号已保存，但 GitHub 自动备份失败：${error.message}',
        isError: true,
        source: GitHubAutoBackupNotificationSource.accountAddition,
      );
    } on Object {
      state = state.copyWith(isProcessing: false);
      _notify(
        '账号已保存，但 GitHub 自动备份失败，请稍后重试。',
        isError: true,
        source: GitHubAutoBackupNotificationSource.accountAddition,
      );
    } finally {
      passwordBytes?.fillRange(0, passwordBytes.length, 0);
    }
  }

  Future<void> _deletePasswordIgnoringErrors() async {
    try {
      await ref
          .read(deviceSecretStoreProvider)
          .delete(_githubAutoBackupPasswordKey);
    } on Object {
      // The state still becomes disabled; a later initialize retries cleanup.
    }
  }

  void _notify(
    String message, {
    bool isError = false,
    required GitHubAutoBackupNotificationSource source,
  }) {
    state = state.copyWith(
      notification: message,
      notificationId: state.notificationId + 1,
      notificationIsError: isError,
      notificationSource: source,
    );
  }
}
