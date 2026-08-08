import 'dart:convert';

import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(initializeIesimTimeZones);

  test('整批写入订阅与动作记录且重复执行幂等', () {
    final database = openIesimStore(':memory:');
    addTearDown(database.close);
    final report = _report([_subscription('a')], [_activity('act-a', 'a')]);
    final store = SimHubImportStore(database);

    expect(store.apply(report), isA<Ok<SimHubImportSummary>>());
    expect(store.apply(report), isA<Ok<SimHubImportSummary>>());

    final subscriptions = SubscriptionRepository(database).listAll();
    final activities = ActivityRecordRepository(database).listAll();
    expect((subscriptions as Ok).value, hasLength(1));
    expect((activities as Ok).value, hasLength(1));
  });

  test('开发者清空会删除业务、提醒与同步状态', () {
    final database = openIesimStore(':memory:');
    addTearDown(database.close);
    final store = SimHubImportStore(database);
    expect(
      store.apply(_report([_subscription('a')], [_activity('act-a', 'a')])),
      isA<Ok<SimHubImportSummary>>(),
    );
    database.execute(
      "INSERT INTO sync_tombstones (entity_type, entity_id, deleted_at) "
      "VALUES ('subscription', 'old', '2026-08-08T00:00:00.000Z')",
    );
    database.execute(
      "UPDATE sync_state SET etag = 'etag', "
      "last_synced_at = '2026-08-08T00:00:00.000Z' WHERE singleton = 1",
    );

    expect(store.clearAll(), isA<Ok<void>>());

    expect((SubscriptionRepository(database).listAll() as Ok).value, isEmpty);
    expect((ActivityRecordRepository(database).listAll() as Ok).value, isEmpty);
    expect(database.select('SELECT * FROM scheduled_reminders'), isEmpty);
    expect(database.select('SELECT * FROM sync_tombstones'), isEmpty);
    final syncState = database.select('SELECT * FROM sync_state').single;
    expect(syncState['etag'], isNull);
    expect(syncState['last_synced_at'], isNull);
  });

  test('开发者清空可分别保留设备资产或 Profile 业务数据', () {
    final profileDatabase = openIesimStore(':memory:');
    addTearDown(profileDatabase.close);
    final profileStore = SimHubImportStore(profileDatabase);
    expect(profileStore.apply(_deviceReport()), isA<Ok>());

    expect(
      profileStore.clearSelected(
        clearProfiles: true,
        clearAssets: false,
        resetSyncState: true,
      ),
      isA<Ok<void>>(),
    );
    expect(
      (SubscriptionRepository(profileDatabase).listAll() as Ok).value,
      isEmpty,
    );
    final retainedAssets =
        (AssetRepository(profileDatabase).load() as Ok<AssetInventory>).value;
    expect(retainedAssets.devices, hasLength(1));
    expect(retainedAssets.cards, hasLength(1));
    expect(retainedAssets.profiles, isEmpty);

    final assetDatabase = openIesimStore(':memory:');
    addTearDown(assetDatabase.close);
    final assetStore = SimHubImportStore(assetDatabase);
    expect(assetStore.apply(_deviceReport()), isA<Ok>());

    expect(
      assetStore.clearSelected(
        clearProfiles: false,
        clearAssets: true,
        resetSyncState: true,
      ),
      isA<Ok<void>>(),
    );
    expect(
      (SubscriptionRepository(assetDatabase).listAll() as Ok).value,
      hasLength(1),
    );
    final clearedAssets =
        (AssetRepository(assetDatabase).load() as Ok<AssetInventory>).value;
    expect(clearedAssets.devices, isEmpty);
    expect(clearedAssets.cards, isEmpty);
    expect(clearedAssets.profiles, isEmpty);
  });

  test('后续记录约束失败时回滚本批已经写入的记录', () {
    final database = openIesimStore(':memory:');
    addTearDown(database.close);
    final subscriptions = SubscriptionRepository(database);
    expect(
      subscriptions.upsert(_subscription('existing', iccid: 'duplicate')),
      isA<Ok<void>>(),
    );
    final report = _report([
      _subscription('new-ok'),
      _subscription('new-conflict', iccid: 'duplicate'),
    ]);

    expect(SimHubImportStore(database).apply(report), isA<Err>());

    final result = subscriptions.listAll() as Ok<List<Subscription>>;
    expect(result.value.map((item) => item.id), ['existing']);
  });

  test('SimHub v5 订阅与设备资产在同一事务中写入', () {
    final database = openIesimStore(':memory:');
    addTearDown(database.close);
    final report = SimHubCodec().decode(
      jsonEncode({
        'formatVersion': 5,
        'esimCards': [
          {
            'id': 'sub-a',
            'phoneNumber': '10001',
            'deviceID': 'device-a',
            'eid': '89000000000000000000000000000001',
          },
        ],
        'devices': [
          {
            'id': 'device-a',
            'name': '测试设备',
            'deviceTypeRaw': 'phone',
            'simCapabilityRaw': 'multiESIM',
            'eid': '89000000000000000000000000000001',
          },
        ],
      }),
      defaultTimeZoneId: 'UTC',
    );

    final result = SimHubImportStore(database).apply(report);
    expect(result, isA<Ok<SimHubImportSummary>>());
    final summary = (result as Ok<SimHubImportSummary>).value;
    expect(summary.devicesWritten, 1);
    expect(summary.cardsWritten, 1);
    expect(summary.profilesWritten, 1);
    final assets =
        (AssetRepository(database).load() as Ok<AssetInventory>).value;
    expect(assets.devices, hasLength(1));
    expect(assets.profiles.single.subscriptionId, 'sub-a');
  });

  test('Nekoko 报告可复用原子导入事务', () {
    final db = openIesimStore(':memory:');
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 8);
    final subscription = Subscription(
      id: 'nekoko-sub',
      iccid: '8986001',
      number: PhoneNumber('+4912345'),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'Europe/Berlin',
      createdAt: now,
      updatedAt: now,
    );
    final card = RemovableEuiccCard(
      id: 'nekoko-card',
      name: 'eUICC',
      createdAt: now,
      updatedAt: now,
    );
    final eid = Euicc(
      id: 'nekoko-eid',
      cardId: card.id,
      value: '8900001',
      createdAt: now,
      updatedAt: now,
    );
    final report = NekokoImportReport(
      sourceProfileCount: 1,
      subscriptions: [subscription],
      assets: AssetInventory(
        cards: [card],
        eids: [eid],
        profiles: [
          EsimProfile(
            id: 'nekoko-profile',
            eidId: eid.id,
            iccid: subscription.iccid,
            subscriptionId: subscription.id,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
      issues: const [],
    );

    expect(SimHubImportStore(db).applyNekoko(report), isA<Ok>());
    expect((SubscriptionRepository(db).listAll() as Ok).value, hasLength(1));
    final assets = (AssetRepository(db).load() as Ok<AssetInventory>).value;
    expect(assets.cards, hasLength(1));
    expect(assets.profiles.single.subscriptionId, subscription.id);
  });
}

SimHubImportReport _report(
  List<Subscription> subscriptions, [
  List<ActivityRecord> activities = const [],
]) => SimHubImportReport(
  subscriptions: subscriptions,
  activityRecords: activities,
  issues: const [],
  sourceRecordCount: subscriptions.length,
);

Subscription _subscription(String id, {String? iccid}) => Subscription(
  id: id,
  iccid: iccid,
  number: PhoneNumber('10086$id'.replaceAll(RegExp('[^0-9]'), '')),
  plan: Plan(),
  keepAlive: KeepAlive(required: true),
  timeZoneId: 'UTC',
  createdAt: DateTime.utc(2026, 8, 8),
  updatedAt: DateTime.utc(2026, 8, 8),
);

ActivityRecord _activity(String id, String subscriptionId) => ActivityRecord(
  id: id,
  subscriptionId: subscriptionId,
  type: ActivityType.topUp,
  occurredAt: DateTime.utc(2026, 8, 8),
);

SimHubImportReport _deviceReport() => SimHubCodec().decode(
  jsonEncode({
    'formatVersion': 5,
    'esimCards': [
      {
        'id': 'selective-subscription',
        'phoneNumber': '10086',
        'iccid': '8986000000000000001',
        'deviceID': 'selective-device',
        'createdAt': '2026-08-08T00:00:00Z',
      },
    ],
    'dormantCards': [],
    'devices': [
      {
        'id': 'selective-device',
        'name': '测试设备',
        'deviceTypeRaw': 'phone',
        'simCapabilityRaw': 'physicalOnly',
        'createdAt': '2026-08-08T00:00:00Z',
      },
    ],
  }),
  defaultTimeZoneId: 'UTC',
);
