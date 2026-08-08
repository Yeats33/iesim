import 'package:test/test.dart';
import 'package:iesim_core/src/model/activity_record.dart';
import 'package:iesim_core/src/value/money.dart';

void main() {
  group('ActivityRecord', () {
    test('完整构造保留全部字段', () {
      final r = ActivityRecord(
        id: 'act-1',
        subscriptionId: 'sub-1',
        type: ActivityType.topUp,
        occurredAt: DateTime.utc(2026, 8, 7, 4, 0),
        amount: const Money(minorUnits: 10000, currencyCode: 'CNY'),
      );
      expect(r.id, equals('act-1'));
      expect(r.subscriptionId, equals('sub-1'));
      expect(r.type, equals(ActivityType.topUp));
      expect(r.occurredAt, equals(DateTime.utc(2026, 8, 7, 4, 0)));
      expect(r.updatedAt, equals(r.occurredAt));
      expect(
        r.amount,
        equals(const Money(minorUnits: 10000, currencyCode: 'CNY')),
      );
    });

    test('amount 可空（通话与短信无金额）', () {
      final r = ActivityRecord(
        id: 'act-2',
        subscriptionId: 'sub-1',
        type: ActivityType.call,
        occurredAt: DateTime.utc(2026, 8, 7, 5, 0),
      );
      expect(r.amount, isNull);
    });

    test('拒绝非 UTC 的 occurredAt', () {
      expect(
        () => ActivityRecord(
          id: 'act-3',
          subscriptionId: 'sub-1',
          type: ActivityType.sms,
          occurredAt: DateTime(2026, 8, 7, 5, 0),
        ),
        throwsArgumentError,
      );
    });

    test('拒绝非 UTC 的 updatedAt', () {
      expect(
        () => ActivityRecord(
          id: 'act-bad-updated',
          subscriptionId: 'sub-1',
          type: ActivityType.sms,
          occurredAt: DateTime.utc(2026, 8, 7, 5),
          updatedAt: DateTime(2026, 8, 7, 5),
        ),
        throwsArgumentError,
      );
    });

    test('copyWith 修改后原实例不变', () {
      final r = ActivityRecord(
        id: 'act-4',
        subscriptionId: 'sub-1',
        type: ActivityType.call,
        occurredAt: DateTime.utc(2026, 8, 7, 6, 0),
      );
      final next = r.copyWith(type: ActivityType.renewal);
      expect(r.type, equals(ActivityType.call));
      expect(next.type, equals(ActivityType.renewal));
    });

    test('相同字段视为相等', () {
      ActivityRecord make() => ActivityRecord(
        id: 'act-5',
        subscriptionId: 'sub-1',
        type: ActivityType.topUp,
        occurredAt: DateTime.utc(2026, 8, 7, 4, 0),
      );
      expect(make(), equals(make()));
      expect(make().copyWith(id: 'act-6'), isNot(equals(make())));
    });

    test('空 id 与空 subscriptionId 抛出 ArgumentError', () {
      expect(
        () => ActivityRecord(
          id: '',
          subscriptionId: 'sub-1',
          type: ActivityType.call,
          occurredAt: DateTime.utc(2026, 8, 7, 5, 0),
        ),
        throwsArgumentError,
      );
      expect(
        () => ActivityRecord(
          id: 'act-x',
          subscriptionId: '',
          type: ActivityType.call,
          occurredAt: DateTime.utc(2026, 8, 7, 5, 0),
        ),
        throwsArgumentError,
      );
    });
  });
}
