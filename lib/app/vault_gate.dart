import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/session/system_auto_lock_coordinator.dart';
import '../features/accounts/accounts_page.dart';
import '../features/onboarding/create_vault_page.dart';
import '../features/unlock/unlock_page.dart';
import 'state/providers.dart';
import 'widgets/vault_security_shell.dart';

/// Replaces the complete navigation surface when the Vault locks or unlocks.
class VaultGate extends ConsumerStatefulWidget {
  const VaultGate({
    required this.onToggleTheme,
    required this.onClearSensitiveRoutes,
    super.key,
  });

  final VoidCallback onToggleTheme;

  /// Removes every modal route immediately before a system-triggered lock.
  final VoidCallback onClearSensitiveRoutes;

  @override
  ConsumerState<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends ConsumerState<VaultGate>
    with WidgetsBindingObserver {
  Timer? _inactivityTimer;
  DateTime? _backgroundedAt;
  SystemAutoLockCoordinator? _systemAutoLockCoordinator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_initialize);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    unawaited(_systemAutoLockCoordinator?.dispose());
    super.dispose();
  }

  Future<void> _initialize() async {
    final coordinator = SystemAutoLockCoordinator(
      eventService: ref.read(systemSessionEventServiceProvider),
      isVaultUnlocked: () => ref.read(vaultSessionProvider).isUnlocked,
      clearSensitiveRoutes: widget.onClearSensitiveRoutes,
      lockVault: () => ref.read(vaultSessionProvider.notifier).lock(),
    );
    _systemAutoLockCoordinator = coordinator;
    await coordinator.start();
    if (!mounted) return;
    await ref.read(vaultSessionProvider.notifier).initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (backgroundedAt != null &&
          DateTime.now().difference(backgroundedAt) >= _autoLockDuration) {
        ref.read(vaultSessionProvider.notifier).lock();
      } else {
        _resetInactivityTimer();
      }
    }
  }

  Duration get _autoLockDuration {
    final minutes =
        ref.read(vaultSessionProvider).payload?.preferences['autoLockMinutes']
            as int? ??
        5;
    return Duration(minutes: minutes.clamp(1, 60));
  }

  void _resetInactivityTimer() {
    final session = ref.read(vaultSessionProvider);
    _inactivityTimer?.cancel();
    if (!session.isUnlocked) return;
    _inactivityTimer = Timer(
      _autoLockDuration,
      () => ref.read(vaultSessionProvider.notifier).lock(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(vaultSessionProvider);
    if (session.isUnlocked && _inactivityTimer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resetInactivityTimer();
      });
    } else if (!session.isUnlocked && _inactivityTimer != null) {
      _inactivityTimer?.cancel();
      _inactivityTimer = null;
    }

    final page = switch (session.phase) {
      VaultSessionPhase.loading => const _LoadingPage(),
      VaultSessionPhase.needsSetup => const CreateVaultPage(),
      VaultSessionPhase.locked => const UnlockPage(),
      VaultSessionPhase.unlocked => AccountsPage(
        onToggleTheme: widget.onToggleTheme,
      ),
      VaultSessionPhase.error => _StartupErrorPage(
        message: session.message ?? '无法启动应用',
        onRetry: () =>
            ref.read(vaultSessionProvider.notifier).retryInitialize(),
      ),
    };

    return Focus(
      onKeyEvent: (_, _) {
        _resetInactivityTimer();
        return KeyEventResult.ignored;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _resetInactivityTimer(),
        onPointerSignal: (_) => _resetInactivityTimer(),
        child: session.isUnlocked
            ? AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(key: ValueKey(session.phase), child: page),
              )
            // Dispose the unlocked page in the same frame as a security lock.
            : KeyedSubtree(key: ValueKey(session.phase), child: page),
      ),
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.shield_rounded,
                size: 29,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 14),
            Text(
              '正在打开本地保险库…',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartupErrorPage extends StatelessWidget {
  const _StartupErrorPage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return VaultSecurityShell(
      icon: Icons.error_outline_rounded,
      title: '无法打开 TOTP Vault',
      description: '本地数据没有被重置，可以安全重试。',
      child: Column(
        children: [
          VaultInlineMessage(message: message),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ),
        ],
      ),
    );
  }
}
