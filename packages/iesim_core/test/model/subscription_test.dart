import 'package:test/test.dart';
import 'package:iesim_core/src/model/appearance.dart';
import 'package:iesim_core/src/model/keep_alive.dart';
import 'package:iesim_core/src/model/plan.dart';
import 'package:iesim_core/src/model/subscription.dart';
import 'package:iesim_core/src/value/phone_number.dart';

void main() {
  Subscription base() => Subscription(
    id: 'sub-1',
    iccid: '89000000000000000001',
    number: PhoneNumber('+8613800000000'),
    operator: '中国移动',
    plan: Plan(name: '畅享 5G', cycleDays: 30),
    keepAlive: KeepAlive.notRequired(),
    tags: const ['主力号'],
    appearance: const Appearance(flag: '🇨🇳'),
    timeZoneId: 'Asia/Shanghai',
    createdAt: DateTime.utc(2026, 8, 7, 4, 0),
    updatedAt: DateTime.utc(2026, 8, 7, 4, 0),
  );

  group('Subscription', () {
    test('完整构造保留全部字段', () {
      final s = base();
      expect(s.id, equals('sub-1'));
      expect(s.iccid, equals('89000000000000000001'));
      expect(s.number.value, equals('+8613800000000'));
      expect(s.operator, equals('中国移动'));
      expect(s.plan.name, equals('畅享 5G'));
      expect(s.keepAlive.required, isFalse);
      expect(s.tags, equals(['主力号']));
      expect(s.appearance.flag, equals('🇨🇳'));
      expect(s.timeZoneId, equals('Asia/Shanghai'));
      expect(s.createdAt, equals(DateTime.utc(2026, 8, 7, 4, 0)));
      expect(s.updatedAt, equals(DateTime.utc(2026, 8, 7, 4, 0)));
    });

    test('iccid 与 operator 可空（直接构造）', () {
      final s = Subscription(
        id: 'sub-2',
        number: PhoneNumber('+8613800000000'),
        plan: Plan(name: '畅享 5G', cycleDays: 30),
        keepAlive: KeepAlive.notRequired(),
        tags: const ['主力号'],
        timeZoneId: 'Asia/Shanghai',
        createdAt: DateTime.utc(2026, 8, 7, 4, 0),
        updatedAt: DateTime.utc(2026, 8, 7, 4, 0),
      );
      expect(s.iccid, isNull);
      expect(s.operator, isNull);
    });

    test('拒绝非 UTC 的时间戳', () {
      expect(
        () => base().copyWith(createdAt: DateTime(2026, 8, 7)),
        throwsArgumentError,
      );
      expect(
        () => base().copyWith(updatedAt: DateTime(2026, 8, 7)),
        throwsArgumentError,
      );
    });

    test('tags 不可被外部修改', () {
      final s = base();
      expect(() => s.tags.add('x'), throwsUnsupportedError);
    });

    test('copyWith 修改后原实例不变', () {
      final s = base();
      final next = s.copyWith(operator: '中国联通');
      expect(s.operator, equals('中国移动'));
      expect(next.operator, equals('中国联通'));
      expect(next.id, equals(s.id));
    });

    test('相同字段视为相等，tags 顺序敏感', () {
      expect(base(), equals(base()));
      expect(base().copyWith(tags: const ['备胎', '主力号']), isNot(equals(base())));
    });

    test('空 id 与空 timeZoneId 抛出 ArgumentError', () {
      expect(() => base().copyWith(id: ''), throwsArgumentError);
      expect(() => base().copyWith(timeZoneId: ''), throwsArgumentError);
    });
  });
}
