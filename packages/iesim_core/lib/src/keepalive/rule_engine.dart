import '../model/activity_record.dart';
import '../model/keep_alive.dart';
import '../model/profile_lifecycle.dart';
import '../model/subscription.dart';
import '../time/calendar.dart';
import '../time/clock.dart';
import 'evaluator.dart';
import 'status.dart';

enum KeepAliveRuleState {
  satisfied,
  safe,
  dueSoon,
  overdue,
  pending,
  needsConfirmation,
  unknown,
  notApplicable,
}

enum KeepAliveAttention {
  none,
  pending,
  unknown,
  confirmation,
  dueSoon,
  overdue,
}

/// 一条可执行保号规则的判定结果。
class KeepAliveRuleEvaluation {
  const KeepAliveRuleEvaluation({
    required this.id,
    required this.title,
    required this.details,
    required this.state,
    this.anchorAt,
    this.deadlineUtc,
    this.evidenceAt,
    this.evidenceActivity,
    this.daysRemaining,
    this.inferred = false,
    this.requiresManualConfirmation = false,
    this.completedLate = false,
    this.regions = const [],
  });

  final String id;
  final String title;
  final String details;
  final KeepAliveRuleState state;
  final DateTime? anchorAt;
  final DateTime? deadlineUtc;
  final DateTime? evidenceAt;
  final ActivityRecord? evidenceActivity;
  final int? daysRemaining;
  final bool inferred;
  final bool requiresManualConfirmation;
  final bool completedLate;
  final List<String> regions;

  bool get isActionable => switch (state) {
    KeepAliveRuleState.dueSoon ||
    KeepAliveRuleState.overdue ||
    KeepAliveRuleState.needsConfirmation ||
    KeepAliveRuleState.unknown => true,
    _ => false,
  };
}

class KeepAliveEvaluation {
  KeepAliveEvaluation(List<KeepAliveRuleEvaluation> rules)
    : rules = List.unmodifiable(rules);

  final List<KeepAliveRuleEvaluation> rules;

  KeepAliveAttention get attention {
    if (rules.any((rule) => rule.state == KeepAliveRuleState.overdue)) {
      return KeepAliveAttention.overdue;
    }
    if (rules.any((rule) => rule.state == KeepAliveRuleState.dueSoon)) {
      return KeepAliveAttention.dueSoon;
    }
    if (rules.any(
      (rule) => rule.state == KeepAliveRuleState.needsConfirmation,
    )) {
      return KeepAliveAttention.confirmation;
    }
    if (rules.any((rule) => rule.state == KeepAliveRuleState.unknown)) {
      return KeepAliveAttention.unknown;
    }
    if (rules.any((rule) => rule.state == KeepAliveRuleState.pending)) {
      return KeepAliveAttention.pending;
    }
    return KeepAliveAttention.none;
  }

  Iterable<KeepAliveRuleEvaluation> get actionableRules =>
      rules.where((rule) => rule.isActionable);
}

/// 对主周期和附加条件统一判定。
///
/// 活动记录可以自动满足动作型规则；地区限制和手动型规则必须由用户明确
/// 确认，系统不会仅凭一次动作猜测其发生地点或付费状态。
class KeepAliveRuleEngine {
  const KeepAliveRuleEngine({
    required this._clock,
    this.dueSoonThresholdDays = 7,
  });

  final Clock _clock;
  final int dueSoonThresholdDays;

  KeepAliveEvaluation evaluate(
    Subscription subscription, {
    Iterable<ActivityRecord> activities = const [],
  }) {
    if (subscription.lifecycle.stage != ProfileStage.active) {
      return KeepAliveEvaluation(const []);
    }
    final rules = <KeepAliveRuleEvaluation>[
      _evaluateCycle(subscription),
      for (final constraint in subscription.keepAlive.policy.constraints)
        _evaluateConstraint(subscription, constraint, activities),
    ];
    return KeepAliveEvaluation(rules);
  }

