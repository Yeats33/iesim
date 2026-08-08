import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iesim_core/iesim_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

class WebDavConfiguration {
  const WebDavConfiguration({
    required this.directoryUrl,
    required this.username,
    required this.password,
  });

  final String directoryUrl;
  final String username;
  final String password;

  Uri get directoryUri {
    final uri = Uri.parse(directoryUrl.trim());
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请输入不含凭据和参数的 HTTPS WebDAV 目录地址');
    }
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: path);
  }

  Uri get snapshotUri => directoryUri.resolve('iesim-v1.json');
}

abstract interface class WebDavGateway {
  Future<WebDavConfiguration?> loadConfiguration();

  Future<void> saveConfiguration(WebDavConfiguration configuration);

  Future<void> clearConfiguration();

  Future<Result<void>> testConnection(WebDavConfiguration configuration);

  Future<Result<SyncRunReport>> sync(WebDavConfiguration configuration);

  Result<List<SyncConflictLog>> listConflicts();

  Result<SyncState> readState();
}

class AppWebDavService implements WebDavGateway {
  AppWebDavService(this._store);

  static const _urlKey = 'webdav.directory_url';
  static const _usernameKey = 'webdav.username';
  static const _passwordKey = 'webdav.password';
  static const _secureStorage = FlutterSecureStorage();

  final SyncStore _store;

  @override
  Future<WebDavConfiguration?> loadConfiguration() async {
    final preferences = await SharedPreferences.getInstance();
    final url = preferences.getString(_urlKey);
    final username = preferences.getString(_usernameKey);
    final password = await _secureStorage.read(key: _passwordKey);
    if (url == null || username == null || password == null) return null;
    return WebDavConfiguration(
      directoryUrl: url,
      username: username,
      password: password,
    );
  }

  @override
  Future<void> saveConfiguration(WebDavConfiguration configuration) async {
    final preferences = await SharedPreferences.getInstance();
    final oldUrl = preferences.getString(_urlKey);
    final oldUsername = preferences.getString(_usernameKey);
    final normalizedUrl = configuration.directoryUri.toString();
    if (oldUrl != normalizedUrl ||
        oldUsername != configuration.username.trim()) {
      final reset = _store.resetState();
      if (reset case Err(failure: final failure)) {
        throw StateError('$failure');
      }
    }
    await preferences.setString(_urlKey, normalizedUrl);
    await preferences.setString(_usernameKey, configuration.username.trim());
    await _secureStorage.write(
      key: _passwordKey,
      value: configuration.password,
    );
  }

  @override
  Future<void> clearConfiguration() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_urlKey);
    await preferences.remove(_usernameKey);
    await _secureStorage.delete(key: _passwordKey);
  }

  @override
  Future<Result<void>> testConnection(WebDavConfiguration configuration) async {
    final transport = HttpWebDavTransport(configuration);
    try {
      final collection = await transport.ensureCollection();
      if (collection case Err(failure: final failure)) return Err(failure);
      final stat = await transport.stat();
      if (stat case Err(failure: final failure)) return Err(failure);
      return const Ok(null);
    } finally {
      transport.close();
    }
  }

  @override
  Future<Result<SyncRunReport>> sync(WebDavConfiguration configuration) async {
    final transport = HttpWebDavTransport(configuration);
    try {
      return await WebDavSyncEngine(store: _store, transport: transport).sync();
    } finally {
      transport.close();
    }
  }

  @override
  Result<List<SyncConflictLog>> listConflicts() => _store.listConflicts();

  @override
  Result<SyncState> readState() => _store.readState();
}

class NoopWebDavGateway implements WebDavGateway {
  const NoopWebDavGateway();

  @override
  Future<WebDavConfiguration?> loadConfiguration() async => null;

  @override
  Future<void> saveConfiguration(WebDavConfiguration configuration) async {}

  @override
  Future<void> clearConfiguration() async {}

  @override
  Future<Result<void>> testConnection(
    WebDavConfiguration configuration,
  ) async => const Err(NetworkError('WebDAV 未初始化'));

  @override
  Future<Result<SyncRunReport>> sync(WebDavConfiguration configuration) async =>
      const Err(NetworkError('WebDAV 未初始化'));

  @override
  Result<List<SyncConflictLog>> listConflicts() => const Ok([]);

  @override
  Result<SyncState> readState() => const Ok(SyncState());
}

