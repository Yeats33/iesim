import 'package:sqlite3/sqlite3.dart';

import '../model/assets.dart';
import '../model/keep_alive.dart';
import '../model/plan.dart';
import '../model/profile_lifecycle.dart';
import '../model/subscription.dart';
import '../model/subscription_details.dart';
import '../result.dart';
import '../value/phone_number.dart';
import 'nekoko_tag_codec.dart';

class NekokoImportIssue {
  const NekokoImportIssue({required this.record, required this.message});

  /// 1-based profile row number, or null for a file-level issue.
  final int? record;
  final String message;
}

class NekokoImportReport {
  NekokoImportReport({
    required this.sourceProfileCount,
    required List<Subscription> subscriptions,
    required this.assets,
    required List<NekokoImportIssue> issues,
  }) : subscriptions = List.unmodifiable(subscriptions),
       issues = List.unmodifiable(issues);

  final int sourceProfileCount;
  final List<Subscription> subscriptions;
  final AssetInventory assets;
  final List<NekokoImportIssue> issues;
}

/// Reads a NekokoLPA2 SQLite database export without modifying it.
///
/// Interoperable Profile and inventory fields are normalized into ieSIM's own
/// domain model: EID/ICCID relations, display name, tags, operator metadata,
/// enabled state, Profile class/size/GID and the optional MSISDN cache. LPA
/// keys, notification payloads and remote-server history are deliberately
/// ignored.
class NekokoDatabaseCodec {
  NekokoDatabaseCodec({
    String Function()? idFactory,
    DateTime Function()? nowUtc,
  }) : _idFactory = idFactory ?? _fallbackId,
       _nowUtc = nowUtc ?? _systemNowUtc;

  final String Function() _idFactory;
  final DateTime Function() _nowUtc;

  Result<NekokoImportReport> inspectFile(
    String path, {
    required String defaultTimeZoneId,
    Iterable<Subscription> existingSubscriptions = const [],
    AssetInventory? existingAssets,
  }) {
    Database? database;
    try {
      database = sqlite3.open(path, mode: OpenMode.readOnly);
      database.execute('PRAGMA query_only = ON');
      return Ok(
        _decode(
          database,
          defaultTimeZoneId: defaultTimeZoneId,
          existingSubscriptions: existingSubscriptions,
          existingAssets: existingAssets ?? AssetInventory(),
        ),
      );
    } on SqliteException catch (error) {
      return Err(SchemaError('无法读取 Nekoko 数据库：${error.message}'));
    } on FormatException catch (error) {
      return Err(SchemaError(error.message));
    } on ArgumentError catch (error) {
      return Err(SchemaError(error.message?.toString() ?? error.toString()));
    } catch (error) {
      return Err(SchemaError('无法读取 Nekoko 数据库：$error'));
    } finally {
      database?.close();
    }
  }

