import 'dart:convert';

import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(initializeIesimTimeZones);

  late SimHubCodec codec;
  var nextId = 0;
  final now = DateTime.utc(2026, 8, 8, 10);

  setUp(() {
    nextId = 0;
    codec = SimHubCodec(
      idFactory: () => 'generated-${nextId++}',
      nowUtc: () => now,
    );
  });

  test('完整记录按基准时区解释无偏移日期并解析扩展字段', () {
    final report = codec.decode(
      jsonEncode([
        {
          'id': 'sub-1',
          'phoneNumber': '+86 138-0000-0000',
          'carrier': '示例运营商',
          'countryCode': 'CN',
          'countryName': '中国',
          'secondaryPhoneNumber': '10010',
          'secondaryPhoneNumberEnabled': true,
          'activationDate': '2026-08-01',
          'expiryDate': '2026-09-01',
          'createdAt': '2026-08-01',
          'plan': '30 天套餐',
          'cyclePaymentMinorUnits': 1990,
          'currencyCode': 'cny',
          'currentBalance': '12.34',
          'autoTopUpEnabled': true,
          'topUpCycleUnit': 'month',
          'renewalIntervalValue': 1,
          'renewalUnit': 'month',
          'transactionNotes': '测试备注',
          'carrierAppName': '运营商 App',
          'renewDays': 30,
          'billingType': 'prepaid',
          'tags': ['旅行', '备用'],
          'iccid': '8986001',
          'lastActivityAt': '2026-08-02T04:00:00Z',
          'activityConfidence': 'confirmed',
          'timeZoneId': 'Asia/Shanghai',
          'cardColorHex': '#123456',
          'activityRecords': [
            {
              'id': 'act-1',
              'type': 'topUp',
              'occurredAt': '2026-08-02T04:00:00Z',
              'amountMinorUnits': 1990,
              'amountCurrency': 'CNY',
            },
          ],
        },
      ]),
      defaultTimeZoneId: 'UTC',
    );

    expect(report.importedCount, 1);
    expect(report.issues, isEmpty);
    final subscription = report.subscriptions.single;
    expect(subscription.number.value, '+8613800000000');
    expect(subscription.createdAt, DateTime.utc(2026, 7, 31, 16));
    expect(subscription.plan.expiryDate, DateTime.utc(2026, 8, 31, 16));
    expect(
      subscription.plan.cyclePrice,
      const Money(minorUnits: 1990, currencyCode: 'CNY'),
    );
    expect(subscription.keepAlive.required, isTrue);
    expect(subscription.keepAlive.confidence, DataConfidence.confirmed);
    expect(subscription.tags, ['旅行', '备用']);
    expect(subscription.details.countryCode, 'CN');
    expect(subscription.details.secondaryPhoneNumber, '10010');
    expect(
      subscription.details.currentBalance,
      const Money(minorUnits: 1234, currencyCode: 'CNY'),
    );
    expect(subscription.details.autoTopUpEnabled, isTrue);
    expect(subscription.details.transactionNotes, '测试备注');
    expect(report.activityRecords.single.subscriptionId, 'sub-1');
  });

  test('新旧 cardType 字段名均接受', () {
    for (final field in ['cardType', 'billingType']) {
      final report = codec.decode(
        jsonEncode({
          'phoneNumber': '10086',
          field: 'prepaid',
          'renewDays': 90,
          'createdAt': '2026-08-01',
        }),
        defaultTimeZoneId: 'Asia/Shanghai',
      );
      expect(report.subscriptions.single.keepAlive.required, isTrue);
    }
  });

  test('导入 SimHub v5 备份中的 esimCards 与 dormantCards', () {
    final report = codec.decode(
      jsonEncode({
        'formatVersion': 5,
        'esimCards': [
          {
            'id': 'active',
            'phoneNumber': '',
            'carrier': 'Provider A',
            'smdpAddress': 'rsp.example.com',
            'activationCode': 'MATCH-A',
            'createdAt': '2026-08-01T00:00:00Z',
          },
        ],
        'dormantCards': [
          {
            'id': 'wrapper',
            'card': {
              'id': 'dormant',
              'phoneNumber': '10086',
              'carrier': 'Provider B',
              'createdAt': '2026-08-02T00:00:00Z',
            },
          },
        ],
        'devices': [],
        'services': [],
        'boundServices': [],
      }),
      defaultTimeZoneId: 'UTC',
    );

    expect(report.sourceRecordCount, 2);
    expect(report.importedCount, 2);
    expect(report.subscriptions.first.number.isUnknown, isTrue);
    expect(
      report.subscriptions.first.activation?.smdpAddress,
      'rsp.example.com',
    );
    expect(report.subscriptions.first.activation?.matchingId, 'MATCH-A');
    expect(
      report.subscriptions
          .singleWhere((item) => item.id == 'dormant')
          .details
          .isDormant,
      isTrue,
    );
    expect(
      report.subscriptions
          .singleWhere((item) => item.id == 'dormant')
          .lifecycle
          .stage,
      ProfileStage.museum,
    );
    final exported =
        jsonDecode(codec.encodeV5(report.subscriptions, assets: report.assets))
            as Map<String, dynamic>;
    expect(exported['esimCards'], hasLength(1));
    expect(exported['dormantCards'], hasLength(1));
  });

  test('SimHub v5 设备、卡槽、eUICC、EID 和 Profile 自动建立关联', () {
    final report = codec.decode(
      jsonEncode({
        'formatVersion': 5,
        'esimCards': [
          {
            'id': 'sub-a',
            'phoneNumber': '10001',
            'carrier': 'Provider A',
            'deviceID': 'device-a',
            'eid': '89000000000000000000000000000001',
            'createdAt': '2026-08-01T00:00:00Z',
          },
          {
            'id': 'sub-b',
            'phoneNumber': '10002',
            'carrier': 'Provider B',
            'deviceID': 'device-a',
            'eid': '89000000000000000000000000000001',
            'createdAt': '2026-08-02T00:00:00Z',
          },
        ],
        'dormantCards': [],
        'devices': [
          {
            'id': 'device-a',
            'name': '测试手机',
            'brand': 'Example',
            'deviceTypeRaw': 'phone',
            'simCapabilityRaw': 'physicalPlusESIM',
            'removableESIM': true,
            'eid': '89000000000000000000000000000001',
            'createdAt': '2026-07-01T00:00:00Z',
            'updatedAt': '2026-08-01T00:00:00Z',
          },
        ],
      }),
      defaultTimeZoneId: 'UTC',
    );

    expect(report.assets.devices, hasLength(1));
    expect(report.assets.slots, hasLength(2));
    expect(report.assets.cards, hasLength(1));
    expect(report.assets.eids, hasLength(1));
    expect(report.assets.profiles, hasLength(2));
    expect(
      report.assets.profiles.map((profile) => profile.subscriptionId),
      containsAll(['sub-a', 'sub-b']),
    );
    expect(
      report.assets.slotHolding(report.assets.cards.single.id)?.deviceId,
      report.assets.devices.single.id,
    );

    final exported = codec.encodeV5(
      report.subscriptions,
      assets: report.assets,
    );
    final restored = codec.decode(exported, defaultTimeZoneId: 'UTC');
    expect(restored.subscriptions, hasLength(2));
    expect(restored.assets.devices, hasLength(1));
    expect(restored.assets.profiles, hasLength(2));
  });

  test('SimHub v5 实体卡的设备归属可往返', () {
    final report = codec.decode(
      jsonEncode({
        'formatVersion': 5,
        'esimCards': [
          {
            'id': 'physical-sub',
            'iccid': '8986000001',
            'phoneNumber': '10001',
            'deviceID': 'device-a',
            'createdAt': '2026-08-01T00:00:00Z',
          },
        ],
        'dormantCards': [],
        'devices': [
          {
            'id': 'device-a',
            'name': '测试手机',
            'deviceTypeRaw': 'phone',
            'simCapabilityRaw': 'physicalOnly',
            'createdAt': '2026-08-01T00:00:00Z',
          },
        ],
      }),
      defaultTimeZoneId: 'UTC',
    );
    expect(report.assets.cards.single, isA<PhysicalSimCard>());
    final encoded =
        jsonDecode(codec.encodeV5(report.subscriptions, assets: report.assets))
            as Map<String, dynamic>;
    final card = (encoded['esimCards'] as List).single as Map<String, dynamic>;
    expect(card['deviceID'], 'device-a');
    final restored = codec.decode(
      jsonEncode(encoded),
      defaultTimeZoneId: 'UTC',
    );
    expect(
      restored.assets.slotHolding(restored.assets.cards.single.id),
      isNotNull,
    );
  });

  test('缺失动作时间时仅在有创建日期可推测的情况下标记 inferred', () {
    final report = codec.decode(
      jsonEncode([
        {'phoneNumber': '10001', 'createdAt': '2026-08-01', 'renewDays': 30},
        {'phoneNumber': '10002', 'renewDays': 30},
      ]),
      defaultTimeZoneId: 'Asia/Shanghai',
    );

    expect(
      report.subscriptions[0].keepAlive.confidence,
      DataConfidence.inferred,
    );
    expect(report.subscriptions[0].keepAlive.lastActivityAt, isNotNull);
    expect(report.subscriptions[1].keepAlive.lastActivityAt, isNull);
    expect(
      KeepAliveEvaluator(clock: FixedClock(DateTime.utc(2026, 8, 8))).evaluate(
        report.subscriptions[1].keepAlive,
        report.subscriptions[1].timeZoneId,
      ),
      isA<Unknown>(),
    );
  });

  test('坏记录不阻断整批，坏日期字段留空并进入报告', () {
    final report = codec.decode(
      jsonEncode([
        {'phoneNumber': 'invalid-letter'},
        {'phoneNumber': '10010', 'expiryDate': '2026-02-30'},
        42,
      ]),
      defaultTimeZoneId: 'UTC',
    );

    expect(report.sourceRecordCount, 3);
    expect(report.importedCount, 1);
    expect(report.skippedCount, 2);
    expect(report.subscriptions.single.plan.expiryDate, isNull);
    expect(
      report.issues.map((issue) => issue.field),
      containsAll(['phoneNumber', 'expiryDate', r'$']),
    );
  });

  test('重复 id 与 ICCID 不进入数据库候选列表', () {
    final report = codec.decode(
      jsonEncode([
        {'id': 'same', 'phoneNumber': '10000', 'iccid': 'a'},
        {'id': 'same', 'phoneNumber': '10001', 'iccid': 'b'},
        {'id': 'other', 'phoneNumber': '10002', 'iccid': 'a'},
      ]),
      defaultTimeZoneId: 'UTC',
    );

    expect(report.importedCount, 1);
    expect(
      report.issues.map((issue) => issue.field),
      containsAll(['id', 'iccid']),
    );
  });

  test('导出后可恢复 iesim 扩展字段和动作记录', () {
    final subscription = Subscription(
      id: 'sub-1',
      iccid: '8986001',
      number: PhoneNumber('+8613800000000'),
      operator: '示例运营商',
      activation: LpaActivation(
        smdpAddress: 'rsp.example.com',
        matchingId: 'MATCH-1',
        extra: r'1.2.3$1',
        confirmationCode: '654321',
      ),
      plan: Plan(
        name: '套餐 A',
        cyclePrice: const Money(minorUnits: 880, currencyCode: 'CNY'),
        cycleDays: 30,
        expiryDate: DateTime.utc(2026, 9, 1, 4),
      ),
      keepAlive: KeepAlive(
        required: true,
        cycleDays: 90,
        lastActivityAt: DateTime.utc(2026, 8, 1, 4),
        confidence: DataConfidence.confirmed,
      ),
      tags: const ['旅行'],
      appearance: const Appearance(flag: '🇨🇳', cardColorHex: '#0C615F'),
      details: const SubscriptionDetails(
        profileName: '英国主号',
        isPinned: true,
        profileClassCode: 2,
        declaredProfileSizeBytes: 48000,
        installedProfileSizeBytes: 52000,
        gid1: '01',
        gid2: '02',
        affiliateOffers: [
          AffiliateOffer(
            id: 'aff-1',
            brand: 'CTExcel UK',
            category: AffiliateOfferCategory.mobileOperator,
            url:
                'https://www.ctexcel.com/uk/buyCard/buyCardPackage/1?recommendCode=RNAFZW',
            promoCode: 'RNAFZW',
            isBuiltIn: true,
          ),
        ],
      ),
      timeZoneId: 'Asia/Shanghai',
      createdAt: DateTime.utc(2026, 7, 1, 4),
      updatedAt: DateTime.utc(2026, 8, 2, 7),
    );
    final activity = ActivityRecord(
      id: 'act-1',
      subscriptionId: 'sub-1',
      type: ActivityType.topUp,
      occurredAt: DateTime.utc(2026, 8, 1, 4),
      amount: const Money(minorUnits: 880, currencyCode: 'CNY'),
      balanceAfter: const Money(minorUnits: 1880, currencyCode: 'CNY'),
      note: 'AFF 返利入账',
    );

    final encoded = codec.encode([subscription], activityRecords: [activity]);
    final decoded = codec.decode(encoded, defaultTimeZoneId: 'UTC');

    expect(decoded.issues, isEmpty);
    final restored = decoded.subscriptions.single;
    expect(restored.id, subscription.id);
    expect(restored.iccid, subscription.iccid);
    expect(restored.number, subscription.number);
    expect(restored.plan.cyclePrice, subscription.plan.cyclePrice);
    expect(restored.keepAlive, subscription.keepAlive);
    expect(restored.updatedAt, subscription.updatedAt);
    expect(restored.activation, subscription.activation);
    expect(restored.details.isPinned, isTrue);
    expect(
      restored.details.affiliateOffers,
      subscription.details.affiliateOffers,
    );
    expect(decoded.activityRecords.single, activity);
  });

  test('畸形顶层 JSON 只返回报告，不抛异常', () {
    final report = codec.decode('{broken', defaultTimeZoneId: 'UTC');
    expect(report.subscriptions, isEmpty);
    expect(report.issues.single.recordIndex, isNull);
  });
}
