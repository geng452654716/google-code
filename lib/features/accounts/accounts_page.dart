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
import '../../platform/files/image_import_picker.dart';
import '../../platform/screenshot/screen_capture_service.dart';
import 'account_editor_dialog.dart';
import 'camera_qr_scanner_dialog.dart';
import 'account_share_dialog.dart';
import 'google_migration_import_dialog.dart';
import '../backup/backup_center_dialog.dart';
import '../backup/backup_export_dialog.dart';
import '../backup/backup_restore_dialog.dart';
import '../security/security_settings_dialog.dart';

enum _ScreenCapturePermissionAction { cancel, openSettings, restart }

const _ungroupedGroupId = '__ungrouped__';

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
  bool _isPickingImage = false;
  GoogleMigrationBatchAccumulator? _migrationBatch;
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _refreshCodes();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshCodes(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_offerQuickUnlockOnboarding());
    });
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
    final allAccounts = session.payload?.accounts ?? const <Account>[];
    final groups = _AccountGroupView.fromPayload(session.payload?.groups);
    final visibleAccounts = session.visibleAccounts
        .where((account) {
          if (_selectedGroupId == null) {
            return true;
          }
          if (_selectedGroupId == _ungroupedGroupId) {
            return account.groupId == null;
          }
          return account.groupId == _selectedGroupId;
        })
        .toList(growable: false);
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
                      accountCount: allAccounts.length,
                      onSearch: ref
                          .read(vaultSessionProvider.notifier)
                          .setSearchQuery,
                    ),
                    if (_migrationBatch case final batch?)
                      _MigrationProgressBanner(
                        received: batch.receivedPartCount,
                        total: batch.batchSize,
                        isImporting: _isImporting,
                        onContinueCamera: _importFromCamera,
                        onContinueImage: _importFromImage,
                        onContinueScreenshot: _importFromScreenshot,
                        onCancel: () => setState(() => _migrationBatch = null),
                      ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _GroupSidebar(
                            groups: groups,
                            accounts: allAccounts,
                            selectedGroupId: _selectedGroupId,
                            isProcessing: session.isProcessing,
                            onSelect: (groupId) =>
                                setState(() => _selectedGroupId = groupId),
                            onCreate: _showCreateGroupDialog,
                            onRename: _showRenameGroupDialog,
                            onDelete: _confirmDeleteGroup,
                            onMoveAccount: _moveAccountToGroup,
                          ),
                          VerticalDivider(
                            width: 1,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          Expanded(
                            child: visibleAccounts.isEmpty
                                ? _EmptyState(
                                    isSearching:
                                        session.searchQuery.trim().isNotEmpty ||
                                        _selectedGroupId != null,
                                    onAdd: _showAddOptions,
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                      28,
                                      8,
                                      32,
                                      100,
                                    ),
                                    itemCount: visibleAccounts.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final account = visibleAccounts[index];
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
                                        onShare: () =>
                                            _showShareDialog(account),
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
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: session.isProcessing || _isImporting || _isPickingImage
              ? null
              : _showAddOptions,
          icon: _isImporting || _isPickingImage
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_rounded),
          label: Text(
            _isPickingImage
                ? '等待选择图片…'
                : _isImporting
                ? '正在解析…'
                : '添加账号',
          ),
        ),
      ),
    );
  }

  Future<String?> _showGroupNameDialog({
    required String title,
    String initialValue = '',
  }) async {
    var value = initialValue;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          key: const ValueKey('group-name-field'),
          initialValue: initialValue,
          autofocus: true,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '分组名称',
            hintText: '例如：工作、个人、服务器',
          ),
          onChanged: (text) => value = text,
          onFieldSubmitted: (text) {
            if (text.trim().isNotEmpty) Navigator.of(context).pop(text);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('save-group-name'),
            onPressed: () => Navigator.of(context).pop(value),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateGroupDialog() async {
    final name = await _showGroupNameDialog(title: '新建分组');
    if (name == null || !mounted) return;
    final created = await ref
        .read(vaultSessionProvider.notifier)
        .createGroup(name);
    if (!mounted) return;
    if (created) {
      _showMessage('分组已创建');
    } else {
      _showMessage(ref.read(vaultSessionProvider).message ?? '创建分组失败');
    }
  }

  Future<void> _showRenameGroupDialog(_AccountGroupView group) async {
    final name = await _showGroupNameDialog(
      title: '重命名分组',
      initialValue: group.name,
    );
    if (name == null || !mounted) return;
    final renamed = await ref
        .read(vaultSessionProvider.notifier)
        .renameGroup(group.id, name);
    if (!mounted) return;
    if (renamed) {
      _showMessage('分组已重命名');
    } else {
      _showMessage(ref.read(vaultSessionProvider).message ?? '重命名分组失败');
    }
  }

  Future<void> _confirmDeleteGroup(_AccountGroupView group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${group.name}」？'),
        content: const Text('删除分组不会删除其中的验证码账号，账号将移到“未分组”。'),
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
            child: const Text('删除分组'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final deleted = await ref
        .read(vaultSessionProvider.notifier)
        .deleteGroup(group.id);
    if (!mounted) return;
    if (deleted) {
      if (_selectedGroupId == group.id) {
        setState(() => _selectedGroupId = _ungroupedGroupId);
      }
      _showMessage('分组已删除，账号已移到未分组');
    } else {
      _showMessage(ref.read(vaultSessionProvider).message ?? '删除分组失败');
    }
  }

  Future<void> _moveAccountToGroup(
    String accountId,
    String? groupId,
    String destinationName,
  ) async {
    final moved = await ref
        .read(vaultSessionProvider.notifier)
        .moveAccountToGroup(accountId, groupId);
    if (!mounted) return;
    if (moved) {
      _showMessage(groupId == null ? '已移到未分组' : '已移动到「$destinationName」');
    } else {
      _showMessage(ref.read(vaultSessionProvider).message ?? '移动账号失败');
    }
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
                Navigator.of(context).pop(_AddAccountAction.camera),
            child: const ListTile(
              leading: Icon(Icons.qr_code_scanner_rounded),
              title: Text('摄像头扫描'),
              subtitle: Text('使用本机摄像头扫描普通二维码或迁移二维码'),
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
              title: Text('扫描屏幕二维码'),
              subtitle: Text('窗口会暂时离开屏幕；拖动框选二维码，Esc 取消'),
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
      case _AddAccountAction.camera:
        await _importFromCamera();
      case _AddAccountAction.qrImage:
        await _importFromImage();
      case _AddAccountAction.screenshot:
        await _importFromScreenshot();
      case _AddAccountAction.clipboard:
        await _importFromClipboard();
    }
  }

  /// Opens the desktop camera scanner and reuses the shared confirmation flow.
  Future<void> _importFromCamera() async {
    if (_isImporting || ref.read(vaultSessionProvider).isProcessing) return;
    setState(() => _isImporting = true);
    try {
      final result = await showDialog<OtpImportResult>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const CameraQrScannerDialog(),
      );
      if (result == null || !mounted) return;
      await _handleImportResult(result, successMessage: '摄像头二维码账号已加密保存');
    } on Object {
      if (mounted) _showMessage('摄像头扫描失败，请重新打开扫描窗口。');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _importFromImage() async {
    if (_isImporting ||
        _isPickingImage ||
        ref.read(vaultSessionProvider).isProcessing) {
      return;
    }

    PickedImageData? selected;
    setState(() => _isPickingImage = true);
    try {
      // Let the Flutter dialog finish dismissing before macOS attaches its
      // native open panel to the same window.
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      selected = await ref.read(imageImportPickerProvider).pickImage();
    } on Object {
      if (mounted) _showMessage('无法打开图片选择窗口，请重新尝试。');
      return;
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
    if (selected == null || !mounted) return;

    setState(() => _isImporting = true);
    try {
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
    final shouldCapture = await _confirmScreenshotCapture();
    if (!mounted || !shouldCapture) return;
    setState(() => _isImporting = true);
    try {
      final bytes = await ref
          .read(screenCaptureServiceProvider)
          .captureRegion();
      if (bytes == null || !mounted) {
        if (mounted) _showMessage('已取消屏幕二维码扫描，应用窗口已恢复。');
        return;
      }
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

  /// Explains the native selector before the app window temporarily leaves the screen.
  Future<bool> _confirmScreenshotCapture() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('扫描屏幕二维码'),
        content: const Text(
          '开始后应用窗口会暂时离开屏幕，鼠标会变成系统截图的十字光标。\n\n'
          '请拖动框选二维码；如需取消，请按 Esc。完成或取消后，应用窗口会自动恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('暂不扫描'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.crop_free_rounded),
            label: const Text('开始框选'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Distinguishes missing permission from a grant that needs an app restart.
  Future<void> _showScreenCapturePermissionDialog(String message) async {
    final action = await showDialog<_ScreenCapturePermissionAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('屏幕录制权限尚未生效'),
        content: Text(
          '$message\n\n'
          '首次授权或安装新版本后，macOS 可能需要彻底重启应用才能让权限生效。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(_ScreenCapturePermissionAction.cancel),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(_ScreenCapturePermissionAction.openSettings),
            child: const Text('打开系统设置'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(_ScreenCapturePermissionAction.restart),
            child: const Text('退出并重新打开'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    try {
      switch (action) {
        case _ScreenCapturePermissionAction.openSettings:
          final destination = await ref
              .read(screenCaptureServiceProvider)
              .openPermissionSettings();
          if (!mounted) return;
          _showMessage(
            destination == ScreenCaptureSettingsDestination.screenRecording
                ? '已打开屏幕录制权限。请开启当前应用，然后点“退出并重新打开”。'
                : '已打开系统设置。请进入“隐私与安全性”→“屏幕与系统音频录制”，开启当前应用后彻底重启。',
          );
          return;
        case _ScreenCapturePermissionAction.restart:
          await ref.read(screenCaptureServiceProvider).restartApplication();
          return;
        case _ScreenCapturePermissionAction.cancel || null:
          return;
      }
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

  /// Offers quick unlock once for Vaults that have not handled onboarding.
  Future<void> _offerQuickUnlockOnboarding() async {
    final session = ref.read(vaultSessionProvider);
    if (session.payload?.preferences['quickUnlockOnboardingDismissed'] ==
        true) {
      return;
    }
    final status = await ref.read(quickUnlockServiceProvider).inspect();
    if (!mounted || status.isConfigured || !status.canEnable) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const SecuritySettingsDialog(isOnboarding: true),
    );
    if (!mounted) return;
    await ref
        .read(vaultSessionProvider.notifier)
        .markQuickUnlockOnboardingSeen();
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
    required this.onContinueCamera,
    required this.onContinueImage,
    required this.onContinueScreenshot,
    required this.onCancel,
  });

  final int received;
  final int total;
  final bool isImporting;
  final VoidCallback onContinueCamera;
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
            onPressed: isImporting ? null : onContinueCamera,
            child: const Text('继续摄像头扫描'),
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

class _AccountGroupView {
  const _AccountGroupView({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final int sortOrder;

  static List<_AccountGroupView> fromPayload(
    List<Map<String, Object?>>? source,
  ) {
    final groups = <_AccountGroupView>[];
    for (final value in source ?? const <Map<String, Object?>>[]) {
      final id = value['id'];
      final name = value['name'];
      if (id is! String ||
          id.isEmpty ||
          name is! String ||
          name.trim().isEmpty) {
        continue;
      }
      groups.add(
        _AccountGroupView(
          id: id,
          name: name.trim(),
          sortOrder: value['sortOrder'] is int
              ? value['sortOrder']! as int
              : groups.length,
        ),
      );
    }
    groups.sort((left, right) {
      final order = left.sortOrder.compareTo(right.sortOrder);
      return order != 0
          ? order
          : left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return groups;
  }
}

typedef _MoveAccountToGroup =
    Future<void> Function(
      String accountId,
      String? groupId,
      String destinationName,
    );

class _GroupSidebar extends StatelessWidget {
  const _GroupSidebar({
    required this.groups,
    required this.accounts,
    required this.selectedGroupId,
    required this.isProcessing,
    required this.onSelect,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
    required this.onMoveAccount,
  });

  final List<_AccountGroupView> groups;
  final List<Account> accounts;
  final String? selectedGroupId;
  final bool isProcessing;
  final ValueChanged<String?> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<_AccountGroupView> onRename;
  final ValueChanged<_AccountGroupView> onDelete;
  final _MoveAccountToGroup onMoveAccount;

  @override
  Widget build(BuildContext context) {
    final ungroupedCount = accounts
        .where((account) => account.groupId == null)
        .length;
    return SizedBox(
      width: 236,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 2, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '分组',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('create-group-button'),
                    tooltip: '新建分组',
                    onPressed: isProcessing ? null : onCreate,
                    icon: const Icon(Icons.create_new_folder_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  _GroupDropTile(
                    key: const ValueKey('group-filter-all'),
                    label: '全部账号',
                    icon: Icons.all_inbox_rounded,
                    count: accounts.length,
                    selected: selectedGroupId == null,
                    acceptsDrop: false,
                    isProcessing: isProcessing,
                    onTap: () => onSelect(null),
                    onMoveAccount: onMoveAccount,
                  ),
                  const SizedBox(height: 4),
                  _GroupDropTile(
                    key: const ValueKey('group-drop-ungrouped'),
                    label: '未分组',
                    icon: Icons.folder_off_rounded,
                    count: ungroupedCount,
                    selected: selectedGroupId == _ungroupedGroupId,
                    acceptsDrop: true,
                    isProcessing: isProcessing,
                    onTap: () => onSelect(_ungroupedGroupId),
                    onMoveAccount: onMoveAccount,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1),
                  ),
                  for (final group in groups) ...[
                    _GroupDropTile(
                      key: ValueKey('group-drop-${group.id}'),
                      label: group.name,
                      icon: Icons.folder_rounded,
                      count: accounts
                          .where((account) => account.groupId == group.id)
                          .length,
                      selected: selectedGroupId == group.id,
                      destinationGroupId: group.id,
                      acceptsDrop: true,
                      isProcessing: isProcessing,
                      onTap: () => onSelect(group.id),
                      onMoveAccount: onMoveAccount,
                      trailing: PopupMenuButton<String>(
                        tooltip: '分组操作',
                        enabled: !isProcessing,
                        onSelected: (value) {
                          if (value == 'rename') onRename(group);
                          if (value == 'delete') onDelete(group);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'rename', child: Text('重命名')),
                          PopupMenuItem(value: 'delete', child: Text('删除分组')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (groups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                      child: Text(
                        '创建分组后，可拖动账号卡片左侧的手柄进行整理。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupDropTile extends StatelessWidget {
  const _GroupDropTile({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.acceptsDrop,
    required this.isProcessing,
    required this.onTap,
    required this.onMoveAccount,
    this.destinationGroupId,
    this.trailing,
    super.key,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final bool acceptsDrop;
  final bool isProcessing;
  final VoidCallback onTap;
  final _MoveAccountToGroup onMoveAccount;
  final String? destinationGroupId;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => acceptsDrop && !isProcessing,
      onAcceptWithDetails: (details) {
        onTap();
        unawaited(onMoveAccount(details.data, destinationGroupId, label));
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isHovering
                ? Border.all(color: colors.primary, width: 1.5)
                : null,
          ),
          child: Material(
            color: isHovering
                ? colors.primaryContainer
                : selected
                ? colors.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              dense: true,
              minLeadingWidth: 22,
              contentPadding: const EdgeInsets.only(left: 10, right: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(icon, size: 20),
              title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: isHovering ? const Text('松开以移动') : null,
              trailing:
                  trailing ??
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('$count'),
                  ),
              selected: selected,
              onTap: onTap,
            ),
          ),
        );
      },
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

    Widget dragHandle() => Draggable<String>(
      key: ValueKey('account-drag-handle-${account.id}'),
      data: account.id,
      rootOverlay: true,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 280,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                blurRadius: 16,
                color: Color(0x33000000),
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.drag_indicator_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$displayIssuer · ${account.accountName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: Icon(
          Icons.drag_indicator_rounded,
          color: colors.onSurfaceVariant,
        ),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(
          message: '拖动到分组',
          child: Icon(
            Icons.drag_indicator_rounded,
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );

    Widget avatar() => CircleAvatar(
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
    );

    Widget identity() => Column(
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
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );

    Widget codeButton() => Semantics(
      label: '验证码 $code',
      button: true,
      child: InkWell(
        onTap: onCopy,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
    );

    Widget countdown() => SizedBox(
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
    );

    Widget copyButton() => IconButton(
      tooltip: '复制验证码',
      onPressed: onCopy,
      icon: const Icon(Icons.copy_rounded),
    );

    Widget actionsMenu() => PopupMenuButton<String>(
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
    );

    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 10, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      dragHandle(),
                      const SizedBox(width: 8),
                      avatar(),
                      const SizedBox(width: 12),
                      Expanded(child: identity()),
                      actionsMenu(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const SizedBox(width: 28),
                      Expanded(child: codeButton()),
                      countdown(),
                      copyButton(),
                    ],
                  ),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: Row(
              children: [
                dragHandle(),
                const SizedBox(width: 10),
                avatar(),
                const SizedBox(width: 16),
                Expanded(child: identity()),
                codeButton(),
                const SizedBox(width: 14),
                countdown(),
                copyButton(),
                actionsMenu(),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// User-selected account creation entry point.
enum _AddAccountAction { manualOrUri, camera, qrImage, screenshot, clipboard }
