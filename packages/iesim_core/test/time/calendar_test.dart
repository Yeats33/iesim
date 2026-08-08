import 'package:test/test.dart';
import 'package:iesim_core/src/time/calendar.dart';

void main() {
  setUpAll(initializeIesimTimeZones);

  group('ZonedCalendar.daysBetween', () {
    test('同一日历日内的不同时刻相差 0 天', () {
      final cal = ZonedCalendar('Asia/Shanghai');
      // 北京时间 2026-08-07 01:00 与 23:00
      final a = DateTime.utc(2026, 8, 6, 17, 0);
      final b = DateTime.utc(2026, 8, 7, 15, 0);
      expect(cal.daysBetween(a, b), equals(0));
    });

    test('跨日历日相差 1 天，即便实际间隔不足 24 小时', () {
      final cal = ZonedCalendar('Asia/Shanghai');
      // 北京时间 2026-08-07 23:00 与 2026-08-08 01:00，实际仅隔 2 小时
      final a = DateTime.utc(2026, 8, 7, 15, 0);
      final b = DateTime.utc(2026, 8, 7, 17, 0);
      expect(cal.daysBetween(a, b), equals(1));
    });

    test('各时区按各自本地日历计数', () {
      final a = DateTime.utc(2026, 8, 7, 20, 0);
      final b = DateTime.utc(2026, 8, 9, 20, 0);
      // 上海：8/8 04:00 → 8/10 04:00，相差 2 天
      expect(ZonedCalendar('Asia/Shanghai').daysBetween(a, b), equals(2));
      // 纽约：8/7 16:00 → 8/9 16:00，相差 2 天
      expect(ZonedCalendar('America/New_York').daysBetween(a, b), equals(2));
    });

    test('落在时区分界两侧的同一时刻归属不同日历日', () {
      // 2026-08-07 20:00 UTC：上海已是 8/8 凌晨，纽约仍是 8/7 下午
      final instant = DateTime.utc(2026, 8, 7, 20, 0);
      final dayStart = DateTime.utc(2026, 8, 7, 0, 0);
      // 上海：8/7 08:00 → 8/8 04:00，跨了一个日历日
      expect(
        ZonedCalendar('Asia/Shanghai').daysBetween(dayStart, instant),
        equals(1),
      );
      // 纽约：8/6 20:00 → 8/7 16:00，同样跨一日但起点不同
      expect(
        ZonedCalendar('America/New_York').daysBetween(dayStart, instant),
        equals(1),
      );
    });

    test('夏令时切换日仍按日历日计数', () {
      final cal = ZonedCalendar('America/New_York');
      // 2026-03-08 是美国夏令时开始日，当天只有 23 小时
      final a = DateTime.utc(2026, 3, 8, 12, 0); // 纽约 3/8 07:00 EST→EDT
      final b = DateTime.utc(2026, 3, 9, 12, 0); // 纽约 3/9 08:00 EDT
      expect(cal.daysBetween(a, b), equals(1));
    });

    test('起点晚于终点时返回负数', () {
      final cal = ZonedCalendar('Asia/Shanghai');
      final a = DateTime.utc(2026, 8, 10, 0, 0);
      final b = DateTime.utc(2026, 8, 7, 0, 0);
      expect(cal.daysBetween(a, b), equals(-3));
    });

    test('极端时区 UTC+14 可用', () {
      final cal = ZonedCalendar('Pacific/Kiritimati');
      final a = DateTime.utc(2026, 8, 7, 0, 0);
      final b = DateTime.utc(2026, 8, 8, 0, 0);
      expect(cal.daysBetween(a, b), equals(1));
    });

    test('未知时区标识抛出 ArgumentError', () {
      expect(() => ZonedCalendar('Not/AZone'), throwsArgumentError);
    });
  });

  group('ZonedCalendar.addDays', () {
    test('加天数保持当地时钟时间', () {
      final cal = ZonedCalendar('Asia/Shanghai');
      final start = DateTime.utc(2026, 8, 7, 4, 0); // 北京 12:00
      final result = cal.addDays(start, 30);
      expect(cal.daysBetween(start, result), equals(30));
    });
  });

  group('ZonedCalendar 展示与输入转换', () {
    test('momentAt 返回订阅时区日期和 UTC 偏移', () {
      final moment = ZonedCalendar(
        'Asia/Shanghai',
      ).momentAt(DateTime.utc(2026, 8, 7, 16, 30));
      expect((moment.year, moment.month, moment.day), equals((2026, 8, 8)));
      expect((moment.hour, moment.minute), equals((0, 30)));
      expect(moment.utcOffset, equals(const Duration(hours: 8)));
    });

    test('utcFromParts 按基准时区解释日期选择器输入', () {
      final utc = ZonedCalendar(
        'Asia/Shanghai',
      ).utcFromParts(year: 2026, month: 8, day: 8, hour: 12);
      expect(utc, equals(DateTime.utc(2026, 8, 8, 4)));
    });

    test('momentAt 拒绝非 UTC 时刻', () {
      expect(
        () => ZonedCalendar('UTC').momentAt(DateTime(2026, 8, 8)),
        throwsArgumentError,
      );
    });
  });
}
