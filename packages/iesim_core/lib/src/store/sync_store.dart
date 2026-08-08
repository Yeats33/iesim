import 'package:sqlite3/sqlite3.dart';

import '../result.dart';
import '../sync/sync_snapshot.dart';
import '../time/clock.dart';
import 'activity_record_repository.dart';
import 'asset_repository.dart';
import 'subscription_repository.dart';
import 'subscription_reminder_service.dart';

class SyncState {
  const SyncState({this.etag, this.lastSyncedAtUtc});

  final String? etag;
  final DateTime? lastSyncedAtUtc;
}

class SyncConflictLog {
  const SyncConflictLog({
    required this.id,
    required this.conflict,
    required this.recordedAtUtc,
  });

  final int id;
  final SyncConflict conflict;
  final DateTime recordedAtUtc;
}

class SyncStore {
  SyncStore(this._db)
    : _subscriptions = SubscriptionRepository(_db),
      _activities = ActivityRecordRepository(_db),
      _assets = AssetRepository(_db);

  final Database _db;
  final SubscriptionRepository _subscriptions;
  final ActivityRecordRepository _activities;
  final AssetRepository _assets;

  Result<SyncSnapshot> loadSnapshot({required DateTime generatedAtUtc}) {
    try {
      final subscriptions = _subscriptions.listAll();
      final activities = _activities.listAll();
      final assets = _assets.load();
      if (subscriptions case Err(failure: final failure)) return Err(failure);
      if (activities case Err(failure: final failure)) return Err(failure);
      if (assets case Err(failure: final failure)) return Err(failure);
      final rows = _db.select(
        'SELECT entity_type, entity_id, deleted_at FROM sync_tombstones',
      );
      return Ok(
        SyncSnapshot(
          generatedAtUtc: generatedAtUtc,
          subscriptions: (subscriptions as Ok).value,
          activityRecords: (activities as Ok).value,
          assets: (assets as Ok).value,
          tombstones: [
            for (final row in rows)
              SyncTombstone(
                entityType: SyncEntityType.values.byName(
                  row['entity_type'] as String,
                ),
                entityId: row['entity_id'] as String,
                deletedAtUtc: DateTime.parse(row['deleted_at'] as String),
              ),
          ],
        ),
      );
    } on SqliteException catch (error) {
      return Err(StoreError(error.message));
    } catch (error) {
      return Err(StoreError(error.toString()));
    }
  }

  Result<SyncState> readState() {
    try {
      final row = _db
          .select(
            'SELECT etag, last_synced_at FROM sync_state WHERE singleton = 1',
          )
          .single;
      return Ok(
        SyncState(
          etag: row['etag'] as String?,
          lastSyncedAtUtc: _parse(row['last_synced_at'] as String?),
        ),
      );
    } on SqliteException catch (error) {
      return Err(StoreError(error.message));
    } catch (error) {
      return Err(StoreError(error.toString()));
    }
  }

  Result<void> resetState() {
    try {
      _db.execute(
        'UPDATE sync_state SET etag = NULL, last_synced_at = NULL '
        'WHERE singleton = 1',
      );
      return const Ok(null);
    } on SqliteException catch (error) {
      return Err(StoreError(error.message));
    } catch (error) {
      return Err(StoreError(error.toString()));
    }
  }

