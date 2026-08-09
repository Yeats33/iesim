import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/home_action_center.dart';
import 'package:iesim_core/iesim_core.dart';

void main() {
  setUpAll(initializeIesimTimeZones);

  final now = DateTime.utc(2026, 8, 9);
  final center = HomeActionCenter(clock: FixedClock(now));

  test('同时汇总保号逾期、附加条件待确认和近期套餐到期', () {
    final subscription = _subscription(
      lastActivityAt: DateTime.utc(2026, 4, 1),
      planExpiry: DateTime.utc(2026, 8, 12),
      constraints: [
        KeepAliveConstraint(
          id: 'regional-first-use',
          kind: KeepAliveConstraintKind.firstUse,
          title: '首次使用',
          details: '需要在英国使用',
          withinDays: 180,
          regions: const ['英国'],
        ),
      ],
    );
    final actions = center.build(
      subscriptions: [subscription],
      activities: [
        ActivityRecord(
          id: 'call-1',
          subscriptionId: subscription.id,
          type: ActivityType.call,
          occurredAt: DateTime.utc(2026, 8, 1),
        ),
      ],
    );

    expect(
      actions.map((item) => item.kind),
      containsAll([
        HomeActionKind.keepAlive,
        HomeActionKind.keepAliveConstraint,
        HomeActionKind.planExpiry,
      ]),
    );
    expect(actions.first.urgency, HomeActionUrgency.critical);
  });

  test('待激活 Profile 只生成激活行动，不执行保号规则', () {
    final subscription = _subscription(
      lifecycle: ProfileLifecycle(
        stage: ProfileStage.pendingActivation,
        activationDeadline: DateTime.utc(2026, 8, 15),
      ),
    );
    final actions = center.build(
      subscriptions: [subscription],
      activities: const [],
    );

    expect(actions, hasLength(1));
    expect(actions.single.kind, HomeActionKind.activation);
  });

  test('资料完整且期限较远时首页保持清爽', () {
    final subscription = _subscription(
      lastActivityAt: DateTime.utc(2026, 8, 1),
      planExpiry: DateTime.utc(2027, 8, 1),
    );
    expect(
      center.build(subscriptions: [subscription], activities: const []),
      isEmpty,
    );
  });
}

Subscription _subscription({
  DateTime? lastActivityAt,
  DateTime? planExpiry,
  List<KeepAliveConstraint> constraints = const [],
  ProfileLifecycle lifecycle = const ProfileLifecycle(),
}) => Subscription(
  id: 'sub-a',
  number: PhoneNumber('+447700900001'),
  operator: 'Example',
  plan: Plan(expiryDate: planExpiry),
  keepAlive: KeepAlive(
    required: true,
    cycleDays: 90,
    lastActivityAt: lastActivityAt ?? DateTime.utc(2026, 8, 1),
    policy: KeepAlivePolicy(constraints: constraints),
  ),
  lifecycle: lifecycle,
  timeZoneId: 'UTC',
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 1),
);