  NekokoImportReport _decode(
    Database database, {
    required String defaultTimeZoneId,
    required Iterable<Subscription> existingSubscriptions,
    required AssetInventory existingAssets,
  }) {
    final tables = {
      for (final row in database.select(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ))
        row['name'] as String,
    };
    if (!tables.contains('profile_metadata')) {
      throw const FormatException('所选文件不含 Nekoko profile_metadata 表');
    }
    final columns = {
      for (final row in database.select('PRAGMA table_info(profile_metadata)'))
        row['name'] as String,
    };
    if (!columns.contains('iccid')) {
      throw const FormatException('Nekoko profile_metadata 缺少 ICCID 字段');
    }

    final selected = <String>[
      'iccid',
      for (final name in const [
        'nickname',
        'name',
        'providerName',
        'mcc',
        'mnc',
        'enabled',
        'profileClass',
        'profileSize',
        'gid1',
        'gid2',
        'tags',
        'lastSeen',
        'eid',
      ])
        if (columns.contains(name)) name,
    ];
    final rows = database.select(
      'SELECT ${selected.map(_quotedIdentifier).join(', ')} '
      'FROM profile_metadata ORDER BY ${columns.contains('lastSeen') ? 'lastSeen DESC' : 'iccid'}',
    );
    final msisdnByIccid = <String, String>{};
    if (tables.contains('profile_msisdn')) {
      final msisdnColumns = {
        for (final row in database.select('PRAGMA table_info(profile_msisdn)'))
          row['name'] as String,
      };
      if (msisdnColumns.containsAll({'iccid', 'msisdn'})) {
        for (final row in database.select(
          'SELECT iccid, msisdn FROM profile_msisdn',
        )) {
          final iccid = _text(row['iccid']);
          final msisdn = _text(row['msisdn']);
          if (iccid != null && msisdn != null) msisdnByIccid[iccid] = msisdn;
        }
      }
    }
    final installedSizeByIccid = <String, int>{};
    if (tables.contains('profile_storage')) {
      final storageColumns = {
        for (final row in database.select('PRAGMA table_info(profile_storage)'))
          row['name'] as String,
      };
      if (storageColumns.containsAll({'iccid', 'spaceConsumed'})) {
        for (final row in database.select(
          'SELECT iccid, spaceConsumed FROM profile_storage',
        )) {
          final iccid = _text(row['iccid']);
          final size = _integer(row['spaceConsumed']);
          if (iccid != null && size != null && size >= 0) {
            installedSizeByIccid[iccid] = size;
          }
        }
      }
    }

    final issues = <NekokoImportIssue>[];
    final subscriptions = <Subscription>[];
    final cardsToWrite = <SimCard>[];
    final eidsToWrite = <Euicc>[];
    final profilesToWrite = <EsimProfile>[];
    final subscriptionsByIccid = <String, Subscription>{
      for (final item in existingSubscriptions)
        if (_text(item.iccid) case final String iccid) iccid: item,
    };
    final eidsByValue = <String, Euicc>{
      for (final item in existingAssets.eids) item.value: item,
    };
    final profilesByIccid = <String, EsimProfile>{
      for (final item in existingAssets.profiles)
        if (_text(item.iccid) case final String iccid) iccid: item,
    };
    final importedSubscriptionIds = <String>{};
    final now = _nowUtc().toUtc();

    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final iccid = _text(row['iccid']);
      if (iccid == null) {
        issues.add(
          NekokoImportIssue(record: index + 1, message: 'ICCID 为空，本条已跳过'),
        );
        continue;
      }
      final updatedAt = _millisecondTimestamp(row['lastSeen']) ?? now;
      final providerName = _text(row['providerName']);
      final sourceName = _text(row['name']);
      final provider = providerName ?? sourceName;
      final nickname = _text(row['nickname']);
      final rawTags = _text(row['tags']);
      final interoperableNickname = _mergeNicknameTags(nickname, rawTags);
      final profileName =
          _plainProfileName(nickname) ??
          (sourceName != providerName ? sourceName : null);
      final tags = _plainTags([nickname, rawTags]);
      final msisdn = msisdnByIccid[iccid];
      final profileClassCode = _integer(row['profileClass']);
      final declaredProfileSize = _integer(row['profileSize']);
      final installedProfileSize = installedSizeByIccid[iccid];
      final gid1 = _text(row['gid1']);
      final gid2 = _text(row['gid2']);
      final deviceState = switch (row['enabled']) {
        1 => ProfileDeviceState.enabled,
        0 => ProfileDeviceState.disabled,
        _ => ProfileDeviceState.unknown,
      };
      var subscription = subscriptionsByIccid[iccid];
      if (subscription != null) {
        final mergedTags = {...subscription.tags, ...tags}.toList();
        subscription = subscription.copyWith(
          operator: subscription.operator ?? provider,
          lifecycle: subscription.lifecycle.copyWith(deviceState: deviceState),
          tags: mergedTags,
          details: subscription.details.copyWith(
            profileName: subscription.details.profileName ?? profileName,
            profileClassCode:
                subscription.details.profileClassCode ?? profileClassCode,
            declaredProfileSizeBytes:
                subscription.details.declaredProfileSizeBytes ??
                declaredProfileSize,
            installedProfileSizeBytes:
                subscription.details.installedProfileSizeBytes ??
                installedProfileSize,
            gid1: subscription.details.gid1 ?? gid1,
            gid2: subscription.details.gid2 ?? gid2,
            mcc: subscription.details.mcc ?? _text(row['mcc']),
            mnc: subscription.details.mnc ?? _text(row['mnc']),
          ),
          updatedAt: subscription.updatedAt.isAfter(updatedAt)
              ? subscription.updatedAt
              : updatedAt,
        );
      } else {
        var number = const PhoneNumber.unknown();
        if (msisdn != null) {
          try {
            number = PhoneNumber(msisdn);
          } on ArgumentError {
            issues.add(
              NekokoImportIssue(
                record: index + 1,
                message: '缓存号码格式无效，已保留 Profile 但号码留空',
              ),
            );
          }
        }
        subscription = Subscription(
          id: _idFactory(),
          iccid: iccid,
          number: number,
          operator: provider,
          lifecycle: ProfileLifecycle(deviceState: deviceState),
          plan: Plan(),
          keepAlive: msisdn == null
              ? KeepAlive.notRequired()
              : KeepAlive(required: true, confidence: DataConfidence.confirmed),
          tags: tags,
          details: SubscriptionDetails(
            profileName: profileName,
            profileClassCode: profileClassCode,
            declaredProfileSizeBytes: declaredProfileSize,
            installedProfileSizeBytes: installedProfileSize,
            gid1: gid1,
            gid2: gid2,
            mcc: _text(row['mcc']),
            mnc: _text(row['mnc']),
          ),
          timeZoneId: defaultTimeZoneId,
          createdAt: updatedAt,
          updatedAt: updatedAt,
        );
      }
      if (importedSubscriptionIds.add(subscription.id)) {
        subscriptions.add(subscription);
        subscriptionsByIccid[iccid] = subscription;
      }

      final eidValue = _text(row['eid']);
      if (eidValue == null) {
        issues.add(
          NekokoImportIssue(
            record: index + 1,
            message: '缺少 EID；订阅资料可导入，但无法建立 Profile 资产关系',
          ),
        );
        continue;
      }
      var eid = eidsByValue[eidValue];
      if (eid == null) {
        final cardId = 'nekoko-card:$eidValue';
        final eidId = 'nekoko-eid:$eidValue';
        cardsToWrite.add(
          RemovableEuiccCard(
            id: cardId,
            name: provider == null ? 'Nekoko eUICC' : '$provider eUICC',
            note: '由 Nekoko 数据库备份导入，当前位于库存',
            createdAt: updatedAt,
            updatedAt: updatedAt,
          ),
        );
        eid = Euicc(
          id: eidId,
          cardId: cardId,
          value: eidValue,
          label: provider,
          createdAt: updatedAt,
          updatedAt: updatedAt,
        );
        eidsToWrite.add(eid);
        eidsByValue[eidValue] = eid;
      }
      final existingProfile = profilesByIccid[iccid];
      final profile = EsimProfile(
        id: existingProfile?.id ?? 'nekoko-profile:$iccid',
        eidId: eid.id,
        iccid: iccid,
        operatorName: provider ?? existingProfile?.operatorName,
        nickname: interoperableNickname ?? existingProfile?.nickname,
        subscriptionId: subscription.id,
        createdAt: existingProfile?.createdAt ?? updatedAt,
        updatedAt:
            existingProfile != null &&
                existingProfile.updatedAt.isAfter(updatedAt)
            ? existingProfile.updatedAt
            : updatedAt,
      );
      profilesToWrite.add(profile);
      profilesByIccid[iccid] = profile;
    }

