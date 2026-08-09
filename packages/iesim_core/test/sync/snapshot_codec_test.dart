import 'dart:convert';

import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  test('同步快照完整往返订阅、动作、资产和墓碑', () {
    final now = DateTime.utc(2026, 8, 7);
    final snapshot = SyncSnapshot(
      generatedAtUtc: DateTime.utc(2026, 8, 8),
      subscriptions: [_subscription('s1', now)],
      activityRecords: [
        ActivityRecord(
          id: 'a1',
          subscriptionId: 's1',
          type: ActivityType.topUp,
          occurredAt: DateTime.utc(2026, 8, 6),
          updatedAt: DateTime.utc(2026, 8, 7, 1),
          amount: const Money(minorUnits: 1000, currencyCode: 'CNY'),
          balanceAfter: const Money(minorUnits: 2100, currencyCode: 'CNY'),
          note: '同步余额流水',
        ),
      ],
      assets: AssetInventory(
        devices: [
          DeviceAsset(
            id: 'd1',
            name: '手机',
            kind: DeviceKind.phone,
            simCapability: SimCapability.physicalPlusEsim,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        cards: [
          EmbeddedEuiccCard(
            id: 'c1',
            name: '内置 eSIM',
            embeddedDeviceId: 'd1',
            createdAt: now,
            updatedAt: now,
          ),
          PhysicalSimCard(
            id: 'physical-without-iccid',
            name: '普通实体 SIM',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        slots: [
          SimSlot(
            id: 'slot1',
            deviceId: 'd1',
            label: 'eSIM',
            kind: SimSlotKind.embeddedEuicc,
            position: 0,
            cardId: 'c1',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        eids: [
          Euicc(
            id: 'e1',
            cardId: 'c1',
            value: '89000000000000000000000000000001',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        profiles: [
          EsimProfile(
            id: 'p1',
            eidId: 'e1',
            iccid: '8986000000000000001',
            nickname: '旅行 Profile',
            nekokoTagsRaw: 't:旅行\x0Ad:260901:套餐到期',
            subscriptionId: 's1',
            isPinned: true,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        events: [
          ProfileMoved(
            id: 'event1',
            profileId: 'p1',
            fromEidId: 'old-eid',
            toEidId: 'e1',
            occurredAt: now,
          ),
        ],
      ),
      tombstones: [
        SyncTombstone(
          entityType: SyncEntityType.activityRecord,
          entityId: 'deleted-a',
          deletedAtUtc: DateTime.utc(2026, 8, 5),
        ),
      ],
    );
    const codec = SyncSnapshotCodec();
    final encoded = codec.encode(snapshot);
    expect(encoded, isNot(contains('rsp.example.test')));
    expect(encoded, isNot(contains('MATCHING-ID-SECRET')));
    expect(encoded, isNot(contains('CONFIRMATION-SECRET')));
    final decoded = codec.decode(encoded);
    expect(decoded, isA<Ok<SyncSnapshot>>());
    final value = (decoded as Ok<SyncSnapshot>).value;
    expect(
      value.subscriptions.single,
      snapshot.subscriptions.single.copyWith(activation: null),
    );
    expect(value.subscriptions.single.activation, isNull);
    expect(value.activityRecords.single, snapshot.activityRecords.single);
    expect(value.assets.devices, snapshot.assets.devices);
    expect(value.assets.slots, snapshot.assets.slots);
    expect(value.assets.cards, snapshot.assets.cards);
    expect(value.assets.eids, snapshot.assets.eids);
    expect(value.assets.profiles, snapshot.assets.profiles);
    expect(value.assets.events, snapshot.assets.events);
    expect(value.tombstones.single, snapshot.tombstones.single);
  });

  test('开发期不完整 v1 快照不再兼容', () {
    final result = const SyncSnapshotCodec().decode(
      jsonEncode({
        'schemaVersion': 1,
        'generatedAt': '2026-08-08T00:00:00.000Z',
        'subscriptions': [],
        'activityRecords': [],
        'tombstones': [],
      }),
    );
    expect(result, isA<Err<SyncSnapshot>>());
    expect((result as Err).failure, isA<SchemaError>());
  });

  test('开发期旧编号快照直接拒绝', () {
    final snapshot = SyncSnapshot(
      generatedAtUtc: DateTime.utc(2026, 8, 8),
      subscriptions: [_subscription('s1', DateTime.utc(2026, 8, 7))],
    );
    final root =
        jsonDecode(const SyncSnapshotCodec().encode(snapshot))
            as Map<String, dynamic>;
    root['schemaVersion'] = 2;

    final result = const SyncSnapshotCodec().decode(jsonEncode(root));
    expect(result, isA<Err<SyncSnapshot>>());
    expect((result as Err).failure, isA<SchemaError>());
  });

  test('高版本快照拒绝读取并返回 SchemaError', () {
    final result = const SyncSnapshotCodec().decode(
      jsonEncode({
        'schemaVersion': 99,
        'generatedAt': '2026-08-08T00:00:00.000Z',
        'subscriptions': [],
        'activityRecords': [],
        'tombstones': [],
      }),
    );
    expect(result, isA<Err<SyncSnapshot>>());
    expect((result as Err).failure, isA<SchemaError>());
  });

  test('无时区时间戳不被静默当作 UTC', () {
    final result = const SyncSnapshotCodec().decode(
      jsonEncode({
        'schemaVersion': 1,
        'generatedAt': '2026-08-08T00:00:00',
        'subscriptions': [],
        'activityRecords': [],
        'tombstones': [],
      }),
    );
    expect((result as Err).failure, isA<SchemaError>());
  });
}

Subscription _subscription(String id, DateTime updatedAt) => Subscription(
  id: id,
  iccid: '89$id',
  number: PhoneNumber('10086'),
  operator: '运营商',
  lifecycle: ProfileLifecycle(
    stage: ProfileStage.museum,
    deviceState: ProfileDeviceState.disabled,
    activationDeadline: DateTime.utc(2026, 6, 1),
    activationRequirements: '首次下载需要联网',
    serviceExpiresAt: DateTime.utc(2026, 7, 1),
    activatedAt: DateTime.utc(2026, 1, 2),
    archivedAt: DateTime.utc(2026, 8, 1),
    archiveReason: ProfileArchiveReason.expired,
  ),
  activation: LpaActivation(
    smdpAddress: 'rsp.example.test',
    matchingId: 'MATCHING-ID-SECRET',
    confirmationCode: 'CONFIRMATION-SECRET',
  ),
  plan: Plan(
    name: '套餐',
    cyclePrice: const Money(minorUnits: 990, currencyCode: 'CNY'),
    cycleDays: 30,
    expiryDate: DateTime.utc(2027, 1, 1),
  ),
  keepAlive: KeepAlive(
    required: true,
    cycleDays: 90,
    lastActivityAt: DateTime.utc(2026, 8, 1),
  ),
  tags: const ['主卡'],
  appearance: const Appearance(flag: '🇨🇳', cardColorHex: '#123456'),
  details: const SubscriptionDetails(
    profileName: '同步 Profile',
    profileClassCode: 2,
    declaredProfileSizeBytes: 48000,
    installedProfileSizeBytes: 52000,
    gid1: '01',
    gid2: '02',
    countryCode: 'CN',
    currentBalance: Money(minorUnits: 100, currencyCode: 'CNY'),
    affiliateOffers: [
      AffiliateOffer(
        id: 'aff-1',
        brand: 'eSIM.gg',
        category: AffiliateOfferCategory.esimService,
        url: 'https://esim.gg/',
        promoCode: '1esim',
        isBuiltIn: true,
      ),
    ],
    isDormant: true,
    isPinned: true,
  ),
  timeZoneId: 'Asia/Shanghai',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: updatedAt,
);
