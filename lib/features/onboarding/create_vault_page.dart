import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/providers.dart';
import '../../app/widgets/vault_security_shell.dart';

/// First-run screen for creating the encrypted local Vault.
class CreateVaultPage extends ConsumerStatefulWidget {
  const CreateVaultPage({super.key});

  @override
  ConsumerState<CreateVaultPage> createState() => _CreateVaultPageState();
}

class _CreateVaultPageState extends ConsumerState<CreateVaultPage> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultSessionProvider);
    return VaultSecurityShell(
      icon: Icons.shield_outlined,
      title: '创建本地保险库',
      description: '所有账号 Secret 都会使用主密码加密后保存在当前设备。主密码不会上传，也无法找回。',
      child: Column(
        children: [
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofocus: true,
            enabled: !state.isProcessing,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: '主密码',
              helperText: '至少 8 个字符，请妥善保存',
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmationController,
            obscureText: _obscurePassword,
            enabled: !state.isProcessing,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _create(),
            decoration: const InputDecoration(
              labelText: '再次输入主密码',
              prefixIcon: Icon(Icons.check_circle_outline_rounded),
            ),
          ),
          if (state.message != null) ...[
            const SizedBox(height: 14),
            VaultInlineMessage(message: state.message!),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: state.isProcessing ? null : _create,
              icon: state.isProcessing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_rounded),
              label: Text(state.isProcessing ? '正在创建…' : '创建并进入'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    await ref
        .read(vaultSessionProvider.notifier)
        .createVault(_passwordController.text, _confirmationController.text);
  }
}
