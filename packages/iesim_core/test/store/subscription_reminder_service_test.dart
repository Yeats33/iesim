import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(initializeIesimTimeZones);

  test('订阅与四档提醒在同一事务中写入', () {
    final db = openIesimStore(':memory:');
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 1);
    final result = SubscriptionReminderService(db).upsert(
      subscription: _subscription(
        id: 's1',
        iccid: '8901',
        expiry: DateTime.utc(2026, 8, 20),
        updatedAt: now,
      ),
      clock: FixedClock(now),
    );
    expect(result, isA<Ok<void>>());
    expect(db.select('SELECT * FROM subscriptions'), hasLength(1));
    final reminders = db.select(
      'SELECT kind, slot FROM scheduled_reminders ORDER BY fire_at',
    );
    expect(reminders, hasLength(4));
    expect(reminders.map((row) => row['kind']).toSet(), {'planExpiry'});
  });

  test('订阅写入失败时不破坏原提醒排程', () {
    final db = openIesimStore(':memory:');
    addTearDown(db.close);
    final service = SubscriptionReminderService(db);
    final now = DateTime.utc(2026, 8, 1);
    expect(
      service.upsert(
        subscription: _subscription(
          id: 's1',
          iccid: 'same',
          expiry: DateTime.utc(2026, 8, 20),
          updatedAt: now,
        ),
        clock: FixedClock(now),
      ),
      isA<Ok<void>>(),
    );
    final keysBefore = db
        .select('SELECT stable_key FROM scheduled_reminders')
        .map((row) => row['stable_key'])
        .toList();
    final failed = service.upsert(
      subscription: _subscription(
        id: 's2',
        iccid: 'same',
        expiry: DateTime.utc(2026, 9, 20),
        updatedAt: now,
      ),
      clock: FixedClock(now),
    );
    expect(failed, isA<Err<void>>());
    expect(db.select('SELECT * FROM subscriptions'), hasLength(1));
    expect(
      db
          .select('SELECT stable_key FROM scheduled_reminders')
          .map((row) => row['stable_key']),
      keysBefore,
    );
  });

  test('业务 Profile 与 EID 归属原子写入，更换 EID 记录移动', () {
    final db = openIesimStore(':memory:');
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 1);
    final assets = AssetRepository(db);
    final card = RemovableEuiccCard(
      id: 'card-1',
      name: '测试 eUICC',
      createdAt: now,
      updatedAt: now,
    );
    final eid1 = Euicc(
      id: 'eid-1',
      cardId: card.id,
      value: '89000000000000000000000000000001',
      createdAt: now,
      updatedAt: now,
    );
    final eid2 = Euicc(
      id: 'eid-2',
      cardId: card.id,
      value: '89000000000000000000000000000002',
      createdAt: now,
      updatedAt: now,
    );
    expect(assets.upsertCard(card), isA<Ok<void>>());
    expect(assets.upsertEid(eid1), isA<Ok<void>>());
    expect(assets.upsertEid(eid2), isA<Ok<void>>());

    final subscription = _subscription(
      id: 's1',
      iccid: '8901',
      expiry: DateTime.utc(2026, 8, 20),
      updatedAt: now,
    );
    final profile = EsimProfile(
      id: 'profile-1',
      eidId: eid1.id,
      iccid: subscription.iccid,
      subscriptionId: subscription.id,
      createdAt: now,
      updatedAt: now,
    );
    final service = SubscriptionReminderService(db);
    expect(
      service.upsert(
        subscription: subscription,
        clock: FixedClock(now),
        assetProfile: profile,
        movementEventId: 'unused-for-new-profile',
      ),
      isA<Ok<void>>(),
    );

    final movedAt = now.add(const Duration(hours: 1));
    expect(
      service.upsert(
        subscription: subscription.copyWith(updatedAt: movedAt),
        clock: FixedClock(movedAt),
        assetProfile: profile.copyWith(eidId: eid2.id, updatedAt: movedAt),
        movementEventId: 'profile-move-1',
      ),
      isA<Ok<void>>(),
    );
    final inventory = (assets.load() as Ok<AssetInventory>).value;
    expect(inventory.profiles.single.eidId, eid2.id);
    expect(inventory.profiles.single.subscriptionId, subscription.id);
    expect(inventory.events, hasLength(1));
    expect(inventory.events.single, isA<ProfileMoved>());
  });

  test('EID 归属写入失败时回滚业务 Profile 与提醒', () {
    final db = openIesimStore(':memory:');
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 1);
    final subscription = _subscription(
      id: 's1',
      iccid: '8901',
      expiry: DateTime.utc(2026, 8, 20),
      updatedAt: now,
    );
    final result = SubscriptionReminderService(db).upsert(
      subscription: subscription,
      clock: FixedClock(now),
      assetProfile: EsimProfile(
        id: 'profile-1',
        eidId: 'missing-eid',
        iccid: subscription.iccid,
        subscriptionId: subscription.id,
        createdAt: now,
        updatedAt: now,
      ),
      movementEventId: 'unused-for-new-profile',
    );

    expect(result, isA<Err<void>>());
    expect(db.select('SELECT * FROM subscriptions'), isEmpty);
    expect(db.select('SELECT * FROM scheduled_reminders'), isEmpty);
    expect(db.select('SELECT * FROM profiles'), isEmpty);
  });
}

Subscription _subscription({
  required String id,
  required String iccid,
  required DateTime expiry,
  required DateTime updatedAt,
}) => Subscription(
  id: id,
  iccid: iccid,
  number: PhoneNumber('10086${id.substring(1)}'),
  plan: Plan(expiryDate: expiry),
  keepAlive: KeepAlive.notRequired(),
  timeZoneId: 'UTC',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: updatedAt,
);