  KeepAliveRuleEvaluation _evaluateCycle(Subscription subscription) {
    final keepAlive = subscription.keepAlive;
    final status = KeepAliveEvaluator(
      clock: _clock,
      dueSoonThresholdDays: dueSoonThresholdDays,
    ).evaluate(keepAlive, subscription.timeZoneId);
    final deadline =
        keepAlive.required &&
            keepAlive.lastActivityAt != null &&
            keepAlive.cycleDays != null
        ? ZonedCalendar(
            subscription.timeZoneId,
          ).addDays(keepAlive.lastActivityAt!, keepAlive.cycleDays!)
        : null;
    final state = switch (status) {
      NotRequired() => KeepAliveRuleState.notApplicable,
      Safe() => KeepAliveRuleState.safe,
      DueSoon() => KeepAliveRuleState.dueSoon,
      Overdue() => KeepAliveRuleState.overdue,
      Unknown() => KeepAliveRuleState.unknown,
    };
    final daysRemaining = switch (status) {
      Safe(daysLeft: final days) || DueSoon(daysLeft: final days) => days,
      Overdue(daysOver: final days) => -days,
      _ => null,
    };
    return KeepAliveRuleEvaluation(
      id: 'cycle',
      title: '周期保号',
      details: keepAlive.required
          ? (keepAlive.policy.summary ?? '按有效动作重置保号周期')
          : '此 Profile 不需要周期保号',
      state: state,
      anchorAt: keepAlive.lastActivityAt,
      deadlineUtc: deadline,
      evidenceAt: keepAlive.lastActivityAt,
      daysRemaining: daysRemaining,
      inferred: keepAlive.confidence == DataConfidence.inferred,
    );
  }

  KeepAliveRuleEvaluation _evaluateConstraint(
    Subscription subscription,
    KeepAliveConstraint constraint,
    Iterable<ActivityRecord> activities,
  ) {
    final anchor = _anchorFor(subscription, constraint);
    final inferredAnchor =
        constraint.kind == KeepAliveConstraintKind.firstUse &&
        subscription.lifecycle.activatedAt == null;
    final deadline = anchor != null && constraint.withinDays != null
        ? ZonedCalendar(
            subscription.timeZoneId,
          ).addDays(anchor, constraint.withinDays!)
        : null;
    final manuallyCompletedAt = constraint.completedAt;
    if (manuallyCompletedAt != null) {
      return _constraintResult(
        constraint,
        state: KeepAliveRuleState.satisfied,
        anchor: anchor,
        deadline: deadline,
        evidenceAt: manuallyCompletedAt,
        inferred: inferredAnchor,
        completedLate:
            deadline != null && manuallyCompletedAt.isAfter(deadline),
      );
    }

    if (anchor != null && anchor.isAfter(_clock.nowUtc())) {
      return _constraintResult(
        constraint,
        state: KeepAliveRuleState.pending,
        anchor: anchor,
        deadline: deadline,
        inferred: inferredAnchor,
      );
    }

    final evidence = anchor == null
        ? null
        : _firstEvidence(subscription, constraint, activities, anchor);
    final inheritedEvidenceAt =
        constraint.qualifyingActions.isNotEmpty ||
            subscription.keepAlive.confidence == DataConfidence.inferred ||
            anchor == null ||
            subscription.keepAlive.lastActivityAt == null ||
            subscription.keepAlive.lastActivityAt!.isBefore(anchor)
        ? null
        : subscription.keepAlive.lastActivityAt;
    final evidenceAt = evidence?.occurredAt ?? inheritedEvidenceAt;
    final manual =
        constraint.evaluationMode == KeepAliveConstraintEvaluationMode.manual ||
        constraint.regions.isNotEmpty;

    if (!manual && evidenceAt != null) {
      return _constraintResult(
        constraint,
        state: KeepAliveRuleState.satisfied,
        anchor: anchor,
        deadline: deadline,
        evidenceAt: evidenceAt,
        evidenceActivity: evidence,
        inferred: inferredAnchor,
        completedLate: deadline != null && evidenceAt.isAfter(deadline),
      );
    }

    if (manual && evidenceAt != null) {
      return _constraintResult(
        constraint,
        state: KeepAliveRuleState.needsConfirmation,
        anchor: anchor,
        deadline: deadline,
        evidenceAt: evidenceAt,
        evidenceActivity: evidence,
        inferred: inferredAnchor,
        requiresManualConfirmation: true,
      );
    }

    if (anchor == null && constraint.withinDays != null) {
      return _constraintResult(
        constraint,
        state: KeepAliveRuleState.unknown,
        requiresManualConfirmation: manual,
      );
    }
    if (deadline == null) {
      return _constraintResult(
        constraint,
        state: manual
            ? KeepAliveRuleState.needsConfirmation
            : KeepAliveRuleState.pending,
        anchor: anchor,
        inferred: inferredAnchor,
        requiresManualConfirmation: manual,
      );
    }
    final days = ZonedCalendar(
      subscription.timeZoneId,
    ).daysBetween(_clock.nowUtc(), deadline);
    final state = days < 0
        ? KeepAliveRuleState.overdue
        : days <= dueSoonThresholdDays
        ? KeepAliveRuleState.dueSoon
        : KeepAliveRuleState.safe;
    return _constraintResult(
      constraint,
      state: state,
      anchor: anchor,
      deadline: deadline,
      daysRemaining: days,
      inferred: inferredAnchor,
      requiresManualConfirmation: manual,
    );
  }