  Result<void> commitSuccessfulSync({
    required SyncSnapshot snapshot,
    required String? etag,
    required DateTime syncedAtUtc,
    Iterable<SyncConflict> conflicts = const [],
  }) {
    try {
      _db.execute('BEGIN IMMEDIATE');
      _db.execute('DELETE FROM asset_events');
      _db.execute('DELETE FROM profiles');
      _db.execute('DELETE FROM eids');
      _db.execute('UPDATE slots SET card_id = NULL');
      _db.execute('DELETE FROM slots');
      _db.execute('DELETE FROM cards');
      _db.execute('DELETE FROM devices');
      _db.execute('DELETE FROM activity_records');
      _db.execute('DELETE FROM subscriptions');
      _db.execute('DELETE FROM sync_tombstones');
      for (final subscription in snapshot.subscriptions) {
        _unwrap(_subscriptions.upsert(subscription));
        replaceReminderSchedulesInTransaction(
          _db,
          subscription: subscription,
          clock: FixedClock(syncedAtUtc),
        );
      }
      for (final activity in snapshot.activityRecords) {
        _unwrap(_activities.upsert(activity));
      }
      for (final device in snapshot.assets.devices) {
        _unwrap(_assets.upsertDevice(device));
      }
      for (final card in snapshot.assets.cards) {
        _unwrap(_assets.upsertCard(card));
      }
      for (final slot in snapshot.assets.slots) {
        _unwrap(_assets.upsertSlot(slot));
      }
      for (final eid in snapshot.assets.eids) {
        _unwrap(_assets.upsertEid(eid));
      }
      for (final profile in snapshot.assets.profiles) {
        _unwrap(_assets.upsertProfile(profile));
      }
      for (final event in snapshot.assets.events) {
        _unwrap(_assets.upsertEvent(event));
      }
      for (final tombstone in snapshot.tombstones) {
        _db.execute(
          '''INSERT INTO sync_tombstones
  (entity_type, entity_id, deleted_at) VALUES (?, ?, ?)''',
          [
            tombstone.entityType.name,
            tombstone.entityId,
            tombstone.deletedAtUtc.toIso8601String(),
          ],
        );
      }
      _db.execute(
        '''UPDATE sync_state SET etag = ?, last_synced_at = ?
WHERE singleton = 1''',
        [etag, syncedAtUtc.toIso8601String()],
      );
      for (final conflict in conflicts) {
        _db.execute(
          '''INSERT INTO sync_conflicts
  (entity_type, entity_id, local_updated_at, remote_updated_at, winner, recorded_at)
VALUES (?, ?, ?, ?, ?, ?)''',
          [
            conflict.entityType.name,
            conflict.entityId,
            conflict.localUpdatedAtUtc.toIso8601String(),
            conflict.remoteUpdatedAtUtc.toIso8601String(),
            conflict.winner.name,
            syncedAtUtc.toIso8601String(),
          ],
        );
      }
      _db.execute('COMMIT');
      return const Ok(null);
    } catch (error) {
      try {
        _db.execute('ROLLBACK');
      } catch (_) {}
      return Err(
        StoreError(error is SqliteException ? error.message : error.toString()),
      );
    }
  }

  Result<List<SyncConflictLog>> listConflicts({int limit = 50}) {
    try {
      final rows = _db.select(
        '''SELECT * FROM sync_conflicts
ORDER BY recorded_at DESC, id DESC LIMIT ?''',
        [limit],
      );
      return Ok([
        for (final row in rows)
          SyncConflictLog(
            id: row['id'] as int,
            conflict: SyncConflict(
              entityType: SyncEntityType.values.byName(
                row['entity_type'] as String,
              ),
              entityId: row['entity_id'] as String,
              localUpdatedAtUtc: DateTime.parse(
                row['local_updated_at'] as String,
              ),
              remoteUpdatedAtUtc: DateTime.parse(
                row['remote_updated_at'] as String,
              ),
              winner: SyncWinner.values.byName(row['winner'] as String),
            ),
            recordedAtUtc: DateTime.parse(row['recorded_at'] as String),
          ),
      ]);
    } on SqliteException catch (error) {
      return Err(StoreError(error.message));
    } catch (error) {
      return Err(StoreError(error.toString()));
    }
  }

  Result<int> removeExpiredTombstones({
    required DateTime nowUtc,
    Duration retention = const Duration(days: 90),
  }) {
    try {
      final cutoff = nowUtc.subtract(retention).toIso8601String();
      _db.execute('DELETE FROM sync_tombstones WHERE deleted_at < ?', [cutoff]);
      return Ok(_db.updatedRows);
    } on SqliteException catch (error) {
      return Err(StoreError(error.message));
    } catch (error) {
      return Err(StoreError(error.toString()));
    }
  }

  static void _unwrap(Result<void> result) {
    if (result case Err(failure: final failure)) throw StateError('$failure');
  }

  static DateTime? _parse(String? source) =>
      source == null ? null : DateTime.parse(source);
}
