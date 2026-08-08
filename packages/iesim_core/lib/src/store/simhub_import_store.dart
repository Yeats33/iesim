import 'package:sqlite3/sqlite3.dart';

import '../interop/simhub_codec.dart';
import '../interop/nekoko_database_codec.dart';
import '../model/activity_record.dart';
import '../model/assets.dart';
import '../model/subscription.dart';
import '../result.dart';
import '../time/clock.dart';
import 'activity_record_repository.dart';
import 'asset_repository.dart';
import 'subscription_repository.dart';
import 'subscription_reminder_service.dart';

class SimHubImportSummary {
  final int subscriptionsWritten;
  final int activitiesWritten;
  final int devicesWritten;
  final int cardsWritten;
  final int profilesWritten;

  const SimHubImportSummary({
    required this.subscriptionsWritten,
    required this.activitiesWritten,
    this.devicesWritten = 0,
    this.cardsWritten = 0,
    this.profilesWritten = 0,
  });
}

/// 将已验证的 SimHub 报告原子写入 SQLite。
///
/// 任一唯一约束或磁盘错误都会回滚整批，避免出现“订阅写了一半、动作记录
/// 没写完”的不可解释状态。重复导入同一文件保持幂等。
class SimHubImportStore {
  SimHubImportStore(Database database)
    : _database = database,
      _subscriptions = SubscriptionRepository(database),
      _activities = ActivityRecordRepository(database),
      _assets = AssetRepository(database);

  final Database _database;
  final SubscriptionRepository _subscriptions;
  final ActivityRecordRepository _activities;
  final AssetRepository _assets;

  /// 清空全部本地业务、资产、提醒与同步状态。
  ///
  /// 仅用于开发者模式；不会接触任何远端 WebDAV 文件。
  Result<void> clearAll() => clearSelected(
    clearProfiles: true,
    clearAssets: true,
    resetSyncState: true,
  );

  /// 按开发者选择清空本地数据。
  ///
  /// [clearProfiles] 包含订阅、套餐、余额、动作、提醒和 Profile 资产；
  /// [clearAssets] 包含设备、卡槽、卡片、EID 与资产事件。任一业务范围
  /// 被清空时都应同时重置同步状态，避免旧 ETag 描述已经不存在的数据。
  Result<void> clearSelected({
    required bool clearProfiles,
    required bool clearAssets,
    required bool resetSyncState,
  }) {
    try {
      _database.execute('BEGIN IMMEDIATE');
      if (clearProfiles) {
        _database.execute('''
DELETE FROM scheduled_reminders;
DELETE FROM asset_events WHERE profile_id IS NOT NULL;
DELETE FROM profiles;
DELETE FROM activity_records;
DELETE FROM subscriptions;
''');
      }
      if (clearAssets) {
        _database.execute('''
DELETE FROM asset_events;
DELETE FROM profiles;
DELETE FROM eids;
DELETE FROM slots;
DELETE FROM cards;
DELETE FROM devices;
''');
      }
      if (resetSyncState) {
        _database.execute('''
DELETE FROM sync_tombstones;
DELETE FROM sync_conflicts;
DELETE FROM sync_state;
INSERT INTO sync_state (singleton) VALUES (1);
''');
      }
      _database.execute('COMMIT');
      return const Ok(null);
    } on SqliteException catch (error) {
      _rollback();
      return Err(StoreError(error.message));
    } catch (error) {
      _rollback();
      return Err(StoreError(error.toString()));
    }
  }

  Result<SimHubImportSummary> apply(SimHubImportReport report) {
    return _apply(
      subscriptions: report.subscriptions,
      activities: report.activityRecords,
      assets: report.assets,
    );
  }

  Result<SimHubImportSummary> applyNekoko(NekokoImportReport report) {
    return _apply(
      subscriptions: report.subscriptions,
      activities: const [],
      assets: report.assets,
    );
  }

  Result<SimHubImportSummary> _apply({
    required List<Subscription> subscriptions,
    required List<ActivityRecord> activities,
    required AssetInventory assets,
  }) {
    try {
      _database.execute('BEGIN IMMEDIATE');
      for (final subscription in subscriptions) {
        final result = _subscriptions.upsert(subscription);
        if (result case Err(failure: final failure)) {
          throw _ImportFailure(failure);
        }
        replaceReminderSchedulesInTransaction(
          _database,
          subscription: subscription,
          clock: const SystemClock(),
        );
      }
      for (final activity in activities) {
        final result = _activities.upsert(activity);
        if (result case Err(failure: final failure)) {
          throw _ImportFailure(failure);
        }
      }
      for (final device in assets.devices) {
        _requireOk(_assets.upsertDevice(device));
      }
      for (final card in assets.cards) {
        _requireOk(_assets.upsertCard(card));
      }
      for (final slot in assets.slots) {
        _requireOk(_assets.upsertSlot(slot));
      }
      for (final eid in assets.eids) {
        _requireOk(_assets.upsertEid(eid));
      }
      for (final profile in assets.profiles) {
        _requireOk(_assets.upsertProfile(profile));
      }
      _database.execute('COMMIT');
      return Ok(
        SimHubImportSummary(
          subscriptionsWritten: subscriptions.length,
          activitiesWritten: activities.length,
          devicesWritten: assets.devices.length,
          cardsWritten: assets.cards.length,
          profilesWritten: assets.profiles.length,
        ),
      );
    } on _ImportFailure catch (error) {
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
      // 原始错误更有诊断价值；库可能已关闭或事务已自行回滚。
    }
  }

  static void _requireOk(Result<void> result) {
    if (result case Err(failure: final failure)) {
      throw _ImportFailure(failure);
    }
  }
}

class _ImportFailure implements Exception {
  final Failure failure;

  const _ImportFailure(this.failure);
}
