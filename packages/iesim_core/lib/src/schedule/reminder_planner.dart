import '../model/keep_alive.dart';
import '../model/profile_lifecycle.dart';
import '../model/subscription.dart';
import '../time/calendar.dart';
import '../time/clock.dart';
import '../keepalive/rule_engine.dart';

enum ReminderKind {
  keepAlive,
  keepAliveConstraint,
  planExpiry,
  activationDeadline,
  profileExpiry,
}

/// 一次可交给平台本地通知预排程的提醒。
class ScheduledReminder {
  final String subscriptionId;
  final ReminderKind kind;

  /// 稳定槽位：offset-7 / offset-3 / offset-1 / offset-0 / current。
  final String slot;
  final DateTime fireAtUtc;
  final DateTime deadlineUtc;
  final int daysBefore;
  final bool inferred;
  final String? ruleId;
  final String? ruleTitle;

  ScheduledReminder({
    required this.subscriptionId,
    required this.kind,
    required this.slot,
    required this.fireAtUtc,
    required this.deadlineUtc,
    required this.daysBefore,
    required this.inferred,
    this.ruleId,
    this.ruleTitle,
  }) {
    if (!fireAtUtc.isUtc || !deadlineUtc.isUtc) {
      throw ArgumentError('提醒时刻与截止时刻必须是 UTC');
    }
  }

  String get stableKey => ruleId == null
      ? '$subscriptionId:${kind.name}:$slot'
      : '$subscriptionId:${kind.name}:$ruleId:$slot';
}

/// 根据订阅变更一次性计算全部未来通知，不依赖后台轮询。
class ReminderPlanner {
  ReminderPlanner({
    required this._clock,
    List<int> daysBefore = const [7, 3, 1, 0],
    this.localHour = 9,
  }) : daysBefore = List.unmodifiable(
         {...daysBefore}.toList()..sort((a, b) => b.compareTo(a)),
       ) {
    if (this.daysBefore.any((days) => days < 0)) {
      throw ArgumentError.value(daysBefore, 'daysBefore', '不得包含负数');
    }
    if (localHour < 0 || localHour > 23) {
      throw ArgumentError.value(localHour, 'localHour', '必须在 0..23');
    }
  }

  final Clock _clock;
  final List<int> daysBefore;
  final int localHour;

  List<ScheduledReminder> planFor(Subscription subscription) {
    final events = <ScheduledReminder>[];
    final lifecycle = subscription.lifecycle;
    if (lifecycle.stage == ProfileStage.museum) return events;
    if (lifecycle.stage == ProfileStage.pendingActivation) {
      final deadline = lifecycle.activationDeadline;
      if (deadline != null) {
        events.addAll(
          _planDeadline(
            subscription: subscription,
            kind: ReminderKind.activationDeadline,
            deadlineUtc: deadline,
            inferred: false,
          ),
        );
      }
      return events;
    }
    final keepAlive = subscription.keepAlive;
    if (keepAlive.required &&
        keepAlive.lastActivityAt != null &&
        keepAlive.cycleDays != null) {
      final calendar = ZonedCalendar(subscription.timeZoneId);
      final deadline = calendar.addDays(
        keepAlive.lastActivityAt!,
        keepAlive.cycleDays!,
      );
      events.addAll(
        _planDeadline(
          subscription: subscription,
          kind: ReminderKind.keepAlive,
          deadlineUtc: deadline,
          inferred: keepAlive.confidence == DataConfidence.inferred,
        ),
      );
    }
    final ruleEvaluation = KeepAliveRuleEngine(
      clock: _clock,
    ).evaluate(subscription);
    for (final rule in ruleEvaluation.rules) {
      if (rule.id == 'cycle' || rule.deadlineUtc == null) continue;
      if (rule.state == KeepAliveRuleState.satisfied ||
          rule.state == KeepAliveRuleState.overdue ||
          rule.state == KeepAliveRuleState.notApplicable ||
          rule.state == KeepAliveRuleState.unknown) {
        continue;
      }
      events.addAll(
        _planDeadline(
          subscription: subscription,
          kind: ReminderKind.keepAliveConstraint,
          deadlineUtc: rule.deadlineUtc!,
          inferred: rule.inferred,
          ruleId: rule.id,
          ruleTitle: rule.title,
        ),
      );
    }
    final expiry = subscription.plan.expiryDate;
    if (expiry != null) {
      events.addAll(
        _planDeadline(
          subscription: subscription,
          kind: ReminderKind.planExpiry,
          deadlineUtc: expiry,
          inferred: false,
        ),
      );
    }
    final profileExpiry = lifecycle.serviceExpiresAt;
    if (profileExpiry != null) {
      events.addAll(
        _planDeadline(
          subscription: subscription,
          kind: ReminderKind.profileExpiry,
          deadlineUtc: profileExpiry,
          inferred: false,
        ),
      );
    }
    events.sort((a, b) => a.fireAtUtc.compareTo(b.fireAtUtc));
    return events;
  }

  List<ScheduledReminder> _planDeadline({
    required Subscription subscription,
    required ReminderKind kind,
    required DateTime deadlineUtc,
    required bool inferred,
    String? ruleId,
    String? ruleTitle,
  }) {
    final now = _clock.nowUtc();
    final calendar = ZonedCalendar(subscription.timeZoneId);
    final deadlineMoment = calendar.momentAt(deadlineUtc);
    final deadlineDayAtLocalHour = calendar.utcFromParts(
      year: deadlineMoment.year,
      month: deadlineMoment.month,
      day: deadlineMoment.day,
      hour: localHour,
    );
    final result = <ScheduledReminder>[];
    for (final offset in daysBefore) {
      final fireAt = calendar.addDays(deadlineDayAtLocalHour, -offset);
      if (!fireAt.isAfter(now)) continue;
      result.add(
        ScheduledReminder(
          subscriptionId: subscription.id,
          kind: kind,
          slot: 'offset-$offset',
          fireAtUtc: fireAt,
          deadlineUtc: deadlineUtc,
          daysBefore: offset,
          inferred: inferred,
          ruleId: ruleId,
          ruleTitle: ruleTitle,
        ),
      );
    }

    final daysLeft = calendar.daysBetween(now, deadlineUtc);
    final maximum = daysBefore.isEmpty ? -1 : daysBefore.first;
    final exactFutureExists = result.any(
      (reminder) => reminder.daysBefore == daysLeft,
    );
    if (daysLeft >= 0 && daysLeft <= maximum && !exactFutureExists) {
      result.add(
        ScheduledReminder(
          subscriptionId: subscription.id,
          kind: kind,
          slot: 'current',
          fireAtUtc: now.add(const Duration(minutes: 1)),
          deadlineUtc: deadlineUtc,
          daysBefore: daysLeft,
          inferred: inferred,
          ruleId: ruleId,
          ruleTitle: ruleTitle,
        ),
      );
    }
    return result;
  }
}
