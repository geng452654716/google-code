import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/providers.dart';
import '../../platform/cloud_backup/cloud_backup_provider.dart';
import '../../platform/cloud_backup/external_url_launcher.dart';
import '../../platform/cloud_backup/github_api_backup_provider.dart';
import '../../platform/files/backup_file_service.dart';

/// Result returned when a cloud backup has been downloaded for restore.
class CloudBackupDialogResult {
  const CloudBackupDialogResult.restore(this.backup);

  final PickedBackupFile backup;
}

/// Manual encrypted upload/download for user-owned cloud destinations.
class CloudBackupDialog extends ConsumerStatefulWidget {
  const CloudBackupDialog({super.key});

  @override
  ConsumerState<CloudBackupDialog> createState() => _CloudBackupDialogState();
}

class _CloudBackupDialogState extends ConsumerState<CloudBackupDialog> {
  CloudBackupProviderType? _processingProvider;
  GitHubConnectionState? _githubConnection;
  bool _loadingGitHub = true;
  bool _closingForLock = false;
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      await Future.wait([
        _refreshGitHubState(),
        ref.read(githubAutoBackupProvider.notifier).initialize(),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(vaultSessionProvider);
    if (!session.isUnlocked) {
      _closeForVaultLock();
      return const SizedBox.shrink();
    }
    final providers = ref.watch(cloudBackupProvidersProvider);
    final autoBackup = ref.watch(githubAutoBackupProvider);
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.cloud_sync_rounded),
          SizedBox(width: 10),
          Text('云备份'),
        ],
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '云端只保存独立密码加密的 .gcbak。iCloud 与 Google Drive 使用桌面同步目录；GitHub 支持登录任意账号并授权专用私有仓库。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              for (final provider in providers) ...[
                if (provider is GitHubCloudBackupProvider)
                  _GitHubProviderCard(
                    provider: provider,
                    connection: _githubConnection,
                    isLoading: _loadingGitHub,
                    isProcessing:
                        _processingProvider == CloudBackupProviderType.github ||
                        autoBackup.isProcessing,
                    disabled:
                        _processingProvider != null || autoBackup.isProcessing,
                    autoBackup: autoBackup,
                    onConnect: () => _connectGitHub(provider),
                    onSelectRepository: () => _selectGitHubRepository(provider),
                    onDisconnect: () => _disconnectGitHub(provider),
                    onUpload: () => _upload(provider),
                    onRestore: () => _restore(provider),
                    onToggleAutoBackup: (enabled) =>
                        _toggleGitHubAutoBackup(enabled),
                  )
                else
                  _CloudProviderCard(
                    provider: provider,
                    isProcessing: _processingProvider == provider.info.type,
                    disabled: _processingProvider != null,
                    onUpload: () => _upload(provider),
                    onRestore: () => _restore(provider),
                  ),
                const SizedBox(height: 12),
              ],
              if (_message != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isError
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _message!,
                    key: const ValueKey('cloud-backup-message'),
                    style: TextStyle(
                      color: _isError
                          ? Theme.of(context).colorScheme.onErrorContainer
                          : Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                '建议使用专用目录或专用私有仓库。GitHub Token 只保存在当前设备的系统安全存储中；设备快速解锁材料不会进入云备份。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _processingProvider == null && !autoBackup.isProcessing
              ? () => Navigator.of(context).pop()
              : null,
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _refreshGitHubState() async {
    final provider = ref.read(githubBackupProvider);
    try {
      final state = await provider.connectionState();
      if (!mounted) return;
      setState(() {
        _githubConnection = state;
        _loadingGitHub = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _githubConnection = const GitHubConnectionState(isConnected: false);
        _loadingGitHub = false;
      });
    }
  }

  Future<void> _connectGitHub(GitHubCloudBackupProvider provider) async {
    if (_processingProvider != null) return;
    _startProcessing(CloudBackupProviderType.github);
    try {
      final code = await provider.startAuthorization();
      if (!mounted) return;
      final authorized = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _GitHubAuthorizationDialog(
          provider: provider,
          launcher: ref.read(externalUrlLauncherProvider),
          code: code,
        ),
      );
      if (!mounted || authorized != true) return;
      await _selectGitHubRepository(provider, keepProcessing: true);
    } on CloudBackupException catch (error) {
      if (mounted) _showError(error.message);
    } on Object {
      if (mounted) _showError('GitHub 连接失败，请稍后重试。');
    } finally {
      await _refreshGitHubState();
      if (mounted) setState(() => _processingProvider = null);
    }
  }

  Future<void> _selectGitHubRepository(
    GitHubCloudBackupProvider provider, {
    bool keepProcessing = false,
  }) async {
    if (!keepProcessing && _processingProvider != null) return;
    if (!keepProcessing) _startProcessing(CloudBackupProviderType.github);
    try {
      final repositories = await provider.listRepositories();
      if (!mounted) return;
      if (repositories.isEmpty) {
        _showError('没有可用的私有仓库。请先把 GitHub App 安装到专用私有仓库，并授予 Contents 写入权限。');
        return;
      }
      final selected = await showDialog<GitHubBackupRepository>(
        context: context,
        builder: (_) => _VaultLockDialogGuard(
          child: _GitHubRepositoryDialog(repositories: repositories),
        ),
      );
      if (!mounted || selected == null) return;
      await provider.selectRepository(selected);
      await ref.read(githubAutoBackupProvider.notifier).initialize(force: true);
      if (!mounted) return;
      setState(() {
        _message = '已选择 GitHub 私有仓库：${selected.fullName}';
        _isError = false;
      });
    } on CloudBackupException catch (error) {
      if (mounted) _showError(error.message);
    } on Object {
      if (mounted) _showError('无法读取 GitHub 仓库列表。');
    } finally {
      await _refreshGitHubState();
      if (!keepProcessing && mounted) {
        setState(() => _processingProvider = null);
      }
    }
  }

  Future<void> _disconnectGitHub(GitHubCloudBackupProvider provider) async {
    if (_processingProvider != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _VaultLockDialogGuard(
        child: AlertDialog(
          title: const Text('断开 GitHub？'),
          content: const Text(
            '这会删除当前设备保存的 GitHub 授权 Token，并关闭自动备份、删除设备中的自动备份密码；不会删除仓库中的加密备份。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('github-disconnect-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('断开'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    _startProcessing(CloudBackupProviderType.github);
    try {
      await ref.read(githubAutoBackupProvider.notifier).disable();
      await provider.disconnect();
      if (!mounted) return;
      setState(() {
        _message = '已断开 GitHub，授权信息和自动备份密码已从当前设备删除。';
        _isError = false;
      });
    } on Object {
      if (mounted) _showError('无法删除当前设备的 GitHub 授权信息。');
    } finally {
      await _refreshGitHubState();
      if (mounted) setState(() => _processingProvider = null);
    }
  }

  Future<void> _toggleGitHubAutoBackup(bool enabled) async {
    if (_processingProvider != null) return;
    final controller = ref.read(githubAutoBackupProvider.notifier);
    if (!enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _VaultLockDialogGuard(
          child: AlertDialog(
            title: const Text('关闭 GitHub 自动备份？'),
            content: const Text(
              '这会删除当前设备系统安全存储中的自动备份密码，不会删除 GitHub 授权或仓库中的加密备份。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey('github-auto-backup-disable-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || confirmed != true) return;
      await controller.disable();
    } else {
      final payload = ref.read(vaultSessionProvider).payload;
      if (payload == null) return;
      final password = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _GitHubAutoBackupPasswordDialog(),
      );
      if (!mounted || password == null) return;
      await controller.enable(password: password, payload: payload);
    }
    if (!mounted) return;
    final state = ref.read(githubAutoBackupProvider);
    setState(() {
      _message = state.notification;
      _isError = state.notificationIsError;
    });
  }

  Future<void> _upload(CloudBackupProvider provider) async {
    final payload = ref.read(vaultSessionProvider).payload;
    if (payload == null || _processingProvider != null) return;
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _CloudBackupPasswordDialog(providerName: provider.info.title),
    );
    if (!mounted ||
        password == null ||
        !ref.read(vaultSessionProvider).isUnlocked) {
      return;
    }
    _startProcessing(provider.info.type);
    try {
      final result = await ref
          .read(cloudBackupServiceProvider)
          .upload(provider: provider, payload: payload, password: password);
      if (!mounted || result == null) return;
      setState(() {
        _message = '${provider.info.title} 加密备份完成。';
        _isError = false;
      });
    } on CloudBackupException catch (error) {
      if (mounted) _showError(error.message);
    } on Object {
      if (mounted) _showError('${provider.info.title} 备份失败，当前 Vault 未被修改。');
    } finally {
      if (mounted) setState(() => _processingProvider = null);
    }
  }

  Future<void> _restore(CloudBackupProvider provider) async {
    if (_processingProvider != null) return;
    _startProcessing(provider.info.type);
    try {
      final backup = await ref
          .read(cloudBackupServiceProvider)
          .downloadLatest(provider);
      if (!mounted || backup == null) return;
      Navigator.of(context).pop(CloudBackupDialogResult.restore(backup));
    } on CloudBackupException catch (error) {
      if (mounted) _showError(error.message);
    } on Object {
      if (mounted) _showError('${provider.info.title} 恢复文件下载失败。');
    } finally {
      if (mounted) setState(() => _processingProvider = null);
    }
  }

  void _startProcessing(CloudBackupProviderType type) {
    setState(() {
      _processingProvider = type;
      _message = null;
      _isError = false;
    });
  }

  void _showError(String message) {
    setState(() {
      _message = message;
      _isError = true;
    });
  }

  /// Closes this sensitive route as soon as the decrypted Vault is locked.
  void _closeForVaultLock() {
    if (_closingForLock) return;
    _closingForLock = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }
}

/// Removes a nested dialog route when the Vault no longer holds decrypted data.
class _VaultLockDialogGuard extends ConsumerStatefulWidget {
  const _VaultLockDialogGuard({required this.child});

  final Widget child;

  @override
  ConsumerState<_VaultLockDialogGuard> createState() =>
      _VaultLockDialogGuardState();
}

class _VaultLockDialogGuardState extends ConsumerState<_VaultLockDialogGuard> {
  bool _closingForLock = false;

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(vaultSessionProvider).isUnlocked) {
      _closeForVaultLock();
      return const SizedBox.shrink();
    }
    return widget.child;
  }

  /// Removes only the guarded dialog route, leaving no orphaned modal behind.
  void _closeForVaultLock() {
    if (_closingForLock) return;
    _closingForLock = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }
}

class _CloudProviderCard extends StatelessWidget {
  const _CloudProviderCard({
    required this.provider,
    required this.isProcessing,
    required this.disabled,
    required this.onUpload,
    required this.onRestore,
  });

  final CloudBackupProvider provider;
  final bool isProcessing;
  final bool disabled;
  final VoidCallback onUpload;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final info = provider.info;
    final icon = switch (info.type) {
      CloudBackupProviderType.iCloudDrive => Icons.cloud_outlined,
      CloudBackupProviderType.googleDrive => Icons.add_to_drive_outlined,
      CloudBackupProviderType.github => Icons.code_rounded,
    };
    return _ProviderCardShell(
      icon: icon,
      title: info.title,
      description: info.description,
      trailing: isProcessing
          ? const CircularProgressIndicator(strokeWidth: 2.5)
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('cloud-restore-${info.type.name}'),
                  onPressed: disabled ? null : onRestore,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('恢复'),
                ),
                FilledButton.icon(
                  key: ValueKey('cloud-upload-${info.type.name}'),
                  onPressed: disabled ? null : onUpload,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('备份'),
                ),
              ],
            ),
    );
  }
}

