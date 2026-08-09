import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:iesim_core/iesim_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OperatorResourceResponse {
  const OperatorResourceResponse({
    required this.statusCode,
    this.bodyBytes = const [],
    this.etag,
  });

  final int statusCode;
  final List<int> bodyBytes;
  final String? etag;
}

abstract interface class OperatorIdentityTransport {
  Future<OperatorResourceResponse> get(Uri uri, {String? etag});
}

class HttpOperatorIdentityTransport implements OperatorIdentityTransport {
  @override
  Future<OperatorResourceResponse> get(Uri uri, {String? etag}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'iesim/0.0.1-alpha operator-identity',
      );
      if (etag != null) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > OperatorIdentityService.maximumIconBytes) {
          throw const FormatException('运营商目录或 Logo 超过大小限制');
        }
      }
      return OperatorResourceResponse(
        statusCode: response.statusCode,
        bodyBytes: bytes,
        etag: response.headers.value(HttpHeaders.etagHeader),
      );
    } finally {
      client.close(force: true);
    }
  }
}

abstract interface class OperatorIconStore {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
}

class FileOperatorIconStore implements OperatorIconStore {
  Future<Directory> _directory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'operator-icons-v1'));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<Uint8List?> read(String key) async {
    final file = File(p.join((await _directory()).path, '$key.png'));
    if (!await file.exists()) return null;
    final length = await file.length();
    if (length <= 0 || length > OperatorIdentityService.maximumIconBytes) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final file = File(p.join((await _directory()).path, '$key.png'));
    await file.writeAsBytes(bytes, flush: true);
  }
}

class OperatorIdentity {
  const OperatorIdentity({
    required this.match,
    this.iconUri,
    this.iconBytes,
    this.iconFromCache = false,
  });

  final OperatorCatalogMatch match;
  final Uri? iconUri;
  final Uint8List? iconBytes;
  final bool iconFromCache;

  String get displayName => match.displayName;
  String get operatorName => match.operatorName;
  String get brand => match.brand;
}

typedef OperatorPreferencesLoader = Future<SharedPreferences> Function();

/// Resolves a Profile's network identity and logo using the same public
/// operator-icons catalogs and evidence order used by NekokoLPA2.
class OperatorIdentityService {
  OperatorIdentityService({
    OperatorIdentityTransport? transport,
    OperatorPreferencesLoader? preferencesLoader,
    OperatorIconStore? iconStore,
    Uri? catalogBaseUri,
    Uri? iconBaseUri,
  }) : _transport = transport ?? HttpOperatorIdentityTransport(),
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
       _iconStore = iconStore ?? FileOperatorIconStore(),
       catalogBaseUri = catalogBaseUri ?? defaultCatalogBaseUri,
       iconBaseUri = iconBaseUri ?? defaultIconBaseUri;

  static final OperatorIdentityService instance = OperatorIdentityService();

  static final defaultCatalogBaseUri = Uri.parse(
    'https://operator-icons.pages.dev/catalog/',
  );
  static final defaultIconBaseUri = Uri.parse(
    'https://operator-icons.pages.dev/icons/',
  );
  static const sourceAttribution = 'operator-icons · NekokoLPA2 compatible';
  static const maximumCatalogBytes = 512 * 1024;
  static const maximumIconBytes = 1024 * 1024;

  static const _bodyKeyPrefix = 'operator_icons_catalog_body_v1_';
  static const _etagKeyPrefix = 'operator_icons_catalog_etag_v1_';

  final OperatorIdentityTransport _transport;
  final OperatorPreferencesLoader _preferencesLoader;
  final OperatorIconStore _iconStore;
  final Uri catalogBaseUri;
  final Uri iconBaseUri;
  final Map<String, OperatorCatalog> _catalogs = {};
  final Set<String> _missingCatalogs = {};
  final Map<String, Future<OperatorCatalog?>> _pendingCatalogs = {};
  final Map<String, Uint8List> _icons = {};
  final Map<String, Future<({Uint8List? bytes, bool fromCache})>>
  _pendingIcons = {};

