import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/operator_identity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _catalog = r'''
mcc = "234"
country = "United Kingdom"
iso = "GB"

[[operators]]
mnc = "10"
operator = "Telefonica Europe"
brand = "O2 (UK)"
icon = "o2"
icon_scope = "234"

[[operators.gids]]
gid1 = "508f"
profile_provider_names = ["giffgaff"]
profile_names = ["giffgaff"]
icon = "giffgaff"
icon_scope = "234"
''';

final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  1,
]);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('按 Nekoko 证据顺序匹配运营商并缓存 Logo', () async {
    final transport = _Transport();
    final store = _MemoryIconStore();
    final service = OperatorIdentityService(
      transport: transport,
      iconStore: store,
    );

    final identity = await service.resolve(
      mcc: '234',
      mnc: '10',
      gid1: '508F',
      profileName: 'giffgaff',
      serviceProviderName: 'giffgaff',
    );

    expect(identity, isNotNull);
    expect(identity!.displayName, 'giffgaff');
    expect(identity.match.score, 150);
    expect(identity.iconUri.toString(), endsWith('/234/giffgaff.png'));
    expect(identity.iconBytes, _png);
    expect(store.values, hasLength(1));
    expect(transport.catalogRequests, 1);
    expect(transport.iconRequests, 1);
  });

  test('在线失败时复用目录和 Logo 的最近有效缓存', () async {
    final store = _MemoryIconStore();
    await OperatorIdentityService(
      transport: _Transport(),
      iconStore: store,
    ).resolve(mcc: '234', mnc: '10');

    final offline = await OperatorIdentityService(
      transport: const _FailingTransport(),
      iconStore: store,
    ).resolve(mcc: '234', mnc: '10');

    expect(offline?.displayName, 'O2 (UK)');
    expect(offline?.iconBytes, _png);
    expect(offline?.iconFromCache, isTrue);
  });

  test('不存在的 MCC 目录在本次运行中只请求一次', () async {
    final transport = _MissingTransport();
    final service = OperatorIdentityService(
      transport: transport,
      iconStore: _MemoryIconStore(),
    );

    expect(await service.resolve(mcc: '999', mnc: '01'), isNull);
    expect(await service.resolve(mcc: '999', mnc: '01'), isNull);
    expect(transport.requests, 1);
  });
}

class _Transport implements OperatorIdentityTransport {
  int catalogRequests = 0;
  int iconRequests = 0;

  @override
  Future<OperatorResourceResponse> get(Uri uri, {String? etag}) async {
    if (uri.path.endsWith('.toml')) {
      catalogRequests++;
      return OperatorResourceResponse(
        statusCode: HttpStatus.ok,
        bodyBytes: _catalog.codeUnits,
        etag: '"234-1"',
      );
    }
    iconRequests++;
    return OperatorResourceResponse(statusCode: HttpStatus.ok, bodyBytes: _png);
  }
}

class _FailingTransport implements OperatorIdentityTransport {
  const _FailingTransport();

  @override
  Future<OperatorResourceResponse> get(Uri uri, {String? etag}) {
    throw const SocketException('offline');
  }
}

class _MissingTransport implements OperatorIdentityTransport {
  int requests = 0;

  @override
  Future<OperatorResourceResponse> get(Uri uri, {String? etag}) async {
    requests++;
    return const OperatorResourceResponse(statusCode: HttpStatus.notFound);
  }
}

class _MemoryIconStore implements OperatorIconStore {
  final values = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String key) async => values[key];

  @override
  Future<void> write(String key, Uint8List bytes) async {
    values[key] = bytes;
  }
}