    return NekokoImportReport(
      sourceProfileCount: rows.length,
      subscriptions: subscriptions,
      assets: AssetInventory(
        cards: cardsToWrite,
        eids: eidsToWrite,
        profiles: profilesToWrite,
      ),
      issues: issues,
    );
  }

  static List<String> _plainTags(Iterable<String?> sources) {
    final result = <String>{};
    for (final source in sources) {
      if (source == null) continue;
      final decoded = NekokoTagCodec.decode(source);
      for (final tag in decoded.tags) {
        if (tag case NekokoTextTag(value: final value)) result.add(value);
      }
    }
    return result.toList();
  }

  static String? _mergeNicknameTags(String? nickname, String? rawTags) {
    if (rawTags == null) return nickname;
    if (nickname == null) return rawTags;
    final missing = rawTags
        .split(RegExp(r'\s+'))
        .where((tag) => tag.isNotEmpty && !nickname.contains(tag));
    final suffix = missing.join(' ');
    return suffix.isEmpty ? nickname : '$nickname $suffix';
  }

  static String? _plainProfileName(String? nickname) {
    if (nickname == null) return null;
    final value = NekokoTagCodec.replaceTags(nickname, const []).trim();
    return value.isEmpty ? null : value;
  }

  static DateTime? _millisecondTimestamp(Object? value) {
    final milliseconds = switch (value) {
      int() => value,
      String() => int.tryParse(value),
      _ => null,
    };
    if (milliseconds == null || milliseconds <= 0) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    } on RangeError {
      return null;
    }
  }

  static String? _text(Object? value) {
    final text = value is String ? value.trim() : null;
    return text == null || text.isEmpty ? null : text;
  }

  static int? _integer(Object? value) => switch (value) {
    int() => value,
    String() => int.tryParse(value.trim()),
    _ => null,
  };

  static String _quotedIdentifier(String value) =>
      '"${value.replaceAll('"', '""')}"';

  static DateTime _systemNowUtc() => DateTime.now().toUtc();

  static int _counter = 0;
  static String _fallbackId() =>
      'nekoko-import-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
}
