import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:iesim_core/iesim_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CarrierPresetSource { network, cache, builtIn }

class CarrierPresetLoadResult {
  const CarrierPresetLoadResult({
    required this.catalog,
    required this.source,
    required this.loadedAt,
    this.warning,
  });

  final CarrierPresetCatalog catalog;
  final CarrierPresetSource source;
  final DateTime loadedAt;
  final String? warning;
}

class CarrierPresetResponse {
  const CarrierPresetResponse({
    required this.statusCode,
    this.body = '',
    this.etag,
  });

  final int statusCode;
  final String body;
  final String? etag;
}

abstract interface class CarrierPresetTransport {
  Future<CarrierPresetResponse> get(Uri uri, {String? etag});
}

class HttpCarrierPresetTransport implements CarrierPresetTransport {
  static const _maxBytes = 2 * 1024 * 1024;

  @override
  Future<CarrierPresetResponse> get(Uri uri, {String? etag}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'iesim/0.0.1-bate carrier-presets',
      );
      if (etag != null && etag.isNotEmpty) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode == HttpStatus.notModified) {
        return CarrierPresetResponse(
          statusCode: response.statusCode,
          etag: response.headers.value(HttpHeaders.etagHeader),
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('运营商预设源返回 ${response.statusCode}', uri: uri);
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBytes) {
          throw const FormatException('运营商预设超过 2 MB 大小限制');
        }
      }
      return CarrierPresetResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
        etag: response.headers.value(HttpHeaders.etagHeader),
      );
    } finally {
      client.close(force: true);
    }
  }
}

typedef CarrierPresetPreferencesLoader = Future<SharedPreferences> Function();

class CarrierPresetService {
  CarrierPresetService({
    Uri? sourceUri,
    CarrierPresetTransport? transport,
    CarrierPresetPreferencesLoader? preferencesLoader,
  }) : sourceUri = sourceUri ?? defaultSourceUri,
       _transport = transport ?? HttpCarrierPresetTransport(),
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance {
    if (this.sourceUri.scheme.toLowerCase() != 'https' ||
        !this.sourceUri.hasAuthority) {
      throw const FormatException('运营商预设地址必须是有效的 HTTPS 地址');
    }
  }

  static const _configuredSource = String.fromEnvironment(
    'IESIM_CARRIER_PRESET_URL',
    defaultValue:
        'https://raw.githubusercontent.com/Yeats33/iesim-presets/main/catalog/v1/carriers.json',
  );
  static final defaultSourceUri = Uri.parse(_configuredSource);

  static const _bodyKey = 'carrier_presets_v1_body';
  static const _etagKey = 'carrier_presets_v1_etag';
  static const _loadedAtKey = 'carrier_presets_v1_loaded_at';

  static final builtInCatalog = CarrierPresetCatalog.decode(_builtInSource);

  final Uri sourceUri;
  final CarrierPresetTransport _transport;
  final CarrierPresetPreferencesLoader _preferencesLoader;

  Future<CarrierPresetLoadResult> load() async {
    final preferences = await _preferencesLoader();
    final cached = _readCache(preferences);
    try {
      final response = await _transport.get(
        sourceUri,
        etag: preferences.getString(_etagKey),
      );
      if (response.statusCode == HttpStatus.notModified) {
        if (cached == null) {
          throw const FormatException('预设源未返回内容，本地也没有可用缓存');
        }
        return cached;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('运营商预设源返回 ${response.statusCode}');
      }
      final catalog = CarrierPresetCatalog.decode(response.body);
      final now = DateTime.now().toUtc();
      await preferences.setString(_bodyKey, response.body);
      if (response.etag case final etag? when etag.isNotEmpty) {
        await preferences.setString(_etagKey, etag);
      } else {
        await preferences.remove(_etagKey);
      }
      await preferences.setInt(_loadedAtKey, now.millisecondsSinceEpoch);
      return CarrierPresetLoadResult(
        catalog: catalog,
        source: CarrierPresetSource.network,
        loadedAt: now,
      );
    } catch (error) {
      if (cached != null) {
        return CarrierPresetLoadResult(
          catalog: cached.catalog,
          source: CarrierPresetSource.cache,
          loadedAt: cached.loadedAt,
          warning: '在线目录暂时不可用，已使用本地缓存：$error',
        );
      }
      return CarrierPresetLoadResult(
        catalog: builtInCatalog,
        source: CarrierPresetSource.builtIn,
        loadedAt: builtInCatalog.updatedAt,
        warning: '在线目录暂时不可用，已使用 ieSIM 内置预设：$error',
      );
    }
  }

