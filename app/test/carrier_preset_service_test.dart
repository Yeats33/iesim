import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/carrier_preset_service.dart';
import 'package:iesim_core/iesim_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('内置预设包含 CTExcel UK 与 eSIM.gg 的官网规则', () {
    final catalog = CarrierPresetService.builtInCatalog;
    final ctExcel = catalog.carriers.singleWhere(
      (carrier) => carrier.id == 'ctexcel-uk',
    );
    final esimGg = catalog.carriers.singleWhere(
      (carrier) => carrier.id == 'esim-gg-estonia',
    );

    expect(ctExcel.keepAliveDays, 90);
    expect(
      ctExcel.keepAlivePolicy.qualifyingActions,
      containsAll([
        KeepAliveAction.mobileData,
        KeepAliveAction.call,
        KeepAliveAction.sms,
        KeepAliveAction.topUp,
        KeepAliveAction.planPurchase,
      ]),
    );
    expect(ctExcel.keepAlivePolicy.constraints, hasLength(3));
    expect(esimGg.keepAliveDays, 365);
    expect(esimGg.keepAlivePolicy.sourceUrl, 'https://esim.gg/support/faq');
  });

  test('远端不可用且无缓存时返回内置预设', () async {
    final result = await CarrierPresetService(
      sourceUri: Uri.parse('https://example.com/carriers.json'),
      transport: _FailingTransport(),
    ).load();

    expect(result.source, CarrierPresetSource.builtIn);
    expect(result.catalog.carriers, isNotEmpty);
    expect(result.warning, isNotNull);
  });

  test('下载成功后缓存并使用 ETag 做热更新', () async {
    final first = _FakeTransport([
      CarrierPresetResponse(
        statusCode: 200,
        body: CarrierPresetService.builtInCatalog.encode(),
        etag: '"carriers-1"',
      ),
    ]);
    final downloaded = await CarrierPresetService(
      sourceUri: Uri.parse('https://example.com/carriers.json'),
      transport: first,
    ).load();
    expect(downloaded.source, CarrierPresetSource.network);

    final second = _FakeTransport([
      const CarrierPresetResponse(statusCode: 304),
    ]);
    final cached = await CarrierPresetService(
      sourceUri: Uri.parse('https://example.com/carriers.json'),
      transport: second,
    ).load();
    expect(second.receivedEtag, '"carriers-1"');
    expect(cached.source, CarrierPresetSource.cache);
  });
}

class _FailingTransport implements CarrierPresetTransport {
  @override
  Future<CarrierPresetResponse> get(Uri uri, {String? etag}) {
    throw const FormatException('offline');
  }
}

class _FakeTransport implements CarrierPresetTransport {
  _FakeTransport(this.responses);

  final List<CarrierPresetResponse> responses;
  String? receivedEtag;

  @override
  Future<CarrierPresetResponse> get(Uri uri, {String? etag}) async {
    receivedEtag = etag;
    return responses.removeAt(0);
  }
}
