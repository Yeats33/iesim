import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/apple_app_store_lookup_service.dart';

void main() {
  test('通过公开 App ID 读取 Apple 元数据且请求不包含号码', () async {
    final transport = _FakeTransport(
      const AppleAppStoreLookupResponse(
        statusCode: 200,
        body: '''
{
  "resultCount": 1,
  "results": [{
    "trackId": 310633997,
    "trackName": "WhatsApp Messenger",
    "sellerName": "WhatsApp Inc.",
    "bundleId": "net.whatsapp.WhatsApp",
    "artworkUrl100": "https://example.com/icon.png",
    "trackViewUrl": "https://apps.apple.com/us/app/id310633997",
    "primaryGenreName": "Social Networking",
    "version": "26.1"
  }]
}
''',
      ),
    );
    final result = await AppleAppStoreLookupService(
      transport: transport,
    ).lookupById('310633997', country: 'ee');

    expect(result.name, 'WhatsApp Messenger');
    expect(result.bundleId, 'net.whatsapp.WhatsApp');
    expect(result.fetchedAt.isUtc, isTrue);
    expect(transport.uri!.host, 'itunes.apple.com');
    expect(transport.uri!.queryParameters, {
      'id': '310633997',
      'country': 'EE',
      'entity': 'software',
    });
    expect(transport.uri.toString(), isNot(contains('+372')));
  });

  test('拒绝无效 App ID 和空查询结果', () async {
    final service = AppleAppStoreLookupService(
      transport: _FakeTransport(
        const AppleAppStoreLookupResponse(
          statusCode: 200,
          body: '{"resultCount":0,"results":[]}',
        ),
      ),
    );

    await expectLater(
      service.lookupById('net.whatsapp'),
      throwsFormatException,
    );
    await expectLater(service.lookupById('310633997'), throwsFormatException);
  });
}

class _FakeTransport implements AppleAppStoreLookupTransport {
  _FakeTransport(this.response);

  final AppleAppStoreLookupResponse response;
  Uri? uri;

  @override
  Future<AppleAppStoreLookupResponse> get(Uri uri) async {
    this.uri = uri;
    return response;
  }
}
