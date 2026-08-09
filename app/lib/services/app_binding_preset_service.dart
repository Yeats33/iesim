import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:iesim_core/iesim_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppBindingPresetSource { network, cache, builtIn }

class AppBindingPresetLoadResult {
  const AppBindingPresetLoadResult({
    required this.catalog,
    required this.source,
    required this.loadedAt,
    this.warning,
  });

  final AppBindingPresetCatalog catalog;
  final AppBindingPresetSource source;
  final DateTime loadedAt;
  final String? warning;
}

class AppBindingPresetResponse {
  const AppBindingPresetResponse({
    required this.statusCode,
    this.body = '',
    this.etag,
  });

  final int statusCode;
  final String body;
  final String? etag;
}

abstract interface class AppBindingPresetTransport {
  Future<AppBindingPresetResponse> get(Uri uri, {String? etag});
}

class HttpAppBindingPresetTransport implements AppBindingPresetTransport {
  static const _maxBytes = 2 * 1024 * 1024;

  @override
  Future<AppBindingPresetResponse> get(Uri uri, {String? etag}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'iesim/0.0.1-bate app-binding-presets',
      );
      if (etag != null && etag.isNotEmpty) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode == HttpStatus.notModified) {
        return AppBindingPresetResponse(
          statusCode: response.statusCode,
          etag: response.headers.value(HttpHeaders.etagHeader),
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('App 绑定预设源返回 ${response.statusCode}', uri: uri);
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBytes) {
          throw const FormatException('App 绑定预设超过 2 MB 大小限制');
        }
      }
      return AppBindingPresetResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
        etag: response.headers.value(HttpHeaders.etagHeader),
      );
    } finally {
      client.close(force: true);
    }
  }
}

typedef AppBindingPresetPreferencesLoader =
    Future<SharedPreferences> Function();

class AppBindingPresetService {
  AppBindingPresetService({
    Uri? sourceUri,
    AppBindingPresetTransport? transport,
    AppBindingPresetPreferencesLoader? preferencesLoader,
  }) : sourceUri = sourceUri ?? defaultSourceUri,
       _transport = transport ?? HttpAppBindingPresetTransport(),
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance {
    if (this.sourceUri.scheme.toLowerCase() != 'https' ||
        !this.sourceUri.hasAuthority) {
      throw const FormatException('App 绑定预设地址必须是有效的 HTTPS 地址');
    }
  }

  static const _configuredSource = String.fromEnvironment(
    'IESIM_APP_BINDING_PRESET_URL',
    defaultValue:
        'https://raw.githubusercontent.com/Yeats33/iesim-presets/main/catalog/v1/app-bindings.json',
  );
  static final defaultSourceUri = Uri.parse(_configuredSource);

  static const _bodyKey = 'app_binding_presets_v1_body';
  static const _etagKey = 'app_binding_presets_v1_etag';
  static const _loadedAtKey = 'app_binding_presets_v1_loaded_at';

  static final builtInCatalog = AppBindingPresetCatalog.decode(_builtInSource);

  final Uri sourceUri;
  final AppBindingPresetTransport _transport;
  final AppBindingPresetPreferencesLoader _preferencesLoader;

  Future<AppBindingPresetLoadResult> load() async {
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
        throw HttpException('App 绑定预设源返回 ${response.statusCode}');
      }
      final catalog = AppBindingPresetCatalog.decode(response.body);
      final now = DateTime.now().toUtc();
      await preferences.setString(_bodyKey, response.body);
      if (response.etag case final etag? when etag.isNotEmpty) {
        await preferences.setString(_etagKey, etag);
      } else {
        await preferences.remove(_etagKey);
      }
      await preferences.setInt(_loadedAtKey, now.millisecondsSinceEpoch);
      return AppBindingPresetLoadResult(
        catalog: catalog,
        source: AppBindingPresetSource.network,
        loadedAt: now,
      );
    } catch (error) {
      if (cached != null) {
        return AppBindingPresetLoadResult(
          catalog: cached.catalog,
          source: AppBindingPresetSource.cache,
          loadedAt: cached.loadedAt,
          warning: '在线目录暂时不可用，已使用本地缓存：$error',
        );
      }
      return AppBindingPresetLoadResult(
        catalog: builtInCatalog,
        source: AppBindingPresetSource.builtIn,
        loadedAt: builtInCatalog.updatedAt,
        warning: '在线目录暂时不可用，已使用 ieSIM 内置预设：$error',
      );
    }
  }

  AppBindingPresetLoadResult? _readCache(SharedPreferences preferences) {
    final body = preferences.getString(_bodyKey);
    if (body == null) return null;
    try {
      final loadedAt = preferences.getInt(_loadedAtKey);
      return AppBindingPresetLoadResult(
        catalog: AppBindingPresetCatalog.decode(body),
        source: AppBindingPresetSource.cache,
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
  "catalogVersion": "2026.08.09.1",
  "updatedAt": "2026-08-09T00:00:00.000Z",
  "apps": [
    {
      "id": "whatsapp",
      "displayName": "WhatsApp Messenger",
      "developerName": "WhatsApp LLC",
      "description": "使用手机号码注册的消息与通话应用；部分地区通过短信或语音完成号码验证。",
      "websiteUrl": "https://www.whatsapp.com/",
      "iconUrl": "https://play-lh.googleusercontent.com/Gqxk4T0uZsDwFp07DE-508hkyvcNmgFuRwPiwTEfF7D7OzGv1FdHDzEyMxNsSBZLOJlGpe3ULvVM2RgrRAlBqA",
      "aliases": ["WhatsApp", "Whats App", "WA"],
      "defaultPurposes": ["messaging", "verification"],
      "verificationChannels": ["sms", "voiceCall"],
      "verificationNote": "WhatsApp 可能通过短信或语音来电验证号码；ieSIM 仅记录绑定与验证状态，不读取验证码。",
      "appStore": {
        "appId": "310633997",
        "bundleId": "net.whatsapp.WhatsApp",
        "url": "https://apps.apple.com/app/whatsapp-messenger/id310633997"
      },
      "googlePlay": {
        "packageName": "com.whatsapp",
        "url": "https://play.google.com/store/apps/details?id=com.whatsapp"
      }
    }
  ]
}
''';
}
