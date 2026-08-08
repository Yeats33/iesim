import 'package:iesim_core/iesim_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Database db;
  late AssetRepository repository;
  final created = DateTime.utc(2026, 8, 8);

  setUp(() {
    db = openIesimStore(':memory:');
    repository = AssetRepository(db);
  });

  tearDown(() => db.close());

  DeviceAsset device(String id) => DeviceAsset(
    id: id,
    name: '测试设备 $id',
    kind: DeviceKind.phone,
    simCapability: SimCapability.physicalPlusEsim,
    createdAt: created,
    updatedAt: created,
  );

  SimSlot slot(
    String id,
    String deviceId,
    int position, {
    SimSlotKind kind = SimSlotKind.physical,
  }) => SimSlot(
    id: id,
    deviceId: deviceId,
    label: '卡槽 ${position + 1}',
    kind: kind,
    position: position,
    createdAt: created,
    updatedAt: created,
  );

  test('设备、卡槽、eUICC、EID 与 Profile 可完整往返', () {
    repository.upsertDevice(device('d1'));
    repository.upsertSlot(slot('s1', 'd1', 0));
    repository.upsertCard(
      RemovableEuiccCard(
        id: 'c1',
        name: '实体 eSIM',
        presetId: '9esim-removable',
        createdAt: created,
        updatedAt: created,
      ),
    );
    repository.upsertEid(
      Euicc(
        id: 'e1',
        cardId: 'c1',
        value: '89000000000000000000000000000001',
        createdAt: created,
        updatedAt: created,
      ),
    );
    db.execute('''
INSERT INTO subscriptions (
  id, number, plan_is_long_term, keepalive_required, keepalive_confidence,
  tags_json, time_zone_id, created_at, updated_at
) VALUES (
  'sub-imported', '', 0, 1, 'confirmed', '[]', 'UTC',
  '2026-08-08T00:00:00.000Z', '2026-08-08T00:00:00.000Z'
)
''');
    repository.upsertProfile(
      EsimProfile(
        id: 'p1',
        eidId: 'e1',
        subscriptionId: 'sub-imported',
        operatorName: 'Example',
        isPinned: true,
        createdAt: created,
        updatedAt: created,
      ),
    );

    final inventory = (repository.load() as Ok<AssetInventory>).value;
    expect(inventory.devices, hasLength(1));
    expect(inventory.slots, hasLength(1));
    expect(inventory.cards.single, isA<RemovableEuiccCard>());
    expect(inventory.cards.single.presetId, '9esim-removable');
    expect(inventory.eids.single.value, hasLength(32));
    expect(inventory.profiles.single.subscriptionId, 'sub-imported');
    expect(inventory.profiles.single.isPinned, isTrue);
  });

  test('移动卡片和移至库存会记录独立资产事件', () {
    repository.upsertDevice(device('d1'));
    repository.upsertDevice(device('d2'));
    repository.upsertSlot(slot('s1', 'd1', 0));
    repository.upsertSlot(slot('s2', 'd2', 0));
    repository.upsertCard(
      PhysicalSimCard(
        id: 'c1',
        name: '实体 SIM',
        physicalIccid: '8901000000000000001',
        createdAt: created,
        updatedAt: created,
      ),
    );

    expect(
      repository.moveCard(
        cardId: 'c1',
        toSlotId: 's1',
        eventId: 'ev1',
        occurredAt: created,
      ),
      isA<Ok<void>>(),
    );
    expect(
      repository.moveCard(
        cardId: 'c1',
        toSlotId: 's2',
        eventId: 'ev2',
        occurredAt: created.add(const Duration(hours: 1)),
      ),
      isA<Ok<void>>(),
    );
    expect(
      repository.moveCard(
        cardId: 'c1',
        toSlotId: null,
        eventId: 'ev3',
        occurredAt: created.add(const Duration(hours: 2)),
      ),
      isA<Ok<void>>(),
    );

    final inventory = (repository.load() as Ok<AssetInventory>).value;
    expect(inventory.slotHolding('c1'), isNull);
    expect(inventory.events, hasLength(3));
    expect(inventory.events.first, isA<CardStored>());
  });

  test('内置 eUICC 不能移到其他设备或库存', () {
    repository.upsertDevice(device('d1'));
    repository.upsertDevice(device('d2'));
    repository.upsertSlot(slot('s1', 'd1', 0, kind: SimSlotKind.embeddedEuicc));
    repository.upsertSlot(slot('s2', 'd2', 0, kind: SimSlotKind.embeddedEuicc));
    repository.upsertCard(
      EmbeddedEuiccCard(
        id: 'c1',
        name: '内置 eUICC',
        embeddedDeviceId: 'd1',
        createdAt: created,
        updatedAt: created,
      ),
    );

    expect(
      repository.moveCard(
        cardId: 'c1',
        toSlotId: 's1',
        eventId: 'ev1',
        occurredAt: created,
      ),
      isA<Ok<void>>(),
    );
    expect(
      repository.moveCard(
        cardId: 'c1',
        toSlotId: 's2',
        eventId: 'ev2',
        occurredAt: created,
      ),
      isA<Err<void>>(),
    );
    expect(
      repository.moveCard(
        cardId: 'c1',
        toSlotId: null,
        eventId: 'ev3',
        occurredAt: created,
      ),
      isA<Err<void>>(),
    );
  });

  test('内置 eUICC 不能被换卡操作从所属卡槽拆下', () {
    repository.upsertDevice(device('d1'));
    repository.upsertSlot(slot('s1', 'd1', 0, kind: SimSlotKind.embeddedEuicc));
    repository.upsertCard(
      EmbeddedEuiccCard(
        id: 'embedded',
        name: '内置 eUICC',
        embeddedDeviceId: 'd1',
        createdAt: created,
        updatedAt: created,
      ),
    );
    repository.moveCard(
      cardId: 'embedded',
      toSlotId: 's1',
      eventId: 'installed',
      occurredAt: created,
    );
    repository.upsertCard(
      PhysicalSimCard(
        id: 'replacement',
        name: '替换卡',
        physicalIccid: '8901000000000000001',
        createdAt: created,
        updatedAt: created,
      ),
    );

    expect(
      repository.replaceCardInSlot(
        slotId: 's1',
        cardId: 'replacement',
        storedEventId: 'stored',
        movedEventId: 'replacement-moved',
        occurredAt: created.add(const Duration(minutes: 1)),
      ),
      isA<Err<void>>(),
    );
    final inventory = (repository.load() as Ok<AssetInventory>).value;
    expect(inventory.slotHolding('embedded')?.id, 's1');
    expect(inventory.slotHolding('replacement'), isNull);
  });

  test('直接写入卡槽也不能绕过卡片类型约束', () {
    repository.upsertDevice(device('d1'));
    repository.upsertCard(
      PhysicalSimCard(
        id: 'physical',
        name: '实体 SIM',
        physicalIccid: '8901000000000000001',
        createdAt: created,
        updatedAt: created,
      ),
    );
    final embeddedSlot = slot(
      'embedded-slot',
      'd1',
      0,
      kind: SimSlotKind.embeddedEuicc,
    ).copyWith(cardId: 'physical');
    expect(repository.upsertSlot(embeddedSlot), isA<Err<void>>());
    expect((repository.load() as Ok<AssetInventory>).value.slots, isEmpty);
  });

  test('建立内置 eUICC 失败时卡槽、卡片和 EID 全部回滚', () {
    repository.upsertDevice(device('d1'));
    repository.upsertCard(
      RemovableEuiccCard(
        id: 'existing-card',
        name: '已有卡',
        createdAt: created,
        updatedAt: created,
      ),
    );
    repository.upsertEid(
      Euicc(
        id: 'existing-eid',
        cardId: 'existing-card',
        value: '89000000000000000000000000000001',
        createdAt: created,
        updatedAt: created,
      ),
    );
    final card = EmbeddedEuiccCard(
      id: 'embedded-card',
      name: '内置 eUICC',
      embeddedDeviceId: 'd1',
      createdAt: created,
      updatedAt: created,
    );
    final result = repository.createEmbeddedEuicc(
      card: card,
      eid: Euicc(
        id: 'new-eid',
        cardId: card.id,
        value: '89000000000000000000000000000001',
        createdAt: created,
        updatedAt: created,
      ),
      slot: slot('embedded-slot', 'd1', 0, kind: SimSlotKind.embeddedEuicc),
      eventId: 'event',
      occurredAt: created,
    );
    expect(result, isA<Err<void>>());
    final inventory = (repository.load() as Ok<AssetInventory>).value;
    expect(inventory.slots, isEmpty);
    expect(inventory.cardById('embedded-card'), isNull);
    expect(inventory.eids, hasLength(1));
  });

  test('换卡在单一事务中完成并记录两个事件', () {
    repository.upsertDevice(device('d1'));
    repository.upsertSlot(slot('s1', 'd1', 0));
    for (final id in ['c1', 'c2']) {
      repository.upsertCard(
        PhysicalSimCard(
          id: id,
          name: id,
          physicalIccid: '890100000000000000${id == 'c1' ? '1' : '2'}',
          createdAt: created,
          updatedAt: created,
        ),
      );
    }
    repository.moveCard(
      cardId: 'c1',
      toSlotId: 's1',
      eventId: 'initial',
      occurredAt: created,
    );
    final result = repository.replaceCardInSlot(
      slotId: 's1',
      cardId: 'c2',
      storedEventId: 'stored',
      movedEventId: 'moved',
      occurredAt: created.add(const Duration(minutes: 1)),
    );
    expect(result, isA<Ok<void>>());
    final inventory = (repository.load() as Ok<AssetInventory>).value;
    expect(inventory.slots.single.cardId, 'c2');
    expect(inventory.events.whereType<CardStored>(), hasLength(1));
    expect(inventory.events.whereType<CardMoved>(), hasLength(2));
  });

  test('Profile 可迁移到其他 EID 并保留历史', () {
    repository.upsertDevice(device('d1'));
    repository.upsertCard(
      RemovableEuiccCard(
        id: 'c1',
        name: 'eUICC 1',
        createdAt: created,
        updatedAt: created,
      ),
    );
    repository.upsertCard(
      RemovableEuiccCard(
        id: 'c2',
        name: 'eUICC 2',
        createdAt: created,
        updatedAt: created,
      ),
    );
    for (final pair in [('e1', 'c1'), ('e2', 'c2')]) {
      repository.upsertEid(
        Euicc(
          id: pair.$1,
          cardId: pair.$2,
          value: pair.$1 == 'e1'
              ? '89000000000000000000000000000001'
              : '89000000000000000000000000000002',
          createdAt: created,
          updatedAt: created,
        ),
      );
    }
    repository.upsertProfile(
      EsimProfile(
        id: 'p1',
        eidId: 'e1',
        iccid: '8901000000000000001',
        createdAt: created,
        updatedAt: created,
      ),
    );

    expect(
      repository.moveProfile(
        profileId: 'p1',
        toEidId: 'e2',
        eventId: 'ev1',
        occurredAt: created,
      ),
      isA<Ok<void>>(),
    );
    final inventory = (repository.load() as Ok<AssetInventory>).value;
    expect(inventory.profiles.single.eidId, 'e2');
    expect(inventory.events.single, isA<ProfileMoved>());
  });
}