class HttpWebDavTransport implements WebDavTransport {
  HttpWebDavTransport(this.configuration, {HttpClient? client})
    : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 12);
  }

  final WebDavConfiguration configuration;
  final HttpClient _client;

  void close() => _client.close(force: true);

  @override
  Future<Result<void>> ensureCollection() async {
    try {
      final response = await _request('MKCOL', configuration.directoryUri);
      if ({200, 201, 204, 405}.contains(response.statusCode)) {
        return const Ok(null);
      }
      return _failure<void>(response, action: '创建同步目录');
    } catch (error) {
      return Err(_networkFailure(error));
    }
  }

  @override
  Future<Result<RemoteFileMetadata?>> stat() async {
    try {
      final response = await _request(
        'PROPFIND',
        configuration.snapshotUri,
        headers: {
          'Depth': '0',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        body: utf8.encode(
          '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:getetag/></d:prop></d:propfind>',
        ),
      );
      if (response.statusCode == 404) return const Ok(null);
      if (response.statusCode != 200 && response.statusCode != 207) {
        return _failure(response, action: '读取远端状态');
      }
      final etag = _extractEtag(response);
      if (etag == null || etag.isEmpty) {
        return const Err(NetworkError('WebDAV 服务未返回 ETag，无法安全防止并发覆盖'));
      }
      return Ok(RemoteFileMetadata(etag: etag));
    } catch (error) {
      return Err(_networkFailure(error));
    }
  }

  @override
  Future<Result<RemoteDocument>> download() async {
    try {
      final response = await _request('GET', configuration.snapshotUri);
      if (response.statusCode != 200) {
        return _failure(response, action: '下载远端快照');
      }
      if (response.bytes.length > 10 * 1024 * 1024) {
        return const Err(SchemaError('远端快照超过 10 MB，已拒绝读取'));
      }
      final etag = _extractEtag(response);
      if (etag == null || etag.isEmpty) {
        return const Err(NetworkError('下载响应缺少 ETag，无法安全合并'));
      }
      return Ok(
        RemoteDocument(content: utf8.decode(response.bytes), etag: etag),
      );
    } on FormatException catch (error) {
      return Err(SchemaError('远端快照不是有效 UTF-8：${error.message}'));
    } catch (error) {
      return Err(_networkFailure(error));
    }
  }

  @override
  Future<Result<RemoteUploadResult>> upload(
    String content, {
    String? ifMatch,
    bool ifNoneMatch = false,
  }) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'If-Match': ?ifMatch,
        if (ifNoneMatch) 'If-None-Match': '*',
      };
      final response = await _request(
        'PUT',
        configuration.snapshotUri,
        headers: headers,
        body: utf8.encode(content),
      );
      if (response.statusCode == 412) {
        return const Err(PreconditionFailed());
      }
      if (!{200, 201, 204}.contains(response.statusCode)) {
        return _failure(response, action: '上传同步快照');
      }
      return Ok(RemoteUploadResult(etag: _extractEtag(response)));
    } catch (error) {
      return Err(_networkFailure(error));
    }
  }

  Future<_DavResponse> _request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = await _client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 15));
    final token = base64Encode(
      utf8.encode('${configuration.username}:${configuration.password}'),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Basic $token');
    request.headers.set(HttpHeaders.userAgentHeader, 'iesim-android/1.0');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (body != null) {
      request.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    final bytes = await response
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk))
        .timeout(const Duration(seconds: 20));
    return _DavResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      bytes: bytes,
    );
  }

  static String? _extractEtag(_DavResponse response) {
    final header = response.headers.value(HttpHeaders.etagHeader)?.trim();
    if (header != null && header.isNotEmpty) return header;
    if (response.bytes.isEmpty) return null;
    try {
      final document = XmlDocument.parse(utf8.decode(response.bytes));
      for (final element in document.descendants.whereType<XmlElement>()) {
        if (element.name.local.toLowerCase() == 'getetag') {
          return element.innerText.trim();
        }
      }
    } catch (_) {}
    return null;
  }

  static Result<T> _failure<T>(
    _DavResponse response, {
    required String action,
  }) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      return Err(AuthError('$action被拒绝，请检查用户名、密码和目录权限'));
    }
    return Err(NetworkError('$action失败：服务器返回 HTTP ${response.statusCode}'));
  }

  static NetworkError _networkFailure(Object error) {
    if (error is TimeoutException) {
      return const NetworkError('连接超时，请检查网络和服务器地址');
    }
    if (error is SocketException) {
      return NetworkError('无法连接 WebDAV：${error.message}');
    }
    if (error is FormatException) return NetworkError(error.message);
    return NetworkError('WebDAV 请求失败：$error');
  }
}

class _DavResponse {
  const _DavResponse({
    required this.statusCode,
    required this.headers,
    required this.bytes,
  });

  final int statusCode;
  final HttpHeaders headers;
  final List<int> bytes;
}
