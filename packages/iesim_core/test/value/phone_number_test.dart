import 'package:test/test.dart';
import 'package:iesim_core/src/value/phone_number.dart';

void main() {
  group('PhoneNumber', () {
    test('去除空格、连字符与括号并保留 + 前缀', () {
      final p = PhoneNumber('+86 138-0000-0000');
      expect(p.value, equals('+8613800000000'));
    });

    test('无国际前缀的号码保持原样', () {
      expect(PhoneNumber('(021) 1234-5678').value, equals('02112345678'));
    });

    test('USSD 号码保留 # 与 *', () {
      expect(PhoneNumber('#100#').value, equals('#100#'));
      expect(PhoneNumber('*101*6#').value, equals('*101*6#'));
    });

    test('空输入抛出 ArgumentError', () {
      expect(() => PhoneNumber('   '), throwsArgumentError);
    });

    test('含字母抛出 ArgumentError', () {
      expect(() => PhoneNumber('138-0000-0000a'), throwsArgumentError);
    });

    test('仅一个 + 号抛出 ArgumentError', () {
      expect(() => PhoneNumber('+'), throwsArgumentError);
    });

    test('相同号码视为相等', () {
      expect(
        PhoneNumber('+86 138-0000-0000'),
        equals(PhoneNumber('+8613800000000')),
      );
    });

    test('不同号码不相等且 hashCode 不同', () {
      final a = PhoneNumber('13800000000');
      final b = PhoneNumber('13900000000');
      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });
  });
}