class _GitHubProviderCard extends StatelessWidget {
  const _GitHubProviderCard({
    required this.provider,
    required this.connection,
    required this.isLoading,
    required this.isProcessing,
    required this.disabled,
    required this.autoBackup,
    required this.onConnect,
    required this.onSelectRepository,
    required this.onDisconnect,
    required this.onUpload,
    required this.onRestore,
    required this.onToggleAutoBackup,
  });

  final GitHubCloudBackupProvider provider;
  final GitHubConnectionState? connection;
  final bool isLoading;
  final bool isProcessing;
  final bool disabled;
  final GitHubAutoBackupState autoBackup;
  final VoidCallback onConnect;
  final VoidCallback onSelectRepository;
  final VoidCallback onDisconnect;
  final VoidCallback onUpload;
  final VoidCallback onRestore;
  final ValueChanged<bool> onToggleAutoBackup;

  @override
  Widget build(BuildContext context) {
    final state = connection;
    final repository = state?.repository;
    final status = !provider.isConfigured
        ? '当前安装包未配置 GitHub App Client ID'
        : state?.isConnected != true
        ? '尚未连接 GitHub'
        : repository == null
        ? '已连接，请选择专用私有仓库'
        : '当前仓库：$repository';

    Widget trailing;
    if (isLoading || isProcessing) {
      trailing = const CircularProgressIndicator(strokeWidth: 2.5);
    } else if (!provider.isConfigured) {
      trailing = const SizedBox.shrink();
    } else if (state?.isConnected != true) {
      trailing = FilledButton.icon(
        key: const ValueKey('github-connect'),
        onPressed: disabled ? null : onConnect,
        icon: const Icon(Icons.login_rounded),
        label: const Text('连接 GitHub'),
      );
    } else if (repository == null) {
      trailing = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            key: const ValueKey('github-disconnect'),
            onPressed: disabled ? null : onDisconnect,
            child: const Text('断开'),
          ),
          FilledButton.icon(
            key: const ValueKey('github-select-repository'),
            onPressed: disabled ? null : onSelectRepository,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('选择私有仓库'),
          ),
        ],
      );
    } else {
      trailing = Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          TextButton(
            key: const ValueKey('github-disconnect'),
            onPressed: disabled ? null : onDisconnect,
            child: const Text('断开'),
          ),
          OutlinedButton(
            key: const ValueKey('github-change-repository'),
            onPressed: disabled ? null : onSelectRepository,
            child: const Text('更换仓库'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('cloud-restore-github'),
            onPressed: disabled ? null : onRestore,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('恢复'),
          ),
          FilledButton.icon(
            key: const ValueKey('cloud-upload-github'),
            onPressed: disabled ? null : onUpload,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('备份'),
          ),
        ],
      );
    }

    return _ProviderCardShell(
      icon: Icons.code_rounded,
      title: provider.info.title,
      description: '${provider.info.description}\n$status',
      trailing: trailing,
      warning: !provider.isConfigured,
      footer: repository == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Material(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                  child: SwitchListTile(
                    key: const ValueKey('github-auto-backup-switch'),
                    contentPadding: EdgeInsets.zero,
                    value: autoBackup.isEnabled,
                    onChanged: disabled ? null : onToggleAutoBackup,
                    title: const Text('新增账号后自动备份'),
                    subtitle: Text(
                      autoBackup.isProcessing
                          ? '正在创建 GitHub 加密备份…'
                          : autoBackup.lastSuccessfulAt == null
                          ? '保存新 GA 后自动上传 .gcbak；备份密码只保存在当前设备。'
                          : '上次成功：${_formatBackupTime(autoBackup.lastSuccessfulAt!)}',
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  String _formatBackupTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _ProviderCardShell extends StatelessWidget {
  const _ProviderCardShell({
    required this.icon,
    required this.title,
    required this.description,
    required this.trailing,
    this.warning = false,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget trailing;
  final bool warning;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: warning
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: warning
                      ? Theme.of(context).colorScheme.onErrorContainer
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: warning
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(child: trailing),
            ],
          ),
          ?footer,
        ],
      ),
    ),
  );
}

