import 'package:test/test.dart';
import 'package:iesim_core/src/model/plan.dart';
import 'package:iesim_core/src/value/money.dart';

void main() {
  group('Plan', () {
    test('默认构造为可空全空、非长期', () {
      final plan = Plan();
      expect(plan.name, isNull);
      expect(plan.cyclePrice, isNull);
      expect(plan.cycleDays, isNull);
      expect(plan.startDate, isNull);
      expect(plan.expiryDate, isNull);
      expect(plan.isLongTerm, isFalse);
    });

    test('cycleDays 必须为正数', () {
      expect(() => Plan(cycleDays: 0), throwsArgumentError);
      expect(() => Plan(cycleDays: -30), throwsArgumentError);
    });

    test('拒绝非 UTC 的日期', () {
      expect(() => Plan(startDate: DateTime(2026, 8, 1)), throwsArgumentError);
      expect(() => Plan(expiryDate: DateTime(2026, 8, 1)), throwsArgumentError);
    });

    test('copyWith 仅覆盖指定字段', () {
      final plan = Plan(name: 'A', cycleDays: 30);
      final next = plan.copyWith(cyclePrice: Money.zero('CNY'));
      expect(next.name, equals('A'));
      expect(next.cycleDays, equals(30));
      expect(next.cyclePrice, equals(Money.zero('CNY')));
    });

    test('相同字段视为相等', () {
      expect(
        Plan(name: 'A', cycleDays: 30),
        equals(Plan(name: 'A', cycleDays: 30)),
      );
      expect(
        Plan(name: 'A', cycleDays: 30),
        isNot(equals(Plan(name: 'A', cycleDays: 60))),
      );
    });
  });
}
