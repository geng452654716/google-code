import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/totp/totp.dart';

/// Initial desktop shell that exercises the Phase 0 TOTP implementation.
class PhaseZeroHomePage extends StatefulWidget {
  const PhaseZeroHomePage({required this.onToggleTheme, super.key});

  final VoidCallback onToggleTheme;

  @override
  State<PhaseZeroHomePage> createState() => _PhaseZeroHomePageState();
}

class _PhaseZeroHomePageState extends State<PhaseZeroHomePage> {
  static const _demoAccounts = <TotpConfig>[
    TotpConfig(
      secret: 'JBSWY3DPEHPK3PXP',
      accountName: 'personal@example.com',
      issuer: 'Demo Account',
    ),
    TotpConfig(
      secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
      accountName: 'developer@example.com',
      issuer: 'RFC Sample',
      digits: 8,
    ),
  ];

  final _totpService = TotpService();
  final _codes = <String>[];
  late final Timer _timer;
  int _remainingSeconds = 30;

  @override
  void initState() {
    super.initState();
    _refreshCodes();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshCodes());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _refreshCodes() async {
    final now = DateTime.now();
    final nextCodes = await Future.wait(
      _demoAccounts.map((account) => _totpService.generate(account, now)),
    );
    if (!mounted) return;
    setState(() {
      _codes
        ..clear()
        ..addAll(nextCodes);
      _remainingSeconds = _totpService.remainingSeconds(
        _demoAccounts.first,
        now,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _NavigationRail(onToggleTheme: widget.onToggleTheme),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(32, 28, 32, 16),
                    sliver: SliverToBoxAdapter(child: _buildHeader(context)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    sliver: SliverList.separated(
                      itemCount: _demoAccounts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _AccountCard(
                        account: _demoAccounts[index],
                        code: index < _codes.length
                            ? _codes[index]
                            : '--------',
                        remainingSeconds: _remainingSeconds,
                      ),
                    ),
                  ),
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(32, 28, 32, 32),
                    sliver: SliverToBoxAdapter(child: _PhaseStatusPanel()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPhaseNotice(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('添加账号'),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('验证码', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                '本地离线生成 · 当前为 Phase 0 开发预览',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 260,
          child: SearchBar(
            hintText: '搜索账号或服务',
            leading: const Icon(Icons.search_rounded),
            onChanged: (_) {},
          ),
        ),
      ],
    );
  }

  void _showPhaseNotice(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('账号导入界面将在下一阶段接入。')));
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({required this.onToggleTheme});

  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.shield_rounded, color: colors.onPrimary),
          ),
          const SizedBox(height: 28),
          IconButton.filledTonal(
            tooltip: '验证码',
            onPressed: () {},
            icon: const Icon(Icons.password_rounded),
          ),
          const SizedBox(height: 8),
          IconButton(
            tooltip: '分组',
            onPressed: () {},
            icon: const Icon(Icons.folder_outlined),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () {},
            icon: const Icon(Icons.settings_outlined),
          ),
          const Spacer(),
          IconButton(
            tooltip: '切换主题',
            onPressed: onToggleTheme,
            icon: const Icon(Icons.contrast_rounded),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.code,
    required this.remainingSeconds,
  });

  final TotpConfig account;
  final String code;
  final int remainingSeconds;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final formattedCode = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code.length == 8
        ? '${code.substring(0, 4)} ${code.substring(4)}'
        : code;
    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: colors.primaryContainer,
              child: Text(
                (account.issuer ?? account.accountName).characters.first,
                style: TextStyle(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.issuer ?? '未命名服务',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    account.accountName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              formattedCode,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: remainingSeconds / account.period,
                    strokeWidth: 3,
                    backgroundColor: colors.surfaceContainerHighest,
                  ),
                  Text(
                    '$remainingSeconds',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '复制验证码',
              onPressed: () {},
              icon: const Icon(Icons.copy_rounded),
            ),
            IconButton(
              tooltip: '更多',
              onPressed: () {},
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseStatusPanel extends StatelessWidget {
  const _PhaseStatusPanel();

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      (Icons.timer_outlined, 'TOTP 核心', 'RFC 6238 三种算法'),
      (Icons.lock_outline_rounded, '加密 Vault', 'Argon2id + AES-256-GCM'),
      (Icons.qr_code_2_rounded, '二维码闭环', 'PNG 生成与本地解析'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Phase 0 基础能力', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0) const SizedBox(width: 12),
              Expanded(
                child: _StatusCard(
                  icon: items[index].$1,
                  title: items[index].$2,
                  description: items[index].$3,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.check_circle_rounded, color: colors.primary, size: 18),
        ],
      ),
    );
  }
}
