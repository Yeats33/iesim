import 'package:flutter/material.dart';

import '../app/brand.dart';
import '../app/theme.dart';
import 'app_logo.dart';

class OverviewHeader extends StatelessWidget {
  const OverviewHeader({
    super.key,
    required this.total,
    required this.urgent,
    required this.safe,
    required this.unknown,
    required this.onAdd,
    required this.onImport,
  });

  final int total;
  final int urgent;
  final int safe;
  final int unknown;
  final VoidCallback onAdd;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _BrandHeader(onAdd: onAdd),
      const SizedBox(height: 18),
      _OverviewHero(
        total: total,
        urgent: urgent,
        safe: safe,
        unknown: unknown,
        onAdd: onAdd,
        onImport: onImport,
      ),
    ],
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const AppLogo(size: 46),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppBrand.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 1),
              Text(
                AppBrand.tagline,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 15, color: scheme.primary),
              const SizedBox(width: 5),
              Text(
                '本地优先',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: '添加 Profile',
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

class _OverviewHero extends StatelessWidget {
  const _OverviewHero({
    required this.total,
    required this.urgent,
    required this.safe,
    required this.unknown,
    required this.onAdd,
    required this.onImport,
  });

  final int total;
  final int urgent;
  final int safe;
  final int unknown;
  final VoidCallback onAdd;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final title = total == 0
        ? '从第一张 SIM 开始'
        : urgent > 0
        ? '$urgent 项需要处理'
        : unknown > 0
        ? '$unknown 个 Profile 待完善'
        : '所有 Profile 状态良好';
    final subtitle = total == 0
        ? '手动记录，或从二维码与外部备份快速导入。'
        : unknown > 0
        ? '可补充套餐或保号资料，也可以先保持现状。'
        : '复杂保号规则、激活期限和套餐到期都在掌握中。';

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.teal, AppColors.tealDark],
                ),
              ),
            ),
          ),
          Positioned(
            right: -44,
            top: -50,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.mintStrong.withValues(alpha: .14),
                  width: 24,
                ),
              ),
            ),
          ),
          Positioned(
            right: 32,
            top: 34,
            child: Icon(
              Icons.wifi_tethering_rounded,
              size: 42,
              color: AppColors.mintStrong.withValues(alpha: .23),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_greeting()} · 今日概览',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.mintStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    letterSpacing: -.6,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: .78),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _HeroMetric(value: total, label: '全部'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroMetric(value: urgent, label: '需关注'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroMetric(value: safe, label: '状态良好'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.paper,
                          foregroundColor: AppColors.tealDark,
                        ),
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('添加 Profile'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: .42),
                          ),
                        ),
                        onPressed: onImport,
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('外部数据'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 11) return '早上好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: Colors.white.withValues(alpha: .12)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: .72),
          ),
        ),
      ],
    ),
  );
}
