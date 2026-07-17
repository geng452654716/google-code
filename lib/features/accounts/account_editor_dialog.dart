import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/providers.dart';
import '../../domain/entities/entities.dart';
import '../../domain/totp/totp.dart';

/// Account editor used by manual, URI, QR import, and existing-account flows.
class AccountEditorDialog extends ConsumerStatefulWidget {
  const AccountEditorDialog({
    this.account,
    this.initialDraft,
    this.importSourceLabel,
    this.isDuplicate = false,
    super.key,
  }) : assert(account == null || initialDraft == null);

  final Account? account;
  final AccountDraft? initialDraft;
  final String? importSourceLabel;
  final bool isDuplicate;

  @override
  ConsumerState<AccountEditorDialog> createState() =>
      _AccountEditorDialogState();
}

class _AccountEditorDialogState extends ConsumerState<AccountEditorDialog> {
  late final TextEditingController _issuerController;
  late final TextEditingController _accountNameController;
  late final TextEditingController _secretController;
  late final TextEditingController _periodController;
  late TotpAlgorithm _algorithm;
  late int _digits;
  bool _obscureSecret = true;
  bool _keepDuplicate = false;
  String? _errorMessage;

  bool get _isEditing => widget.account != null;
  bool get _isImporting => widget.initialDraft != null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    final draft = widget.initialDraft;
    _issuerController = TextEditingController(
      text: account?.issuer ?? draft?.issuer ?? '',
    );
    _accountNameController = TextEditingController(
      text: account?.accountName ?? draft?.accountName ?? '',
    );
    _secretController = TextEditingController(
      text: account?.secret ?? draft?.secret ?? '',
    );
    _periodController = TextEditingController(
      text: (account?.periodSeconds ?? draft?.periodSeconds ?? 30).toString(),
    );
    _algorithm = account?.algorithm ?? draft?.algorithm ?? TotpAlgorithm.sha1;
    _digits = account?.digits ?? draft?.digits ?? 6;
  }

  @override
  void dispose() {
    _issuerController.dispose();
    _accountNameController.dispose();
    _secretController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(vaultSessionProvider);
    return AlertDialog(
      title: Text(
        _isEditing
            ? '编辑账号'
            : _isImporting
            ? '确认导入账号'
            : '添加账号',
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isImporting) ...[
                _ImportNotice(
                  sourceLabel: widget.importSourceLabel ?? '二维码',
                  isDuplicate: widget.isDuplicate,
                ),
                if (widget.isDuplicate)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _keepDuplicate,
                    onChanged: session.isProcessing
                        ? null
                        : (value) =>
                              setState(() => _keepDuplicate = value ?? false),
                    title: const Text('仍然作为新账号添加'),
                    subtitle: const Text('默认会拦截完全相同的账号，勾选后允许保留副本。'),
                  ),
                const SizedBox(height: 16),
              ],
              if (!_isEditing && !_isImporting) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: session.isProcessing ? null : _fillFromOtpAuth,
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('从 otpauth:// 链接填充'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _issuerController,
                enabled: !session.isProcessing,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '服务名称（Issuer）',
                  hintText: '例如 GitHub',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _accountNameController,
                enabled: !session.isProcessing,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '账号名称',
                  hintText: '例如 user@example.com',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _secretController,
                enabled: !session.isProcessing,
                obscureText: _obscureSecret,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Base32 Secret',
                  hintText: 'JBSWY3DPEHPK3PXP',
                  suffixIcon: IconButton(
                    tooltip: _obscureSecret ? '显示 Secret' : '隐藏 Secret',
                    onPressed: () =>
                        setState(() => _obscureSecret = !_obscureSecret),
                    icon: Icon(
                      _obscureSecret
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<TotpAlgorithm>(
                      initialValue: _algorithm,
                      decoration: const InputDecoration(labelText: '算法'),
                      items: TotpAlgorithm.values
                          .map(
                            (algorithm) => DropdownMenuItem(
                              value: algorithm,
                              child: Text(algorithm.otpAuthName),
                            ),
                          )
                          .toList(),
                      onChanged: session.isProcessing
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _algorithm = value);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _digits,
                      decoration: const InputDecoration(labelText: '位数'),
                      items: const [
                        DropdownMenuItem(value: 6, child: Text('6 位')),
                        DropdownMenuItem(value: 8, child: Text('8 位')),
                      ],
                      onChanged: session.isProcessing
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _digits = value);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _periodController,
                      enabled: !session.isProcessing,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: '周期（秒）'),
                    ),
                  ),
                ],
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: session.isProcessing
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: session.isProcessing ? null : _save,
          child: Text(session.isProcessing ? '保存中…' : '保存'),
        ),
      ],
    );
  }

  Future<void> _fillFromOtpAuth() async {
    final uri = await showDialog<String>(
      context: context,
      builder: (context) => const _OtpAuthUriDialog(),
    );
    if (uri == null || !mounted) return;
    try {
      final config = OtpAuthUriCodec().parse(uri);
      setState(() {
        _issuerController.text = config.issuer ?? '';
        _accountNameController.text = config.accountName;
        _secretController.text = config.secret;
        _periodController.text = config.period.toString();
        _algorithm = config.algorithm;
        _digits = config.digits;
        _errorMessage = null;
      });
    } on FormatException catch (error) {
      setState(() => _errorMessage = '链接无效：${error.message}');
    }
  }

  Future<void> _save() async {
    final period = int.tryParse(_periodController.text);
    if (period == null) {
      setState(() => _errorMessage = '请输入有效的验证码周期');
      return;
    }
    final draft = AccountDraft(
      issuer: _issuerController.text,
      accountName: _accountNameController.text,
      secret: _secretController.text,
      algorithm: _algorithm,
      digits: _digits,
      periodSeconds: period,
    );
    final controller = ref.read(vaultSessionProvider.notifier);
    final success = _isEditing
        ? await controller.updateAccount(widget.account!.id, draft)
        : await controller.addAccount(
            draft,
            allowDuplicate: _isImporting && _keepDuplicate,
          );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorMessage = ref.read(vaultSessionProvider).message ?? '保存失败';
      });
    }
  }
}

class _ImportNotice extends StatelessWidget {
  const _ImportNotice({required this.sourceLabel, required this.isDuplicate});

  final String sourceLabel;
  final bool isDuplicate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDuplicate ? colors.errorContainer : colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isDuplicate ? Icons.copy_all_rounded : Icons.qr_code_2_rounded,
            color: isDuplicate
                ? colors.onErrorContainer
                : colors.onPrimaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isDuplicate
                  ? '从$sourceLabel识别到的账号已存在。请检查内容，或明确选择保留副本。'
                  : '已从$sourceLabel识别账号。保存前请确认发行方、账号名称和 TOTP 参数。',
              style: TextStyle(
                color: isDuplicate
                    ? colors.onErrorContainer
                    : colors.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpAuthUriDialog extends StatefulWidget {
  const _OtpAuthUriDialog();

  @override
  State<_OtpAuthUriDialog> createState() => _OtpAuthUriDialogState();
}

class _OtpAuthUriDialogState extends State<_OtpAuthUriDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('粘贴 otpauth:// 链接'),
      content: SizedBox(
        width: 460,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 4,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'otpauth://totp/...'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('解析'),
        ),
      ],
    );
  }
}
