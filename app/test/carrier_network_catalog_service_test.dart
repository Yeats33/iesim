import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/carrier_network_catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mccMncJson = '''
[
  {"MCC":"234","MNC":"15","ISO":"GB","Country":"United Kingdom","Operator":"Vodafone Limited","Brand":"Vodafone","Bands":"LTE"},
  {"MCC":"234","MNC":"10","ISO":"GB","Country":"United Kingdom","Operator":"Telefonica UK","Brand":"O2","Bands":"LTE"}
]
''';

const _apnXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<apns version="1">
  <apn carrier="Vodafone Internet" mcc="234" mnc="15" apn="internet" type="default,supl" protocol="IPV4V6" />
  <apn carrier="Vodafone MMS" mcc="234" mnc="15" apn="wap.vodafone.co.uk" type="mms" />
  <apn carrier="O2 Internet" mcc="234" mnc="10" apn="mobile.o2.co.uk" type="default" />
</apns>
''';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('按国家合并 MCC-MNC.net 运营商与 AOSP APN', () {
    final catalog = CarrierNetworkCatalog.decode(
      mccMncJson: '\uFEFF$_mccMncJson',
      aospApnXml: _apnXml,
    );

    final unitedKingdom = catalog.countries.singleWhere(
      (country) => country.code == 'GB',
    );
    expect(unitedKingdom.flag, '🇬🇧');
    expect(unitedKingdom.callingCode, '+44');
    expect(unitedKingdom.networkCount, 2);
    expect(unitedKingdom.matches('+44'), isTrue);
    expect(unitedKingdom.matches('44'), isTrue);
    expect(unitedKingdom.matches('gb'), isTrue);
    expect(unitedKingdom.matches('United Kingdom'), isTrue);

    final japan = catalog.countries.singleWhere(
      (country) => country.code == 'JP',
    );
    expect(japan.callingCode, '+81');
    expect(japan.networkCount, 0);

    final networks = catalog.networksForCountry('GB');
    final vodafone = networks.singleWhere(
      (network) => network.displayName == 'Vodafone',
    );
    expect(vodafone.mcc, '234');
    expect(vodafone.mnc, '15');
    expect(vodafone.apns, hasLength(2));
    expect(vodafone.preferredApn?.apn, 'internet');
  });

  test('在线目录会缓存，离线后继续使用缓存', () async {
    final online = await CarrierNetworkCatalogService(
      transport: const _CatalogTransport(),
    ).load();
    expect(online.source, CarrierNetworkCatalogSource.network);
    expect(online.catalog.networksForCountry('GB'), hasLength(2));

    final offline = await CarrierNetworkCatalogService(
      transport: const _FailingCatalogTransport(),
    ).load();
    expect(offline.source, CarrierNetworkCatalogSource.cache);
    expect(offline.catalog.networksForCountry('GB'), hasLength(2));
    expect(offline.warning, contains('暂不可用'));
  });

  test('首次离线时仍提供内置基础目录', () async {
    final result = await CarrierNetworkCatalogService(
      transport: const _FailingCatalogTransport(),
    ).load();

    expect(result.source, CarrierNetworkCatalogSource.builtIn);
    expect(result.catalog.countries, isNotEmpty);
    expect(
      result.catalog
          .networksForCountry('CN')
          .firstWhere((network) => network.mnc == '00')
          .preferredApn
          ?.apn,
      'cmnet',
    );
  });
}

class _CatalogTransport implements CarrierNetworkCatalogTransport {
  const _CatalogTransport();

  @override
  Future<String> get(Uri uri) async {
    if (uri == CarrierNetworkCatalogService.mccMncSourceUri) {
      return _mccMncJson;
    }
    if (uri == CarrierNetworkCatalogService.aospApnSourceUri) {
      return base64Encode(utf8.encode(_apnXml));
    }
    throw StateError('unexpected URI: $uri');
  }
}

class _FailingCatalogTransport implements CarrierNetworkCatalogTransport {
  const _FailingCatalogTransport();

  @override
  Future<String> get(Uri uri) => throw const FormatException('offline');
}
