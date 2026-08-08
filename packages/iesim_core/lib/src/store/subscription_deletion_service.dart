import 'package:sqlite3/sqlite3.dart';

import '../result.dart';
import '../sync/sync_snapshot.dart';

/// 删除订阅和子动作，同时写入可跨设备传播的墓碑。
class SubscriptionDeletionService {
  const SubscriptionDeletionService(this._db);

  final Database _db;

  Result<void> delete({
    required String subscriptionId,
    required DateTime nowUtc,
  }) {
    if (!nowUtc.isUtc) {
      return const Err(StoreError('删除时间必须是 UTC'));
    }
    try {
      _db.execute('BEGIN IMMEDIATE');
      final activityIds = _db.select(
        'SELECT id FROM activity_records WHERE subscription_id = ?',
        [subscriptionId],
      );
      for (final row in activityIds) {
        _upsertTombstone(
          SyncEntityType.activityRecord,
          row['id'] as String,
          nowUtc,
        );
      }
      final profileIds = _db.select(
        'SELECT id FROM profiles WHERE subscription_id = ?',
        [subscriptionId],
      );
      for (final row in profileIds) {
        _upsertTombstone(SyncEntityType.profile, row['id'] as String, nowUtc);
      }
      _upsertTombstone(SyncEntityType.subscription, subscriptionId, nowUtc);
      _db.execute('DELETE FROM profiles WHERE subscription_id = ?', [
        subscriptionId,
      ]);
      _db.execute('DELETE FROM subscriptions WHERE id = ?', [subscriptionId]);
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

  void _upsertTombstone(SyncEntityType type, String id, DateTime deletedAtUtc) {
    _db.execute(
      '''INSERT INTO sync_tombstones (entity_type, entity_id, deleted_at)
VALUES (?, ?, ?)
ON CONFLICT(entity_type, entity_id) DO UPDATE SET
  deleted_at = excluded.deleted_at''',
      [type.name, id, deletedAtUtc.toIso8601String()],
    );
  }
}
