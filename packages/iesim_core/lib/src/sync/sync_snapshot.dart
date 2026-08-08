import '../model/activity_record.dart';
import '../model/assets.dart';
import '../model/subscription.dart';

enum SyncEntityType {
  subscription,
  activityRecord,
  device,
  slot,
  card,
  eid,
  profile,
  assetEvent,
}

class SyncTombstone {
  const SyncTombstone({
    required this.entityType,
    required this.entityId,
    required this.deletedAtUtc,
  });

  final SyncEntityType entityType;
  final String entityId;
  final DateTime deletedAtUtc;

  @override
  bool operator ==(Object other) =>
      other is SyncTombstone &&
      other.entityType == entityType &&
      other.entityId == entityId &&
      other.deletedAtUtc == deletedAtUtc;

  @override
  int get hashCode => Object.hash(entityType, entityId, deletedAtUtc);
}

class SyncSnapshot {
  SyncSnapshot({
    this.schemaVersion = currentSchemaVersion,
    required this.generatedAtUtc,
    Iterable<Subscription> subscriptions = const [],
    Iterable<ActivityRecord> activityRecords = const [],
    AssetInventory? assets,
    Iterable<SyncTombstone> tombstones = const [],
  }) : subscriptions = List.unmodifiable(subscriptions),
       activityRecords = List.unmodifiable(activityRecords),
       assets = assets ?? AssetInventory(),
       tombstones = List.unmodifiable(tombstones) {
    if (!generatedAtUtc.isUtc) {
      throw ArgumentError.value(generatedAtUtc, 'generatedAtUtc', '必须为 UTC');
    }
  }

  static const currentSchemaVersion = 1;

  final int schemaVersion;
  final DateTime generatedAtUtc;
  final List<Subscription> subscriptions;
  final List<ActivityRecord> activityRecords;
  final AssetInventory assets;
  final List<SyncTombstone> tombstones;
}

enum SyncWinner { local, remote, deletion }

class SyncConflict {
  const SyncConflict({
    required this.entityType,
    required this.entityId,
    required this.localUpdatedAtUtc,
    required this.remoteUpdatedAtUtc,
    required this.winner,
  });

  final SyncEntityType entityType;
  final String entityId;
  final DateTime localUpdatedAtUtc;
  final DateTime remoteUpdatedAtUtc;
  final SyncWinner winner;
}

class SyncMergeResult {
  SyncMergeResult({
    required this.snapshot,
    Iterable<SyncConflict> conflicts = const [],
  }) : conflicts = List.unmodifiable(conflicts);

  final SyncSnapshot snapshot;
  final List<SyncConflict> conflicts;
}
