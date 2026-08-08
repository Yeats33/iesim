import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(initializeIesimTimeZones);

  test('分别为保号截止和套餐到期预排程四档提醒', () {
    final now = DateTime.utc(2026, 8, 1, 0);
    final subscription = _subscription(
      lastActivityAt: DateTime.utc(2026, 7, 10, 4),
      keepAliveDays: 30,
      expiry: DateTime.utc(2026, 8, 20, 4),
    );

    final reminders = ReminderPlanner(
      clock: FixedClock(now),
    ).planFor(subscription);

    expect(
      reminders.where((item) => item.kind == ReminderKind.keepAlive),
      hasLength(4),
    );
    expect(
      reminders.where((item) => item.kind == ReminderKind.planExpiry),
      hasLength(4),
    );
    expect(reminders.map((item) => item.stableKey).toSet(), hasLength(8));
  });

  test('在当日提醒时刻之后新建记录会安排一分钟后的 current 提醒', () {
    // 上海 2026-08-08 12:00，已过 09:00；截止日就是今天。
    final now = DateTime.utc(2026, 8, 8, 4);
    final subscription = _subscription(
      lastActivityAt: DateTime.utc(2026, 7, 9, 4),
      keepAliveDays: 30,
    );

    final reminders = ReminderPlanner(
      clock: FixedClock(now),
    ).planFor(subscription);
    final current = reminders.singleWhere((item) => item.slot == 'current');
    expect(current.fireAtUtc, now.add(const Duration(minutes: 1)));
    expect(current.daysBefore, 0);
  });

  test('截止已过不再安排通知', () {
    final subscription = _subscription(
      lastActivityAt: DateTime.utc(2026, 6, 1),
      keepAliveDays: 30,
      expiry: DateTime.utc(2026, 7, 1),
    );
    final reminders = ReminderPlanner(
      clock: FixedClock(DateTime.utc(2026, 8, 8)),
    ).planFor(subscription);
    expect(reminders, isEmpty);
  });

  test('未知保号状态不安排保号通知', () {
    final subscription = _subscription(keepAliveDays: 30);
    final reminders = ReminderPlanner(
      clock: FixedClock(DateTime.utc(2026, 8, 1)),
    ).planFor(subscription);
    expect(reminders, isEmpty);
  });

  test('推测动作时间会传递到提醒，供 UI 明确标注', () {
    final subscription = _subscription(
      lastActivityAt: DateTime.utc(2026, 8, 1),
      keepAliveDays: 30,
      inferred: true,
    );
    final reminders = ReminderPlanner(
      clock: FixedClock(DateTime.utc(2026, 8, 2)),
    ).planFor(subscription);
    expect(reminders, isNotEmpty);
    expect(reminders.every((item) => item.inferred), isTrue);
  });

  test('夏令时跨越期间仍固定在订阅时区 09:00', () {
    final subscription = _subscription(
      timeZoneId: 'America/New_York',
      lastActivityAt: DateTime.utc(2026, 10, 10, 13),
      keepAliveDays: 30,
    );
    final reminders = ReminderPlanner(
      clock: FixedClock(DateTime.utc(2026, 10, 20)),
      daysBefore: const [7, 0],
    ).planFor(subscription);
    for (final reminder in reminders) {
      final local = ZonedCalendar(
        'America/New_York',
      ).momentAt(reminder.fireAtUtc);
      expect(local.hour, 9);
    }
  });

  test('未激活 Profile 只安排激活期限提醒', () {
    final subscription = _subscription(
      lastActivityAt: DateTime.utc(2026, 8, 1),
      keepAliveDays: 30,
      expiry: DateTime.utc(2026, 9, 1),
      lifecycle: ProfileLifecycle(
        stage: ProfileStage.pendingActivation,
        activationDeadline: DateTime.utc(2026, 9, 15),
      ),
    );
    final reminders = ReminderPlanner(
      clock: FixedClock(DateTime.utc(2026, 8, 1)),
    ).planFor(subscription);
    expect(reminders, isNotEmpty);
    expect(
      reminders.every((item) => item.kind == ReminderKind.activationDeadline),
      isTrue,
    );
  });

  test('博物馆 Profile 不再安排任何提醒', () {
    final subscription = _subscription(
      lastActivityAt: DateTime.utc(2026, 8, 1),
      keepAliveDays: 30,
      expiry: DateTime.utc(2026, 9, 1),
      lifecycle: ProfileLifecycle(
        stage: ProfileStage.museum,
        archivedAt: DateTime.utc(2026, 8, 8),
      ),
    );
    expect(
      ReminderPlanner(
        clock: FixedClock(DateTime.utc(2026, 8, 2)),
      ).planFor(subscription),
      isEmpty,
    );
  });
}

Subscription _subscription({
  String timeZoneId = 'Asia/Shanghai',
  DateTime? lastActivityAt,
  int? keepAliveDays,
  DateTime? expiry,
  bool inferred = false,
  ProfileLifecycle lifecycle = const ProfileLifecycle(),
}) => Subscription(
  id: 'sub-a',
  number: PhoneNumber('10086'),
  lifecycle: lifecycle,
  plan: Plan(expiryDate: expiry),
  keepAlive: KeepAlive(
    required: true,
    cycleDays: keepAliveDays,
    lastActivityAt: lastActivityAt,
    confidence: inferred ? DataConfidence.inferred : DataConfidence.confirmed,
  ),
  timeZoneId: timeZoneId,
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 1),
);