  Future<OperatorIdentity?> resolve({
    required String? mcc,
    required String? mnc,
    String? gid1,
    String? gid2,
    String? profileName,
    String? serviceProviderName,
  }) async {
    final normalizedMcc = _normalizeMcc(mcc);
    final normalizedMnc = _normalizeMnc(mnc);
    if (normalizedMcc == null || normalizedMnc == null) return null;

    final catalog = await _loadCatalog(normalizedMcc);
    final match = catalog?.resolve(
      mnc: normalizedMnc,
      gid1: gid1,
      gid2: gid2,
      profileName: profileName,
      serviceProviderName: serviceProviderName,
    );
    if (match == null) return null;

    final hasIcon = match.icon.isNotEmpty && match.iconScope.isNotEmpty;
    final iconUri = hasIcon
        ? iconBaseUri.resolve(
            '${Uri.encodeComponent(match.iconScope)}/'
            '${Uri.encodeComponent(match.icon)}.png',
          )
        : null;
    final iconKey = _safeIconKey(
      normalizedMcc,
      normalizedMnc,
      match.iconScope,
      match.icon,
    );
    final icon = iconUri == null
        ? (bytes: null, fromCache: false)
        : await _loadIcon(iconKey, iconUri);
    return OperatorIdentity(
      match: match,
      iconUri: iconUri,
      iconBytes: icon.bytes,
      iconFromCache: icon.fromCache && icon.bytes != null,
    );
  }

  Future<OperatorCatalog?> _loadCatalog(String mcc) {
    final cached = _catalogs[mcc];
    if (cached != null) return Future.value(cached);
    if (_missingCatalogs.contains(mcc)) return Future.value(null);
    return _pendingCatalogs.putIfAbsent(mcc, () async {
      try {
        return await _fetchCatalog(mcc);
      } finally {
        _pendingCatalogs.remove(mcc);
      }
    });
  }

  Future<OperatorCatalog?> _fetchCatalog(String mcc) async {
    final preferences = await _preferencesLoader();
    final bodyKey = '$_bodyKeyPrefix$mcc';
    final etagKey = '$_etagKeyPrefix$mcc';
    final cachedBody = preferences.getString(bodyKey);
    try {
      final response = await _transport.get(
        catalogBaseUri.resolve('$mcc.toml'),
        etag: preferences.getString(etagKey),
      );
      if (response.statusCode == HttpStatus.notModified && cachedBody != null) {
        return _rememberCatalog(mcc, cachedBody);
      }
      if (response.statusCode == HttpStatus.notFound) {
        _missingCatalogs.add(mcc);
        return null;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('运营商目录返回 ${response.statusCode}');
      }
      if (response.bodyBytes.length > maximumCatalogBytes) {
        throw const FormatException('运营商目录超过大小限制');
      }
      final body = utf8.decode(response.bodyBytes);
      final catalog = OperatorCatalog.decode(body, expectedMcc: mcc);
      await preferences.setString(bodyKey, body);
      final etag = response.etag;
      if (etag != null) await preferences.setString(etagKey, etag);
      _catalogs[mcc] = catalog;
      return catalog;
    } catch (_) {
      if (cachedBody == null) return null;
      try {
        return _rememberCatalog(mcc, cachedBody);
      } on FormatException {
        return null;
      }
    }
  }

  OperatorCatalog _rememberCatalog(String mcc, String body) {
    final catalog = OperatorCatalog.decode(body, expectedMcc: mcc);
    _catalogs[mcc] = catalog;
    return catalog;
  }

  Future<({Uint8List? bytes, bool fromCache})> _loadIcon(
    String key,
    Uri uri,
  ) async {
    final memory = _icons[key];
    if (memory != null) return (bytes: memory, fromCache: true);
    return _pendingIcons.putIfAbsent(key, () async {
      try {
        final stored = await _iconStore.read(key);
        if (_validPng(stored)) {
          _icons[key] = stored!;
          return (bytes: stored, fromCache: true);
        }
        final response = await _transport.get(uri);
        if (response.statusCode != HttpStatus.ok ||
            response.bodyBytes.length > maximumIconBytes) {
          return (bytes: null, fromCache: false);
        }
        final bytes = Uint8List.fromList(response.bodyBytes);
        if (!_validPng(bytes)) return (bytes: null, fromCache: false);
        _icons[key] = bytes;
        await _iconStore.write(key, bytes);
        return (bytes: bytes, fromCache: false);
      } catch (_) {
        return (bytes: null, fromCache: false);
      } finally {
        _pendingIcons.remove(key);
      }
    });
  }
}

String? _normalizeMcc(String? value) {
  final text = value?.trim();
  return text != null && RegExp(r'^\d{3}$').hasMatch(text) ? text : null;
}

String? _normalizeMnc(String? value) {
  final text = value?.trim();
  return text != null && RegExp(r'^\d{1,3}$').hasMatch(text) ? text : null;
}

String _safeIconKey(String mcc, String mnc, String scope, String icon) =>
    '$mcc-$mnc-$scope-$icon'.toLowerCase().replaceAll(
      RegExp('[^a-z0-9_-]'),
      '_',
    );

bool _validPng(Uint8List? bytes) =>
    bytes != null &&
    bytes.length >= 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47 &&
    bytes[4] == 0x0D &&
    bytes[5] == 0x0A &&
    bytes[6] == 0x1A &&
    bytes[7] == 0x0A;
