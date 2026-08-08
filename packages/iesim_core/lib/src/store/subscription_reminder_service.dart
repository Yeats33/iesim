import 'package:sqlite3/sqlite3.dart';

import '../model/assets.dart';
import '../model/subscription.dart';
import '../result.dart';
import '../schedule/reminder_planner.dart';
import '../time/clock.dart';
import 'asset_repository.dart';
import 'subscription_repository.dart';

/// 业务 Profile、提醒时刻与可选 EID 归属处于同一 SQLite 事务。
class SubscriptionReminderService {
  SubscriptionReminderService(this._database)
    : _subscriptions = SubscriptionRepository(_database),
      _assets = AssetRepository(_database);

  final Database _database;
  final SubscriptionRepository _subscriptions;
  final AssetRepository _assets;

  Result<void> upsert({
    required Subscription subscription,
    required Clock clock,
    EsimProfile? assetProfile,
    String? movementEventId,
  }) {
    try {
      _database.execute('BEGIN IMMEDIATE');
      final result = _subscriptions.upsert(subscription);
      if (result case Err(failure: final failure)) {
        throw _ReminderWriteFailure(failure);
      }
      replaceReminderSchedulesInTransaction(
        _database,
        subscription: subscription,
        clock: clock,
      );
      if (assetProfile != null) {
        if (assetProfile.subscriptionId != subscription.id) {
          throw const _ReminderWriteFailure(
            StoreError('eSIM Profile 必须关联当前业务 Profile'),
          );
        }
        final previousRows = _database.select(
          'SELECT eid_id FROM profiles WHERE id = ?',
          [assetProfile.id],
        );
        final previousEidId = previousRows.isEmpty
            ? null
            : previousRows.single['eid_id'] as String;
        final assetResult = _assets.upsertProfile(assetProfile);
        if (assetResult case Err(failure: final failure)) {
          throw _ReminderWriteFailure(failure);
        }
        if (previousEidId != null && previousEidId != assetProfile.eidId) {
          if (movementEventId == null) {
            throw const _ReminderWriteFailure(StoreError('缺少 Profile 移动事件 ID'));
          }
          final eventResult = _assets.upsertEvent(
            ProfileMoved(
              id: movementEventId,
              profileId: assetProfile.id,
              fromEidId: previousEidId,
              toEidId: assetProfile.eidId,
              occurredAt: assetProfile.updatedAt,
              note: '从 Profile 编辑器更换 EID',
            ),
          );
          if (eventResult case Err(failure: final failure)) {
            throw _ReminderWriteFailure(failure);
          }
        }
      }
      _database.execute('COMMIT');
      return const Ok(null);
    } on _ReminderWriteFailure catch (error) {
      _rollback();
      return Err(error.failure);
    } on SqliteException catch (error) {
      _rollback();
      return Err(StoreError(error.message));
    } catch (error) {
      _rollback();
      return Err(StoreError(error.toString()));
    }
  }

  void _rollback() {
    try {
      _database.execute('ROLLBACK');
    } catch (_) {}
  }
}

void replaceReminderSchedulesInTransaction(
  Database database, {
  required Subscription subscription,
  required Clock clock,
}) {
  database.execute(
    'DELETE FROM scheduled_reminders WHERE subscription_id = ?',
    [subscription.id],
  );
  final reminders = ReminderPlanner(clock: clock).planFor(subscription);
  for (final reminder in reminders) {
    database.execute(
      '''INSERT INTO scheduled_reminders (
  stable_key, subscription_id, kind, slot, fire_at, deadline, days_before, inferred
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        reminder.stableKey,
        reminder.subscriptionId,
        reminder.kind.name,
        reminder.slot,
        reminder.fireAtUtc.toIso8601String(),
        reminder.deadlineUtc.toIso8601String(),
        reminder.daysBefore,
        reminder.inferred ? 1 : 0,
      ],
    );
  }
}

class _ReminderWriteFailure implements Exception {
  const _ReminderWriteFailure(this.failure);

  final Failure failure;
}
