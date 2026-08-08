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
    return _write(record, replace: false);
  }

  /// 导入/同步用幂等写入。相同 id 的远端记录覆盖本地记录。
  Result<void> upsert(ActivityRecord record) => _write(record, replace: true);

  Result<void> _write(ActivityRecord record, {required bool replace}) {
    try {
      _db.execute(
        '''INSERT ${replace ? 'OR REPLACE ' : ''}INTO activity_records
  (id, subscription_id, type, occurred_at, updated_at, amount_minor,
   amount_currency, balance_after_minor, balance_after_currency, note)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          record.id,
          record.subscriptionId,
          record.type.name,
          record.occurredAt.toIso8601String(),
          record.updatedAt.toIso8601String(),
          record.amount?.minorUnits,
          record.amount?.currencyCode,
          record.balanceAfter?.minorUnits,
          record.balanceAfter?.currencyCode,
          record.note,
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
    final balanceAfterMinor = row['balance_after_minor'] as int?;
    return ActivityRecord(
      id: row['id'] as String,
      subscriptionId: row['subscription_id'] as String,
      type: ActivityType.values.byName(row['type'] as String),
      occurredAt: DateTime.parse(row['occurred_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      amount: minor == null
          ? null
          : Money(
              minorUnits: minor,
              currencyCode: row['amount_currency'] as String,
            ),
      balanceAfter: balanceAfterMinor == null
          ? null
          : Money(
              minorUnits: balanceAfterMinor,
              currencyCode: row['balance_after_currency'] as String,
            ),
      note: row['note'] as String?,
    );
  }
}
