import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/profile_catalog_service.dart';
import 'package:iesim_core/iesim_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _catalog = '''
{
  "reference_eum": "89044045",
  "results": [
    {
      "plmn": "20201",
      "serviceProviderName": "COSMOTE",
      "rsp": "rsp.example.com",
      "names": ["eSIM_COSMOTE"],
      "reference_size": 39008,
      "eum_sizes": {
        "89044045": 39008,
        "89049032": 41175
      }
    }
  ]
}
''';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('从 euicc.info 容量库读取 Profile 字节数', () async {
    final service = ProfileCatalogService(
      transport: _ProfileTransport([
        const ProfileCatalogResponse(
          statusCode: HttpStatus.ok,
          body: _catalog,
          etag: '"sizes-1"',
        ),
      ]),
    );

    final match = await service.lookup(
      LpaActivation.parse(r'LPA:1$rsp.example.com$CODE'),
    );

    expect(match.referenceEum, '89044045');
    expect(match.candidates.single.referenceSizeBytes, 39008);
    expect(match.candidates.single.sizeForEum('89049032'), 41175);
  });

  test('缓存容量库并通过 ETag 复用', () async {
    await ProfileCatalogService(
      transport: _ProfileTransport([
        const ProfileCatalogResponse(
          statusCode: HttpStatus.ok,
          body: _catalog,
          etag: '"sizes-1"',
        ),
      ]),
    ).lookup(LpaActivation.parse(r'LPA:1$rsp.example.com$CODE'));

    final transport = _ProfileTransport([
      const ProfileCatalogResponse(statusCode: HttpStatus.notModified),
    ]);
    final cached = await ProfileCatalogService(
      transport: transport,
    ).lookup(LpaActivation.parse(r'LPA:1$rsp.example.com$CODE'));

    expect(transport.receivedEtag, '"sizes-1"');
    expect(cached.candidates.single.referenceSizeBytes, 39008);
  });

  test('在线失败时使用最近一次有效缓存', () async {
    await ProfileCatalogService(
      transport: _ProfileTransport([
        const ProfileCatalogResponse(statusCode: HttpStatus.ok, body: _catalog),
      ]),
    ).lookup(LpaActivation.parse(r'LPA:1$rsp.example.com$CODE'));

    final cached = await ProfileCatalogService(
      transport: const _FailingProfileTransport(),
    ).lookup(LpaActivation.parse(r'LPA:1$rsp.example.com$CODE'));

    expect(cached.candidates.single.serviceProviderName, 'COSMOTE');
  });
}

class _ProfileTransport implements ProfileCatalogTransport {
  _ProfileTransport(this.responses);

  final List<ProfileCatalogResponse> responses;
  String? receivedEtag;

  @override
  Future<ProfileCatalogResponse> get(Uri uri, {String? etag}) async {
    receivedEtag = etag;
    return responses.removeAt(0);
  }
}

class _FailingProfileTransport implements ProfileCatalogTransport {
  const _FailingProfileTransport();

  @override
  Future<ProfileCatalogResponse> get(Uri uri, {String? etag}) {
    throw const SocketException('offline');
  }
}
