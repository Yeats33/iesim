import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/euicc_card_presets.dart';

enum EuiccCardPresetSource { network, cache, builtIn }

class EuiccCardPresetLoadResult {
  const EuiccCardPresetLoadResult({
    required this.catalog,
    required this.source,
    required this.loadedAt,
    this.warning,
  });

  final EuiccCardPresetCatalog catalog;
  final EuiccCardPresetSource source;
  final DateTime loadedAt;
  final String? warning;
}

class EuiccCardPresetResponse {
  const EuiccCardPresetResponse({
    required this.statusCode,
    this.body = '',
    this.etag,
  });

  final int statusCode;
  final String body;
  final String? etag;
}

abstract interface class EuiccCardPresetTransport {
  Future<EuiccCardPresetResponse> get(Uri uri, {String? etag});
}

class HttpEuiccCardPresetTransport implements EuiccCardPresetTransport {
  static const _maxBytes = 512 * 1024;

  @override
  Future<EuiccCardPresetResponse> get(Uri uri, {String? etag}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'iesim/0.0.3 euicc-card-presets',
      );
      if (etag != null && etag.isNotEmpty) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode == HttpStatus.notModified) {
        return EuiccCardPresetResponse(
          statusCode: response.statusCode,
          etag: response.headers.value(HttpHeaders.etagHeader),
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('eUICC 预设源返回 ${response.statusCode}', uri: uri);
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBytes) {
          throw const FormatException('eUICC 预设超过 512 KiB 大小限制');
        }
      }
      return EuiccCardPresetResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
        etag: response.headers.value(HttpHeaders.etagHeader),
      );
    } finally {
      client.close(force: true);
    }
  }
}

typedef EuiccCardPresetPreferencesLoader = Future<SharedPreferences> Function();

class EuiccCardPresetService {
  EuiccCardPresetService({
    Uri? sourceUri,
    EuiccCardPresetTransport? transport,
    EuiccCardPresetPreferencesLoader? preferencesLoader,
  }) : sourceUri = sourceUri ?? defaultSourceUri,
       _transport = transport ?? HttpEuiccCardPresetTransport(),
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance {
    if (this.sourceUri.scheme.toLowerCase() != 'https' ||
        !this.sourceUri.hasAuthority) {
      throw const FormatException('eUICC 预设地址必须是有效的 HTTPS 地址');
    }
  }

  static const _configuredSource = String.fromEnvironment(
    'IESIM_EUICC_CARD_PRESET_URL',
    defaultValue:
        'https://raw.githubusercontent.com/Yeats33/iesim-presets/main/catalog/v1/euicc-cards.json',
  );
  static final defaultSourceUri = Uri.parse(_configuredSource);

  static const _bodyKey = 'euicc_card_presets_v1_body';
  static const _etagKey = 'euicc_card_presets_v1_etag';
  static const _loadedAtKey = 'euicc_card_presets_v1_loaded_at';

  final Uri sourceUri;
  final EuiccCardPresetTransport _transport;
  final EuiccCardPresetPreferencesLoader _preferencesLoader;
  Future<EuiccCardPresetLoadResult>? _loadInFlight;

  Future<EuiccCardPresetLoadResult> loadCachedOrBuiltIn() async {
    final preferences = await _preferencesLoader();
    return _readCache(preferences) ?? _builtInResult();
  }

  Future<EuiccCardPresetLoadResult> load() =>
      _loadInFlight ??= _load().whenComplete(() => _loadInFlight = null);

  Future<EuiccCardPresetLoadResult> _load() async {
    final preferences = await _preferencesLoader();
    final cached = _readCache(preferences);
    final baseline = cached ?? _builtInResult();
    try {
      final response = await _transport.get(
        sourceUri,
        etag: preferences.getString(_etagKey),
      );
      if (response.statusCode == HttpStatus.notModified) {
        if (cached == null) {
          throw const FormatException('eUICC 预设源未返回内容，本地也没有可用缓存');
        }
        return cached;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('eUICC 预设源返回 ${response.statusCode}');
      }
      final catalog = EuiccCardPresetCatalog.decode(response.body);
      if (catalog.updatedAt.isBefore(baseline.catalog.updatedAt)) {
        throw FormatException(
          '远端目录 ${catalog.catalogVersion} 早于本机已知版本 '
          '${baseline.catalog.catalogVersion}，已拒绝回滚',
        );
      }
      final now = DateTime.now().toUtc();
      await preferences.setString(_bodyKey, response.body);
      if (response.etag case final etag? when etag.isNotEmpty) {
        await preferences.setString(_etagKey, etag);
      } else {
        await preferences.remove(_etagKey);
      }
      await preferences.setInt(_loadedAtKey, now.millisecondsSinceEpoch);
      return EuiccCardPresetLoadResult(
        catalog: catalog,
        source: EuiccCardPresetSource.network,
        loadedAt: now,
      );
    } catch (error) {
      return EuiccCardPresetLoadResult(
        catalog: baseline.catalog,
        source: baseline.source,
        loadedAt: baseline.loadedAt,
        warning:
            '在线 eUICC 型号库暂时不可用，已使用'
            '${baseline.source == EuiccCardPresetSource.cache ? '本地缓存' : 'ieSIM 内置目录'}：$error',
      );
    }
  }

  EuiccCardPresetLoadResult? _readCache(SharedPreferences preferences) {
    final body = preferences.getString(_bodyKey);
    if (body == null) return null;
    try {
      final catalog = EuiccCardPresetCatalog.decode(body);
      if (catalog.updatedAt.isBefore(builtInEuiccCardPresetCatalog.updatedAt)) {
        return null;
      }
      final loadedAt = preferences.getInt(_loadedAtKey);
      return EuiccCardPresetLoadResult(
        catalog: catalog,
        source: EuiccCardPresetSource.cache,
        loadedAt: loadedAt == null
            ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
            : DateTime.fromMillisecondsSinceEpoch(loadedAt, isUtc: true),
      );
    } on FormatException {
      return null;
    }
  }

  static EuiccCardPresetLoadResult _builtInResult() =>
      EuiccCardPresetLoadResult(
        catalog: builtInEuiccCardPresetCatalog,
        source: EuiccCardPresetSource.builtIn,
        loadedAt: builtInEuiccCardPresetCatalog.updatedAt,
      );
}
