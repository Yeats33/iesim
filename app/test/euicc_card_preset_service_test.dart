import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/data/euicc_card_presets.dart';
import 'package:iesim/services/euicc_card_preset_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  String catalog({
    required String version,
    required String updatedAt,
    String affiliateOfferId = 'builtin-9esim',
  }) {
    final root =
        jsonDecode(builtInEuiccCardPresetCatalog.encode())
            as Map<String, dynamic>;
    root['catalogVersion'] = version;
    root['updatedAt'] = updatedAt;
    final cards = root['cards'] as List;
    (cards.first as Map<String, dynamic>)['affiliateOfferId'] =
        affiliateOfferId;
    return jsonEncode(root);
  }

  test('目录解析保留容量、管理通道与内置 AFF 引用', () {
    final restored = EuiccCardPresetCatalog.decode(
      builtInEuiccCardPresetCatalog.encode(),
    );
    final v3 = restored.cards.singleWhere((item) => item.id == '9esim-v3');
    expect(v3.storageBytes, 1500 * 1024);
    expect(v3.maxProfileCount, 50);
    expect(v3.managementMethods, contains(EuiccManagementMethod.lpa));
    expect(v3.affiliateOffer.id, 'builtin-9esim');
  });

  test('下载成功后写入缓存，下次使用 ETag 取回有效目录', () async {
    final first = _FakeTransport([
      EuiccCardPresetResponse(
        statusCode: 200,
        body: catalog(
          version: 'remote-1',
          updatedAt: '2026-08-10T00:00:00.000Z',
        ),
        etag: '"euicc-1"',
      ),
    ]);
    final downloaded = await EuiccCardPresetService(
      sourceUri: Uri.parse('https://example.com/euicc-cards.json'),
      transport: first,
    ).load();
    expect(downloaded.source, EuiccCardPresetSource.network);
    expect(downloaded.catalog.catalogVersion, 'remote-1');

    final second = _FakeTransport([
      const EuiccCardPresetResponse(statusCode: 304),
    ]);
    final cached = await EuiccCardPresetService(
      sourceUri: Uri.parse('https://example.com/euicc-cards.json'),
      transport: second,
    ).load();
    expect(second.receivedEtag, '"euicc-1"');
    expect(cached.source, EuiccCardPresetSource.cache);
    expect(cached.catalog.catalogVersion, 'remote-1');
  });

  test('坏 JSON 和非内置 AFF 引用都不会覆盖已知有效目录', () async {
    final broken = await EuiccCardPresetService(
      sourceUri: Uri.parse('https://example.com/euicc-cards.json'),
      transport: _FakeTransport([
        const EuiccCardPresetResponse(statusCode: 200, body: '{broken'),
      ]),
    ).load();
    expect(broken.source, EuiccCardPresetSource.builtIn);
    expect(broken.warning, isNotNull);

    final injectedAffiliate = await EuiccCardPresetService(
      sourceUri: Uri.parse('https://example.com/euicc-cards.json'),
      transport: _FakeTransport([
        EuiccCardPresetResponse(
          statusCode: 200,
          body: catalog(
            version: 'bad-aff',
            updatedAt: '2026-08-10T00:00:00.000Z',
            affiliateOfferId: 'https://attacker.example/ref',
          ),
        ),
      ]),
    ).load();
    expect(injectedAffiliate.source, EuiccCardPresetSource.builtIn);
    expect(injectedAffiliate.warning, contains('affiliateOfferId'));
  });

  test('拒绝远端目录时间戳回滚', () async {
    await EuiccCardPresetService(
      sourceUri: Uri.parse('https://example.com/euicc-cards.json'),
      transport: _FakeTransport([
        EuiccCardPresetResponse(
          statusCode: 200,
          body: catalog(
            version: 'newer',
            updatedAt: '2026-08-11T00:00:00.000Z',
          ),
        ),
      ]),
    ).load();

    final result = await EuiccCardPresetService(
      sourceUri: Uri.parse('https://example.com/euicc-cards.json'),
      transport: _FakeTransport([
        EuiccCardPresetResponse(
          statusCode: 200,
          body: catalog(
            version: 'older',
            updatedAt: '2026-08-10T00:00:00.000Z',
          ),
        ),
      ]),
    ).load();
    expect(result.source, EuiccCardPresetSource.cache);
    expect(result.catalog.catalogVersion, 'newer');
    expect(result.warning, contains('拒绝回滚'));
  });

  test('拒绝非 HTTPS 目录地址', () {
    expect(
      () => EuiccCardPresetService(
        sourceUri: Uri.parse('http://example.com/euicc-cards.json'),
        transport: _FakeTransport(const []),
      ),
      throwsFormatException,
    );
  });
}

class _FakeTransport implements EuiccCardPresetTransport {
  _FakeTransport(this.responses);

  final List<EuiccCardPresetResponse> responses;
  String? receivedEtag;

  @override
  Future<EuiccCardPresetResponse> get(Uri uri, {String? etag}) async {
    receivedEtag = etag;
    if (responses.isEmpty) throw StateError('没有测试响应');
    return responses.removeAt(0);
  }
}