  DateTime? _anchorFor(
    Subscription subscription,
    KeepAliveConstraint constraint,
  ) => switch (constraint.kind) {
    KeepAliveConstraintKind.firstUse =>
      subscription.lifecycle.activatedAt ?? subscription.createdAt,
    KeepAliveConstraintKind.afterPlanExpiry => subscription.plan.expiryDate,
    KeepAliveConstraintKind.paidRetention ||
    KeepAliveConstraintKind.custom => constraint.anchorAt,
  };

  ActivityRecord? _firstEvidence(
    Subscription subscription,
    KeepAliveConstraint constraint,
    Iterable<ActivityRecord> activities,
    DateTime anchor,
  ) {
    ActivityRecord? result;
    for (final activity in activities) {
      if (activity.subscriptionId != subscription.id ||
          activity.occurredAt.isBefore(anchor) ||
          !_accepts(subscription, constraint, activity.type)) {
        continue;
      }
      if (result == null || activity.occurredAt.isBefore(result.occurredAt)) {
        result = activity;
      }
    }
    return result;
  }

  bool _accepts(
    Subscription subscription,
    KeepAliveConstraint constraint,
    ActivityType type,
  ) {
    final actions = constraint.qualifyingActions.isEmpty
        ? subscription.keepAlive.policy.qualifyingActions
        : constraint.qualifyingActions;
    return actions.contains(_actionFor(type));
  }

  KeepAliveAction _actionFor(ActivityType type) => switch (type) {
    ActivityType.mobileData => KeepAliveAction.mobileData,
    ActivityType.call => KeepAliveAction.call,
    ActivityType.sms => KeepAliveAction.sms,
    ActivityType.topUp => KeepAliveAction.topUp,
    ActivityType.planPurchase => KeepAliveAction.planPurchase,
    ActivityType.renewal => KeepAliveAction.renewal,
    ActivityType.balanceChange => KeepAliveAction.balanceChange,
    ActivityType.other => KeepAliveAction.other,
  };

  KeepAliveRuleEvaluation _constraintResult(
    KeepAliveConstraint constraint, {
    required KeepAliveRuleState state,
    DateTime? anchor,
    DateTime? deadline,
    DateTime? evidenceAt,
    ActivityRecord? evidenceActivity,
    int? daysRemaining,
    bool inferred = false,
    bool requiresManualConfirmation = false,
    bool completedLate = false,
  }) => KeepAliveRuleEvaluation(
    id: constraint.id,
    title: constraint.title,
    details: constraint.details,
    state: state,
    anchorAt: anchor,
    deadlineUtc: deadline,
    evidenceAt: evidenceAt,
    evidenceActivity: evidenceActivity,
    daysRemaining: daysRemaining,
    inferred: inferred,
    requiresManualConfirmation: requiresManualConfirmation,
    completedLate: completedLate,
    regions: constraint.regions,
  );
}
