import 'package:test/test.dart';
import 'package:iesim_core/src/keepalive/evaluator.dart';
import 'package:iesim_core/src/keepalive/status.dart';
import 'package:iesim_core/src/model/keep_alive.dart';
import 'package:iesim_core/src/time/calendar.dart';
import 'package:iesim_core/src/time/clock.dart';

void main() {
  setUpAll(initializeIesimTimeZones);

  const zone = 'Asia/Shanghai';
  // 北京时间 2026-08-07 12:00
  final now = DateTime.utc(2026, 8, 7, 4, 0);
  KeepAliveEvaluator evaluatorAt(DateTime instant) =>
      KeepAliveEvaluator(clock: FixedClock(instant));

  group('KeepAliveEvaluator', () {
    test('长期卡返回 NotRequired', () {
      final status =
          evaluatorAt(now).evaluate(KeepAlive.notRequired(), zone);
      expect(status, isA<NotRequired>());
    });

    test('缺少 lastActivityAt 返回 Unknown，不得视为安全', () {
      final k = KeepAlive(required: true, cycleDays: 90);
      final status = evaluatorAt(now).evaluate(k, zone);
      expect(status, isA<Unknown>());
    });

    test('缺少 cycleDays 返回 Unknown', () {
      final k = KeepAlive(
        required: true,
        lastActivityAt: DateTime.utc(2026, 8, 1),
      );
      expect(evaluatorAt(now).evaluate(k, zone), isA<Unknown>());
    });

    test('距截止 30 天返回 Safe', () {
      // 上次动作 2026-07-08（北京），周期 60 天 → 截止 2026-09-06，余 30 天
      final k = KeepAlive(
        required: true,
        cycleDays: 60,
        lastActivityAt: DateTime.utc(2026, 7, 7, 16, 0),
        confidence: DataConfidence.confirmed,
      );
      final status = evaluatorAt(now).evaluate(k, zone);
      expect(status, isA<Safe>());
      expect((status as Safe).daysLeft, equals(30));
      expect(status.inferred, isFalse);
    });

    test('距截止 3 天返回 DueSoon', () {
      // 截止 2026-08-10，余 3 天，低于默认阈值 7
      final k = KeepAlive(
        required: true,
        cycleDays: 30,
        lastActivityAt: DateTime.utc(2026, 7, 11, 4, 0),
        confidence: DataConfidence.confirmed,
      );
      final status = evaluatorAt(now).evaluate(k, zone);
      expect(status, isA<DueSoon>());
      expect((status as DueSoon).daysLeft, equals(3));
    });

    test('已超期返回 Overdue 并给出精确超期天数', () {
      // 北京时间：上次动作 2026-05-07，周期 30 天 → 截止 2026-06-06
      // 距今（2026-08-07）超期 24(6月剩) + 31(7月) + 7(8月) = 62 天
      final k = KeepAlive(
        required: true,
        cycleDays: 30,
        lastActivityAt: DateTime.utc(2026, 5, 6, 16, 0),
        confidence: DataConfidence.confirmed,
      );
      final status = evaluatorAt(now).evaluate(k, zone);
      expect(status, isA<Overdue>());
      expect((status as Overdue).daysOver, equals(62));
    });

    test('截止当日返回 DueSoon 且剩余 0 天', () {
      // 截止恰为 2026-08-07
      final k = KeepAlive(
        required: true,
        cycleDays: 30,
        lastActivityAt: DateTime.utc(2026, 7, 8, 4, 0),
        confidence: DataConfidence.confirmed,
      );
      final status = evaluatorAt(now).evaluate(k, zone);
      expect(status, isA<DueSoon>());
      expect((status as DueSoon).daysLeft, equals(0));
    });

    test('推测值产生的状态带 inferred 标记', () {
      final k = KeepAlive.inferredFrom(DateTime.utc(2026, 7, 7, 16, 0), 60);
      final status = evaluatorAt(now).evaluate(k, zone);
      expect(status, isA<Safe>());
      expect((status as Safe).inferred, isTrue);
    });

    test('基准时区不同导致剩余天数相差一天', () {
      // 上次动作 2026-07-08 20:00 UTC，周期 30 天。
      // 上海：动作日 7/9，截止 8/8，距今(8/7) 余 1 天
      // 纽约：动作日 7/8，截止 8/7，距今(纽约 8/7 00:00) 余 0 天
      final k = KeepAlive(
        required: true,
        cycleDays: 30,
        lastActivityAt: DateTime.utc(2026, 7, 8, 20, 0),
        confidence: DataConfidence.confirmed,
      );
      final shanghai = evaluatorAt(now).evaluate(k, 'Asia/Shanghai');
      final newYork = evaluatorAt(now).evaluate(k, 'America/New_York');
      expect(shanghai, isA<DueSoon>());
      expect(newYork, isA<DueSoon>());
      expect((shanghai as DueSoon).daysLeft, equals(1));
      expect((newYork as DueSoon).daysLeft, equals(0));
    });

    test('自定义阈值改变 Safe 与 DueSoon 的分界', () {
      final k = KeepAlive(
        required: true,
        cycleDays: 60,
        lastActivityAt: DateTime.utc(2026, 7, 7, 16, 0),
        confidence: DataConfidence.confirmed,
      );
      final strict = KeepAliveEvaluator(
        clock: FixedClock(now),
        dueSoonThresholdDays: 45,
      );
      expect(strict.evaluate(k, zone), isA<DueSoon>());
    });
  });
}
