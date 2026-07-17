import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../app/state/providers.dart';
import '../../application/import/otp_import_service.dart';
import '../../domain/entities/entities.dart';
import '../../domain/import/google_authenticator_migration.dart';
import '../../domain/import/otp_import_candidate.dart';
import '../../domain/totp/totp.dart';
import '../../platform/clipboard/clipboard_import_reader.dart';
import '../../platform/screenshot/screen_capture_service.dart';
import 'account_editor_dialog.dart';
import 'account_share_dialog.dart';
import 'google_migration_import_dialog.dart';
import '../backup/backup_center_dialog.dart';
import '../backup/backup_export_dialog.dart';
import '../backup/backup_restore_dialog.dart';
import '../security/security_settings_dialog.dart';

/// Main unlocked account list backed by the encrypted local Vault.
class AccountsPage extends ConsumerStatefulWidget {
  const AccountsPage({required this.onToggleTheme, super.key});

  final VoidCallback onToggleTheme;

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  final _totpService = TotpService();
  final _codes = <String, String>{};
  final _remaining = <String, int>{};
  late final Timer _ticker;
  bool _isImporting = false;
  GoogleMigrationBatchAccumulator? _migrationBatch;

  @override
  void initState() {
    super.initState();
    _refreshCodes();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshCodes(),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  Future<void> _refreshCodes() async {
    final session = ref.read(vaultSessionProvider);
    final accounts = session.payload?.accounts ?? const <Account>[];
    final now = DateTime.now();
    final entries = await Future.wait(
      accounts.map((account) async {
        final config = account.toTotpConfig();
        return (
          account.id,
          await _totpService.generate(config, now),
          _totpService.remainingSeconds(config, now),
        );
      }),
    );
    if (!mounted) return;
    setState(() {
      _codes
        ..clear()
        ..addEntries(entries.map((entry) => MapEntry(entry.$1, entry.$2)));
      _remaining
        ..clear()
        ..addEntries(entries.map((entry) => MapEntry(entry.$1, entry.$3)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(vaultSessionProvider);
    final accounts = session.visibleAccounts;
    return Focus(
      autofocus: true,
      onKeyEvent: _handlePasteShortcut,
      child: Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _NavigationRail(
                onToggleTheme: widget.onToggleTheme,
                onBackup: _showBackupCenter,
                onSecurity: _showSecuritySettings,
                onLock: () => ref.read(vaultSessionProvider.notifier).lock(),
              ),
              Expanded(
                child: Column(
                  children: [
                    _Header(
                      accountCount: session.payload?.accounts.length ?? 0,
                      onSearch: ref
                          .read(vaultSessionProvider.notifier)
                          .setSearchQuery,
                    ),
                    if (_migrationBatch case final batch?)
                      _MigrationProgressBanner(
                        received: batch.receivedPartCount,
                        total: batch.batchSize,
                        isImporting: _isImporting,
                        onContinueImage: _importFromImage,
                        onContinueScreenshot: _importFromScreenshot,
                        onCancel: () => setState(() => _migrationBatch = null),
                      ),
                    Expanded(
                      child: accounts.isEmpty
                          ? _EmptyState(
                              isSearching: session.searchQuery
                                  .trim()
                                  .isNotEmpty,
                              onAdd: _showAddOptions,
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                32,
                                8,
                                32,
                                100,
                              ),
                              itemCount: accounts.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final account = accounts[index];
                                return _AccountCard(
                                  account: account,
                                  code:
                                      _codes[account.id] ??
                                      (account.digits == 8
                                          ? '--------'
                                          : '------'),
                                  remainingSeconds:
                                      _remaining[account.id] ??
                                      account.periodSeconds,
                                  onCopy: () => _copyCode(account),
                                  onEdit: () => _showEditDialog(account),
                                  onShare: () => _showShareDialog(account),
                                  onDelete: () => _confirmDelete(account),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: session.isProcessing || _isImporting
              ? null
              : _showAddOptions,
          icon: _isImporting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_rounded),
          label: Text(_isImporting ? '正在解析…' : '添加账号'),
        ),
      ),
    );
  }

  /// Opens backup export or restore only after the entry dialog closes.
  Future<void> _showBackupCenter() async {
    final action = await showDialog<BackupCenterAction>(
      context: context,
      builder: (_) => const BackupCenterDialog(),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case BackupCenterAction.export:
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const BackupExportDialog(),
        );
      case BackupCenterAction.restore:
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const BackupRestoreDialog(),
        );
    }
  }

  /// Handles desktop paste shortcuts without stealing paste from text fields.
  KeyEventResult _handlePasteShortcut(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyV) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isMetaPressed && !keyboard.isControlPressed) {
      return KeyEventResult.ignored;
    }

    final focusContext = FocusManager.instance.primaryFocus?.context;
    final isEditingText =
        focusContext != null &&
        (focusContext.widget is EditableText ||
            focusContext.findAncestorWidgetOfExactType<EditableText>() != null);
    if (isEditingText) return KeyEventResult.ignored;

    unawaited(_importFromClipboard());
    return KeyEventResult.handled;
  }

  Future<void> _showAddOptions() async {
    final action = await showDialog<_AddAccountAction>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('添加账号'),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(_AddAccountAction.manualOrUri),
            child: const ListTile(
              leading: Icon(Icons.edit_note_rounded),
              title: Text('手动输入或链接'),
              subtitle: Text('输入 Base32 Secret，或粘贴 otpauth:// 链接'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(_AddAccountAction.qrImage),
            child: const ListTile(
              leading: Icon(Icons.image_search_rounded),
              title: Text('从二维码图片导入'),
              subtitle: Text('支持普通二维码和 Google Authenticator 多张迁移批次'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(_AddAccountAction.screenshot),
            child: const ListTile(
              leading: Icon(Icons.crop_free_rounded),
              title: Text('区域截图扫描'),
              subtitle: Text('框选屏幕区域并识别二维码'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(_AddAccountAction.clipboard),
            child: const ListTile(
              leading: Icon(Icons.content_paste_search_rounded),
              title: Text('从剪贴板导入'),
              subtitle: Text('读取二维码图片或 otpauth:// 链接（⌘/Ctrl + V）'),
            ),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _AddAccountAction.manualOrUri:
        await _showAddDialog();
      case _AddAccountAction.qrImage:
        await _importFromImage();
      case _AddAccountAction.screenshot:
        await _importFromScreenshot();
      case _AddAccountAction.clipboard:
        await _importFromClipboard();
    }
  }

  Future<void> _importFromImage() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final selected = await ref.read(imageImportPickerProvider).pickImage();
      if (selected == null || !mounted) return;
      final result = await ref
          .read(otpImportServiceProvider)
          .decodeImageBytes(selected.bytes);
      if (!mounted) return;
      await _handleImportResult(result, successMessage: '二维码账号已加密保存');
    } on OtpImportException catch (error) {
      if (mounted) _showMessage(error.message);
    } on Object {
      if (mounted) _showMessage('无法读取所选图片，请检查文件权限或更换图片。');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  /// Captures a selected screen region and reuses the QR import pipeline.
  Future<void> _importFromScreenshot() async {
    if (_isImporting || ref.read(vaultSessionProvider).isProcessing) return;
    setState(() => _isImporting = true);
    try {
      final bytes = await ref
          .read(screenCaptureServiceProvider)
          .captureRegion();
      if (bytes == null || !mounted) return;
      final result = await ref
          .read(otpImportServiceProvider)
          .decodeImageBytes(bytes, source: OtpImportSource.screenshot);
      if (!mounted) return;
      await _handleImportResult(result, successMessage: '区域截图账号已加密保存');
    } on ScreenCaptureException catch (error) {
      if (!mounted) return;
      if (error.kind == ScreenCaptureFailureKind.permissionDenied) {
        await _showScreenCapturePermissionDialog(error.message);
      } else {
        _showMessage(error.message);
      }
    } on OtpImportException catch (error) {
      if (mounted) _showMessage(error.message);
    } on Object {
      if (mounted) _showMessage('区域截图导入失败，请重试或改用二维码图片导入。');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  /// Explains macOS permission requirements and optionally opens System Settings.
  Future<void> _showScreenCapturePermissionDialog(String message) async {
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要屏幕录制权限'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('打开系统设置'),
          ),
        ],
      ),
    );
    if (openSettings != true || !mounted) return;
    try {
      await ref.read(screenCaptureServiceProvider).openPermissionSettings();
    } on ScreenCaptureException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  /// Reads a QR image or otpauth URI from the clipboard and confirms import.
  Future<void> _importFromClipboard() async {
    if (_isImporting || ref.read(vaultSessionProvider).isProcessing) return;
    setState(() => _isImporting = true);
    try {
      final clipboard = await ref.read(clipboardImportReaderProvider).read();
      if (!mounted) return;
      if (clipboard == null) {
        _showMessage('剪贴板中没有可导入的二维码图片或 otpauth:// 链接。');
        return;
      }

      final service = ref.read(otpImportServiceProvider);
      final result = switch (clipboard) {
        ClipboardImageData(:final bytes) => await service.decodeImageBytes(
          bytes,
          source: OtpImportSource.clipboardImage,
        ),
        ClipboardTextData(:final text) => service.decodeQrText(
          text,
          source: OtpImportSource.clipboardText,
        ),
      };
      if (!mounted) return;
      await _handleImportResult(result, successMessage: '剪贴板账号已加密保存');
    } on ClipboardImportReadException catch (error) {
      if (mounted) _showMessage(error.message);
    } on OtpImportException catch (error) {
      if (mounted) _showMessage(error.message);
    } on Object {
      if (mounted) _showMessage('剪贴板导入失败，请重新复制后重试。');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  /// Routes a decoded QR to either single-account or migration confirmation.
  Future<void> _handleImportResult(
    OtpImportResult result, {
    required String successMessage,
  }) async {
    switch (result) {
      case SingleOtpImportResult(:final candidate):
        await _confirmImportCandidate(
          candidate,
          successMessage: successMessage,
        );
      case GoogleMigrationOtpImportResult(:final part):
        await _handleMigrationPart(part);
    }
  }

  /// Accumulates multi-QR migration parts and persists only after a complete batch.
  Future<void> _handleMigrationPart(GoogleMigrationPart part) async {
    final current = _migrationBatch;
    if (current == null) {
      _migrationBatch = GoogleMigrationBatchAccumulator.fromPart(part);
    } else {
      late final GoogleMigrationPartAddResult addResult;
      try {
        addResult = current.add(part);
      } on FormatException {
        _showMessage('当前迁移批次尚未完成，请继续扫描同一批次的二维码，或先取消当前批次。');
        return;
      }
      if (addResult == GoogleMigrationPartAddResult.duplicate) {
        _showMessage('这张迁移二维码已经读取过，请扫描批次中的下一张。');
        return;
      }
    }

    final batch = _migrationBatch!;
    if (!batch.isComplete) {
      setState(() {});
      _showMessage(
        '已读取迁移批次 ${batch.receivedPartCount}/${batch.batchSize} 张，请继续扫描。',
      );
      return;
    }

    final entries = batch.entries;
    setState(() => _migrationBatch = null);
    final existingAccounts =
        ref.read(vaultSessionProvider).payload?.accounts ?? const <Account>[];
    final selection = await showDialog<GoogleMigrationSelection>(
      context: context,
      barrierDismissible: false,
      builder: (context) => GoogleMigrationImportDialog(
        entries: entries,
        existingAccounts: existingAccounts,
      ),
    );
    if (selection == null || selection.drafts.isEmpty || !mounted) return;

    final saved = await ref
        .read(vaultSessionProvider.notifier)
        .addAccounts(selection.drafts, allowDuplicates: true);
    if (!saved || !mounted) {
      final message = ref.read(vaultSessionProvider).message;
      if (message != null) _showMessage(message);
      return;
    }
    await _refreshCodes();
    if (!mounted) return;
    _showMessage(
      '批量导入完成：成功 ${selection.drafts.length}，'
      '跳过 ${selection.skippedCount}，无效 ${selection.invalidCount}',
    );
  }

  /// Shows the shared editable confirmation flow before encrypted persistence.
  Future<void> _confirmImportCandidate(
    OtpImportCandidate candidate, {
    required String successMessage,
  }) async {
    final existingAccounts =
        ref.read(vaultSessionProvider).payload?.accounts ?? const <Account>[];
    final isDuplicate = existingAccounts.any(candidate.isDuplicateOf);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AccountEditorDialog(
        initialDraft: candidate.draft,
        importSourceLabel: candidate.sourceLabel,
        isDuplicate: isDuplicate,
      ),
    );
    if (saved == true) {
      await _refreshCodes();
      if (mounted) _showMessage(successMessage);
    }
  }

  Future<void> _showAddDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AccountEditorDialog(),
    );
    if (saved == true) {
      await _refreshCodes();
      if (mounted) _showMessage('账号已加密保存');
    }
  }

  Future<void> _showEditDialog(Account account) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AccountEditorDialog(account: account),
    );
    if (saved == true) {
      await _refreshCodes();
      if (mounted) _showMessage('账号已更新');
    }
  }

  Future<void> _copyCode(Account account) async {
    final code = _codes[account.id];
    if (code == null) return;
    await ref.read(sensitiveClipboardServiceProvider).writeText(code);
    if (mounted) _showMessage('验证码已复制，60 秒后尝试清理剪贴板');
  }

  /// Opens device-only quick-unlock and authentication settings.
  Future<void> _showSecuritySettings() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const SecuritySettingsDialog(),
    );
  }

  /// Opens the high-risk single-account export flow with fresh authentication.
  Future<void> _showShareDialog(Account account) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AccountShareDialog(
        account: account,
        writeSensitiveText: (text, ttl) => ref
            .read(sensitiveClipboardServiceProvider)
            .writeText(text, ttl: ttl),
      ),
    );
  }

