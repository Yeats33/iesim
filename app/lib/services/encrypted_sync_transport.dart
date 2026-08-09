import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:iesim_core/iesim_core.dart';

import 'credential_vault.dart';

class DecryptedSyncPayload {
  const DecryptedSyncPayload({
    required this.snapshot,
    required this.credentials,
  });

  final String snapshot;
  final List<ActivationCredentialRecord> credentials;
}

/// ieSIM WebDAV 端到端加密封装。
///
/// 口令经 PBKDF2-HMAC-SHA256 派生 256 位密钥，正文用 AES-256-GCM 加密并认证。
/// 盐、nonce 与 MAC 可公开；口令和明文不会写入远端文件。
class EncryptedSyncPayloadCodec {
  EncryptedSyncPayloadCodec({this.iterations = 210000});

  static const format = 'iesim-encrypted-sync';
  static const version = 1;
  static const _associatedData = 'iesim-encrypted-sync:v1';

  final int iterations;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<String> encrypt({
    required String snapshot,
    required List<ActivationCredentialRecord> credentials,
    required String password,
  }) async {
    _validatePassword(password);
    final salt = randomBytes(16);
    final key = await _deriveKey(password, salt, iterations);
    final inner = utf8.encode(
      jsonEncode({
        'snapshot': jsonDecode(snapshot),
        'credentials': [for (final item in credentials) item.toJson()],
      }),
    );
    final box = await _cipher.encrypt(
      inner,
      secretKey: key,
      aad: utf8.encode(_associatedData),
    );
    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': version,
      'kdf': {
        'name': 'PBKDF2-HMAC-SHA256',
        'iterations': iterations,
        'salt': base64Encode(salt),
      },
      'cipher': {
        'name': 'AES-256-GCM',
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      },
    });
  }

  Future<DecryptedSyncPayload> decrypt(
    String source, {
    required String password,
  }) async {
    _validatePassword(password);
    try {
      final root = _map(jsonDecode(source), '加密快照');
      if (root['format'] != format || root['version'] != version) {
        throw const FormatException('远端文件不是 ieSIM 加密快照 v1');
      }
      final kdf = _map(root['kdf'], 'kdf');
      final cipher = _map(root['cipher'], 'cipher');
      if (kdf['name'] != 'PBKDF2-HMAC-SHA256' ||
          cipher['name'] != 'AES-256-GCM') {
        throw const FormatException('远端快照使用了不支持的加密算法');
      }
      final rounds = _integer(kdf, 'iterations');
      if (rounds < 100000 || rounds > 1000000) {
        throw const FormatException('远端快照的 KDF 参数不安全或超出限制');
      }
      final salt = _bytes(kdf, 'salt');
      final nonce = _bytes(cipher, 'nonce');
      final ciphertext = _bytes(cipher, 'ciphertext');
      final mac = _bytes(cipher, 'mac');
      if (salt.length != 16 || nonce.length != _cipher.nonceLength) {
        throw const FormatException('远端快照的盐或 nonce 长度无效');
      }
      final key = await _deriveKey(password, salt, rounds);
      final clearBytes = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: utf8.encode(_associatedData),
      );
      final inner = _map(jsonDecode(utf8.decode(clearBytes)), '加密正文');
      final snapshot = inner['snapshot'];
      final credentials = inner['credentials'];
      if (snapshot is! Map<String, dynamic> || credentials is! List) {
        throw const FormatException('加密正文结构无效');
      }
      return DecryptedSyncPayload(
        snapshot: jsonEncode(snapshot),
        credentials: [
          for (var index = 0; index < credentials.length; index++)
            ActivationCredentialRecord.fromJson(
              _map(credentials[index], 'credentials[$index]'),
            ),
        ],
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException('同步加密口令不正确，或远端文件已损坏');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('同步加密口令不正确，或远端文件已损坏');
    }
  }

  static void _validatePassword(String password) {
    if (password.length < 12) {
      throw const FormatException('同步加密口令至少需要 12 个字符');
    }
  }

  static Future<SecretKey> _deriveKey(
    String password,
    List<int> salt,
    int iterations,
  ) => Pbkdf2.hmacSha256(
    iterations: iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
}

