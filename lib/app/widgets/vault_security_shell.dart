import 'package:flutter/material.dart';

/// Shared branded shell for setup, unlock, and other security-first screens.
class VaultSecurityShell extends StatelessWidget {
  const VaultSecurityShell({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
    this.maxWidth = 440,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).scaffoldBackgroundColor,
              Color.alphaBlend(
                colors.primaryContainer.withValues(alpha: isDark ? 0.18 : 0.5),
                Theme.of(context).scaffoldBackgroundColor,
              ),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(36, 32, 36, 36),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colors.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.28 : 0.08,
                        ),
                        blurRadius: 34,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              Icons.shield_rounded,
                              size: 18,
                              color: colors.onPrimary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'TOTP Vault',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(icon, size: 31, color: colors.primary),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 9),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact semantic feedback block used by password and recovery flows.
class VaultInlineMessage extends StatelessWidget {
  const VaultInlineMessage({
    required this.message,
    this.isError = true,
    super.key,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = isError
        ? colors.errorContainer
        : colors.primaryContainer;
    final foreground = isError
        ? colors.onErrorContainer
        : colors.onPrimaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 18,
            color: foreground,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: foreground, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
