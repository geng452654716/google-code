import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/providers.dart';
import '../../application/security/quick_unlock_service.dart';
import '../../platform/auth/local_authentication_service.dart';

/// Manages device-only quick unlock without changing the master-password root.
class SecuritySettingsDialog extends ConsumerStatefulWidget {
  const SecuritySettingsDialog({this.isOnboarding = false, super.key});

  /// Uses first-run copy while retaining the same password + device-auth flow.
  final bool isOnboarding;

  @override
  ConsumerState<SecuritySettingsDialog> createState() =>
      _SecuritySettingsDialogState();
}

class _SecuritySettingsDialogState
    extends ConsumerState<SecuritySettingsDialog> {
  final _passwordController = TextEditingController();
  QuickUnlockStatus? _status;
  bool _isBusy = false;
  bool _obscurePassword = true;
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _passwordController
      ..clear()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = _status;
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.isOnboarding
                ? Icons.fingerprint_rounded
                : Icons.security_rounded,
          ),
          const SizedBox(width: 10),
          Text(widget.isOnboarding ? '启用 Touch ID 快速解锁' : '安全设置'),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: status == null
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isOnboarding &&
                        !status.isConfigured &&
                        status.canEnable) ...[
                      Text(
                        '保险库已创建。建议现在启用 ${status.authenticationName}，以后无需每次输入主密码。',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 14),
                    ],
                    _StatusCard(status: status),
                    const SizedBox(height: 18),
                    Text(
                      '快速解锁只在当前设备的系统安全存储中保存 Vault 数据加密密钥副本。'
                      '主密码仍是恢复根凭据，独立 .gcbak 备份不会包含快速解锁材料。',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    if (!status.isConfigured && status.canEnable) ...[
                      const SizedBox(height: 20),
                      const Text('启用前必须重新验证主密码，并完成一次设备认证。'),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('quick-unlock-master-password'),
                        controller: _passwordController,
                        enabled: !_isBusy,
                        obscureText: _obscurePassword,
                        onSubmitted: (_) => _enable(),
                        decoration: InputDecoration(
                          labelText: '主密码',
                          prefixIcon: const Icon(Icons.password_rounded),
                          suffixIcon: IconButton(
                            onPressed: _isBusy
                                ? null
                                : () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (_message case final message?) ...[
                      const SizedBox(height: 14),
                      Text(
                        message,
                        style: TextStyle(
                          color: _isError ? colors.error : colors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          child: Text(widget.isOnboarding ? '稍后' : '关闭'),
        ),
        if (status?.isConfigured == true)
          FilledButton.tonalIcon(
            key: const ValueKey('disable-quick-unlock'),
            onPressed: _isBusy ? null : _disable,
            icon: const Icon(Icons.phonelink_erase_rounded),
            label: const Text('禁用快速解锁'),
          )
        else if (status?.canEnable == true)
          FilledButton.icon(
            key: const ValueKey('enable-quick-unlock'),
            onPressed: _isBusy ? null : _enable,
            icon: _isBusy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fingerprint_rounded),
            label: Text(_isBusy ? '正在启用…' : '启用快速解锁'),
          ),
      ],
    );
  }

  Future<void> _refreshStatus() async {
    final status = await ref.read(quickUnlockServiceProvider).inspect();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _enable() async {
    if (_passwordController.text.isEmpty) {
      _setMessage('请输入主密码。', isError: true);
      return;
    }
    setState(() {
      _isBusy = true;
      _message = null;
    });
    final result = await ref
        .read(quickUnlockServiceProvider)
        .enable(_passwordController.text);
    _passwordController.clear();
    if (!mounted) return;
    switch (result) {
      case QuickUnlockEnableResult.enabled:
        _setMessage('快速解锁已在当前设备启用。');
        await _refreshStatus();
      case QuickUnlockEnableResult.wrongPassword:
        _setMessage('主密码错误，未启用快速解锁。', isError: true);
      case QuickUnlockEnableResult.cancelled:
        _setMessage('已取消设备认证。');
      case QuickUnlockEnableResult.unavailable:
        _setMessage('设备认证当前不可用。', isError: true);
      case QuickUnlockEnableResult.failed:
        _setMessage('启用失败，未保存快速解锁材料。', isError: true);
    }
    if (mounted) setState(() => _isBusy = false);
  }

  Future<void> _disable() async {
    setState(() {
      _isBusy = true;
      _message = null;
    });
    final disabled = await ref.read(quickUnlockServiceProvider).disable();
    if (!mounted) return;
    _setMessage(disabled ? '当前设备的快速解锁材料已删除。' : '禁用失败，请重试。', isError: !disabled);
    await _refreshStatus();
    if (mounted) setState(() => _isBusy = false);
  }

  void _setMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _isError = isError;
    });
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final QuickUnlockStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, title, detail, background) = switch ((
      status.authenticationAvailability,
      status.isConfigured,
    )) {
      (DeviceAuthenticationAvailability.available, true) => (
        Icons.verified_user_rounded,
        '快速解锁已启用',
        '可使用 ${status.authenticationName} 解锁及重新认证敏感操作。',
        colors.primaryContainer,
      ),
      (DeviceAuthenticationAvailability.available, false) => (
        Icons.lock_person_rounded,
        '快速解锁未启用',
        '${status.authenticationName} 可用，可在当前设备安全启用。',
        colors.secondaryContainer,
      ),
      (DeviceAuthenticationAvailability.notEnrolled, _) => (
        Icons.no_accounts_rounded,
        '设备认证尚未配置',
        '请先在系统设置中配置设备密码、生物识别或 Windows Hello。',
        colors.errorContainer,
      ),
      _ => (
        Icons.gpp_bad_rounded,
        '设备认证不可用',
        '当前系统无法提供快速解锁，请继续使用主密码。',
        colors.errorContainer,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