  Future<void> _confirmDelete(Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账号？'),
        content: Text(
          '将永久删除 ${account.issuer.isEmpty ? account.accountName : '${account.issuer} · ${account.accountName}'}。此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await ref
        .read(vaultSessionProvider.notifier)
        .deleteAccount(account.id);
    if (deleted && mounted) _showMessage('账号已删除');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MigrationProgressBanner extends StatelessWidget {
  const _MigrationProgressBanner({
    required this.received,
    required this.total,
    required this.isImporting,
    required this.onContinueImage,
    required this.onContinueScreenshot,
    required this.onCancel,
  });

  final int received;
  final int total;
  final bool isImporting;
  final VoidCallback onContinueImage;
  final VoidCallback onContinueScreenshot;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(32, 0, 32, 16),
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.qr_code_scanner_rounded,
            color: colors.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Google Authenticator 迁移批次：已读取 $received/$total 张',
              style: TextStyle(color: colors.onSecondaryContainer),
            ),
          ),
          TextButton(
            onPressed: isImporting ? null : onContinueImage,
            child: const Text('继续选择图片'),
          ),
          TextButton(
            onPressed: isImporting ? null : onContinueScreenshot,
            child: const Text('继续截图'),
          ),
          TextButton(
            onPressed: isImporting ? null : onCancel,
            child: const Text('取消批次'),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.accountCount, required this.onSearch});

