import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  test('删除订阅为订阅与所有子动作写入墓碑', () {
    final db = openIesimStore(':memory:');
    addTearDown(db.close);
    final subscription = _subscription('s1', DateTime.utc(2026, 8, 1));
    expect(SubscriptionRepository(db).upsert(subscription), isA<Ok<void>>());
    final assets = AssetRepository(db);
    final assetTime = DateTime.utc(2026, 8, 1);
    expect(
      assets.upsertCard(
        RemovableEuiccCard(
          id: 'c1',
          name: 'eUICC',
          createdAt: assetTime,
          updatedAt: assetTime,
        ),
      ),
      isA<Ok<void>>(),
    );
    expect(
      assets.upsertEid(
        Euicc(
          id: 'e1',
          cardId: 'c1',
          value: '8900001',
          createdAt: assetTime,
          updatedAt: assetTime,
        ),
      ),
      isA<Ok<void>>(),
    );
    expect(
      assets.upsertProfile(
        EsimProfile(
          id: 'p1',
          eidId: 'e1',
          iccid: subscription.iccid,
          subscriptionId: subscription.id,
          createdAt: assetTime,
          updatedAt: assetTime,
        ),
      ),
      isA<Ok<void>>(),
    );
    expect(
      ActivityRecordRepository(db).append(
        ActivityRecord(
          id: 'a1',
          subscriptionId: 's1',
          type: ActivityType.call,
          occurredAt: DateTime.utc(2026, 8, 2),
        ),
      ),
      isA<Ok<void>>(),
    );
    expect(
      SubscriptionDeletionService(
        db,
      ).delete(subscriptionId: 's1', nowUtc: DateTime.utc(2026, 8, 8)),
      isA<Ok<void>>(),
    );
    final snapshot =
        (SyncStore(db).loadSnapshot(generatedAtUtc: DateTime.utc(2026, 8, 8))
                as Ok<SyncSnapshot>)
            .value;
    expect(snapshot.subscriptions, isEmpty);
    expect(snapshot.activityRecords, isEmpty);
    expect(snapshot.assets.profiles, isEmpty);
    expect(
      snapshot.tombstones.map((item) => item.entityType),
      containsAll([
        SyncEntityType.subscription,
        SyncEntityType.activityRecord,
        SyncEntityType.profile,
      ]),
    );
  });

  test('墓碑满 90 天后清理，较新的保留', () {
    final db = openIesimStore(':memory:');
    addTearDown(db.close);
    db.execute('''INSERT INTO sync_tombstones VALUES
('subscription', 'old', '2026-01-01T00:00:00.000Z'),
('subscription', 'new', '2026-07-20T00:00:00.000Z')''');
    final result = SyncStore(
      db,
    ).removeExpiredTombstones(nowUtc: DateTime.utc(2026, 8, 8));
    expect((result as Ok<int>).value, 1);
    expect(
      db.select('SELECT entity_id FROM sync_tombstones').single['entity_id'],
      'new',
    );
  });

  test('成功同步可原子替换完整资产图', () {
    final db = openIesimStore(':memory:');
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 8);
    final device = DeviceAsset(
      id: 'd1',
      name: '手机',
      createdAt: now,
      updatedAt: now,
    );
    final card = RemovableEuiccCard(
      id: 'c1',
      name: 'eUICC',
      createdAt: now,
      updatedAt: now,
    );
    final eid = Euicc(
      id: 'e1',
      cardId: card.id,
      value: '8900001',
      createdAt: now,
      updatedAt: now,
    );
    final snapshot = SyncSnapshot(
      generatedAtUtc: now,
      assets: AssetInventory(
        devices: [device],
        slots: [
          SimSlot(
            id: 'slot1',
            deviceId: device.id,
            label: 'SIM 1',
            kind: SimSlotKind.physical,
            position: 0,
            cardId: card.id,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        cards: [card],
        eids: [eid],
        profiles: [
          EsimProfile(
            id: 'p1',
            eidId: eid.id,
            iccid: '8986001',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );
    final store = SyncStore(db);
    expect(
      store.commitSuccessfulSync(
        snapshot: snapshot,
        etag: 'etag-1',
        syncedAtUtc: now,
      ),
      isA<Ok<void>>(),
    );
    final restored =
        (store.loadSnapshot(generatedAtUtc: now) as Ok<SyncSnapshot>).value;
    expect(restored.assets.devices, [device]);
    expect(restored.assets.slots.single.cardId, card.id);
    expect(restored.assets.profiles.single.eidId, eid.id);
  });
}

Subscription _subscription(String id, DateTime updatedAt) => Subscription(
  id: id,
  number: PhoneNumber('10086'),
  plan: Plan(),
  keepAlive: KeepAlive.notRequired(),
  timeZoneId: 'UTC',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: updatedAt,
);
