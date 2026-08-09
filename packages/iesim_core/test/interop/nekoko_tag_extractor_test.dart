import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(initializeIesimTimeZones);

  test('提取文本标签与已知日期语义到 ieSIM 原生字段', () {
    final source = Subscription(
      id: 's1',
      number: const PhoneNumber.unknown(),
      plan: Plan(),
      keepAlive: KeepAlive(required: true, cycleDays: 90),
      tags: const ['已有'],
      lifecycle: const ProfileLifecycle(stage: ProfileStage.pendingActivation),
      timeZoneId: 'Europe/Berlin',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final result = NekokoTagExtractor.apply(source, [
      NekokoTextTag('旅行'),
      NekokoTextTag('已有'),
      NekokoTextTag('+44_7726_751499'),
      NekokoDateTag(date: DateTime.utc(2026, 9, 1), note: '套餐到期'),
      NekokoDateTag(date: DateTime.utc(2026, 10, 1), note: '保号截止'),
      NekokoDateTag(date: DateTime.utc(2026, 8, 20), note: '激活期限'),
      NekokoDateTag(date: DateTime.utc(2027, 1, 1), note: 'Profile 服务到期'),
    ], updatedAtUtc: DateTime.utc(2026, 8, 9));

    expect(result.subscription.tags, ['已有', '旅行']);
    expect(result.subscription.number.value, '+447726751499');
    expect(result.subscription.plan.expiryDate, DateTime.utc(2026, 8, 31, 22));
    expect(
      result.subscription.keepAlive.lastActivityAt,
      DateTime.utc(2026, 7, 2, 22),
    );
    expect(
      result.subscription.lifecycle.activationDeadline,
      DateTime.utc(2026, 8, 19, 22),
    );
    expect(
      result.subscription.lifecycle.serviceExpiresAt,
      DateTime.utc(2026, 12, 31, 23),
    );
    expect(
      result.appliedFields,
      containsAll([
        '订阅标签 1 个',
        '手机号',
        '套餐到期日',
        '保号截止日',
        '激活期限',
        'Profile 服务到期日',
      ]),
    );
    expect(result.ignoredDateNotes, isEmpty);
  });

  test('没有周期时不猜测保号截止日，原始信息仍可保留', () {
    final source = Subscription(
      id: 's1',
      number: const PhoneNumber.unknown(),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'UTC',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final result = NekokoTagExtractor.apply(source, [
      NekokoDateTag(date: DateTime.utc(2026, 10, 1), note: '保号截止'),
      NekokoDateTag(date: DateTime.utc(2026, 11, 1), note: '神秘日期'),
    ], updatedAtUtc: DateTime.utc(2026, 8, 9));

    expect(result.subscription.keepAlive.lastActivityAt, isNull);
    expect(result.ignoredDateNotes, ['保号截止', '神秘日期']);
  });

  test('无备注日期按 Nekoko 常见格式提取为套餐到期日', () {
    final source = Subscription(
      id: 's1',
      number: const PhoneNumber.unknown(),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'UTC',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final result = NekokoTagExtractor.apply(source, [
      NekokoDateTag(date: DateTime.utc(2027, 3, 2)),
    ], updatedAtUtc: DateTime.utc(2026, 8, 9));

    expect(result.subscription.plan.expiryDate, DateTime.utc(2027, 3, 2));
    expect(result.appliedFields, contains('套餐到期日'));
  });
}