  CarrierPresetLoadResult? _readCache(SharedPreferences preferences) {
    final body = preferences.getString(_bodyKey);
    if (body == null) return null;
    try {
      final loadedAt = preferences.getInt(_loadedAtKey);
      return CarrierPresetLoadResult(
        catalog: CarrierPresetCatalog.decode(body),
        source: CarrierPresetSource.cache,
        loadedAt: loadedAt == null
            ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
            : DateTime.fromMillisecondsSinceEpoch(loadedAt, isUtc: true),
      );
    } on FormatException {
      return null;
    }
  }

  static const _builtInSource = r'''
{
  "schemaVersion": 1,
  "catalogVersion": "2026.08.08.1",
  "updatedAt": "2026-08-08T00:00:00.000Z",
  "carriers": [
    {
      "id": "ctexcel-uk",
      "displayName": "CTExcel UK",
      "operatorName": "CTExcel",
      "countryCode": "GB",
      "countryName": "英国",
      "flag": "🇬🇧",
      "timeZoneId": "Europe/London",
      "websiteUrl": "https://www.ctexcel.com/uk/guaranteeNum",
      "aliases": ["China Telecom Europe", "中国电信欧洲", "CTExcel 英国"],
      "keepAlive": {
        "cycleDays": 90,
        "qualifyingActions": [
          "mobileData",
          "sms",
          "call",
          "topUp",
          "planPurchase"
        ],
        "summary": "连续 90 天未使用任何 CTExcel 服务，号码可能被终止；流量、短信、通话、充值或订购套餐均可重置周期。回国年套餐在套餐截止日前包含保号，此后适用 90 天规则。",
        "constraints": [
          {
            "kind": "firstUse",
            "title": "激活后首次使用",
            "details": "英国卡激活后需在英国或欧盟产生使用记录，否则号码会被停用。",
            "withinDays": 10,
            "regions": ["英国", "欧盟"]
          },
          {
            "kind": "afterPlanExpiry",
            "title": "短期旅行套餐续订",
            "details": "短期回国或欧洲套餐到期后若未续订，号码会被终止。",
            "withinDays": 15
          },
          {
            "kind": "paidRetention",
            "title": "付费保号服务（可选）",
            "details": "可按 £1/月进入休眠保号；需一次性预付所选期间，最短按一个自然月计费。"
          }
        ],
        "presetId": "ctexcel-uk",
        "sourceLabel": "CTExcel UK 官网保号服务与 eSIM FAQ",
        "sourceUrl": "https://www.ctexcel.com/uk/guaranteeNum",
        "sourceCheckedAt": "2026-08-08T00:00:00.000Z"
      }
    },
    {
      "id": "esim-gg-estonia",
      "displayName": "eSIM.gg +372",
      "operatorName": "eSIM.gg",
      "countryCode": "EE",
      "countryName": "爱沙尼亚",
      "flag": "🇪🇪",
      "timeZoneId": "Europe/Tallinn",
      "websiteUrl": "https://esim.gg/support/faq",
      "aliases": ["eSIM.GG", "Elisa Prepaid", "+372"],
      "keepAlive": {
        "cycleDays": 365,
        "qualifyingActions": ["mobileData", "call", "sms", "topUp"],
        "summary": "每 365 天至少完成一次有效动作；使用流量、通话、短信或充值都会重置周期。365 天无有效动作，号码可能被释放；也可启用自动延长。",
        "constraints": [],
        "presetId": "esim-gg-estonia",
        "sourceLabel": "eSIM.gg 官方 FAQ 与号码有效期说明",
        "sourceUrl": "https://esim.gg/support/faq",
        "sourceCheckedAt": "2026-08-08T00:00:00.000Z"
      }
    }
  ]
}
''';
}