  final int accountCount;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('验证码', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 5),
                Text(
                  '$accountCount 个账号 · 数据仅保存在当前设备',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 280,
            child: SearchBar(
              hintText: '搜索账号或服务',
              leading: const Icon(Icons.search_rounded),
              onChanged: onSearch,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({
    required this.onToggleTheme,
    required this.onBackup,
    required this.onSecurity,
    required this.onLock,
  });

  final VoidCallback onToggleTheme;
  final VoidCallback onBackup;
  final VoidCallback onSecurity;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.shield_rounded, color: colors.onPrimary),
          ),
          const SizedBox(height: 28),
          IconButton.filledTonal(
            tooltip: '验证码',
            onPressed: () {},
            icon: const Icon(Icons.password_rounded),
          ),
          const Spacer(),
          IconButton(
            key: const ValueKey('open-security-settings'),
            tooltip: '安全设置',
            onPressed: onSecurity,
            icon: const Icon(Icons.security_rounded),
          ),
          IconButton(
            key: const ValueKey('open-backup-center'),
            tooltip: '备份与恢复',
            onPressed: onBackup,
            icon: const Icon(Icons.settings_backup_restore_rounded),
          ),
          IconButton(
            tooltip: '切换主题',
            onPressed: onToggleTheme,
            icon: const Icon(Icons.contrast_rounded),
          ),
          IconButton(
            tooltip: '立即锁定',
            onPressed: onLock,
            icon: const Icon(Icons.lock_outline_rounded),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isSearching, required this.onAdd});

  final bool isSearching;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSearching ? Icons.search_off_rounded : Icons.password_rounded,
              size: 58,
              color: colors.primary,
            ),
            const SizedBox(height: 16),
            Text(
              isSearching ? '没有匹配的账号' : '还没有验证码账号',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              isSearching ? '尝试调整搜索关键词' : '可以手动输入 Secret，或粘贴 otpauth:// 链接。',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            if (!isSearching) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加第一个账号'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.code,
    required this.remainingSeconds,
    required this.onCopy,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
  });

  final Account account;
  final String code;
  final int remainingSeconds;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final formattedCode = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code.length == 8
        ? '${code.substring(0, 4)} ${code.substring(4)}'
        : code;
    final displayIssuer = account.issuer.isEmpty ? '未命名服务' : account.issuer;
    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: colors.primaryContainer,
              child: Text(
                (displayIssuer.characters.isEmpty
                        ? account.accountName.characters.first
                        : displayIssuer.characters.first)
                    .toUpperCase(),
                style: TextStyle(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayIssuer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    account.accountName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              label: '验证码 $code',
              button: true,
              child: InkWell(
                onTap: onCopy,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    formattedCode,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: remainingSeconds / account.periodSeconds,
                    strokeWidth: 3,
                    backgroundColor: colors.surfaceContainerHighest,
                  ),
                  Text(
                    '$remainingSeconds',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '复制验证码',
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded),
            ),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'share') onShare();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.ios_share_rounded),
                      SizedBox(width: 10),
                      Text('分享账号'),
                    ],
                  ),
                ),
                PopupMenuDivider(),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// User-selected account creation entry point.
enum _AddAccountAction { manualOrUri, qrImage, screenshot, clipboard }
