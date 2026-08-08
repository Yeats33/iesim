import 'package:test/test.dart';
import 'package:iesim_core/src/model/keep_alive.dart';
import 'package:iesim_core/src/model/activity_record.dart';

void main() {
  group('KeepAlive', () {
    test('notRequired 表示长期卡，无需保号', () {
      final k = KeepAlive.notRequired();
      expect(k.required, isFalse);
      expect(k.cycleDays, isNull);
      expect(k.lastActivityAt, isNull);
    });

    test('inferredFrom 以创建时刻作为推测的上次动作时间', () {
      final created = DateTime.utc(2026, 8, 7, 10, 0);
      final k = KeepAlive.inferredFrom(created, 90);
      expect(k.required, isTrue);
      expect(k.cycleDays, equals(90));
      expect(k.lastActivityAt, equals(created));
      expect(k.confidence, equals(DataConfidence.inferred));
    });

    test('明确记录的动作时间为 confirmed', () {
      final k = KeepAlive(
        required: true,
        cycleDays: 90,
        lastActivityAt: DateTime.utc(2026, 8, 1),
        confidence: DataConfidence.confirmed,
      );
      expect(k.confidence, equals(DataConfidence.confirmed));
    });

    test('拒绝非 UTC 的 lastActivityAt', () {
      expect(
        () => KeepAlive(
          required: true,
          cycleDays: 90,
          lastActivityAt: DateTime(2026, 8, 1),
          confidence: DataConfidence.confirmed,
        ),
        throwsArgumentError,
      );
    });

    test('cycleDays 必须为正数', () {
      expect(
        () => KeepAlive(
          required: true,
          cycleDays: 0,
          lastActivityAt: DateTime.utc(2026, 8, 1),
          confidence: DataConfidence.confirmed,
        ),
        throwsArgumentError,
      );
    });

    test('copyWith 记录确认动作后可信度升为 confirmed', () {
      final inferred = KeepAlive.inferredFrom(DateTime.utc(2026, 8, 1), 90);
      final confirmed = inferred.copyWith(
        lastActivityAt: DateTime.utc(2026, 8, 7),
        confidence: DataConfidence.confirmed,
      );
      expect(confirmed.confidence, equals(DataConfidence.confirmed));
      expect(confirmed.lastActivityAt, equals(DateTime.utc(2026, 8, 7)));
      expect(
        inferred.confidence,
        equals(DataConfidence.inferred),
        reason: '原实例不可被修改',
      );
    });

    test('copyWith 不带参数返回等价实例', () {
      final k = KeepAlive(
        required: true,
        cycleDays: 90,
        lastActivityAt: DateTime.utc(2026, 8, 1),
        confidence: DataConfidence.confirmed,
      );
      expect(k.copyWith(), equals(k));
    });

    test('copyWith 可单独修改 required', () {
      final k = KeepAlive.notRequired();
      final updated = k.copyWith(required: true, cycleDays: 90);
      expect(updated.required, isTrue);
      expect(updated.cycleDays, equals(90));
      expect(k.required, isFalse, reason: '原实例不可被修改');
    });

    test('相同字段的实例视为相等', () {
      final a = KeepAlive(
        required: true,
        cycleDays: 90,
        lastActivityAt: DateTime.utc(2026, 8, 1),
        confidence: DataConfidence.confirmed,
      );
      final b = KeepAlive(
        required: true,
        cycleDays: 90,
        lastActivityAt: DateTime.utc(2026, 8, 1),
        confidence: DataConfidence.confirmed,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('字段不同则不相等', () {
      final a = KeepAlive(
        required: true,
        cycleDays: 90,
        lastActivityAt: DateTime.utc(2026, 8, 1),
        confidence: DataConfidence.confirmed,
      );
      expect(a, isNot(equals(KeepAlive.notRequired())));
    });

    test('复杂策略可表达动作集合、附加条件与官网来源', () {
      final policy = KeepAlivePolicy(
        qualifyingActions: const {
          KeepAliveAction.mobileData,
          KeepAliveAction.topUp,
        },
        summary: '使用流量或充值可重置周期',
        constraints: [
          KeepAliveConstraint(
            kind: KeepAliveConstraintKind.firstUse,
            title: '首次使用',
            details: '在服务区完成首次使用',
            withinDays: 10,
            regions: const ['英国', '欧盟'],
          ),
        ],
        presetId: 'carrier-a',
        sourceLabel: '运营商官网',
        sourceUrl: 'https://example.com/terms',
        sourceCheckedAt: DateTime.utc(2026, 8, 8),
      );

      expect(policy.accepts(ActivityType.mobileData), isTrue);
      expect(policy.accepts(ActivityType.topUp), isTrue);
      expect(policy.accepts(ActivityType.call), isFalse);
      expect(KeepAlivePolicy.fromJson(policy.toJson()), equals(policy));
    });

    test('拒绝没有任何有效动作的策略', () {
      expect(
        () => KeepAlivePolicy(qualifyingActions: const {}),
        throwsFormatException,
      );
    });
  });
}
