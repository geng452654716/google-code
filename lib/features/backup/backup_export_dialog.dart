import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/providers.dart';
import '../../application/backup/backup_exception.dart';
import '../../core/security/password_policy.dart';

/// Password-protected `.gcbak` export flow with no clear intermediate file.
class BackupExportDialog extends ConsumerStatefulWidget {
  const BackupExportDialog({super.key});

  @override
  ConsumerState<BackupExportDialog> createState() => _BackupExportDialogState();
}

class _BackupExportDialogState extends ConsumerState<BackupExportDialog> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _passwordPolicy = const PasswordPolicy();
  bool _isProcessing = false;
  bool _closingForLock = false;
  String? _error;
  String? _savedPath;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
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
      title: const Text('导出加密备份'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('备份包含账号、分组、排序和本地偏好，所有内容会使用独立密码重新加密。'),
              const SizedBox(height: 12),
              const _SecurityNotice(text: '备份密码可以不同于主密码；如果忘记该密码，备份将无法恢复。'),
              const SizedBox(height: 18),
              TextField(
                key: const ValueKey('backup-export-password'),
                controller: _password,
                obscureText: true,
                enabled: !_isProcessing,
                decoration: const InputDecoration(labelText: '备份密码'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('backup-export-confirmation'),
                controller: _confirmation,
                obscureText: true,
                enabled: !_isProcessing,
                onSubmitted: (_) => _export(),
                decoration: const InputDecoration(labelText: '确认备份密码'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_savedPath != null) ...[
                const SizedBox(height: 16),
                SelectableText(
                  '备份已保存到：\n$_savedPath',
                  key: const ValueKey('backup-export-saved-path'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: Text(_savedPath == null ? '取消' : '完成'),
        ),
        FilledButton.icon(
          key: const ValueKey('backup-export-submit'),
          onPressed: _isProcessing ? null : _export,
          icon: _isProcessing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_alt_rounded),
          label: Text(_isProcessing ? '正在加密…' : '选择位置并导出'),
        ),
      ],
    );
  }

  Future<void> _export() async {
    final payload = ref.read(vaultSessionProvider).payload;
    if (payload == null || _isProcessing) return;
    final password = _password.text;
    final validation = _passwordPolicy.validate(password, label: '备份密码');
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    if (password != _confirmation.text) {
      setState(() => _error = '两次输入的备份密码不一致');
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = null;
      _savedPath = null;
    });
    Uint8List? encryptedBytes;
    try {
      encryptedBytes = await ref
          .read(backupServiceProvider)
          .export(payload, password);
      _clearPasswords();
      final now = DateTime.now();
      final date =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final saved = await ref
          .read(backupFileServiceProvider)
          .saveBackup(
            encryptedBytes,
            suggestedName: 'google-code-backup-$date.gcbak',
          );
      if (!mounted) return;
      setState(() {
        _savedPath = saved?.path;
        if (saved == null) {
          _error = '已取消保存，未创建备份文件。';
        }
      });
    } on BackupException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) setState(() => _error = '导出失败，未创建备份文件。');
    } finally {
      _clearPasswords();
      encryptedBytes?.fillRange(0, encryptedBytes.length, 0);
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _clearPasswords() {
    _password.clear();
    _confirmation.clear();
  }

  void _closeForVaultLock() {
    if (_closingForLock) return;
    _closingForLock = true;
    _clearPasswords();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }
}

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