class _GitHubAuthorizationDialog extends ConsumerStatefulWidget {
  const _GitHubAuthorizationDialog({
    required this.provider,
    required this.launcher,
    required this.code,
  });

  final GitHubCloudBackupProvider provider;
  final ExternalUrlLauncher launcher;
  final GitHubDeviceCode code;

  @override
  ConsumerState<_GitHubAuthorizationDialog> createState() =>
      _GitHubAuthorizationDialogState();
}

class _GitHubAuthorizationDialogState
    extends ConsumerState<_GitHubAuthorizationDialog> {
  final _cancellation = GitHubAuthorizationCancellation();
  String? _error;
  bool _waiting = true;
  bool _opening = false;
  bool _closingForLock = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_authorize);
  }

  @override
  void dispose() {
    _cancellation.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(vaultSessionProvider).isUnlocked) {
      _closeForVaultLock();
      return const SizedBox.shrink();
    }
    return AlertDialog(
      title: const Text('连接 GitHub'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('浏览器会打开 GitHub。请登录你要使用的账号，输入下面的一次性授权码并确认授权。'),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      widget.code.userCode,
                      key: const ValueKey('github-device-code'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            letterSpacing: 3,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('github-copy-device-code'),
                    tooltip: '复制授权码',
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: widget.code.userCode),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('授权码已复制。')));
                    },
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_waiting)
              const Row(
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.3),
                  ),
                  SizedBox(width: 10),
                  Text('正在等待 GitHub 授权…'),
                ],
              ),
            if (_error != null)
              Text(
                _error!,
                key: const ValueKey('github-authorization-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const ValueKey('github-open-authorization'),
              onPressed: _opening ? null : _openAuthorizationPage,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('重新打开 GitHub 授权页面'),
            ),
          ],
        ),
      ),
      actions: [
        if (_waiting)
          TextButton(
            key: const ValueKey('github-cancel-authorization'),
            onPressed: () {
              _cancellation.cancel();
              Navigator.of(context).pop(false);
            },
            child: const Text('取消连接'),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('关闭'),
          ),
      ],
    );
  }

  Future<void> _authorize() async {
    try {
      await _openAuthorizationPage();
      await widget.provider.finishAuthorization(
        widget.code,
        cancellation: _cancellation,
      );
      if (!mounted || _cancellation.isCancelled) return;
      Navigator.of(context).pop(true);
    } on CloudBackupException catch (error) {
      if (!mounted || _cancellation.isCancelled) return;
      setState(() {
        _waiting = false;
        _error = error.message;
      });
    } on Object {
      if (!mounted || _cancellation.isCancelled) return;
      setState(() {
        _waiting = false;
        _error = 'GitHub 授权失败，请稍后重试。';
      });
    }
  }

  Future<void> _openAuthorizationPage() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.launcher.open(widget.code.verificationUri);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Cancels polling before removing the authorization route on Vault lock.
  void _closeForVaultLock() {
    if (_closingForLock) return;
    _closingForLock = true;
    _cancellation.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }
}

