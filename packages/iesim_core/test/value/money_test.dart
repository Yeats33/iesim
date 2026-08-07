import 'package:test/test.dart';
import 'package:iesim_core/src/value/money.dart';

void main() {
  group('Money', () {
    test('相同金额与币种视为相等', () {
      expect(
        const Money(minorUnits: 1990, currencyCode: 'CNY'),
        equals(const Money(minorUnits: 1990, currencyCode: 'CNY')),
      );
    });

    test('币种不同则不相等', () {
      expect(
        const Money(minorUnits: 1990, currencyCode: 'CNY'),
        isNot(equals(const Money(minorUnits: 1990, currencyCode: 'USD'))),
      );
    });

    test('同币种相加', () {
      const a = Money(minorUnits: 1000, currencyCode: 'CNY');
      const b = Money(minorUnits: 990, currencyCode: 'CNY');
      expect(a + b, equals(const Money(minorUnits: 1990, currencyCode: 'CNY')));
    });

    test('同币种相减', () {
      const a = Money(minorUnits: 1990, currencyCode: 'CNY');
      const b = Money(minorUnits: 990, currencyCode: 'CNY');
      expect(a - b, equals(const Money(minorUnits: 1000, currencyCode: 'CNY')));
    });

    test('跨币种相加抛出 CurrencyMismatchError', () {
      const a = Money(minorUnits: 1000, currencyCode: 'CNY');
      const b = Money(minorUnits: 1000, currencyCode: 'USD');
      expect(() => a + b, throwsA(isA<CurrencyMismatchError>()));
    });

    test('跨币种相减抛出 CurrencyMismatchError', () {
      const a = Money(minorUnits: 1000, currencyCode: 'CNY');
      const b = Money(minorUnits: 1000, currencyCode: 'USD');
      expect(() => a - b, throwsA(isA<CurrencyMismatchError>()));
    });

    test('CurrencyMismatchError 信息含两侧币种', () {
      const a = Money(minorUnits: 1000, currencyCode: 'CNY');
      const b = Money(minorUnits: 1000, currencyCode: 'USD');
      try {
        a + b;
        fail('应抛出 CurrencyMismatchError');
      } on CurrencyMismatchError catch (e) {
        expect(e.toString(), contains('CNY'));
        expect(e.toString(), contains('USD'));
      }
    });

    test('zero 构造出对应币种的零值', () {
      expect(
        Money.zero('JPY'),
        equals(const Money(minorUnits: 0, currencyCode: 'JPY')),
      );
    });

    test('负数金额允许（用于退款与调整）', () {
      expect(
        const Money(minorUnits: -500, currencyCode: 'CNY').minorUnits,
        equals(-500),
      );
    });

    test('copyWith 仅覆盖指定字段', () {
      const a = Money(minorUnits: 1000, currencyCode: 'CNY');
      expect(
        a.copyWith(minorUnits: 2000),
        equals(const Money(minorUnits: 2000, currencyCode: 'CNY')),
      );
      expect(
        a.copyWith(currencyCode: 'USD'),
        equals(const Money(minorUnits: 1000, currencyCode: 'USD')),
      );
      expect(a.copyWith(), equals(a));
    });

    test('相等实例共享 hashCode', () {
      const a = Money(minorUnits: 1990, currencyCode: 'CNY');
      const b = Money(minorUnits: 1990, currencyCode: 'CNY');
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString 含金额与币种', () {
      const a = Money(minorUnits: 1990, currencyCode: 'CNY');
      expect(a.toString(), contains('1990'));
      expect(a.toString(), contains('CNY'));
    });
  });
}
