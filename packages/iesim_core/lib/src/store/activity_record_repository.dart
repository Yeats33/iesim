import 'package:sqlite3/sqlite3.dart';

import '../model/activity_record.dart';
import '../result.dart';
import '../value/money.dart';

/// 续存动作记录的持久化仓库。
///
/// 按订阅查询供 UI 展示历史；listAll 供计划 4 同步快照使用。
class ActivityRecordRepository {
  final Database _db;

  ActivityRecordRepository(this._db);

  /// 追加一条动作记录。
  Result<void> append(ActivityRecord record) {
    try {
      _db.execute(
        '''INSERT INTO activity_records
  (id, subscription_id, type, occurred_at, amount_minor, amount_currency)
  VALUES (?, ?, ?, ?, ?, ?)''',
        [
          record.id,
          record.subscriptionId,
          record.type.name,
          record.occurredAt.toIso8601String(),
          record.amount?.minorUnits,
          record.amount?.currencyCode,
        ],
      );
      return const Ok(null);
    } on SqliteException catch (e) {
      return Err(StoreError(e.message));
    } catch (e) {
      return Err(StoreError(e.toString()));
    }
  }

  /// 某订阅的全部动作记录，按发生时刻升序。
  Result<List<ActivityRecord>> listBySubscription(String subscriptionId) {
    try {
      final rows = _db.select(
        'SELECT * FROM activity_records WHERE subscription_id = ? '
        'ORDER BY occurred_at ASC, id ASC',
        [subscriptionId],
      );
      return Ok([for (final row in rows) _rowToRecord(row)]);
    } on SqliteException catch (e) {
      return Err(StoreError(e.message));
    } catch (e) {
      return Err(StoreError(e.toString()));
    }
  }

  /// 全部动作记录，按发生时刻升序（计划 4 同步快照用）。
  Result<List<ActivityRecord>> listAll() {
    try {
      final rows = _db.select(
        'SELECT * FROM activity_records ORDER BY occurred_at ASC, id ASC',
      );
      return Ok([for (final row in rows) _rowToRecord(row)]);
    } on SqliteException catch (e) {
      return Err(StoreError(e.message));
    } catch (e) {
      return Err(StoreError(e.toString()));
    }
  }

  ActivityRecord _rowToRecord(Row row) {
    final minor = row['amount_minor'] as int?;
    return ActivityRecord(
      id: row['id'] as String,
      subscriptionId: row['subscription_id'] as String,
      type: ActivityType.values.byName(row['type'] as String),
      occurredAt: DateTime.parse(row['occurred_at'] as String),
      amount: minor == null
          ? null
          : Money(
              minorUnits: minor,
              currencyCode: row['amount_currency'] as String,
            ),
    );
  }
}
