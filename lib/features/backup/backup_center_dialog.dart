import 'package:flutter/material.dart';

/// User-selected encrypted backup operation.
enum BackupCenterAction { export, restore }

/// Entry dialog for encrypted backup export and restore operations.
class BackupCenterDialog extends StatelessWidget {
  const BackupCenterDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('备份与恢复'),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('导出加密备份'),
            subtitle: const Text('创建独立密码保护的 .gcbak 文件'),
            onTap: () => Navigator.of(context).pop(BackupCenterAction.export),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore_rounded),
            title: const Text('从备份恢复'),
            subtitle: const Text('先预览，再选择合并或替换当前 Vault'),
            onTap: () => Navigator.of(context).pop(BackupCenterAction.restore),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
    ],
  );
}
