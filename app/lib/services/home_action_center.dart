import 'package:iesim_core/iesim_core.dart';

enum HomeActionKind {
  activation,
  keepAlive,
  keepAliveConstraint,
  planExpiry,
  profileExpiry,
  missingData,
}

enum HomeActionUrgency { critical, warning, confirmation, data }

class HomeActionItem {
  const HomeActionItem({
    required this.id,
    required this.subscriptionId,
    required this.kind,
    required this.urgency,
    required this.title,
    required this.description,
    this.deadlineUtc,
    this.ruleId,
  });

  final String id;
  final String subscriptionId;
  final HomeActionKind kind;
  final HomeActionUrgency urgency;
  final String title;
  final String description;
  final DateTime? deadlineUtc;
  final String? ruleId;
}

/// 将生命周期、套餐和复杂保号规则汇总为首页的可处理事项。
class HomeActionCenter {
  const HomeActionCenter({required this.clock, this.lookAheadDays = 30});

  final Clock clock;
  final int lookAheadDays;

  List<HomeActionItem> build({
    required Iterable<Subscription> subscriptions,
    required Iterable<ActivityRecord> activities,
  }) {
    final recordsBySubscription = <String, List<ActivityRecord>>{};
    for (final record in activities) {
      recordsBySubscription
          .putIfAbsent(record.subscriptionId, () => [])
          .add(record);
    }
    final result = <HomeActionItem>[];
    for (final subscription in subscriptions) {
      final lifecycle = subscription.lifecycle;
      if (lifecycle.stage == ProfileStage.museum) continue;
      if (lifecycle.stage == ProfileStage.pendingActivation) {
        final deadline = lifecycle.activationDeadline;
        if (deadline != null) {
          final days = _days(subscription, deadline);
          if (days <= lookAheadDays) {
            result.add(
              HomeActionItem(
                id: '${subscription.id}:activation',
                subscriptionId: subscription.id,
                kind: HomeActionKind.activation,
                urgency: days < 0
                    ? HomeActionUrgency.critical
                    : HomeActionUrgency.warning,
                title: days < 0 ? '激活期限已过' : 'Profile 待激活',
                description: _deadlineDescription(days, '激活'),
                deadlineUtc: deadline,
              ),
            );
          }
        }
        continue;
      }

      final evaluation = KeepAliveRuleEngine(clock: clock).evaluate(
        subscription,
        activities: recordsBySubscription[subscription.id] ?? const [],
      );
      for (final rule in evaluation.rules) {
        final action = _fromRule(subscription, rule);
        if (action != null) result.add(action);
      }
      _appendDateAction(
        result,
        subscription: subscription,
        kind: HomeActionKind.planExpiry,
        deadline: subscription.plan.expiryDate,
        title: '套餐即将到期',
        overdueTitle: '套餐已到期',
      );
      _appendDateAction(
        result,
        subscription: subscription,
        kind: HomeActionKind.profileExpiry,
        deadline: lifecycle.serviceExpiresAt,
        title: 'Profile 服务即将到期',
        overdueTitle: 'Profile 服务已到期',
      );
    }
    result.sort((left, right) {
      final urgency = left.urgency.index.compareTo(right.urgency.index);
      if (urgency != 0) return urgency;
      final leftDate = left.deadlineUtc;
      final rightDate = right.deadlineUtc;
      if (leftDate == null && rightDate != null) return 1;
      if (leftDate != null && rightDate == null) return -1;
      if (leftDate != null && rightDate != null) {
        final date = leftDate.compareTo(rightDate);
        if (date != 0) return date;
      }
      return left.id.compareTo(right.id);
    });
    return List.unmodifiable(result);
  }

  HomeActionItem? _fromRule(
    Subscription subscription,
    KeepAliveRuleEvaluation rule,
  ) {
    final kind = rule.id == 'cycle'
        ? HomeActionKind.keepAlive
        : HomeActionKind.keepAliveConstraint;
    final prefix = '${subscription.id}:${kind.name}:${rule.id}';
    return switch (rule.state) {
      KeepAliveRuleState.overdue => HomeActionItem(
        id: prefix,
        subscriptionId: subscription.id,
        kind: kind,
        urgency: HomeActionUrgency.critical,
        title: rule.id == 'cycle' ? '保号周期已逾期' : '${rule.title}已逾期',
        description: _deadlineDescription(rule.daysRemaining ?? -1, '处理'),
        deadlineUtc: rule.deadlineUtc,
        ruleId: rule.id,
      ),
      KeepAliveRuleState.dueSoon => HomeActionItem(
        id: prefix,
        subscriptionId: subscription.id,
        kind: kind,
        urgency: HomeActionUrgency.warning,
        title: rule.id == 'cycle' ? '该做保号动作了' : rule.title,
        description: _deadlineDescription(rule.daysRemaining ?? 0, '处理'),
        deadlineUtc: rule.deadlineUtc,
        ruleId: rule.id,
      ),
      KeepAliveRuleState.needsConfirmation => HomeActionItem(
        id: prefix,
        subscriptionId: subscription.id,
        kind: kind,
        urgency: HomeActionUrgency.confirmation,
        title: '${rule.title}待确认',
        description: rule.regions.isEmpty
            ? '需要手动确认该条件是否已经满足'
            : '候选动作已找到，请确认是否发生在 ${rule.regions.join(' / ')}',
        deadlineUtc: rule.deadlineUtc,
        ruleId: rule.id,
      ),
      KeepAliveRuleState.unknown => HomeActionItem(
        id: prefix,
        subscriptionId: subscription.id,
        kind: HomeActionKind.missingData,
        urgency: HomeActionUrgency.data,
        title: rule.id == 'cycle' ? '补充保号资料' : '补充「${rule.title}」资料',
        description: rule.id == 'cycle'
            ? '缺少保号周期或上次动作日期'
            : '缺少规则的起算日期，暂时不能判断是否安全',
        ruleId: rule.id,
      ),
      _ => null,
    };
  }

  void _appendDateAction(
    List<HomeActionItem> result, {
    required Subscription subscription,
    required HomeActionKind kind,
    required DateTime? deadline,
    required String title,
    required String overdueTitle,
  }) {
    if (deadline == null) return;
    final days = _days(subscription, deadline);
    if (days > lookAheadDays) return;
    result.add(
      HomeActionItem(
        id: '${subscription.id}:${kind.name}',
        subscriptionId: subscription.id,
        kind: kind,
        urgency: days < 0
            ? HomeActionUrgency.critical
            : HomeActionUrgency.warning,
        title: days < 0 ? overdueTitle : title,
        description: _deadlineDescription(days, '到期'),
        deadlineUtc: deadline,
      ),
    );
  }

  int _days(Subscription subscription, DateTime deadline) => ZonedCalendar(
    subscription.timeZoneId,
  ).daysBetween(clock.nowUtc(), deadline);

  String _deadlineDescription(int days, String action) {
    if (days < 0) return '已超过$action日期 ${-days} 天';
    if (days == 0) return '今天$action';
    return '$days 天后$action';
  }
}
