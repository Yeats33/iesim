import 'package:sqlite3/sqlite3.dart';

import '../model/activity_record.dart';
import '../model/keep_alive.dart';
import '../model/subscription.dart';
import '../result.dart';
import '../time/clock.dart';
import '../value/money.dart';
import 'activity_record_repository.dart';
import 'subscription_reminder_service.dart';
import 'subscription_repository.dart';

/// 在同一事务中追加动作并刷新订阅的保号基准。
class ActivityService {
  ActivityService(Database database)
    : _database = database,
      _subscriptions = SubscriptionRepository(database),
      _activities = ActivityRecordRepository(database);

  final Database _database;
  final SubscriptionRepository _subscriptions;
  final ActivityRecordRepository _activities;

  Result<Subscription> record({
    required Subscription subscription,
    required ActivityRecord activity,
    required DateTime updatedAtUtc,
  }) {
    if (activity.subscriptionId != subscription.id) {
      return const Err(StoreError('动作记录与订阅 ID 不一致'));
    }
    if (!updatedAtUtc.isUtc) {
      return const Err(StoreError('updatedAtUtc 必须是 UTC 时刻'));
    }
    try {
      _database.execute('BEGIN IMMEDIATE');
      final appendResult = _activities.append(activity);
      if (appendResult case Err(failure: final failure)) {
        throw _ActivityFailure(failure);
      }

      final resetsKeepAlive =
          subscription.keepAlive.required &&
          subscription.keepAlive.policy.accepts(activity.type);
      final updated = resetsKeepAlive
          ? subscription.copyWith(
              keepAlive: subscription.keepAlive.copyWith(
                lastActivityAt: activity.occurredAt,
                confidence: DataConfidence.confirmed,
              ),
              updatedAt: updatedAtUtc,
            )
          : subscription;
      if (resetsKeepAlive) {
        final updateResult = _subscriptions.upsert(updated);
        if (updateResult case Err(failure: final failure)) {
          throw _ActivityFailure(failure);
        }
        replaceReminderSchedulesInTransaction(
          _database,
          subscription: updated,
          clock: FixedClock(updatedAtUtc),
        );
      }
      _database.execute('COMMIT');
      return Ok(updated);
    } on _ActivityFailure catch (error) {
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

  /// 在同一事务里写入余额流水并更新 Profile 当前余额。
  Result<Subscription> updateBalance({
    required Subscription subscription,
    required ActivityRecord activity,
    required Money balance,
    required DateTime updatedAtUtc,
  }) {
    if (activity.subscriptionId != subscription.id) {
      return const Err(StoreError('余额流水与订阅 ID 不一致'));
    }
    if (activity.type != ActivityType.balanceChange ||
        activity.balanceAfter != balance) {
      return const Err(StoreError('余额流水缺少正确的期末余额'));
    }
    if (!updatedAtUtc.isUtc) {
      return const Err(StoreError('updatedAtUtc 必须是 UTC 时刻'));
    }
    try {
      _database.execute('BEGIN IMMEDIATE');
      final appendResult = _activities.append(activity);
      if (appendResult case Err(failure: final failure)) {
        throw _ActivityFailure(failure);
      }

      final resetsKeepAlive =
          subscription.keepAlive.required &&
          subscription.keepAlive.policy.accepts(activity.type);
      final updated = subscription.copyWith(
        details: subscription.details.copyWith(currentBalance: balance),
        keepAlive: resetsKeepAlive
            ? subscription.keepAlive.copyWith(
                lastActivityAt: activity.occurredAt,
                confidence: DataConfidence.confirmed,
              )
            : subscription.keepAlive,
        updatedAt: updatedAtUtc,
      );
      final updateResult = _subscriptions.upsert(updated);
      if (updateResult case Err(failure: final failure)) {
        throw _ActivityFailure(failure);
      }
      replaceReminderSchedulesInTransaction(
        _database,
        subscription: updated,
        clock: FixedClock(updatedAtUtc),
      );
      _database.execute('COMMIT');
      return Ok(updated);
    } on _ActivityFailure catch (error) {
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
    } catch (_) {
      // 保留原始失败。
    }
  }
}

class _ActivityFailure implements Exception {
  final Failure failure;

  const _ActivityFailure(this.failure);
}
