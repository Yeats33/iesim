import '../model/activity_record.dart';
import '../model/assets.dart';
import '../model/subscription.dart';
import 'sync_snapshot.dart';

class SyncSnapshotMerger {
  const SyncSnapshotMerger();

  SyncMergeResult merge({
    required SyncSnapshot local,
    required SyncSnapshot remote,
    required DateTime mergedAtUtc,
    DateTime? lastSyncedAtUtc,
  }) {
    final conflicts = <SyncConflict>[];
    final subscriptions = _mergeRecords<Subscription>(
      local: local.subscriptions,
      remote: remote.subscriptions,
      idOf: (item) => item.id,
      updatedAtOf: (item) => item.updatedAt,
      entityType: SyncEntityType.subscription,
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
    final activities = _mergeRecords<ActivityRecord>(
      local: local.activityRecords,
      remote: remote.activityRecords,
      idOf: (item) => item.id,
      updatedAtOf: (item) => item.updatedAt,
      entityType: SyncEntityType.activityRecord,
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
    final devices = _mergeRecords<DeviceAsset>(
      local: local.assets.devices,
      remote: remote.assets.devices,
      idOf: (item) => item.id,
      updatedAtOf: (item) => item.updatedAt,
      entityType: SyncEntityType.device,
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
    final slots = _mergeRecords<SimSlot>(
      local: local.assets.slots,
      remote: remote.assets.slots,
      idOf: (item) => item.id,
      updatedAtOf: (item) => item.updatedAt,
      entityType: SyncEntityType.slot,
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
    final cards = _mergeRecords<SimCard>(
      local: local.assets.cards,
      remote: remote.assets.cards,
      idOf: (item) => item.id,
      updatedAtOf: (item) => item.updatedAt,
      entityType: SyncEntityType.card,
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
    final eids = _mergeRecords<Euicc>(
      local: local.assets.eids,
      remote: remote.assets.eids,
      idOf: (item) => item.id,
      updatedAtOf: (item) => item.updatedAt,
      entityType: SyncEntityType.eid,
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
    final profiles = _mergeRecords<EsimProfile>(
      local: local.assets.profiles,
      remote: remote.assets.profiles,
      idOf: (item) => item.id,
      updatedAtOf: (item) => item.updatedAt,
      entityType: SyncEntityType.profile,
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
    final assetEvents = _mergeRecords<AssetEvent>(
      local: local.assets.events,
      remote: remote.assets.events,
      idOf: (item) => item.id,
      updatedAtOf: (item) => item.occurredAt,
      entityType: SyncEntityType.assetEvent,
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
    final tombstones = _mergeTombstones(local.tombstones, remote.tombstones);

    _applyTombstones(
      records: subscriptions,
      tombstones: tombstones,
      entityType: SyncEntityType.subscription,
      updatedAtOf: (item) => item.updatedAt,
      localRecords: {for (final item in local.subscriptions) item.id: item},
      remoteRecords: {for (final item in remote.subscriptions) item.id: item},
      localTombstones: _tombstonesOf(local, SyncEntityType.subscription),
      remoteTombstones: _tombstonesOf(remote, SyncEntityType.subscription),
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
    _applyTombstones(
      records: activities,
      tombstones: tombstones,
      entityType: SyncEntityType.activityRecord,
      updatedAtOf: (item) => item.updatedAt,
      localRecords: {for (final item in local.activityRecords) item.id: item},
      remoteRecords: {for (final item in remote.activityRecords) item.id: item},
      localTombstones: _tombstonesOf(local, SyncEntityType.activityRecord),
      remoteTombstones: _tombstonesOf(remote, SyncEntityType.activityRecord),
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
    _applyAssetTombstones(
      records: devices,
      localRecords: local.assets.devices,
      remoteRecords: remote.assets.devices,
      tombstones: tombstones,
      type: SyncEntityType.device,
      updatedAtOf: (item) => item.updatedAt,
      local: local,
      remote: remote,
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
    _applyAssetTombstones(
      records: slots,
      localRecords: local.assets.slots,
      remoteRecords: remote.assets.slots,
      tombstones: tombstones,
      type: SyncEntityType.slot,
      updatedAtOf: (item) => item.updatedAt,
      local: local,
      remote: remote,
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
    _applyAssetTombstones(
      records: cards,
      localRecords: local.assets.cards,
      remoteRecords: remote.assets.cards,
      tombstones: tombstones,
      type: SyncEntityType.card,
      updatedAtOf: (item) => item.updatedAt,
      local: local,
      remote: remote,
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
    _applyAssetTombstones(
      records: eids,
      localRecords: local.assets.eids,
      remoteRecords: remote.assets.eids,
      tombstones: tombstones,
      type: SyncEntityType.eid,
      updatedAtOf: (item) => item.updatedAt,
      local: local,
      remote: remote,
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
    _applyAssetTombstones(
      records: profiles,
      localRecords: local.assets.profiles,
      remoteRecords: remote.assets.profiles,
      tombstones: tombstones,
      type: SyncEntityType.profile,
      updatedAtOf: (item) => item.updatedAt,
      local: local,
      remote: remote,
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );

    final subscriptionIds = subscriptions.keys.toSet();
    activities.removeWhere(
      (_, activity) => !subscriptionIds.contains(activity.subscriptionId),
    );
    final deviceIds = devices.keys.toSet();
    cards.removeWhere(
      (_, card) =>
          card is EmbeddedEuiccCard &&
          !deviceIds.contains(card.embeddedDeviceId),
    );
    final cardIds = cards.keys.toSet();
    slots.removeWhere((_, slot) => !deviceIds.contains(slot.deviceId));
    for (final entry in slots.entries.toList()) {
      if (entry.value.cardId != null && !cardIds.contains(entry.value.cardId)) {
        slots[entry.key] = entry.value.copyWith(clearCard: true);
      }
    }
    eids.removeWhere((_, eid) => !cardIds.contains(eid.cardId));
    final eidIds = eids.keys.toSet();
    profiles.removeWhere((_, profile) => !eidIds.contains(profile.eidId));
    for (final entry in profiles.entries.toList()) {
      if (entry.value.subscriptionId != null &&
          !subscriptionIds.contains(entry.value.subscriptionId)) {
        profiles[entry.key] = entry.value.copyWith(clearSubscription: true);
      }
    }
    final retainedTombstones = tombstones.values.toList()
      ..sort((a, b) {
        final type = a.entityType.index.compareTo(b.entityType.index);
        return type != 0 ? type : a.entityId.compareTo(b.entityId);
      });
    final mergedSubscriptions = subscriptions.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final mergedActivities = activities.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final mergedDevices = devices.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final mergedSlots = slots.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final mergedCards = cards.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final mergedEids = eids.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final mergedProfiles = profiles.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final mergedAssetEvents = assetEvents.values.toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    return SyncMergeResult(
      snapshot: SyncSnapshot(
        generatedAtUtc: mergedAtUtc,
        subscriptions: mergedSubscriptions,
        activityRecords: mergedActivities,
        assets: AssetInventory(
          devices: mergedDevices,
          slots: mergedSlots,
          cards: mergedCards,
          eids: mergedEids,
          profiles: mergedProfiles,
          events: mergedAssetEvents,
        ),
        tombstones: retainedTombstones,
      ),
      conflicts: conflicts,
    );
  }

  static Map<String, T> _mergeRecords<T>({
    required List<T> local,
    required List<T> remote,
    required String Function(T item) idOf,
    required DateTime Function(T item) updatedAtOf,
    required SyncEntityType entityType,
    required DateTime? lastSyncedAtUtc,
    required List<SyncConflict> conflicts,
  }) {
    final localById = {for (final item in local) idOf(item): item};
    final remoteById = {for (final item in remote) idOf(item): item};
    final result = <String, T>{};
    for (final id in {...localById.keys, ...remoteById.keys}) {
      final localItem = localById[id];
      final remoteItem = remoteById[id];
      if (localItem == null) {
        result[id] = remoteItem as T;
        continue;
      }
      if (remoteItem == null) {
        result[id] = localItem;
        continue;
      }
      final localAt = updatedAtOf(localItem);
      final remoteAt = updatedAtOf(remoteItem);
      final remoteWins = !localAt.isAfter(remoteAt);
      result[id] = remoteWins ? remoteItem : localItem;
      if (localItem != remoteItem &&
          _bothChanged(localAt, remoteAt, lastSyncedAtUtc)) {
        conflicts.add(
          SyncConflict(
            entityType: entityType,
            entityId: id,
            localUpdatedAtUtc: localAt,
            remoteUpdatedAtUtc: remoteAt,
            winner: remoteWins ? SyncWinner.remote : SyncWinner.local,
          ),
        );
      }
    }
    return result;
  }

  static void _applyAssetTombstones<T>({
    required Map<String, T> records,
    required List<T> localRecords,
    required List<T> remoteRecords,
    required Map<String, SyncTombstone> tombstones,
    required SyncEntityType type,
    required DateTime Function(T item) updatedAtOf,
    required SyncSnapshot local,
    required SyncSnapshot remote,
    required DateTime? lastSyncedAtUtc,
    required List<SyncConflict> conflicts,
  }) {
    String idOf(T item) => switch (item) {
      DeviceAsset() => item.id,
      SimSlot() => item.id,
      SimCard() => item.id,
      Euicc() => item.id,
      EsimProfile() => item.id,
      _ => throw StateError('不支持的资产类型 $T'),
    };
    _applyTombstones(
      records: records,
      tombstones: tombstones,
      entityType: type,
      updatedAtOf: updatedAtOf,
      localRecords: {for (final item in localRecords) idOf(item): item},
      remoteRecords: {for (final item in remoteRecords) idOf(item): item},
      localTombstones: _tombstonesOf(local, type),
      remoteTombstones: _tombstonesOf(remote, type),
      lastSyncedAtUtc: lastSyncedAtUtc,
      conflicts: conflicts,
    );
  }

  static Map<String, SyncTombstone> _mergeTombstones(
    List<SyncTombstone> local,
    List<SyncTombstone> remote,
  ) {
    final result = <String, SyncTombstone>{};
    for (final tombstone in [...local, ...remote]) {
      final key = _tombstoneKey(tombstone.entityType, tombstone.entityId);
      final existing = result[key];
      if (existing == null ||
          tombstone.deletedAtUtc.isAfter(existing.deletedAtUtc)) {
        result[key] = tombstone;
      }
    }
    return result;
  }

  static void _applyTombstones<T>({
    required Map<String, T> records,
    required Map<String, SyncTombstone> tombstones,
    required SyncEntityType entityType,
    required DateTime Function(T item) updatedAtOf,
    required Map<String, T> localRecords,
    required Map<String, T> remoteRecords,
    required Map<String, SyncTombstone> localTombstones,
    required Map<String, SyncTombstone> remoteTombstones,
    required DateTime? lastSyncedAtUtc,
    required List<SyncConflict> conflicts,
  }) {
    for (final id in records.keys.toList()) {
      final key = _tombstoneKey(entityType, id);
      final tombstone = tombstones[key];
      if (tombstone == null) continue;
      final recordAt = updatedAtOf(records[id] as T);
      final deletionWins = !recordAt.isAfter(tombstone.deletedAtUtc);
      if (deletionWins) {
        records.remove(id);
      } else {
        tombstones.remove(key);
      }

      final localRecord = localRecords[id];
      final remoteRecord = remoteRecords[id];
      final localTombstone = localTombstones[id];
      final remoteTombstone = remoteTombstones[id];
      DateTime? localAt;
      DateTime? remoteAt;
      if (localRecord != null && remoteTombstone != null) {
        localAt = updatedAtOf(localRecord);
        remoteAt = remoteTombstone.deletedAtUtc;
      } else if (localTombstone != null && remoteRecord != null) {
        localAt = localTombstone.deletedAtUtc;
        remoteAt = updatedAtOf(remoteRecord);
      }
      if (localAt != null &&
          remoteAt != null &&
          _bothChanged(localAt, remoteAt, lastSyncedAtUtc)) {
        conflicts.add(
          SyncConflict(
            entityType: entityType,
            entityId: id,
            localUpdatedAtUtc: localAt,
            remoteUpdatedAtUtc: remoteAt,
            winner: deletionWins
                ? SyncWinner.deletion
                : (recordAt == localAt ? SyncWinner.local : SyncWinner.remote),
          ),
        );
      }
    }
  }

  static Map<String, SyncTombstone> _tombstonesOf(
    SyncSnapshot snapshot,
    SyncEntityType type,
  ) => {
    for (final item in snapshot.tombstones)
      if (item.entityType == type) item.entityId: item,
  };

  static bool _bothChanged(
    DateTime localAt,
    DateTime remoteAt,
    DateTime? lastSyncedAtUtc,
  ) =>
      lastSyncedAtUtc == null ||
      (localAt.isAfter(lastSyncedAtUtc) && remoteAt.isAfter(lastSyncedAtUtc));

  static String _tombstoneKey(SyncEntityType type, String id) =>
      '${type.name}:$id';
}
