import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/credential_vault.dart';
import 'package:iesim/services/encrypted_sync_transport.dart';
import 'package:iesim_core/iesim_core.dart';

const _password = 'correct horse battery staple';
const _snapshot =
    '{"schemaVersion":1,"subscriptions":[{"id":"sub-1",'
    '"privateLabel":"snapshot-private-phone"}]}';

void main() {
  late EncryptedSyncPayloadCodec codec;

  setUp(() {
    codec = EncryptedSyncPayloadCodec(iterations: 100000);
  });

  test('AES-GCM 快照不泄漏业务数据或 LPA 凭据，并可完整解密', () async {
    final credential = _credential(
      updatedAt: DateTime.utc(2026, 8, 8),
      matchingId: 'MATCHING-ID-VERY-SECRET',
    );
    final encrypted = await codec.encrypt(
      snapshot: _snapshot,
      credentials: [credential],
      password: _password,
    );

    expect(encrypted, contains('AES-256-GCM'));
    expect(encrypted, contains('PBKDF2-HMAC-SHA256'));
    expect(encrypted, isNot(contains('snapshot-private-phone')));
    expect(encrypted, isNot(contains('rsp.private.example')));
    expect(encrypted, isNot(contains('MATCHING-ID-VERY-SECRET')));
    expect(encrypted, isNot(contains('654321')));
    expect(encrypted, isNot(contains(_password)));

    final decrypted = await codec.decrypt(encrypted, password: _password);
    expect(jsonDecode(decrypted.snapshot), jsonDecode(_snapshot));
    expect(decrypted.credentials.single.subscriptionId, 'sub-1');
    expect(decrypted.credentials.single.activation, credential.activation);
  });

  test('错误口令与被篡改密文都会被认证失败拒绝', () async {
    final encrypted = await codec.encrypt(
      snapshot: _snapshot,
      credentials: const [],
      password: _password,
    );
    await expectLater(
      codec.decrypt(encrypted, password: 'this password is definitely wrong'),
      throwsFormatException,
    );

    final root = jsonDecode(encrypted) as Map<String, dynamic>;
    final cipher = root['cipher'] as Map<String, dynamic>;
    final bytes = base64Decode(cipher['ciphertext'] as String);
    bytes[0] ^= 1;
    cipher['ciphertext'] = base64Encode(bytes);
    await expectLater(
      codec.decrypt(jsonEncode(root), password: _password),
      throwsFormatException,
    );
  });

  test('上传时只带有效 Profile 的凭据，远端文件保持加密', () async {
    final vault = MemoryActivationCredentialVault();
    await vault.write(
      _credential(
        updatedAt: DateTime.utc(2026, 8, 8),
        matchingId: 'LOCAL-SECRET',
      ),
    );
    await vault.write(
      ActivationCredentialRecord(
        subscriptionId: 'removed-profile',
        updatedAtUtc: DateTime.utc(2026, 8, 8),
        activation: null,
      ),
    );
    final delegate = _FakeTransport();
    final transport = EncryptedWebDavTransport(
      delegate,
      password: _password,
      vault: vault,
      codec: codec,
    );

    final result = await transport.upload(_snapshot, ifNoneMatch: true);
    expect(result, isA<Ok<RemoteUploadResult>>());
    expect(delegate.uploadedContent, isNot(contains('LOCAL-SECRET')));
    expect(delegate.ifNoneMatch, isTrue);
    final payload = await codec.decrypt(
      delegate.uploadedContent!,
      password: _password,
    );
    expect(payload.credentials.map((item) => item.subscriptionId), ['sub-1']);
    expect(await vault.read('removed-profile'), isNull);
  });

  test('下载后上传会按 updatedAt 合并远端新凭据', () async {
    final vault = MemoryActivationCredentialVault();
    await vault.write(
      _credential(
        updatedAt: DateTime.utc(2026, 8, 7),
        matchingId: 'OLDER-LOCAL',
      ),
    );
    final remoteCredential = _credential(
      updatedAt: DateTime.utc(2026, 8, 9),
      matchingId: 'NEWER-REMOTE',
    );
    final delegate = _FakeTransport(
      downloadContent: await codec.encrypt(
        snapshot: _snapshot,
        credentials: [remoteCredential],
        password: _password,
      ),
    );
    final transport = EncryptedWebDavTransport(
      delegate,
      password: _password,
      vault: vault,
      codec: codec,
    );

    final downloaded = await transport.download();
    expect(downloaded, isA<Ok<RemoteDocument>>());
    expect((downloaded as Ok<RemoteDocument>).value.content, _snapshot);
    expect(await transport.upload(_snapshot), isA<Ok<RemoteUploadResult>>());

    expect((await vault.read('sub-1'))?.activation?.matchingId, 'NEWER-REMOTE');
    final uploaded = await codec.decrypt(
      delegate.uploadedContent!,
      password: _password,
    );
    expect(uploaded.credentials.single.activation?.matchingId, 'NEWER-REMOTE');
  });
}

ActivationCredentialRecord _credential({
  required DateTime updatedAt,
  required String matchingId,
}) => ActivationCredentialRecord(
  subscriptionId: 'sub-1',
  updatedAtUtc: updatedAt,
  activation: LpaActivation(
    smdpAddress: 'rsp.private.example',
    matchingId: matchingId,
    confirmationCode: '654321',
  ),
);

class _FakeTransport implements WebDavTransport {
  _FakeTransport({this.downloadContent});

  final String? downloadContent;
  String? uploadedContent;
  String? ifMatch;
  bool ifNoneMatch = false;

  @override
  Future<Result<void>> ensureCollection() async => const Ok(null);

  @override
  Future<Result<RemoteFileMetadata?>> stat() async =>
      const Ok(RemoteFileMetadata(etag: 'etag-1'));

  @override
  Future<Result<RemoteDocument>> download() async =>
      Ok(RemoteDocument(content: downloadContent!, etag: 'etag-1'));

  @override
  Future<Result<RemoteUploadResult>> upload(
    String content, {
    String? ifMatch,
    bool ifNoneMatch = false,
  }) async {
    uploadedContent = content;
    this.ifMatch = ifMatch;
    this.ifNoneMatch = ifNoneMatch;
    return const Ok(RemoteUploadResult(etag: 'etag-2'));
  }
}
