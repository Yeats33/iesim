import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  test('远端不存在时使用 If-None-Match 创建快照', () async {
    final db = openIesimStore(':memory:');
    addTearDown(db.close);
    SubscriptionRepository(
      db,
    ).upsert(_sub('s1', '本地', DateTime.utc(2026, 8, 7)));
    final transport = _FakeTransport();
    final result = await WebDavSyncEngine(
      store: SyncStore(db),
      transport: transport,
      clock: FixedClock(DateTime.utc(2026, 8, 8)),
    ).sync();
    expect(result, isA<Ok<SyncRunReport>>());
    expect(transport.lastIfNoneMatch, isTrue);
    expect(
      transport.content,
      contains('"schemaVersion": ${SyncSnapshot.currentSchemaVersion}'),
    );
    expect((result as Ok<SyncRunReport>).value.etag, 'etag-1');
  });

  test('ETag 不一致时逐记录合并并记录同记录冲突', () async {
    final db = openIesimStore(':memory:');
    addTearDown(db.close);
    final store = SyncStore(db);
    final base = _sub('s1', '基础', DateTime.utc(2026, 8, 1));
    store.commitSuccessfulSync(
      snapshot: SyncSnapshot(
        generatedAtUtc: DateTime.utc(2026, 8, 1),
        subscriptions: [base],
      ),
      etag: 'etag-old',
      syncedAtUtc: DateTime.utc(2026, 8, 1),
    );
    SubscriptionRepository(
      db,
    ).upsert(_sub('s1', '本地', DateTime.utc(2026, 8, 5)));
    final remote = SyncSnapshot(
      generatedAtUtc: DateTime.utc(2026, 8, 6),
      subscriptions: [_sub('s1', '远端', DateTime.utc(2026, 8, 6))],
    );
    final transport = _FakeTransport(
      metadata: const RemoteFileMetadata(etag: 'etag-remote'),
      document: RemoteDocument(
        content: const SyncSnapshotCodec().encode(remote),
        etag: 'etag-remote',
      ),
    );
    final result = await WebDavSyncEngine(
      store: store,
      transport: transport,
      clock: FixedClock(DateTime.utc(2026, 8, 8)),
    ).sync();
    final report = (result as Ok<SyncRunReport>).value;
    expect(report.conflictCount, 1);
    final saved =
        (SubscriptionRepository(db).get('s1') as Ok<Subscription?>).value;
    expect(saved!.operator, '远端');
    expect(
      (store.listConflicts() as Ok<List<SyncConflictLog>>).value,
      hasLength(1),
    );
    expect(transport.lastIfMatch, 'etag-remote');
  });

  test('PUT 返回 412 时重新开始，最多范围内可成功', () async {
    final db = openIesimStore(':memory:');
    addTearDown(db.close);
    final transport = _FakeTransport(preconditionFailures: 1);
    final result = await WebDavSyncEngine(
      store: SyncStore(db),
      transport: transport,
      clock: FixedClock(DateTime.utc(2026, 8, 8)),
    ).sync();
    expect((result as Ok<SyncRunReport>).value.attempts, 2);
    expect(transport.uploadCount, 2);
  });

  test('认证失败以 AuthError 返回而非抛出', () async {
    final db = openIesimStore(':memory:');
    addTearDown(db.close);
    final result = await WebDavSyncEngine(
      store: SyncStore(db),
      transport: _FakeTransport(ensureFailure: const AuthError('密码错误')),
      clock: FixedClock(DateTime.utc(2026, 8, 8)),
    ).sync();
    expect((result as Err).failure, isA<AuthError>());
  });
}

class _FakeTransport implements WebDavTransport {
  _FakeTransport({
    this.metadata,
    this.document,
    this.preconditionFailures = 0,
    this.ensureFailure,
  });

  RemoteFileMetadata? metadata;
  RemoteDocument? document;
  int preconditionFailures;
  Failure? ensureFailure;
  int uploadCount = 0;
  bool lastIfNoneMatch = false;
  String? lastIfMatch;
  String? content;

  @override
  Future<Result<void>> ensureCollection() async =>
      ensureFailure == null ? const Ok(null) : Err(ensureFailure!);

  @override
  Future<Result<RemoteFileMetadata?>> stat() async => Ok(metadata);

  @override
  Future<Result<RemoteDocument>> download() async => Ok(document!);

  @override
  Future<Result<RemoteUploadResult>> upload(
    String content, {
    String? ifMatch,
    bool ifNoneMatch = false,
  }) async {
    uploadCount++;
    this.content = content;
    lastIfMatch = ifMatch;
    lastIfNoneMatch = ifNoneMatch;
    if (preconditionFailures > 0) {
      preconditionFailures--;
      return const Err(PreconditionFailed());
    }
    metadata = RemoteFileMetadata(etag: 'etag-$uploadCount');
    return Ok(RemoteUploadResult(etag: metadata!.etag));
  }
}

Subscription _sub(String id, String operator, DateTime updatedAt) =>
    Subscription(
      id: id,
      number: PhoneNumber('10086'),
      operator: operator,
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'UTC',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: updatedAt,
    );
