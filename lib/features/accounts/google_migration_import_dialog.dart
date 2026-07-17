import 'package:flutter/material.dart';

import '../../domain/entities/entities.dart';
import '../../domain/import/google_authenticator_migration.dart';

/// User-confirmed selection returned by the Google migration batch dialog.
class GoogleMigrationSelection {
  const GoogleMigrationSelection({
    required this.drafts,
    required this.skippedCount,
    required this.invalidCount,
  });

  final List<AccountDraft> drafts;
  final int skippedCount;
  final int invalidCount;
}

/// Batch confirmation UI that never reveals migration secrets.
class GoogleMigrationImportDialog extends StatefulWidget {
  const GoogleMigrationImportDialog({
    required this.entries,
    required this.existingAccounts,
    super.key,
  });

  final List<GoogleMigrationEntry> entries;
  final List<Account> existingAccounts;

  @override
  State<GoogleMigrationImportDialog> createState() =>
      _GoogleMigrationImportDialogState();
}

class _GoogleMigrationImportDialogState
    extends State<GoogleMigrationImportDialog> {
  final Set<int> _selectedIndexes = {};
  late final Set<int> _existingDuplicateIndexes;
  late final Set<int> _batchDuplicateIndexes;

  int get _validCount => widget.entries.where((entry) => entry.isValid).length;
  int get _invalidCount => widget.entries.length - _validCount;

  @override
  void initState() {
    super.initState();
    _existingDuplicateIndexes = {};
    _batchDuplicateIndexes = {};
    final seen = <String>{};
    for (var index = 0; index < widget.entries.length; index++) {
      final candidate = widget.entries[index].candidate;
      if (candidate == null) continue;
      final isExisting = widget.existingAccounts.any(candidate.isDuplicateOf);
      if (isExisting) _existingDuplicateIndexes.add(index);
      final key = _draftKey(candidate.draft);
      if (!seen.add(key)) _batchDuplicateIndexes.add(index);
      if (!isExisting && !_batchDuplicateIndexes.contains(index)) {
        _selectedIndexes.add(index);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('确认批量导入'),
      content: SizedBox(
        width: 680,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '已完整读取 Google Authenticator 迁移批次。'
                '有效 $_validCount 个，无效 $_invalidCount 个；重复账号默认不勾选。',
                style: TextStyle(color: colors.onTertiaryContainer),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _selectedIndexes
                      ..clear()
                      ..addAll(
                        Iterable<int>.generate(
                          widget.entries.length,
                        ).where((index) => widget.entries[index].isValid),
                      );
                  }),
                  child: const Text('选择全部有效账号'),
                ),
                TextButton(
                  onPressed: () => setState(_selectedIndexes.clear),
                  child: const Text('全部取消'),
                ),
                const Spacer(),
                Text('已选择 ${_selectedIndexes.length} 个'),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: widget.entries.length,
                itemBuilder: (context, index) {
                  final entry = widget.entries[index];
                  final candidate = entry.candidate;
                  final duplicateLabel =
                      _existingDuplicateIndexes.contains(index)
                      ? '已存在'
                      : _batchDuplicateIndexes.contains(index)
                      ? '批次内重复'
                      : null;
                  return CheckboxListTile(
                    key: ValueKey('migration-entry-$index'),
                    value:
                        candidate != null && _selectedIndexes.contains(index),
                    onChanged: candidate == null
                        ? null
                        : (selected) => setState(() {
                            if (selected ?? false) {
                              _selectedIndexes.add(index);
                            } else {
                              _selectedIndexes.remove(index);
                            }
                          }),
                    title: Text(
                      entry.issuer.isEmpty
                          ? entry.accountName
                          : '${entry.issuer} · ${entry.accountName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      candidate == null
                          ? '无法导入：${entry.issue ?? '数据无效'}'
                          : '${candidate.draft.algorithm.otpAuthName} · '
                                '${candidate.draft.digits} 位 · '
                                '${candidate.draft.periodSeconds} 秒'
                                '${duplicateLabel == null ? '' : ' · $duplicateLabel'}',
                    ),
                    secondary: Icon(
                      candidate == null
                          ? Icons.error_outline_rounded
                          : duplicateLabel == null
                          ? Icons.key_rounded
                          : Icons.copy_all_rounded,
                      color: candidate == null ? colors.error : null,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '迁移二维码包含可持续生成验证码的 Secret。导入内容只会写入当前设备的加密 Vault。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selectedIndexes.isEmpty ? null : _submit,
          child: Text('导入 ${_selectedIndexes.length} 个账号'),
        ),
      ],
    );
  }

  void _submit() {
    final drafts = <AccountDraft>[
      for (final index in _selectedIndexes.toList()..sort())
        widget.entries[index].candidate!.draft,
    ];
    Navigator.of(context).pop(
      GoogleMigrationSelection(
        drafts: List.unmodifiable(drafts),
        skippedCount: _validCount - drafts.length,
        invalidCount: _invalidCount,
      ),
    );
  }

  String _draftKey(AccountDraft draft) =>
      '${draft.issuer.toLowerCase()}\u0000'
      '${draft.accountName.toLowerCase()}\u0000${draft.secret}';
}
