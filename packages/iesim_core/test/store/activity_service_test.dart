import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  test('动作与保号基准在同一事务内更新', () {
    final database = openIesimStore(':memory:');
    addTearDown(database.close);
    final subscription = _subscription('a', 'iccid-a');
    SubscriptionRepository(database).upsert(subscription);
    final occurredAt = DateTime.utc(2026, 8, 8, 12);
    final activity = _activity('act-a', 'a', occurredAt);

    final result = ActivityService(database).record(
      subscription: subscription,
      activity: activity,
      updatedAtUtc: occurredAt,
    );

    expect(result, isA<Ok<Subscription>>());
    final saved =
        (SubscriptionRepository(database).get('a') as Ok<Subscription?>).value!;
    expect(saved.keepAlive.lastActivityAt, occurredAt);
    expect(saved.keepAlive.confidence, DataConfidence.confirmed);
    expect(
      (ActivityRecordRepository(database).listAll() as Ok<List<ActivityRecord>>)
          .value,
      [activity],
    );
    expect(
      database.select(
        "SELECT * FROM scheduled_reminders WHERE subscription_id = 'a'",
      ),
      hasLength(4),
    );
  });

  test('订阅更新失败会回滚已经追加的动作', () {
    final database = openIesimStore(':memory:');
    addTearDown(database.close);
    final repository = SubscriptionRepository(database);
    final original = _subscription('a', 'iccid-a');
    repository.upsert(original);
    repository.upsert(_subscription('b', 'iccid-b'));
    final conflicting = Subscription(
      id: original.id,
      iccid: 'iccid-b',
      number: original.number,
      plan: original.plan,
      keepAlive: original.keepAlive,
      timeZoneId: original.timeZoneId,
      createdAt: original.createdAt,
      updatedAt: original.updatedAt,
    );

    final result = ActivityService(database).record(
      subscription: conflicting,
      activity: _activity('act-a', 'a', DateTime.utc(2026, 8, 8, 12)),
      updatedAtUtc: DateTime.utc(2026, 8, 8, 12),
    );

    expect(result, isA<Err>());
    expect(
      (ActivityRecordRepository(database).listAll() as Ok<List<ActivityRecord>>)
          .value,
      isEmpty,
    );
    expect((repository.get('a') as Ok<Subscription?>).value!.iccid, 'iccid-a');
  });

  test('非规则内动作只保留历史，不重置保号日期', () {
    final database = openIesimStore(':memory:');
    addTearDown(database.close);
    final original = _subscription('a', 'iccid-a').copyWith(
      keepAlive: KeepAlive(
        required: true,
        cycleDays: 30,
        lastActivityAt: DateTime.utc(2026, 7, 1),
        policy: KeepAlivePolicy(
          qualifyingActions: const {KeepAliveAction.topUp},
        ),
      ),
    );
    SubscriptionRepository(database).upsert(original);
    final activity = ActivityRecord(
      id: 'data-a',
      subscriptionId: original.id,
      type: ActivityType.mobileData,
      occurredAt: DateTime.utc(2026, 8, 8),
    );

    final result = ActivityService(database).record(
      subscription: original,
      activity: activity,
      updatedAtUtc: DateTime.utc(2026, 8, 8),
    );

    expect(result, isA<Ok<Subscription>>());
    expect(
      (result as Ok<Subscription>).value.keepAlive.lastActivityAt,
      DateTime.utc(2026, 7, 1),
    );
    expect(
      (ActivityRecordRepository(database).listAll() as Ok<List<ActivityRecord>>)
          .value,
      [activity],
    );
  });

  test('余额与期末流水在同一事务内更新', () {
    final database = openIesimStore(':memory:');
    addTearDown(database.close);
    final original = _subscription('a', 'iccid-a').copyWith(
      details: const SubscriptionDetails(
        currentBalance: Money(minorUnits: 1000, currencyCode: 'CNY'),
      ),
    );
    SubscriptionRepository(database).upsert(original);
    final now = DateTime.utc(2026, 8, 8, 13);
    final activity = ActivityRecord(
      id: 'balance-a',
      subscriptionId: original.id,
      type: ActivityType.balanceChange,
      occurredAt: now,
      amount: const Money(minorUnits: -250, currencyCode: 'CNY'),
      balanceAfter: const Money(minorUnits: 750, currencyCode: 'CNY'),
      note: '购买流量包',
    );

    final result = ActivityService(database).updateBalance(
      subscription: original,
      activity: activity,
      balance: const Money(minorUnits: 750, currencyCode: 'CNY'),
      updatedAtUtc: now,
    );

    expect(result, isA<Ok<Subscription>>());
    final saved =
        (SubscriptionRepository(database).get('a') as Ok<Subscription?>).value!;
    expect(
      saved.details.currentBalance,
      const Money(minorUnits: 750, currencyCode: 'CNY'),
    );
    expect(
      (ActivityRecordRepository(database).listAll() as Ok<List<ActivityRecord>>)
          .value,
      [activity],
    );
  });
}

Subscription _subscription(String id, String iccid) => Subscription(
  id: id,
  iccid: iccid,
  number: PhoneNumber('10086'),
  plan: Plan(),
  keepAlive: KeepAlive(
    required: true,
    cycleDays: 30,
    lastActivityAt: DateTime.utc(2026, 7, 1),
    confidence: DataConfidence.inferred,
  ),
  timeZoneId: 'UTC',
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 1),
);

ActivityRecord _activity(String id, String subscriptionId, DateTime at) =>
    ActivityRecord(
      id: id,
      subscriptionId: subscriptionId,
      type: ActivityType.call,
      occurredAt: at,
    );
