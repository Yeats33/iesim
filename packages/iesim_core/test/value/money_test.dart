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

    test('跨币种相加抛出 CurrencyMismatchError', () {
      const a = Money(minorUnits: 1000, currencyCode: 'CNY');
      const b = Money(minorUnits: 1000, currencyCode: 'USD');
      expect(() => a + b, throwsA(isA<CurrencyMismatchError>()));
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
  });
}
