import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

import '../app/app_scope.dart';
import '../util/formatters.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_badge.dart';
import 'subscription_detail_page.dart';

class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final events = <_ReminderEvent>[];
    for (final subscription in controller.subscriptions) {
      if (subscription.lifecycle.stage == ProfileStage.museum) continue;
      if (subscription.lifecycle.stage == ProfileStage.pendingActivation) {
        final deadline = subscription.lifecycle.activationDeadline;
        if (deadline != null) {
          events.add(
            _ReminderEvent(
              subscription: subscription,
              type: _ReminderType.activationDeadline,
              date: deadline,
              status: controller.statusOf(subscription),
            ),
          );
        }
        continue;
      }
      final keepAlive = subscription.keepAlive;
      if (keepAlive.required &&
          keepAlive.lastActivityAt != null &&
          keepAlive.cycleDays != null) {
        events.add(
          _ReminderEvent(
            subscription: subscription,
            type: _ReminderType.keepAlive,
            date: ZonedCalendar(
              subscription.timeZoneId,
            ).addDays(keepAlive.lastActivityAt!, keepAlive.cycleDays!),
            status: controller.statusOf(subscription),
          ),
        );
      }
      if (subscription.plan.expiryDate != null) {
        events.add(
          _ReminderEvent(
            subscription: subscription,
            type: _ReminderType.planExpiry,
            date: subscription.plan.expiryDate!,
            status: controller.statusOf(subscription),
          ),
        );
      }
      if (subscription.lifecycle.serviceExpiresAt != null) {
        events.add(
          _ReminderEvent(
            subscription: subscription,
            type: _ReminderType.profileExpiry,
            date: subscription.lifecycle.serviceExpiresAt!,
            status: controller.statusOf(subscription),
          ),
        );
      }
    }
    events.sort((a, b) => a.date.compareTo(b.date));
    final unknown = controller.subscriptions
        .where(
          (item) =>
              item.lifecycle.stage == ProfileStage.active &&
              controller.statusOf(item) is Unknown,
        )
        .toList(growable: false);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '提醒',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '保号、套餐、激活期限与 Profile 服务到期分开呈现。',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 22),
                        _ReminderSummary(
                          events: events,
                          unknown: unknown.length,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '时间线',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (events.isEmpty && unknown.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: '暂无提醒',
                  message: '添加保号、套餐、激活期限或服务到期日后，事件会按时间排列在这里。',
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  MediaQuery.paddingOf(context).bottom + 105,
                ),
                sliver: SliverList.list(
                  children: [
                    for (var index = 0; index < events.length; index++)
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: _TimelineEvent(
                            event: events[index],
                            isLast:
                                index == events.length - 1 && unknown.isEmpty,
                          ),
                        ),
                      ),
                    if (unknown.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              '需要补充资料',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                      ),
                      for (final subscription in unknown)
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  child: const Icon(Icons.help_outline_rounded),
                                ),
                                title: Text(subscription.operator ?? '未知运营商'),
                                subtitle: Text(
                                  '${displayPhone(subscription.number)}\n缺少上次动作日期或保号周期',
                                ),
                                isThreeLine: true,
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () => _open(context, subscription.id),
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

  void _open(BuildContext context, String id) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SubscriptionDetailPage(subscriptionId: id),
      ),
    );
  }
}

enum _ReminderType { keepAlive, planExpiry, activationDeadline, profileExpiry }

class _ReminderEvent {
  const _ReminderEvent({
    required this.subscription,
    required this.type,
    required this.date,
    required this.status,
  });

  final Subscription subscription;
  final _ReminderType type;
  final DateTime date;
  final KeepAliveStatus status;
}

class _ReminderSummary extends StatelessWidget {
  const _ReminderSummary({required this.events, required this.unknown});

  final List<_ReminderEvent> events;
  final int unknown;

  @override
  Widget build(BuildContext context) {
    final urgent = events.where((event) {
      if (event.type != _ReminderType.keepAlive) return false;
      return event.status is DueSoon || event.status is Overdue;
    }).length;
    final scheme = Theme.of(context).colorScheme;
    final warning = statusColors(context, StatusTone.warning);
    final background = urgent > 0
        ? warning.background
        : scheme.primaryContainer;
    final foreground = urgent > 0
        ? warning.foreground
        : scheme.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .72),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              urgent > 0
                  ? Icons.notifications_active_rounded
                  : Icons.task_alt_rounded,
              color: foreground,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  urgent > 0 ? '$urgent 个保号事件需处理' : '当前没有紧急事件',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: foreground),
                ),
                const SizedBox(height: 3),
                Text(
                  '${events.length} 个日期事件${unknown > 0 ? ' · $unknown 条资料待完善' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground.withValues(alpha: .76),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEvent extends StatelessWidget {
  const _TimelineEvent({required this.event, required this.isLast});

  final _ReminderEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isKeepAlive = event.type == _ReminderType.keepAlive;
    final label = switch (event.type) {
      _ReminderType.keepAlive => '保号截止',
      _ReminderType.planExpiry => '套餐到期',
      _ReminderType.activationDeadline => 'Profile 激活期限',
      _ReminderType.profileExpiry => 'Profile 服务到期',
    };
    final icon = switch (event.type) {
      _ReminderType.keepAlive => Icons.shield_outlined,
      _ReminderType.planExpiry => Icons.layers_outlined,
      _ReminderType.activationDeadline => Icons.bolt_outlined,
      _ReminderType.profileExpiry => Icons.event_busy_outlined,
    };
    final info = describeStatus(event.status);
    final statusColor = statusColors(context, info.tone);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 54,
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isKeepAlive
                        ? statusColor.background
                        : scheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 19,
                    color: isKeepAlive
                        ? statusColor.foreground
                        : scheme.onSecondaryContainer,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      color: scheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Card(
              margin: const EdgeInsets.only(bottom: 13),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SubscriptionDetailPage(
                      subscriptionId: event.subscription.id,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              formatZonedDate(
                                event.date,
                                event.subscription.timeZoneId,
                              ),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${event.subscription.operator ?? '未知运营商'} · '
                              '${displayPhone(event.subscription.number)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              event.subscription.timeZoneId,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (isKeepAlive)
                        StatusBadge(status: event.status, compact: true)
                      else
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