class _GitHubRepositoryDialog extends StatelessWidget {
  const _GitHubRepositoryDialog({required this.repositories});

  final List<GitHubBackupRepository> repositories;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择 GitHub 私有仓库'),
    content: SizedBox(
      width: 500,
      height: repositories.length > 6 ? 390 : null,
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: repositories.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final repository = repositories[index];
          return ListTile(
            key: ValueKey('github-repository-${repository.id}'),
            leading: const Icon(Icons.lock_outline_rounded),
            title: Text(repository.fullName),
            subtitle: const Text('私有仓库'),
            onTap: () => Navigator.of(context).pop(repository),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
    ],
  );
}

class _CloudBackupPasswordDialog extends ConsumerStatefulWidget {
  const _CloudBackupPasswordDialog({required this.providerName});

  final String providerName;

  @override
  ConsumerState<_CloudBackupPasswordDialog> createState() =>
      _CloudBackupPasswordDialogState();
}

class _CloudBackupPasswordDialogState
    extends ConsumerState<_CloudBackupPasswordDialog> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;
  bool _closingForLock = false;

  @override
  void dispose() {
    _password.clear();
    _confirmation.clear();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(vaultSessionProvider).isUnlocked) {
      _closeForVaultLock();
      return const SizedBox.shrink();
    }
    return AlertDialog(
      title: Text('备份到 ${widget.providerName}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请设置本次云备份的独立恢复密码。云服务只能看到加密文件。'),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('cloud-backup-password'),
              controller: _password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '备份密码',
                helperText: '至少 8 个字符，建议与主密码不同',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('cloud-backup-password-confirmation'),
              controller: _confirmation,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: '确认备份密码'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('cloud-backup-password-submit'),
          onPressed: _submit,
          child: const Text('继续'),
        ),
      ],
    );
  }

  void _submit() {
    if (_password.text.length < 8) {
      setState(() => _error = '备份密码至少需要 8 个字符。');
      return;
    }
    if (_password.text != _confirmation.text) {
      setState(() => _error = '两次输入的备份密码不一致。');
      return;
    }
    final value = _password.text;
    _password.clear();
    _confirmation.clear();
    Navigator.of(context).pop(value);
  }

  /// Clears entered backup passwords before removing the route on Vault lock.
  void _closeForVaultLock() {
    if (_closingForLock) return;
    _closingForLock = true;
    _password.clear();
    _confirmation.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }
}

