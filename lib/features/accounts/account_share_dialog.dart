import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/providers.dart';
import '../../application/share/account_share_service.dart';
import '../../domain/entities/account.dart';
import '../../platform/auth/local_authentication_service.dart';

/// Sensitive clipboard writer supplied by the unlocked account page.
typedef SensitiveShareTextWriter =
    Future<void> Function(String text, Duration ttl);

/// Reauthenticates and reveals one account's portable credentials temporarily.
class AccountShareDialog extends ConsumerStatefulWidget {
  const AccountShareDialog({
    required this.account,
    required this.writeSensitiveText,
    this.revealDuration = const Duration(seconds: 60),
    super.key,
  });

  final Account account;
  final SensitiveShareTextWriter writeSensitiveText;
  final Duration revealDuration;

  @override
  ConsumerState<AccountShareDialog> createState() => _AccountShareDialogState();
}

enum _ShareFormat { secret, uri, qr }

class _AccountShareDialogState extends ConsumerState<AccountShareDialog>
    with WidgetsBindingObserver {
  final _passwordController = TextEditingController();
  Timer? _concealTimer;
  Timer? _countdownTimer;
  AccountShareMaterial? _material;
  _ShareFormat _format = _ShareFormat.secret;
  bool _showSensitiveText = false;
  bool _isAuthenticating = false;
  bool _isSaving = false;
  bool _isClosingForVaultLock = false;
  bool _canUseDeviceAuthentication = false;
  String _deviceAuthenticationName = '设备认证';
  int _remainingSeconds = 0;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inspectDeviceAuthentication();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelTimers();
    _passwordController
      ..clear()
      ..dispose();
    _material = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _conceal('窗口已失焦，分享内容已隐藏，请重新验证。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUnlocked = ref.watch(vaultSessionProvider).isUnlocked;
    if (!isUnlocked) {
      _material = null;
      if (!_isClosingForVaultLock) {
        _isClosingForVaultLock = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final route = ModalRoute.of(context);
          if (route != null) {
            Navigator.of(context, rootNavigator: true).removeRoute(route);
          }
        });
      }
      return const SizedBox.shrink();
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text('分享账号凭据')),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: _material == null
              ? _buildReauthentication(context)
              : _buildShareContent(context, _material!),
        ),
      ),
      actions: _material == null
          ? [
              TextButton(
                onPressed: _isAuthenticating
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: _isAuthenticating ? null : _authenticate,
                icon: _isAuthenticating
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open_rounded),
                label: Text(_isAuthenticating ? '正在验证…' : '验证并继续'),
              ),
            ]
          : [
              TextButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
              FilledButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => _conceal('分享内容已隐藏，如需继续请重新验证。'),
                icon: const Icon(Icons.visibility_off_rounded),
                label: const Text('完成并隐藏'),
              ),
            ],
    );
  }

  Widget _buildReauthentication(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayName = widget.account.issuer.isEmpty
        ? widget.account.accountName
        : '${widget.account.issuer} · ${widget.account.accountName}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.gpp_maybe_rounded, color: colors.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '获得 Secret、链接或二维码的人可以长期生成该账号的验证码。'
                  '分享后无法在本应用内撤销，只能到对应服务重新绑定二次验证。',
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text('账号', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(displayName, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 18),
        const Text('每次分享都必须重新输入主密码。当前应用已解锁不代表可以直接导出凭据。'),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('share-master-password'),
          controller: _passwordController,
          autofocus: true,
          obscureText: true,
          enabled: !_isAuthenticating,
          onSubmitted: (_) => _authenticate(),
          decoration: InputDecoration(
            labelText: '主密码',
            errorText: _error,
            prefixIcon: const Icon(Icons.password_rounded),
          ),
        ),
        if (_canUseDeviceAuthentication) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('share-device-authentication'),
              onPressed: _isAuthenticating ? null : _authenticateWithDevice,
              icon: const Icon(Icons.fingerprint_rounded),
              label: Text('使用 $_deviceAuthenticationName 验证'),
            ),
          ),
        ],
        if (_status case final status?) ...[
          const SizedBox(height: 12),
          Text(status, style: TextStyle(color: colors.primary)),
        ],
      ],
    );
  }

  Widget _buildShareContent(
    BuildContext context,
    AccountShareMaterial material,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_rounded, color: colors.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '高风险内容：将在 $_remainingSeconds 秒后自动隐藏，窗口失焦时立即隐藏。',
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<_ShareFormat>(
          segments: const [
            ButtonSegment(
              value: _ShareFormat.secret,
              icon: Icon(Icons.key_rounded),
              label: Text('Secret'),
            ),
            ButtonSegment(
              value: _ShareFormat.uri,
              icon: Icon(Icons.link_rounded),
              label: Text('链接'),
            ),
            ButtonSegment(
              value: _ShareFormat.qr,
              icon: Icon(Icons.qr_code_2_rounded),
              label: Text('二维码'),
            ),
          ],
          selected: {_format},
          onSelectionChanged: (selection) {
            setState(() {
              _format = selection.single;
              _showSensitiveText = false;
              _error = null;
            });
          },
        ),
        const SizedBox(height: 18),
        switch (_format) {
          _ShareFormat.secret => _buildTextMaterial(
            context,
            title: 'Base32 Secret',
            visibleText: _groupSecret(material.secret),
            concealedText: '•••• •••• •••• ••••',
            copyLabel: '复制 Secret',
            onCopy: () => _copyText(material.secret, 'Secret'),
          ),
          _ShareFormat.uri => _buildTextMaterial(
            context,
            title: '标准 otpauth:// 链接',
            visibleText: material.otpAuthUri,
            concealedText: 'otpauth://totp/••••••••••••',
            copyLabel: '复制链接',
            onCopy: () => _copyText(material.otpAuthUri, '链接'),
          ),
          _ShareFormat.qr => _buildQrMaterial(context, material),
        },
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          Text(error, style: TextStyle(color: colors.error)),
        ],
      ],
    );
  }

  Widget _buildTextMaterial(
    BuildContext context, {
    required String title,
    required String visibleText,
    required String concealedText,
    required String copyLabel,
    required VoidCallback onCopy,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          SelectableText(
            _showSensitiveText ? visibleText : concealedText,
            key: ValueKey('share-sensitive-${_format.name}'),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    setState(() => _showSensitiveText = !_showSensitiveText),
                icon: Icon(
                  _showSensitiveText
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
                label: Text(_showSensitiveText ? '隐藏内容' : '显示内容'),
              ),
              FilledButton.tonalIcon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded),
                label: Text(copyLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQrMaterial(BuildContext context, AccountShareMaterial material) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          color: Colors.white,
          child: Image.memory(
            material.qrPng,
            key: const ValueKey('account-share-qr'),
            width: 280,
            height: 280,
            filterQuality: FilterQuality.none,
          ),
        ),
        const SizedBox(height: 12),
        const Text('二维码包含完整 Secret。请只让受信任的认证器或设备扫描。'),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _isSaving ? null : () => _saveQr(material),
          icon: _isSaving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_alt_rounded),
          label: Text(_isSaving ? '正在保存…' : '保存二维码 PNG'),
        ),
      ],
    );
  }

  Future<void> _inspectDeviceAuthentication() async {
    final status = await ref.read(quickUnlockServiceProvider).inspect();
    if (!mounted) return;
    setState(() {
      _canUseDeviceAuthentication = status.canUse;
      _deviceAuthenticationName = status.authenticationName;
    });
  }

  Future<void> _authenticateWithDevice() async {
    setState(() {
      _isAuthenticating = true;
      _error = null;
      _status = null;
    });
    final result = await ref
        .read(quickUnlockServiceProvider)
        .reauthenticate(reason: '验证后分享 TOTP 账号凭据');
    if (!mounted) return;
    switch (result) {
      case DeviceAuthenticationResult.authenticated:
        _revealShareMaterial();
      case DeviceAuthenticationResult.cancelled:
        setState(() {
          _isAuthenticating = false;
          _status = '已取消设备认证。';
        });
      case DeviceAuthenticationResult.unavailable:
        setState(() {
          _isAuthenticating = false;
          _canUseDeviceAuthentication = false;
          _error = '设备认证当前不可用，请输入主密码。';
        });
      case DeviceAuthenticationResult.failed:
        setState(() {
          _isAuthenticating = false;
          _error = '设备认证失败，请重试或输入主密码。';
        });
    }
  }

  void _revealShareMaterial() {
    try {
      final material = ref
          .read(accountShareServiceProvider)
          .create(widget.account);
      setState(() {
        _material = material;
        _isAuthenticating = false;
        _showSensitiveText = false;
        _format = _ShareFormat.secret;
        _error = null;
        _status = null;
      });
      _startRevealTimers();
    } on Object {
      setState(() {
        _isAuthenticating = false;
        _error = '无法生成分享内容，请关闭后重试。';
      });
    }
  }

  Future<void> _authenticate() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = '请输入主密码');
      return;
    }
    setState(() {
      _isAuthenticating = true;
      _error = null;
      _status = null;
    });
    final authenticated = await ref
        .read(vaultSessionProvider.notifier)
        .reauthenticate(password);
    if (!mounted) return;
    if (!authenticated) {
      setState(() {
        _isAuthenticating = false;
        _error = '主密码错误，验证失败。';
      });
      return;
    }

    _passwordController.clear();
    _revealShareMaterial();
  }

  Future<void> _copyText(String text, String label) async {
    try {
      await widget.writeSensitiveText(text, const Duration(seconds: 30));
      if (mounted) _conceal('$label 已复制，30 秒后尝试清理剪贴板。分享内容已隐藏。');
    } on Object {
      if (mounted) setState(() => _error = '复制失败，请重试。');
    }
  }

  Future<void> _saveQr(AccountShareMaterial material) async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final saved = await ref
          .read(accountShareFileSaverProvider)
          .savePng(material.qrPng, suggestedName: _suggestedFileName());
      if (!mounted) return;
      if (saved) {
        _conceal('二维码已保存到你选择的位置。分享内容已隐藏。');
      } else {
        setState(() => _isSaving = false);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = '保存二维码失败，请重新选择位置后重试。';
        });
      }
    }
  }

  void _startRevealTimers() {
    _cancelTimers();
    _remainingSeconds = widget.revealDuration.inSeconds.clamp(1, 3600);
    _concealTimer = Timer(
      widget.revealDuration,
      () => _conceal('分享内容已超时隐藏，请重新验证。'),
    );
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _material == null) return;
      setState(() {
        _remainingSeconds = (_remainingSeconds - 1).clamp(0, 3600);
      });
    });
  }

  void _cancelTimers() {
    _concealTimer?.cancel();
    _countdownTimer?.cancel();
    _concealTimer = null;
    _countdownTimer = null;
  }

  void _conceal(String status) {
    if (!mounted || _material == null) return;
    _cancelTimers();
    setState(() {
      _material = null;
      _showSensitiveText = false;
      _isSaving = false;
      _remainingSeconds = 0;
      _error = null;
      _status = status;
    });
  }

  String _suggestedFileName() {
    final raw = [
      if (widget.account.issuer.isNotEmpty) widget.account.issuer,
      widget.account.accountName,
      'totp',
    ].join('-');
    final safe = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp('-+'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    final shortened = safe.length > 80 ? safe.substring(0, 80) : safe;
    return '${shortened.isEmpty ? 'account' : shortened}.png';
  }

  String _groupSecret(String secret) {
    final buffer = StringBuffer();
    for (var index = 0; index < secret.length; index++) {
      if (index > 0 && index % 4 == 0) buffer.write(' ');
      buffer.write(secret[index]);
    }
    return buffer.toString();
  }
}
