import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

import '../app/app_scope.dart';
import '../util/formatters.dart';
import '../widgets/empty_state.dart';
import 'subscription_detail_page.dart';

class ActivityLogPage extends StatelessWidget {
  const ActivityLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final records = controller.activities;
    final grouped = <String, List<ActivityRecord>>{};
    for (final record in records) {
      (grouped[_groupName(record.occurredAt)] ??= []).add(record);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '动态',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '充值、通话、短信和续费的完整轨迹。',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        if (records.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          _ActivitySummary(
                            total: records.length,
                            thisMonth: records.where((record) {
                              final now = DateTime.now().toUtc();
                              return record.occurredAt.year == now.year &&
                                  record.occurredAt.month == now.month;
                            }).length,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (records.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.history_rounded,
                  title: '还没有动作记录',
                  message: '进入某个 Profile，记录一次充值、通话、短信或续费。',
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  MediaQuery.paddingOf(context).bottom + 106,
                ),
                sliver: SliverList.list(
                  children: [
                    for (final entry in grouped.entries) ...[
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
                            child: Text(
                              entry.key,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                      ),
                      for (final record in entry.value)
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: _RecordCard(
                              record: record,
                              subscription: controller.subscriptionById(
                                record.subscriptionId,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _groupName(DateTime occurredAt) {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final day = DateTime.utc(occurredAt.year, occurredAt.month, occurredAt.day);
    final distance = today.difference(day).inDays;
    if (distance == 0) return '今天';
    if (distance == 1) return '昨天';
    if (distance < 7) return '最近 7 天';
    if (occurredAt.year == now.year && occurredAt.month == now.month) {
      return '本月';
    }
    return '${occurredAt.year} 年 ${occurredAt.month} 月';
  }
}

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({required this.total, required this.thisMonth});

  final int total;
  final int thisMonth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(Icons.insights_rounded, color: scheme.primary),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '本月已完成 $thisMonth 次动作',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '累计 $total 条续存记录',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.subscription});

  final ActivityRecord record;
  final Subscription? subscription;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _activityColor(record.type);
    final timeZone = subscription?.timeZoneId ?? 'UTC';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: subscription == null
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      SubscriptionDetailPage(subscriptionId: subscription!.id),
                ),
              ),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_activityIcon(record.type), color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          activityName(record.type),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        if (record.amount != null)
                          Text(
                            formatMoney(record.amount!),
                            style: Theme.of(
                              context,
                            ).textTheme.labelLarge?.copyWith(color: accent),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subscription == null
                          ? '已删除的 Profile'
                          : '${subscription!.operator ?? '未知运营商'} · '
                                '${displayPhone(subscription!.number)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatZonedDateTime(record.occurredAt, timeZone),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (subscription != null) ...[
                const SizedBox(width: 7),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Color _activityColor(ActivityType type) => switch (type) {
    ActivityType.topUp => const Color(0xFF20745A),
    ActivityType.call => const Color(0xFF2967A8),
    ActivityType.sms => const Color(0xFF7A56A8),
    ActivityType.renewal => const Color(0xFFC46725),
    ActivityType.mobileData => const Color(0xFF24748A),
    ActivityType.planPurchase => const Color(0xFF8A5C24),
    ActivityType.balanceChange => const Color(0xFF326B66),
    ActivityType.other => const Color(0xFF5E6672),
  };

  static IconData _activityIcon(ActivityType type) => switch (type) {
    ActivityType.topUp => Icons.add_card_rounded,
    ActivityType.call => Icons.call_outlined,
    ActivityType.sms => Icons.sms_outlined,
    ActivityType.renewal => Icons.autorenew_rounded,
    ActivityType.mobileData => Icons.data_usage_rounded,
    ActivityType.planPurchase => Icons.shopping_bag_outlined,
    ActivityType.balanceChange => Icons.account_balance_wallet_outlined,
    ActivityType.other => Icons.more_horiz_rounded,
  };
}
