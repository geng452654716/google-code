import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/providers.dart';
import '../../application/security/quick_unlock_service.dart';

/// Master-password unlock screen shown whenever decrypted state is cleared.
class UnlockPage extends ConsumerStatefulWidget {
  const UnlockPage({super.key});

  @override
  ConsumerState<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends ConsumerState<UnlockPage> {
  @override
  void initState() {
    super.initState();
    _inspectQuickUnlock();
  }

  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  QuickUnlockStatus? _quickUnlockStatus;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultSessionProvider);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: colors.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.lock_rounded, size: 52, color: colors.primary),
                    const SizedBox(height: 18),
                    Text(
                      'Google Code 已锁定',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '输入主密码以解密本地账号',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 26),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      autofocus: true,
                      enabled: !state.isProcessing,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _unlock(),
                      decoration: InputDecoration(
                        labelText: '主密码',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
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
                    if (state.message != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        state.message!,
                        style: TextStyle(color: colors.error),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: state.isProcessing ? null : _unlock,
                        icon: state.isProcessing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.lock_open_rounded),
                        label: Text(state.isProcessing ? '正在解锁…' : '解锁'),
                      ),
                    ),
                    if (_quickUnlockStatus?.canUse == true) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Divider(color: colors.outlineVariant),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              '或',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ),
                          Expanded(
                            child: Divider(color: colors.outlineVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const ValueKey('quick-unlock-button'),
                          onPressed: state.isProcessing ? null : _quickUnlock,
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: Text(
                            '使用 ${_quickUnlockStatus!.authenticationName} 解锁',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _inspectQuickUnlock() async {
    final status = await ref.read(quickUnlockServiceProvider).inspect();
    if (!mounted) return;
    setState(() => _quickUnlockStatus = status);
  }

  Future<void> _quickUnlock() async {
    final result = await ref
        .read(vaultSessionProvider.notifier)
        .unlockWithQuickUnlock();
    if (!mounted || result == QuickUnlockAttemptStatus.success) return;
    if (result == QuickUnlockAttemptStatus.invalidKey ||
        result == QuickUnlockAttemptStatus.notConfigured) {
      await _inspectQuickUnlock();
    }
  }

  Future<void> _unlock() async {
    final success = await ref
        .read(vaultSessionProvider.notifier)
        .unlock(_passwordController.text);
    if (!success) {
      _passwordController
        ..clear()
        ..selection = const TextSelection.collapsed(offset: 0);
    }
  }
}
