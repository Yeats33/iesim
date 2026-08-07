import 'package:test/test.dart';
import 'package:iesim_core/src/time/clock.dart';

void main() {
  group('FixedClock', () {
    test('始终返回构造时给定的时刻', () {
      final instant = DateTime.utc(2026, 8, 7, 12, 0);
      final clock = FixedClock(instant);
      expect(clock.nowUtc(), equals(instant));
      expect(clock.nowUtc(), equals(instant));
    });

    test('拒绝非 UTC 时刻，避免基准歧义', () {
      final local = DateTime(2026, 8, 7, 12, 0);
      expect(() => FixedClock(local), throwsArgumentError);
    });
  });

  group('SystemClock', () {
    test('返回的时刻标记为 UTC', () {
      expect(const SystemClock().nowUtc().isUtc, isTrue);
    });
  });
}
