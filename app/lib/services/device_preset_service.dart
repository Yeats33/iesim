import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:iesim_core/iesim_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DevicePresetSource { network, cache }

class DevicePresetLoadResult {
  const DevicePresetLoadResult({
    required this.catalog,
    required this.source,
    required this.loadedAt,
    this.warning,
  });

  final DevicePresetCatalog catalog;
  final DevicePresetSource source;
  final DateTime loadedAt;
  final String? warning;
}

class DevicePresetResponse {
  const DevicePresetResponse({
    required this.statusCode,
    this.body = '',
    this.etag,
  });

  final int statusCode;
  final String body;
  final String? etag;
}

abstract interface class DevicePresetTransport {
  Future<DevicePresetResponse> get(Uri uri, {String? etag});
}

class HttpDevicePresetTransport implements DevicePresetTransport {
  static const _maxBytes = 2 * 1024 * 1024;

  @override
  Future<DevicePresetResponse> get(Uri uri, {String? etag}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'iesim/0.0.1-alpha device-presets',
      );
      if (etag != null && etag.isNotEmpty) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode == HttpStatus.notModified) {
        return DevicePresetResponse(
          statusCode: response.statusCode,
          etag: response.headers.value(HttpHeaders.etagHeader),
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('设备预设源返回 ${response.statusCode}', uri: uri);
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBytes) {
          throw const FormatException('设备预设超过 2 MB 大小限制');
        }
      }
      return DevicePresetResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
        etag: response.headers.value(HttpHeaders.etagHeader),
      );
    } finally {
      client.close(force: true);
    }
  }
}

typedef DevicePresetPreferencesLoader = Future<SharedPreferences> Function();

class DevicePresetService {
  DevicePresetService({
    Uri? sourceUri,
    DevicePresetTransport? transport,
    DevicePresetPreferencesLoader? preferencesLoader,
  }) : sourceUri = sourceUri ?? defaultSourceUri,
       _transport = transport ?? HttpDevicePresetTransport(),
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance {
    if (this.sourceUri.scheme.toLowerCase() != 'https' ||
        !this.sourceUri.hasAuthority) {
      throw const FormatException('设备预设地址必须是有效的 HTTPS 地址');
    }
  }

  static const _configuredSource = String.fromEnvironment(
    'IESIM_DEVICE_PRESET_URL',
    defaultValue:
        'https://raw.githubusercontent.com/Yeats33/iesim-presets/main/catalog/v1/devices.json',
  );
  static final defaultSourceUri = Uri.parse(_configuredSource);

  static const _bodyKey = 'device_presets_v1_body';
  static const _etagKey = 'device_presets_v1_etag';
  static const _loadedAtKey = 'device_presets_v1_loaded_at';

  final Uri sourceUri;
  final DevicePresetTransport _transport;
  final DevicePresetPreferencesLoader _preferencesLoader;

  Future<DevicePresetLoadResult> load() async {
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
        throw HttpException('设备预设源返回 ${response.statusCode}');
      }

      // Parse before writing so a broken remote update never replaces the
      // last-known-good catalog.
      final catalog = DevicePresetCatalog.decode(response.body);
      final now = DateTime.now().toUtc();
      await preferences.setString(_bodyKey, response.body);
      if (response.etag case final etag? when etag.isNotEmpty) {
        await preferences.setString(_etagKey, etag);
      } else {
        await preferences.remove(_etagKey);
      }
      await preferences.setInt(_loadedAtKey, now.millisecondsSinceEpoch);
      return DevicePresetLoadResult(
        catalog: catalog,
        source: DevicePresetSource.network,
        loadedAt: now,
      );
    } catch (error) {
      if (cached != null) {
        return DevicePresetLoadResult(
          catalog: cached.catalog,
          source: DevicePresetSource.cache,
          loadedAt: cached.loadedAt,
          warning: '在线目录暂时不可用，已使用本地缓存：$error',
        );
      }
      rethrow;
    }
  }

  DevicePresetLoadResult? _readCache(SharedPreferences preferences) {
    final body = preferences.getString(_bodyKey);
    if (body == null) return null;
    try {
      final loadedAt = preferences.getInt(_loadedAtKey);
      return DevicePresetLoadResult(
        catalog: DevicePresetCatalog.decode(body),
        source: DevicePresetSource.cache,
        loadedAt: loadedAt == null
            ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
            : DateTime.fromMillisecondsSinceEpoch(loadedAt, isUtc: true),
      );
    } on FormatException {
      return null;
    }
  }
}
