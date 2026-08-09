import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(initializeIesimTimeZones);

  final now = DateTime.utc(2026, 8, 9, 12);
  KeepAliveRuleEngine engine() => KeepAliveRuleEngine(clock: FixedClock(now));

  test('首次使用规则由符合动作的流水自动完成', () {
    final subscription = _subscription(
      constraints: [
        KeepAliveConstraint(
          id: 'first-use',
          kind: KeepAliveConstraintKind.firstUse,
          title: '首次使用',
          details: '十天内通话',
          withinDays: 10,
          qualifyingActions: const {KeepAliveAction.call},
        ),
      ],
    );
    final result = engine().evaluate(
      subscription,
      activities: [
        _activity(ActivityType.sms, DateTime.utc(2026, 8, 3)),
        _activity(ActivityType.call, DateTime.utc(2026, 8, 4)),
      ],
    );

    final rule = result.rules.singleWhere((item) => item.id == 'first-use');
    expect(rule.state, KeepAliveRuleState.satisfied);
    expect(rule.evidenceActivity?.type, ActivityType.call);
    expect(rule.completedLate, isFalse);
  });

  test('带地区限制的动作必须由用户确认，不猜测发生地点', () {
    final subscription = _subscription(
      constraints: [
        KeepAliveConstraint(
          id: 'uk-first-use',
          kind: KeepAliveConstraintKind.firstUse,
          title: '英国首次使用',
          details: '必须位于英国或欧盟',
          withinDays: 10,
          regions: const ['英国', '欧盟'],
        ),
      ],
    );
    final result = engine().evaluate(
      subscription,
      activities: [_activity(ActivityType.call, DateTime.utc(2026, 8, 4))],
    );

    final rule = result.rules.singleWhere((item) => item.id == 'uk-first-use');
    expect(rule.state, KeepAliveRuleState.needsConfirmation);
    expect(rule.requiresManualConfirmation, isTrue);
    expect(result.attention, KeepAliveAttention.confirmation);
  });

  test('创建时间推测出的上次动作不能作为首次使用证据', () {
    final original = _subscription(
      constraints: [
        KeepAliveConstraint(
          id: 'first-use-inferred',
          kind: KeepAliveConstraintKind.firstUse,
          title: '首次使用',
          details: '十天内完成动作',
          withinDays: 10,
        ),
      ],
    );
    final subscription = original.copyWith(
      keepAlive: original.keepAlive.copyWith(
        confidence: DataConfidence.inferred,
      ),
    );
    final rule = engine()
        .evaluate(subscription)
        .rules
        .singleWhere((item) => item.id == 'first-use-inferred');

    expect(rule.state, KeepAliveRuleState.dueSoon);
    expect(rule.evidenceAt, isNull);
  });

  test('套餐到期后规则使用套餐到期日作为锚点并可判定逾期', () {
    final subscription = _subscription(
      planExpiry: DateTime.utc(2026, 7, 20),
      constraints: [
        KeepAliveConstraint(
          id: 'renew-after-plan',
          kind: KeepAliveConstraintKind.afterPlanExpiry,
          title: '到期后续订',
          details: '十五天内续订',
          withinDays: 15,
          qualifyingActions: const {KeepAliveAction.renewal},
        ),
      ],
    );
    final result = engine().evaluate(subscription);

    final rule = result.rules.singleWhere(
      (item) => item.id == 'renew-after-plan',
    );
    expect(rule.state, KeepAliveRuleState.overdue);
    expect(rule.deadlineUtc, DateTime.utc(2026, 8, 4));
    expect(rule.daysRemaining, -5);
    expect(result.attention, KeepAliveAttention.overdue);
  });

  test('手动规则支持明确完成并标记超期完成', () {
    final subscription = _subscription(
      constraints: [
        KeepAliveConstraint(
          id: 'paid-retention',
          kind: KeepAliveConstraintKind.paidRetention,
          title: '付费保号',
          details: '完成休眠付费',
          withinDays: 5,
          anchorAt: DateTime.utc(2026, 8, 1),
          completedAt: DateTime.utc(2026, 8, 8),
        ),
      ],
    );
    final rule = engine()
        .evaluate(subscription)
        .rules
        .singleWhere((item) => item.id == 'paid-retention');

    expect(rule.state, KeepAliveRuleState.satisfied);
    expect(rule.completedLate, isTrue);
    expect(rule.evidenceAt, DateTime.utc(2026, 8, 8));
  });

  test('缺少套餐到期日时不把附加条件误判为安全', () {
    final subscription = _subscription(
      constraints: [
        KeepAliveConstraint(
          id: 'missing-anchor',
          kind: KeepAliveConstraintKind.afterPlanExpiry,
          title: '到期后动作',
          details: '到期后十天内',
          withinDays: 10,
        ),
      ],
    );
    final rule = engine()
        .evaluate(subscription)
        .rules
        .singleWhere((item) => item.id == 'missing-anchor');

    expect(rule.state, KeepAliveRuleState.unknown);
  });

  test('非激活 Profile 不执行保号规则', () {
    final subscription = _subscription(
      lifecycle: const ProfileLifecycle(stage: ProfileStage.museum),
    );
    expect(engine().evaluate(subscription).rules, isEmpty);
  });
}

Subscription _subscription({
  List<KeepAliveConstraint> constraints = const [],
  DateTime? planExpiry,
  ProfileLifecycle lifecycle = const ProfileLifecycle(),
}) => Subscription(
  id: 'sub-a',
  number: PhoneNumber('+447700900001'),
  plan: Plan(expiryDate: planExpiry),
  keepAlive: KeepAlive(
    required: true,
    cycleDays: 90,
    lastActivityAt: DateTime.utc(2026, 8, 2),
    policy: KeepAlivePolicy(constraints: constraints),
  ),
  lifecycle: lifecycle,
  timeZoneId: 'UTC',
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
);

ActivityRecord _activity(ActivityType type, DateTime occurredAt) =>
    ActivityRecord(
      id: '${type.name}-${occurredAt.day}',
      subscriptionId: 'sub-a',
      type: type,
      occurredAt: occurredAt,
    );
