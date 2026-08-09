import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

import '../util/formatters.dart';

class PortfolioValueDashboard extends StatelessWidget {
  const PortfolioValueDashboard({super.key, required this.summary});

  final PortfolioValueSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('portfolio-value-dashboard'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '总价值',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '账面余额 + 套餐剩余价值 · 按币种独立统计',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _ProfileCoverageBadge(summary: summary),
              ],
            ),
            const SizedBox(height: 18),
            if (summary.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  summary.unvaluedPlanCount > 0
                      ? '已有套餐价格，但周期资料不足，暂时无法估算剩余价值。'
                      : '记录余额，或补全套餐价格与周期后，这里会自动汇总。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 520 ? 2 : 1;
                  final width = columns == 1
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final currency in summary.currencies)
                        SizedBox(
                          width: width,
                          child: _CurrencyValueTile(summary: currency),
                        ),
                    ],
                  );
                },
              ),
            if (summary.unvaluedPlanCount > 0 ||
                summary.excludedMuseumCount > 0) ...[
              const SizedBox(height: 13),
              Text(
                [
                  if (summary.unvaluedPlanCount > 0)
                    '${summary.unvaluedPlanCount} 个套餐待补充周期资料',
                  if (summary.excludedMuseumCount > 0)
                    '已排除 ${summary.excludedMuseumCount} 个过期博物馆 Profile',
                ].join(' · '),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileCoverageBadge extends StatelessWidget {
  const _ProfileCoverageBadge({required this.summary});

  final PortfolioValueSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${summary.profilesWithValueCount}/${summary.includedProfileCount}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CurrencyValueTile extends StatelessWidget {
  const _CurrencyValueTile({required this.summary});

  final CurrencyValueSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('portfolio-value-${summary.currencyCode}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${summary.currencyCode} 总计',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(summary.total),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 11),
          _BreakdownLine(label: '账面余额', value: formatMoney(summary.balance)),
          const SizedBox(height: 5),
          _BreakdownLine(
            label: '套餐残值',
            value: formatMoney(summary.remainingPlanValue),
          ),
        ],
      ),
    );
  }
}

class _BreakdownLine extends StatelessWidget {
  const _BreakdownLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
