import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/device_preset_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  String catalog(String version) => jsonEncode({
    'schemaVersion': 1,
    'catalogVersion': version,
    'updatedAt': '2026-08-08T00:00:00.000Z',
    'devices': [
      {
        'id': 'example-phone',
        'brand': 'Example',
        'model': 'Phone',
        'kind': 'phone',
        'simCapability': 'physicalPlusEsim',
      },
    ],
  });

  test('下载成功后写入缓存并在下次发送 ETag', () async {
    final first = _FakeTransport([
      DevicePresetResponse(
        statusCode: 200,
        body: catalog('1'),
        etag: '"catalog-1"',
      ),
    ]);
    final service = DevicePresetService(
      sourceUri: Uri.parse('https://example.com/devices.json'),
      transport: first,
    );

    final downloaded = await service.load();
    expect(downloaded.catalog.catalogVersion, '1');
    expect(downloaded.source, DevicePresetSource.network);

    final second = _FakeTransport([
      const DevicePresetResponse(statusCode: 304),
    ]);
    final cached = await DevicePresetService(
      sourceUri: Uri.parse('https://example.com/devices.json'),
      transport: second,
    ).load();
    expect(second.receivedEtag, '"catalog-1"');
    expect(cached.catalog.catalogVersion, '1');
    expect(cached.source, DevicePresetSource.cache);
  });

  test('远程坏数据不会覆盖上一次成功缓存', () async {
    await DevicePresetService(
      sourceUri: Uri.parse('https://example.com/devices.json'),
      transport: _FakeTransport([
        DevicePresetResponse(statusCode: 200, body: catalog('good')),
      ]),
    ).load();

    final result = await DevicePresetService(
      sourceUri: Uri.parse('https://example.com/devices.json'),
      transport: _FakeTransport([
        const DevicePresetResponse(statusCode: 200, body: '{broken'),
      ]),
    ).load();

    expect(result.catalog.catalogVersion, 'good');
    expect(result.source, DevicePresetSource.cache);
    expect(result.warning, isNotNull);
  });

  test('拒绝非 HTTPS 的目录地址', () {
    expect(
      () => DevicePresetService(
        sourceUri: Uri.parse('http://example.com/devices.json'),
        transport: _FakeTransport(const []),
      ),
      throwsFormatException,
    );
  });
}

class _FakeTransport implements DevicePresetTransport {
  _FakeTransport(this.responses);

  final List<DevicePresetResponse> responses;
  String? receivedEtag;

  @override
  Future<DevicePresetResponse> get(Uri uri, {String? etag}) async {
    receivedEtag = etag;
    if (responses.isEmpty) throw StateError('没有测试响应');
    return responses.removeAt(0);
  }
}
