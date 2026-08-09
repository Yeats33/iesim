import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../model/appearance.dart';
import '../model/affiliate_offer.dart';
import '../model/keep_alive.dart';
import '../model/plan.dart';
import '../model/profile_lifecycle.dart';
import '../model/subscription.dart';
import '../model/subscription_details.dart';
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
        '''INSERT INTO subscriptions (
  id, iccid, number, operator,
  profile_stage, profile_device_state, activation_deadline,
  activation_requirements, service_expires_at, profile_activated_at,
  profile_archived_at, profile_archive_reason,
  profile_name, profile_class_code, declared_profile_size_bytes,
  installed_profile_size_bytes, gid1, gid2,
  country_code, country_name, mcc, mnc, apn,
  secondary_phone_number, secondary_phone_enabled,
  activation_date, current_balance_minor, current_balance_currency,
  affiliate_offers_json,
  auto_top_up_enabled, top_up_cycle_unit, renewal_interval_value, renewal_unit,
  transaction_notes, carrier_app_name, carrier_app_store_url,
  carrier_app_icon_url, keep_alive_mode_raw, order_index, is_dormant, is_pinned,
  plan_name, plan_cycle_minor, plan_cycle_currency, plan_cycle_days,
  plan_start, plan_expiry, plan_is_long_term,
  keepalive_required, keepalive_cycle_days, keepalive_last_activity_at,
  keepalive_confidence, keepalive_policy_json,
  tags_json,
  appearance_flag, appearance_color_hex, appearance_background_asset,
  appearance_website_url, appearance_custom_prompt,
  time_zone_id, created_at, updated_at
) VALUES (
  ?, ?, ?, ?,
  ?, ?, ?,
  ?, ?, ?,
  ?, ?,
  ?, ?, ?,
  ?, ?, ?,
  ?, ?, ?, ?, ?,
  ?, ?,
  ?, ?, ?,
  ?,
  ?, ?, ?, ?,
  ?, ?, ?,
  ?, ?, ?, ?, ?,
  ?, ?, ?, ?,
  ?, ?, ?,
  ?, ?, ?,
  ?, ?,
  ?,
  ?, ?, ?,
  ?, ?,
  ?, ?, ?
)
ON CONFLICT(id) DO UPDATE SET
  iccid = excluded.iccid,
  number = excluded.number,
  operator = excluded.operator,
  profile_stage = excluded.profile_stage,
  profile_device_state = excluded.profile_device_state,
  activation_deadline = excluded.activation_deadline,
  activation_requirements = excluded.activation_requirements,
  service_expires_at = excluded.service_expires_at,
  profile_activated_at = excluded.profile_activated_at,
  profile_archived_at = excluded.profile_archived_at,
  profile_archive_reason = excluded.profile_archive_reason,
  profile_name = excluded.profile_name,
  profile_class_code = excluded.profile_class_code,
  declared_profile_size_bytes = excluded.declared_profile_size_bytes,
  installed_profile_size_bytes = excluded.installed_profile_size_bytes,
  gid1 = excluded.gid1,
  gid2 = excluded.gid2,
  country_code = excluded.country_code,
  country_name = excluded.country_name,
  mcc = excluded.mcc,
  mnc = excluded.mnc,
  apn = excluded.apn,
  secondary_phone_number = excluded.secondary_phone_number,
  secondary_phone_enabled = excluded.secondary_phone_enabled,
  activation_date = excluded.activation_date,
  current_balance_minor = excluded.current_balance_minor,
  current_balance_currency = excluded.current_balance_currency,
  affiliate_offers_json = excluded.affiliate_offers_json,
  auto_top_up_enabled = excluded.auto_top_up_enabled,
  top_up_cycle_unit = excluded.top_up_cycle_unit,
  renewal_interval_value = excluded.renewal_interval_value,
  renewal_unit = excluded.renewal_unit,
  transaction_notes = excluded.transaction_notes,
  carrier_app_name = excluded.carrier_app_name,
  carrier_app_store_url = excluded.carrier_app_store_url,
  carrier_app_icon_url = excluded.carrier_app_icon_url,
  keep_alive_mode_raw = excluded.keep_alive_mode_raw,
  order_index = excluded.order_index,
  is_dormant = excluded.is_dormant,
  is_pinned = excluded.is_pinned,
  plan_name = excluded.plan_name,
  plan_cycle_minor = excluded.plan_cycle_minor,
  plan_cycle_currency = excluded.plan_cycle_currency,
  plan_cycle_days = excluded.plan_cycle_days,
  plan_start = excluded.plan_start,
  plan_expiry = excluded.plan_expiry,
  plan_is_long_term = excluded.plan_is_long_term,
  keepalive_required = excluded.keepalive_required,
  keepalive_cycle_days = excluded.keepalive_cycle_days,
  keepalive_last_activity_at = excluded.keepalive_last_activity_at,
  keepalive_confidence = excluded.keepalive_confidence,
  keepalive_policy_json = excluded.keepalive_policy_json,
  tags_json = excluded.tags_json,
  appearance_flag = excluded.appearance_flag,
  appearance_color_hex = excluded.appearance_color_hex,
  appearance_background_asset = excluded.appearance_background_asset,
  appearance_website_url = excluded.appearance_website_url,
  appearance_custom_prompt = excluded.appearance_custom_prompt,
  time_zone_id = excluded.time_zone_id,
  created_at = excluded.created_at,
  updated_at = excluded.updated_at''',
        [
          s.id,
          s.iccid,
          s.number.value,
          s.operator,
          s.lifecycle.stage.name,
          s.lifecycle.deviceState.name,
          _toIso(s.lifecycle.activationDeadline),
          s.lifecycle.activationRequirements,
          _toIso(s.lifecycle.serviceExpiresAt),
          _toIso(s.lifecycle.activatedAt),
          _toIso(s.lifecycle.archivedAt),
          s.lifecycle.archiveReason?.name,
          s.details.profileName,
          s.details.profileClassCode,
          s.details.declaredProfileSizeBytes,
          s.details.installedProfileSizeBytes,
          s.details.gid1,
          s.details.gid2,
          s.details.countryCode,
          s.details.countryName,
          s.details.mcc,
          s.details.mnc,
          s.details.apn,
          s.details.secondaryPhoneNumber,
          s.details.secondaryPhoneNumberEnabled ? 1 : 0,
          _toIso(s.details.activationDate),
          s.details.currentBalance?.minorUnits,
          s.details.currentBalance?.currencyCode,
          jsonEncode(
            s.details.affiliateOffers.map((offer) => offer.toJson()).toList(),
          ),
          s.details.autoTopUpEnabled ? 1 : 0,
          s.details.topUpCycleUnit,
          s.details.renewalIntervalValue,
          s.details.renewalUnit,
          s.details.transactionNotes,
          s.details.carrierAppName,
          s.details.carrierAppStoreUrl,
          s.details.carrierAppIconUrl,
          s.details.keepAliveModeRaw,
          s.details.orderIndex,
          s.details.isDormant ? 1 : 0,
          s.details.isPinned ? 1 : 0,
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
          jsonEncode(s.keepAlive.policy.toJson()),
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
      final rows = _db.select('SELECT * FROM subscriptions WHERE id = ?', [id]);
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
        'SELECT * FROM subscriptions ORDER BY order_index ASC, created_at ASC',
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
    final number = row['number'] as String;
    return Subscription(
      id: row['id'] as String,
      iccid: row['iccid'] as String?,
      number: number.isEmpty
          ? const PhoneNumber.unknown()
          : PhoneNumber(number),
      operator: row['operator'] as String?,
      lifecycle: ProfileLifecycle(
        stage: ProfileStage.values.byName(row['profile_stage'] as String),
        deviceState: ProfileDeviceState.values.byName(
          row['profile_device_state'] as String,
        ),
        activationDeadline: _parseUtc(row['activation_deadline'] as String?),
        activationRequirements: row['activation_requirements'] as String?,
        serviceExpiresAt: _parseUtc(row['service_expires_at'] as String?),
        activatedAt: _parseUtc(row['profile_activated_at'] as String?),
        archivedAt: _parseUtc(row['profile_archived_at'] as String?),
        archiveReason: row['profile_archive_reason'] == null
            ? null
            : ProfileArchiveReason.values.byName(
                row['profile_archive_reason'] as String,
              ),
      ),
      activation: null,
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
        lastActivityAt: _parseUtc(row['keepalive_last_activity_at'] as String?),
        confidence: DataConfidence.values.byName(
          row['keepalive_confidence'] as String,
        ),
        policy: _decodeKeepAlivePolicy(row['keepalive_policy_json'] as String?),
      ),
      tags: (jsonDecode(row['tags_json'] as String) as List).cast<String>(),
      appearance: Appearance(
        flag: row['appearance_flag'] as String?,
        cardColorHex: row['appearance_color_hex'] as String?,
        cardBackgroundAssetName: row['appearance_background_asset'] as String?,
        websiteURL: row['appearance_website_url'] as String?,
        customPrompt: row['appearance_custom_prompt'] as String?,
      ),
      details: SubscriptionDetails(
        profileName: row['profile_name'] as String?,
        profileClassCode: row['profile_class_code'] as int?,
        declaredProfileSizeBytes: row['declared_profile_size_bytes'] as int?,
        installedProfileSizeBytes: row['installed_profile_size_bytes'] as int?,
        gid1: row['gid1'] as String?,
        gid2: row['gid2'] as String?,
        countryCode: row['country_code'] as String?,
        countryName: row['country_name'] as String?,
        mcc: row['mcc'] as String?,
        mnc: row['mnc'] as String?,
        apn: row['apn'] as String?,
        secondaryPhoneNumber: row['secondary_phone_number'] as String?,
        secondaryPhoneNumberEnabled: row['secondary_phone_enabled'] == 1,
        activationDate: _parseUtc(row['activation_date'] as String?),
        currentBalance: row['current_balance_minor'] == null
            ? null
            : Money(
                minorUnits: row['current_balance_minor'] as int,
                currencyCode: row['current_balance_currency'] as String,
              ),
        affiliateOffers: _decodeAffiliateOffers(
          row['affiliate_offers_json'] as String,
        ),
        autoTopUpEnabled: row['auto_top_up_enabled'] == 1,
        topUpCycleUnit: row['top_up_cycle_unit'] as String?,
        renewalIntervalValue: row['renewal_interval_value'] as int?,
        renewalUnit: row['renewal_unit'] as String?,
        transactionNotes: row['transaction_notes'] as String?,
        carrierAppName: row['carrier_app_name'] as String?,
        carrierAppStoreUrl: row['carrier_app_store_url'] as String?,
        carrierAppIconUrl: row['carrier_app_icon_url'] as String?,
        keepAliveModeRaw: row['keep_alive_mode_raw'] as String?,
        orderIndex: row['order_index'] as int,
        isDormant: row['is_dormant'] == 1,
        isPinned: row['is_pinned'] == 1,
      ),
      timeZoneId: row['time_zone_id'] as String,
      createdAt: _parseUtc(row['created_at'] as String)!,
      updatedAt: _parseUtc(row['updated_at'] as String)!,
    );
  }

  static String? _toIso(DateTime? t) => t?.toIso8601String();

  static DateTime? _parseUtc(String? s) => s == null ? null : DateTime.parse(s);

  static KeepAlivePolicy _decodeKeepAlivePolicy(String? source) {
    if (source == null || source.trim().isEmpty || source.trim() == '{}') {
      return KeepAlivePolicy();
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('保号策略存储格式无效');
    return KeepAlivePolicy.fromJson(Map<String, dynamic>.from(decoded));
  }

  static List<AffiliateOffer> _decodeAffiliateOffers(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('AFF 推荐存储格式无效');
    }
    return decoded
        .map(
          (value) =>
              AffiliateOffer.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList(growable: false);
  }
}
