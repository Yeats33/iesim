import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../model/appearance.dart';
import '../model/keep_alive.dart';
import '../model/plan.dart';
import '../model/subscription.dart';
import '../result.dart';
import '../value/money.dart';
import '../value/phone_number.dart';

/// 订阅聚合根的持久化仓库。
///
/// 值对象扁平化为单表多列，不存 JSON blob，保证字段可查询。
/// 一切 sqlite 异常捕获为 [StoreError]，不穿透到调用方。
class SubscriptionRepository {
  final Database _db;

  SubscriptionRepository(this._db);

  /// 写入或覆盖订阅（按 id 幂等）。
  Result<void> upsert(Subscription s) {
    try {
      _db.execute(
        '''INSERT OR REPLACE INTO subscriptions (
  id, iccid, number, operator,
  plan_name, plan_cycle_minor, plan_cycle_currency, plan_cycle_days,
  plan_start, plan_expiry, plan_is_long_term,
  keepalive_required, keepalive_cycle_days, keepalive_last_activity_at,
  keepalive_confidence,
  tags_json,
  appearance_flag, appearance_color_hex, appearance_background_asset,
  appearance_website_url, appearance_custom_prompt,
  time_zone_id, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          s.id,
          s.iccid,
          s.number.value,
          s.operator,
          s.plan.name,
          s.plan.cyclePrice?.minorUnits,
          s.plan.cyclePrice?.currencyCode,
          s.plan.cycleDays,
          _toIso(s.plan.startDate),
          _toIso(s.plan.expiryDate),
          s.plan.isLongTerm ? 1 : 0,
          s.keepAlive.required ? 1 : 0,
          s.keepAlive.cycleDays,
          _toIso(s.keepAlive.lastActivityAt),
          s.keepAlive.confidence.name,
          jsonEncode(s.tags),
          s.appearance.flag,
          s.appearance.cardColorHex,
          s.appearance.cardBackgroundAssetName,
          s.appearance.websiteURL,
          s.appearance.customPrompt,
          s.timeZoneId,
          _toIso(s.createdAt)!,
          _toIso(s.updatedAt)!,
        ],
      );
      return const Ok(null);
    } on SqliteException catch (e) {
      return Err(StoreError(e.message));
    } catch (e) {
      return Err(StoreError(e.toString()));
    }
  }

  Result<Subscription?> get(String id) {
    try {
      final rows = _db.select(
        'SELECT * FROM subscriptions WHERE id = ?',
        [id],
      );
      if (rows.isEmpty) return const Ok(null);
      return Ok(_rowToSubscription(rows.single));
    } on SqliteException catch (e) {
      return Err(StoreError(e.message));
    } catch (e) {
      return Err(StoreError(e.toString()));
    }
  }

  /// 全部订阅，按创建时间升序。
  Result<List<Subscription>> listAll() {
    try {
      final rows = _db.select(
        'SELECT * FROM subscriptions ORDER BY created_at ASC',
      );
      return Ok([for (final row in rows) _rowToSubscription(row)]);
    } on SqliteException catch (e) {
      return Err(StoreError(e.message));
    } catch (e) {
      return Err(StoreError(e.toString()));
    }
  }

  Result<void> delete(String id) {
    try {
      _db.execute('DELETE FROM subscriptions WHERE id = ?', [id]);
      return const Ok(null);
    } on SqliteException catch (e) {
      return Err(StoreError(e.message));
    } catch (e) {
      return Err(StoreError(e.toString()));
    }
  }

  Subscription _rowToSubscription(Row row) {
    final cycleMinor = row['plan_cycle_minor'] as int?;
    return Subscription(
      id: row['id'] as String,
      iccid: row['iccid'] as String?,
      number: PhoneNumber(row['number'] as String),
      operator: row['operator'] as String?,
      plan: Plan(
        name: row['plan_name'] as String?,
        cyclePrice: cycleMinor == null
            ? null
            : Money(
                minorUnits: cycleMinor,
                currencyCode: row['plan_cycle_currency'] as String,
              ),
        cycleDays: row['plan_cycle_days'] as int?,
        startDate: _parseUtc(row['plan_start'] as String?),
        expiryDate: _parseUtc(row['plan_expiry'] as String?),
        isLongTerm: row['plan_is_long_term'] == 1,
      ),
      keepAlive: KeepAlive(
        required: row['keepalive_required'] == 1,
        cycleDays: row['keepalive_cycle_days'] as int?,
        lastActivityAt:
            _parseUtc(row['keepalive_last_activity_at'] as String?),
        confidence: DataConfidence.values.byName(
          row['keepalive_confidence'] as String,
        ),
      ),
      tags: (jsonDecode(row['tags_json'] as String) as List)
          .cast<String>(),
      appearance: Appearance(
        flag: row['appearance_flag'] as String?,
        cardColorHex: row['appearance_color_hex'] as String?,
        cardBackgroundAssetName:
            row['appearance_background_asset'] as String?,
        websiteURL: row['appearance_website_url'] as String?,
        customPrompt: row['appearance_custom_prompt'] as String?,
      ),
      timeZoneId: row['time_zone_id'] as String,
      createdAt: _parseUtc(row['created_at'] as String)!,
      updatedAt: _parseUtc(row['updated_at'] as String)!,
    );
  }

  static String? _toIso(DateTime? t) => t?.toIso8601String();

  static DateTime? _parseUtc(String? s) => s == null ? null : DateTime.parse(s);
}