class _GitHubAutoBackupPasswordDialog extends ConsumerStatefulWidget {
  const _GitHubAutoBackupPasswordDialog();

  @override
  ConsumerState<_GitHubAutoBackupPasswordDialog> createState() =>
      _GitHubAutoBackupPasswordDialogState();
}

class _GitHubAutoBackupPasswordDialogState
    extends ConsumerState<_GitHubAutoBackupPasswordDialog> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;
  bool _closingForLock = false;

  @override
  void dispose() {
    _password.clear();
    _confirmation.clear();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(vaultSessionProvider).isUnlocked) {
      _closeForVaultLock();
      return const SizedBox.shrink();
    }
    return AlertDialog(
      title: const Text('开启 GitHub 自动备份'),
      content: SizedBox(
        width: 470,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('设置独立恢复密码后，会先备份当前 Vault；以后每次新增 GA 都会自动上传最新加密备份。'),
            const SizedBox(height: 10),
            Text(
              '密码只保存在当前设备的 Keychain 或 Credential Manager，不会写入 Vault、GitHub、备份文件或日志。换电脑恢复时仍需记得此密码。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('github-auto-backup-password'),
              controller: _password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '自动备份密码',
                helperText: '至少 8 个字符，建议与主密码不同',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('github-auto-backup-password-confirmation'),
              controller: _confirmation,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: '确认自动备份密码'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('github-auto-backup-enable-submit'),
          onPressed: _submit,
          child: const Text('开启并立即备份'),
        ),
      ],
    );
  }

  void _submit() {
    if (_password.text.length < 8) {
      setState(() => _error = '自动备份密码至少需要 8 个字符。');
      return;
    }
    if (_password.text != _confirmation.text) {
      setState(() => _error = '两次输入的自动备份密码不一致。');
      return;
    }
    final value = _password.text;
    _password.clear();
    _confirmation.clear();
    Navigator.of(context).pop(value);
  }

  void _closeForVaultLock() {
    if (_closingForLock) return;
    _closingForLock = true;
    _password.clear();
    _confirmation.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }
}
