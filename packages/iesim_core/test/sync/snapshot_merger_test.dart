import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(initializeIesimTimeZones);

  test('两端修改不同订阅时逐记录保留两边较新内容', () {
    final base = DateTime.utc(2026, 8, 1);
    final local = _snapshot([
      _sub('a', '本地 A', DateTime.utc(2026, 8, 3)),
      _sub('b', '旧 B', base),
    ]);
    final remote = _snapshot([
      _sub('a', '旧 A', base),
      _sub('b', '远端 B', DateTime.utc(2026, 8, 4)),
    ]);
    final result = const SyncSnapshotMerger().merge(
      local: local,
      remote: remote,
      mergedAtUtc: DateTime.utc(2026, 8, 8),
      lastSyncedAtUtc: base,
    );
    expect(
      {
        for (final item in result.snapshot.subscriptions)
          item.id: item.operator,
      },
      {'a': '本地 A', 'b': '远端 B'},
    );
    expect(result.conflicts, isEmpty);
  });

  test('同一记录两端都修改时取 updatedAt 较新者并记录冲突', () {
    final result = const SyncSnapshotMerger().merge(
      local: _snapshot([_sub('a', '本地', DateTime.utc(2026, 8, 5))]),
      remote: _snapshot([_sub('a', '远端', DateTime.utc(2026, 8, 6))]),
      mergedAtUtc: DateTime.utc(2026, 8, 8),
      lastSyncedAtUtc: DateTime.utc(2026, 8, 1),
    );
    expect(result.snapshot.subscriptions.single.operator, '远端');
    expect(result.conflicts.single.winner, SyncWinner.remote);
  });

  test('新墓碑压过旧记录，较新的记录可压过旧墓碑', () {
    final remoteRecord = _sub('deleted', '旧', DateTime.utc(2026, 8, 2));
    final deleted = const SyncSnapshotMerger().merge(
      local: SyncSnapshot(
        generatedAtUtc: DateTime.utc(2026, 8, 7),
        tombstones: [
          SyncTombstone(
            entityType: SyncEntityType.subscription,
            entityId: 'deleted',
            deletedAtUtc: DateTime.utc(2026, 8, 5),
          ),
        ],
      ),
      remote: _snapshot([remoteRecord]),
      mergedAtUtc: DateTime.utc(2026, 8, 8),
      lastSyncedAtUtc: DateTime.utc(2026, 8, 1),
    );
    expect(deleted.snapshot.subscriptions, isEmpty);
    expect(deleted.snapshot.tombstones, hasLength(1));
    expect(deleted.conflicts.single.winner, SyncWinner.deletion);

    final revived = const SyncSnapshotMerger().merge(
      local: SyncSnapshot(
        generatedAtUtc: DateTime.utc(2026, 8, 7),
        tombstones: [
          SyncTombstone(
            entityType: SyncEntityType.subscription,
            entityId: 'deleted',
            deletedAtUtc: DateTime.utc(2026, 8, 5),
          ),
        ],
      ),
      remote: _snapshot([_sub('deleted', '新', DateTime.utc(2026, 8, 6))]),
      mergedAtUtc: DateTime.utc(2026, 8, 8),
    );
    expect(revived.snapshot.subscriptions.single.operator, '新');
    expect(revived.snapshot.tombstones, isEmpty);
  });

  test('所属订阅已删除时不保留孤儿动作记录', () {
    final result = const SyncSnapshotMerger().merge(
      local: _snapshot(const []),
      remote: SyncSnapshot(
        generatedAtUtc: DateTime.utc(2026, 8, 7),
        activityRecords: [
          ActivityRecord(
            id: 'a',
            subscriptionId: 'missing',
            type: ActivityType.call,
            occurredAt: DateTime.utc(2026, 8, 7),
          ),
        ],
      ),
      mergedAtUtc: DateTime.utc(2026, 8, 8),
    );
    expect(result.snapshot.activityRecords, isEmpty);
  });

  test('资产墓碑删除卡片并清空卡槽引用', () {
    final now = DateTime.utc(2026, 8, 7);
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
    final slot = SimSlot(
      id: 'slot1',
      deviceId: 'd1',
      label: 'SIM 1',
      kind: SimSlotKind.physical,
      position: 0,
      cardId: 'c1',
      createdAt: now,
      updatedAt: now,
    );
    final result = const SyncSnapshotMerger().merge(
      local: SyncSnapshot(
        generatedAtUtc: DateTime.utc(2026, 8, 8),
        assets: AssetInventory(devices: [device], slots: [slot]),
        tombstones: [
          SyncTombstone(
            entityType: SyncEntityType.card,
            entityId: 'c1',
            deletedAtUtc: DateTime.utc(2026, 8, 8),
          ),
        ],
      ),
      remote: SyncSnapshot(
        generatedAtUtc: now,
        assets: AssetInventory(devices: [device], slots: [slot], cards: [card]),
      ),
      mergedAtUtc: DateTime.utc(2026, 8, 8),
    );
    expect(result.snapshot.assets.cards, isEmpty);
    expect(result.snapshot.assets.slots.single.cardId, isNull);
  });
}

SyncSnapshot _snapshot(List<Subscription> subscriptions) => SyncSnapshot(
  generatedAtUtc: DateTime.utc(2026, 8, 7),
  subscriptions: subscriptions,
);

Subscription _sub(String id, String operator, DateTime updatedAt) =>
    Subscription(
      id: id,
      number: PhoneNumber('1${id.codeUnitAt(0)}'),
      operator: operator,
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'UTC',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: updatedAt,
    );
