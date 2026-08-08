import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:iesim_core/iesim_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileCatalogResponse {
  const ProfileCatalogResponse({
    required this.statusCode,
    this.body = '',
    this.etag,
  });

  final int statusCode;
  final String body;
  final String? etag;
}

abstract interface class ProfileCatalogTransport {
  Future<ProfileCatalogResponse> get(Uri uri, {String? etag});
}

class HttpProfileCatalogTransport implements ProfileCatalogTransport {
  static const _maxBytes = 5 * 1024 * 1024;

  @override
  Future<ProfileCatalogResponse> get(Uri uri, {String? etag}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'iesim/0.0.1-alpha profile-size-catalog',
      );
      if (etag != null && etag.isNotEmpty) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode == HttpStatus.notModified) {
        return ProfileCatalogResponse(
          statusCode: response.statusCode,
          etag: response.headers.value(HttpHeaders.etagHeader),
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('数据源返回 ${response.statusCode}', uri: uri);
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBytes) {
          throw const FormatException('Profile 容量库超过大小限制');
        }
      }
      return ProfileCatalogResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
        etag: response.headers.value(HttpHeaders.etagHeader),
      );
    } finally {
      client.close(force: true);
    }
  }
}

typedef ProfileCatalogPreferencesLoader = Future<SharedPreferences> Function();

class ProfileCatalogService {
  ProfileCatalogService({
    ProfileCatalogTransport? transport,
    ProfileCatalogPreferencesLoader? preferencesLoader,
  }) : _transport = transport ?? HttpProfileCatalogTransport(),
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static final sourceUri = Uri.parse(
    'https://stats-backend.euicc.info/data/euicc_sizes.json',
  );
  static const sourceName = 'euicc.info Profile Sizes';
  static const sourceDescription = 'Profile 容量估算；不同 eUICC / EUM 的占用可能不同';

  static const _bodyKey = 'euicc_info_profile_sizes_body_v1';
  static const _etagKey = 'euicc_info_profile_sizes_etag_v1';

  final ProfileCatalogTransport _transport;
  final ProfileCatalogPreferencesLoader _preferencesLoader;
  ProfileCatalog? _memoryCatalog;

  Future<ProfileCatalogMatch> lookup(LpaActivation activation) async {
    final catalog = _memoryCatalog ??= await _loadCatalog();
    return catalog.match(activation);
  }

  Future<ProfileCatalog> _loadCatalog() async {
    final preferences = await _preferencesLoader();
    final cachedBody = preferences.getString(_bodyKey);
    try {
      final response = await _transport.get(
        sourceUri,
        etag: preferences.getString(_etagKey),
      );
      if (response.statusCode == HttpStatus.notModified) {
        if (cachedBody == null) {
          throw const FormatException('容量库未返回内容，本地也没有缓存');
        }
        return ProfileCatalog.decode(cachedBody);
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('数据源返回 ${response.statusCode}');
      }

      // Validate before replacing the last-known-good catalog.
      final catalog = ProfileCatalog.decode(response.body);
      await preferences.setString(_bodyKey, response.body);
      if (response.etag case final etag? when etag.isNotEmpty) {
        await preferences.setString(_etagKey, etag);
      } else {
        await preferences.remove(_etagKey);
      }
      return catalog;
    } catch (_) {
      if (cachedBody != null) {
        try {
          return ProfileCatalog.decode(cachedBody);
        } on FormatException {
          // The cache is unusable; preserve the original network error below.
        }
      }
      rethrow;
    }
  }
}
