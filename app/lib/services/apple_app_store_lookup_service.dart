import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AppleAppStoreMetadata {
  const AppleAppStoreMetadata({
    required this.appId,
    required this.name,
    required this.developerName,
    required this.bundleId,
    required this.iconUrl,
    required this.storeUrl,
    required this.category,
    required this.version,
    required this.fetchedAt,
  });

  final String appId;
  final String name;
  final String developerName;
  final String bundleId;
  final String iconUrl;
  final String storeUrl;
  final String category;
  final String version;
  final DateTime fetchedAt;
}

class AppleAppStoreLookupResponse {
  const AppleAppStoreLookupResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

abstract interface class AppleAppStoreLookupTransport {
  Future<AppleAppStoreLookupResponse> get(Uri uri);
}

class HttpAppleAppStoreLookupTransport implements AppleAppStoreLookupTransport {
  static const _maxBytes = 1024 * 1024;

  @override
  Future<AppleAppStoreLookupResponse> get(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'iesim/0.0.3 apple-app-lookup',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBytes) {
          throw const FormatException('App Store 元数据超过 1 MB 大小限制');
        }
      }
      return AppleAppStoreLookupResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
      );
    } finally {
      client.close(force: true);
    }
  }
}

class AppleAppStoreLookupService {
  AppleAppStoreLookupService({AppleAppStoreLookupTransport? transport})
    : _transport = transport ?? HttpAppleAppStoreLookupTransport();

  final AppleAppStoreLookupTransport _transport;

  /// 只向 Apple 发送公开的 App ID 和 storefront 国家代码。
  /// 手机号、账号标签及备注不会进入请求。
  Future<AppleAppStoreMetadata> lookupById(
    String appId, {
    String country = 'US',
  }) async {
    final normalizedId = appId.trim();
    if (!RegExp(r'^\d{1,20}$').hasMatch(normalizedId)) {
      throw const FormatException('App Store ID 必须是数字');
    }
    final normalizedCountry = country.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(normalizedCountry)) {
      throw const FormatException('App Store 国家代码必须是两个字母');
    }
    final uri = Uri.https('itunes.apple.com', '/lookup', {
      'id': normalizedId,
      'country': normalizedCountry,
      'entity': 'software',
    });
    final response = await _transport.get(uri);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'App Store Lookup 返回 ${response.statusCode}',
        uri: uri,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('App Store 响应根节点无效');
    final root = Map<String, dynamic>.from(decoded);
    final results = root['results'];
    if (results is! List || results.isEmpty) {
      throw const FormatException('App Store 没有找到这个 App');
    }
    final first = results.first;
    if (first is! Map) throw const FormatException('App Store App 数据无效');
    final app = Map<String, dynamic>.from(first);
    return AppleAppStoreMetadata(
      appId: _stringOrNumber(app, 'trackId'),
      name: _requiredString(app, 'trackName'),
      developerName: _requiredString(app, 'sellerName'),
      bundleId: _requiredString(app, 'bundleId'),
      iconUrl: _requiredHttps(app, 'artworkUrl100'),
      storeUrl: _requiredHttps(app, 'trackViewUrl'),
      category: _requiredString(app, 'primaryGenreName'),
      version: _requiredString(app, 'version'),
      fetchedAt: DateTime.now().toUtc(),
    );
  }
}

String _requiredString(Map<String, dynamic> value, String field) {
  final raw = value[field];
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  throw FormatException('App Store 响应缺少 $field');
}

String _stringOrNumber(Map<String, dynamic> value, String field) {
  final raw = value[field];
  if (raw is int) return raw.toString();
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  throw FormatException('App Store 响应缺少 $field');
}

String _requiredHttps(Map<String, dynamic> value, String field) {
  final raw = _requiredString(value, field);
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
    throw FormatException('App Store 响应中的 $field 不是 HTTPS 地址');
  }
  return raw;
}