/// 在 HTTP/WebDAV 传输层外增加端到端加密，并同步安全凭据保险库。
class EncryptedWebDavTransport implements WebDavTransport {
  EncryptedWebDavTransport(
    this._delegate, {
    required this.password,
    required this.vault,
    EncryptedSyncPayloadCodec? codec,
  }) : _codec = codec ?? EncryptedSyncPayloadCodec();

  final WebDavTransport _delegate;
  final String password;
  final ActivationCredentialVault vault;
  final EncryptedSyncPayloadCodec _codec;
  List<ActivationCredentialRecord> _downloadedCredentials = const [];

  @override
  Future<Result<void>> ensureCollection() => _delegate.ensureCollection();

  @override
  Future<Result<RemoteFileMetadata?>> stat() => _delegate.stat();

  @override
  Future<Result<RemoteDocument>> download() async {
    final downloaded = await _delegate.download();
    if (downloaded case Err(failure: final failure)) return Err(failure);
    final document = (downloaded as Ok<RemoteDocument>).value;
    try {
      final payload = await _codec.decrypt(
        document.content,
        password: password,
      );
      _downloadedCredentials = payload.credentials;
      return Ok(RemoteDocument(content: payload.snapshot, etag: document.etag));
    } on FormatException catch (error) {
      return Err(AuthError(error.message));
    }
  }

  @override
  Future<Result<RemoteUploadResult>> upload(
    String content, {
    String? ifMatch,
    bool ifNoneMatch = false,
  }) async {
    try {
      final validIds = _subscriptionIds(content);
      final records = _mergeCredentials(
        await vault.readAll(),
        _downloadedCredentials,
        validIds,
      );
      for (final record in records) {
        await vault.write(record);
      }
      await vault.retain(validIds);
      final encrypted = await _codec.encrypt(
        snapshot: content,
        credentials: records,
        password: password,
      );
      return _delegate.upload(
        encrypted,
        ifMatch: ifMatch,
        ifNoneMatch: ifNoneMatch,
      );
    } on FormatException catch (error) {
      return Err(SchemaError(error.message));
    } catch (error) {
      return Err(StoreError('无法读取或更新本机凭据保险库：$error'));
    }
  }

  static Set<String> _subscriptionIds(String snapshot) {
    final root = _map(jsonDecode(snapshot), '同步快照');
    final subscriptions = root['subscriptions'];
    if (subscriptions is! List) {
      throw const FormatException('同步快照缺少 subscriptions');
    }
    return {
      for (var index = 0; index < subscriptions.length; index++)
        _requiredString(
          _map(subscriptions[index], 'subscriptions[$index]'),
          'id',
        ),
    };
  }

  static List<ActivationCredentialRecord> _mergeCredentials(
    List<ActivationCredentialRecord> local,
    List<ActivationCredentialRecord> remote,
    Set<String> validIds,
  ) {
    final merged = <String, ActivationCredentialRecord>{};
    for (final record in [...local, ...remote]) {
      if (!validIds.contains(record.subscriptionId)) continue;
      final current = merged[record.subscriptionId];
      if (current == null ||
          !record.updatedAtUtc.isBefore(current.updatedAtUtc)) {
        merged[record.subscriptionId] = record;
      }
    }
    final result = merged.values.toList()
      ..sort((a, b) => a.subscriptionId.compareTo(b.subscriptionId));
    return result;
  }
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$field 必须是对象');
}

int _integer(Map<String, dynamic> value, String field) {
  final item = value[field];
  if (item is int) return item;
  throw FormatException('$field 必须是整数');
}

String _requiredString(Map<String, dynamic> value, String field) {
  final item = value[field];
  if (item is String && item.isNotEmpty) return item;
  throw FormatException('$field 必须是非空字符串');
}

List<int> _bytes(Map<String, dynamic> value, String field) {
  final item = value[field];
  if (item is! String) throw FormatException('$field 必须是 Base64 字符串');
  try {
    return base64Decode(item);
  } on FormatException {
    throw FormatException('$field 不是有效 Base64');
  }
}
