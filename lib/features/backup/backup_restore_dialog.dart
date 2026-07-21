import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/providers.dart';
import '../../application/backup/backup_exception.dart';
import '../../domain/backup/backup.dart';
import '../../platform/files/backup_file_service.dart';

/// In-memory restore preview followed by one atomic Vault save.
class BackupRestoreDialog extends ConsumerStatefulWidget {
  const BackupRestoreDialog({super.key, this.initialBackup});

  final PickedBackupFile? initialBackup;

  @override
  ConsumerState<BackupRestoreDialog> createState() =>
      _BackupRestoreDialogState();
}

class _BackupRestoreDialogState extends ConsumerState<BackupRestoreDialog>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  PickedBackupFile? _pickedFile;
  BackupRestorePreview? _preview;
  BackupRestoreMode _mode = BackupRestoreMode.merge;
  bool _isProcessing = false;
  bool _closingForLock = false;
  String? _error;
  String? _resultMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pickedFile = widget.initialBackup;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clearSensitivePreview();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearSensitivePreview(notify: false);
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(vaultSessionProvider);
    if (!session.isUnlocked) {
      _closeForVaultLock();
      return const SizedBox.shrink();
    }
    return AlertDialog(
      title: const Text('从加密备份恢复'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _pickedFile == null
                          ? '尚未选择 .gcbak 文件'
                          : _pickedFile!.name,
                      key: const ValueKey('backup-restore-file-name'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('backup-restore-pick-file'),
                    onPressed: _isProcessing ? null : _pickFile,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('选择备份'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('backup-restore-password'),
                controller: _password,
                obscureText: true,
                enabled: !_isProcessing && _pickedFile != null,
                onSubmitted: (_) => _openPreview(),
                decoration: const InputDecoration(labelText: '备份密码'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('backup-restore-preview'),
                onPressed: _isProcessing || _pickedFile == null
                    ? null
                    : _openPreview,
                icon: const Icon(Icons.visibility_rounded),
                label: const Text('验证并预览'),
              ),
              if (_preview case final preview?) ...[
                const SizedBox(height: 20),
                _PreviewCard(preview: preview),
                const SizedBox(height: 16),
                SegmentedButton<BackupRestoreMode>(
                  key: const ValueKey('backup-restore-mode'),
                  segments: const [
                    ButtonSegment(
                      value: BackupRestoreMode.merge,
                      icon: Icon(Icons.merge_rounded),
                      label: Text('合并'),
                    ),
                    ButtonSegment(
                      value: BackupRestoreMode.replace,
                      icon: Icon(Icons.find_replace_rounded),
                      label: Text('替换'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _isProcessing
                      ? null
                      : (selection) => setState(() => _mode = selection.single),
                ),
                const SizedBox(height: 8),
                Text(
                  _mode == BackupRestoreMode.merge
                      ? '完全重复项会跳过；同名但 Secret 不同的账号会保留为新账号。'
                      : '当前账号、分组和偏好将被备份内容完整替换。建议先导出当前 Vault。',
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_resultMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _resultMessage!,
                  key: const ValueKey('backup-restore-result'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: Text(_resultMessage == null ? '取消' : '完成'),
        ),
        FilledButton.icon(
          key: const ValueKey('backup-restore-apply'),
          onPressed: _isProcessing || _preview == null ? null : _applyRestore,
          icon: _isProcessing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.restore_rounded),
          label: Text(_mode == BackupRestoreMode.merge ? '合并恢复' : '替换恢复'),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    _clearSensitivePreview();
    setState(() {
      _error = null;
      _resultMessage = null;
    });
    try {
      final picked = await ref.read(backupFileServiceProvider).pickBackup();
      if (!mounted || picked == null) return;
      setState(() => _pickedFile = picked);
    } on BackupException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) setState(() => _error = '无法读取所选备份文件。');
    }
  }

  Future<void> _openPreview() async {
    final picked = _pickedFile;
    final current = ref.read(vaultSessionProvider).payload;
    if (picked == null || current == null || _isProcessing) return;
    if (_password.text.isEmpty) {
      setState(() => _error = '请输入备份密码');
      return;
    }
    setState(() {
      _isProcessing = true;
      _error = null;
      _resultMessage = null;
      _preview = null;
    });
    try {
      final preview = await ref
          .read(backupServiceProvider)
          .preview(picked.bytes, _password.text, current);
      if (!mounted) return;
      setState(() => _preview = preview);
    } on BackupException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) setState(() => _error = '备份校验失败，当前 Vault 未被修改。');
    } finally {
      _password.clear();
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _applyRestore() async {
    final preview = _preview;
    final current = ref.read(vaultSessionProvider).payload;
    if (preview == null || current == null || _isProcessing) return;
    if (_mode == BackupRestoreMode.replace && !await _confirmReplace()) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    final result = ref
        .read(backupServiceProvider)
        .prepareRestore(current: current, preview: preview, mode: _mode);
    final success = await ref
        .read(vaultSessionProvider.notifier)
        .applyRestoredPayload(result.payload);
    if (!mounted) return;
    if (success) {
      final message = result.mode == BackupRestoreMode.replace
          ? '已替换恢复 ${result.addedAccountCount} 个账号。'
          : '已新增 ${result.addedAccountCount} 个账号，跳过 ${result.skippedDuplicateCount} 个重复项。';
      _clearSensitivePreview(notify: false);
      setState(() {
        _pickedFile = null;
        _resultMessage = message;
        _isProcessing = false;
      });
    } else {
      setState(() {
        _error =
            ref.read(vaultSessionProvider).message ?? '恢复失败，当前 Vault 未被修改。';
        _isProcessing = false;
      });
    }
  }

  Future<bool> _confirmReplace() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认替换当前 Vault？'),
            content: const Text('替换会覆盖当前账号、分组和偏好。建议先取消并导出当前 Vault 的加密备份。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('返回'),
              ),
              FilledButton(
                key: const ValueKey('backup-restore-confirm-replace'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确认替换'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _clearSensitivePreview({bool notify = true}) {
    _password.clear();
    _preview = null;
    if (notify && mounted) setState(() {});
  }

  void _closeForVaultLock() {
    if (_closingForLock) return;
    _closingForLock = true;
    _clearSensitivePreview(notify: false);
    _pickedFile = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final BackupRestorePreview preview;

  @override
  Widget build(BuildContext context) {
    final summary = preview.summary;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          key: const ValueKey('backup-restore-summary'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('恢复预览', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('账号：${summary.accountCount} · 分组：${summary.groupCount}'),
            Text(
              '可新增：${summary.newAccountCount} · 完全重复：${summary.exactDuplicateCount}',
            ),
            Text('同名冲突：${summary.conflictCount}'),
            const SizedBox(height: 4),
            Text('备份时间：${preview.backupCreatedAt.toLocal()}'),
          ],
        ),
      ),
    );
  }
}
