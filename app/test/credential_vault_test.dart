import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/credential_vault.dart';
import 'package:iesim_core/iesim_core.dart';

void main() {
  test('凭据记录 JSON 完整往返且支持删除墓碑', () {
    final record = ActivationCredentialRecord(
      subscriptionId: 'sub-1',
      updatedAtUtc: DateTime.utc(2026, 8, 8),
      activation: LpaActivation(
        smdpAddress: 'rsp.example.test',
        matchingId: 'MATCHING-ID',
        extra: '1.3.6.1.4.1.31746',
        confirmationCode: '123456',
      ),
    );

    final restored = ActivationCredentialRecord.fromJson(record.toJson());
    expect(restored.subscriptionId, record.subscriptionId);
    expect(restored.updatedAtUtc, record.updatedAtUtc);
    expect(restored.activation, record.activation);

    final tombstone = ActivationCredentialRecord.fromJson({
      'subscriptionId': 'sub-1',
      'updatedAt': '2026-08-09T00:00:00.000Z',
      'activation': null,
    });
    expect(tombstone.activation, isNull);
  });

  test('内存保险库只保留指定 Profile，并可单条或全部清理', () async {
    final vault = MemoryActivationCredentialVault();
    final first = ActivationCredentialRecord(
      subscriptionId: 'sub-1',
      updatedAtUtc: DateTime.utc(2026, 8, 8),
      activation: LpaActivation(
        smdpAddress: 'rsp.example.test',
        matchingId: 'MATCH-1',
      ),
    );
    final second = ActivationCredentialRecord(
      subscriptionId: 'sub-2',
      updatedAtUtc: DateTime.utc(2026, 8, 8),
      activation: null,
    );
    await vault.write(first);
    await vault.write(second);

    expect((await vault.read('sub-1'))?.activation, first.activation);
    await vault.retain({'sub-2'});
    expect(await vault.read('sub-1'), isNull);
    expect(await vault.read('sub-2'), isNotNull);
    await vault.purge('sub-2');
    expect(await vault.readAll(), isEmpty);

    await vault.write(first);
    await vault.clear();
    expect(await vault.readAll(), isEmpty);
  });

  test('凭据记录拒绝本地时间和缺失字段', () {
    expect(
      () => ActivationCredentialRecord.fromJson({
        'subscriptionId': 'sub-1',
        'updatedAt': '2026-08-08T12:00:00',
        'activation': null,
      }),
      throwsFormatException,
    );
    expect(
      () => ActivationCredentialRecord.fromJson({
        'updatedAt': '2026-08-08T12:00:00.000Z',
        'activation': null,
      }),
      throwsFormatException,
    );
  });
}
