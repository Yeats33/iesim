import '../result.dart';
import '../store/sync_store.dart';
import '../time/clock.dart';
import 'snapshot_codec.dart';
import 'snapshot_merger.dart';
import 'sync_snapshot.dart';

class RemoteFileMetadata {
  const RemoteFileMetadata({required this.etag});

  final String etag;
}

class RemoteDocument {
  const RemoteDocument({required this.content, required this.etag});

  final String content;
  final String etag;
}

class RemoteUploadResult {
  const RemoteUploadResult({this.etag});

  final String? etag;
}

abstract interface class WebDavTransport {
  Future<Result<void>> ensureCollection();

  Future<Result<RemoteFileMetadata?>> stat();

  Future<Result<RemoteDocument>> download();

  Future<Result<RemoteUploadResult>> upload(
    String content, {
    String? ifMatch,
    bool ifNoneMatch = false,
  });
}

class SyncRunReport {
  const SyncRunReport({
    required this.syncedAtUtc,
    required this.etag,
    required this.attempts,
    required this.subscriptionCount,
    required this.activityCount,
    required this.conflictCount,
  });

  final DateTime syncedAtUtc;
  final String etag;
  final int attempts;
  final int subscriptionCount;
  final int activityCount;
  final int conflictCount;
}

class WebDavSyncEngine {
  const WebDavSyncEngine({
    required this.store,
    required this.transport,
    this.clock = const SystemClock(),
    this.codec = const SyncSnapshotCodec(),
    this.merger = const SyncSnapshotMerger(),
    this.maxAttempts = 3,
  });

  final SyncStore store;
  final WebDavTransport transport;
  final Clock clock;
  final SyncSnapshotCodec codec;
  final SyncSnapshotMerger merger;
  final int maxAttempts;

  Future<Result<SyncRunReport>> sync() async {
    final collection = await transport.ensureCollection();
    if (collection case Err(failure: final failure)) return Err(failure);

    final now = clock.nowUtc();
    final cleanup = store.removeExpiredTombstones(nowUtc: now);
    if (cleanup case Err(failure: final failure)) return Err(failure);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final localResult = store.loadSnapshot(generatedAtUtc: now);
      if (localResult case Err(failure: final failure)) return Err(failure);
      final local = (localResult as Ok<SyncSnapshot>).value;
      final stateResult = store.readState();
      if (stateResult case Err(failure: final failure)) return Err(failure);
      final state = (stateResult as Ok<SyncState>).value;
      final statResult = await transport.stat();
      if (statResult case Err(failure: final failure)) return Err(failure);
      final metadata = (statResult as Ok<RemoteFileMetadata?>).value;

      if (metadata == null) {
        final upload = await transport.upload(
          codec.encode(local),
          ifNoneMatch: true,
        );
        if (_preconditionFailed(upload)) continue;
        if (upload case Err(failure: final failure)) return Err(failure);
        final etagResult = await _resolveEtag(
          (upload as Ok<RemoteUploadResult>).value.etag,
        );
        if (etagResult case Err(failure: final failure)) return Err(failure);
        return _commit(
          snapshot: local,
          etag: (etagResult as Ok<String>).value,
          syncedAtUtc: now,
          attempt: attempt,
        );
      }

      if (metadata.etag == state.etag) {
        final upload = await transport.upload(
          codec.encode(local),
          ifMatch: metadata.etag,
        );
        if (_preconditionFailed(upload)) continue;
        if (upload case Err(failure: final failure)) return Err(failure);
        final etagResult = await _resolveEtag(
          (upload as Ok<RemoteUploadResult>).value.etag,
        );
        if (etagResult case Err(failure: final failure)) return Err(failure);
        return _commit(
          snapshot: local,
          etag: (etagResult as Ok<String>).value,
          syncedAtUtc: now,
          attempt: attempt,
        );
      }

      final downloadResult = await transport.download();
      if (downloadResult case Err(failure: final failure)) return Err(failure);
      final download = (downloadResult as Ok<RemoteDocument>).value;
      final decoded = codec.decode(download.content);
      if (decoded case Err(failure: final failure)) return Err(failure);
      final merged = merger.merge(
        local: local,
        remote: (decoded as Ok<SyncSnapshot>).value,
        mergedAtUtc: now,
        lastSyncedAtUtc: state.lastSyncedAtUtc,
      );
      final upload = await transport.upload(
        codec.encode(merged.snapshot),
        ifMatch: download.etag,
      );
      if (_preconditionFailed(upload)) continue;
      if (upload case Err(failure: final failure)) return Err(failure);
      final etagResult = await _resolveEtag(
        (upload as Ok<RemoteUploadResult>).value.etag,
      );
      if (etagResult case Err(failure: final failure)) return Err(failure);
      return _commit(
        snapshot: merged.snapshot,
        etag: (etagResult as Ok<String>).value,
        syncedAtUtc: now,
        attempt: attempt,
        conflicts: merged.conflicts,
      );
    }
    return const Err(NetworkError('远端文件持续被其他设备修改，已重试 3 次，请稍后再试'));
  }

  Future<Result<String>> _resolveEtag(String? uploadedEtag) async {
    if (uploadedEtag != null && uploadedEtag.isNotEmpty) {
      return Ok(uploadedEtag);
    }
    final result = await transport.stat();
    if (result case Err(failure: final failure)) return Err(failure);
    final metadata = (result as Ok<RemoteFileMetadata?>).value;
    if (metadata == null) return const Err(NetworkError('上传后远端文件不存在'));
    return Ok(metadata.etag);
  }

  Result<SyncRunReport> _commit({
    required SyncSnapshot snapshot,
    required String etag,
    required DateTime syncedAtUtc,
    required int attempt,
    Iterable<SyncConflict> conflicts = const [],
  }) {
    final conflictList = conflicts.toList();
    final committed = store.commitSuccessfulSync(
      snapshot: snapshot,
      etag: etag,
      syncedAtUtc: syncedAtUtc,
      conflicts: conflictList,
    );
    if (committed case Err(failure: final failure)) return Err(failure);
    return Ok(
      SyncRunReport(
        syncedAtUtc: syncedAtUtc,
        etag: etag,
        attempts: attempt,
        subscriptionCount: snapshot.subscriptions.length,
        activityCount: snapshot.activityRecords.length,
        conflictCount: conflictList.length,
      ),
    );
  }

  static bool _preconditionFailed(Result<RemoteUploadResult> result) =>
      switch (result) {
        Err(failure: PreconditionFailed()) => true,
        _ => false,
      };
}
