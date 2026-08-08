import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'country_calling_codes.dart';

class CarrierCountry {
  const CarrierCountry({
    required this.code,
    required this.name,
    required this.flag,
    required this.callingCode,
    required this.networkCount,
  });

  final String code;
  final String name;
  final String flag;
  final String? callingCode;
  final int networkCount;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    if ('$name $code'.toLowerCase().contains(normalized)) return true;
    final compact = normalized.replaceAll(RegExp(r'\s+'), '');
    final dialQuery = compact.startsWith('+') ? compact : '+$compact';
    return callingCode?.startsWith(dialQuery) ?? false;
  }
}

class CarrierApn {
  const CarrierApn({
    required this.name,
    required this.apn,
    this.types = const [],
    this.user,
    this.password,
    this.protocol,
    this.roamingProtocol,
  });

  final String name;
  final String apn;
  final List<String> types;
  final String? user;
  final String? password;
  final String? protocol;
  final String? roamingProtocol;

  bool get isGeneralInternet =>
      types.isEmpty || types.contains('default') || types.contains('*');
}

class CarrierNetwork {
  const CarrierNetwork({
    required this.countryCode,
    required this.countryName,
    required this.flag,
    required this.mcc,
    required this.mnc,
    required this.operatorName,
    required this.brand,
    required this.bands,
    required this.apns,
  });

  final String countryCode;
  final String countryName;
  final String flag;
  final String mcc;
  final String mnc;
  final String operatorName;
  final String brand;
  final String bands;
  final List<CarrierApn> apns;

  String get displayName => brand.trim().isEmpty ? operatorName : brand;
  String get plmn => '$mcc$mnc';

  CarrierApn? get preferredApn {
    for (final item in apns) {
      if (item.isGeneralInternet) return item;
    }
    return apns.isEmpty ? null : apns.first;
  }

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return [
      displayName,
      operatorName,
      brand,
      mcc,
      mnc,
      plmn,
      ...apns.map((item) => item.apn),
    ].join(' ').toLowerCase().contains(normalized);
  }
}

class CarrierNetworkCatalog {
  CarrierNetworkCatalog(List<CarrierNetwork> networks)
    : networks = List.unmodifiable(networks);

  final List<CarrierNetwork> networks;

  List<CarrierCountry> get countries {
    final grouped = <String, List<CarrierNetwork>>{};
    for (final network in networks) {
      grouped.putIfAbsent(network.countryCode, () => []).add(network);
    }
    final result = <CarrierCountry>[
      for (final entry in CountryCallingCodes.byIso.entries)
        CarrierCountry(
          code: entry.key,
          name: grouped[entry.key]?.first.countryName ?? entry.value.name,
          flag: _flag(entry.key),
          callingCode: entry.value.value,
          networkCount: grouped[entry.key]?.length ?? 0,
        ),
    ];
    for (final entry in grouped.entries) {
      if (CountryCallingCodes.byIso.containsKey(entry.key)) continue;
      result.add(
        CarrierCountry(
          code: entry.key,
          name: entry.value.first.countryName,
          flag: entry.value.first.flag,
          callingCode: null,
          networkCount: entry.value.length,
        ),
      );
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  List<CarrierNetwork> networksForCountry(String countryCode) {
    final result = networks
        .where((item) => item.countryCode == countryCode)
        .toList();
    result.sort((a, b) => a.displayName.compareTo(b.displayName));
    return result;
  }

  factory CarrierNetworkCatalog.decode({
    required String mccMncJson,
    required String aospApnXml,
  }) {
    final apns = _decodeAospApns(aospApnXml);
    final source = mccMncJson.replaceFirst('\uFEFF', '').trim();
    final dynamic decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('MCC-MNC.net 数据根节点必须是数组');
    }
    final networks = <CarrierNetwork>[];
    final seen = <String>{};
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final mcc = _text(row['MCC']);
      final mnc = _text(row['MNC']);
      final countryCode = _text(row['ISO'])?.toUpperCase();
      final countryName = _text(row['Country']);
      final operatorName = _text(row['Operator']);
      if (mcc == null ||
          mnc == null ||
          countryCode == null ||
          countryName == null ||
          operatorName == null ||
          !RegExp(r'^\d{3}$').hasMatch(mcc) ||
          !RegExp(r'^\d{2,3}$').hasMatch(mnc) ||
          !RegExp(r'^[A-Z]{2}$').hasMatch(countryCode)) {
        continue;
      }
      final brand = _text(row['Brand']) ?? '';
      final key = '$mcc:$mnc:${brand.isEmpty ? operatorName : brand}';
      if (!seen.add(key)) continue;
      networks.add(
        CarrierNetwork(
          countryCode: countryCode,
          countryName: countryName,
          flag: countryCode == 'XX' ? '🌐' : _flag(countryCode),
          mcc: mcc,
          mnc: mnc,
          operatorName: operatorName,
          brand: brand,
          bands: _text(row['Bands']) ?? '',
          apns: List.unmodifiable(apns['$mcc$mnc'] ?? const []),
        ),
      );
    }
    if (networks.isEmpty) throw const FormatException('运营商目录没有有效记录');
    return CarrierNetworkCatalog(networks);
  }

  static Map<String, List<CarrierApn>> _decodeAospApns(String source) {
    final document = XmlDocument.parse(source);
    final result = <String, List<CarrierApn>>{};
    final seen = <String>{};
    for (final element in document.findAllElements('apn')) {
      final mcc = element.getAttribute('mcc')?.trim();
      final mnc = element.getAttribute('mnc')?.trim();
      final apn = element.getAttribute('apn')?.trim();
      if (mcc == null ||
          mnc == null ||
          apn == null ||
          apn.isEmpty ||
          !RegExp(r'^\d{3}$').hasMatch(mcc) ||
          !RegExp(r'^\d{2,3}$').hasMatch(mnc)) {
        continue;
      }
      final types = (element.getAttribute('type') ?? '')
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      final carrier = element.getAttribute('carrier')?.trim();
      final key = '$mcc$mnc:$apn:${types.join(',')}';
      if (!seen.add(key)) continue;
      result
          .putIfAbsent('$mcc$mnc', () => [])
          .add(
            CarrierApn(
              name: carrier == null || carrier.isEmpty ? apn : carrier,
              apn: apn,
              types: types,
              user: _optionalAttribute(element, 'user'),
              password: _optionalAttribute(element, 'password'),
              protocol: _optionalAttribute(element, 'protocol'),
              roamingProtocol: _optionalAttribute(element, 'roaming_protocol'),
            ),
          );
    }
    for (final entries in result.values) {
      entries.sort((a, b) {
        if (a.isGeneralInternet != b.isGeneralInternet) {
          return a.isGeneralInternet ? -1 : 1;
        }
        return a.name.compareTo(b.name);
      });
    }
    return result;
  }
}

enum CarrierNetworkCatalogSource { network, cache, builtIn, mixed }

class CarrierNetworkCatalogLoadResult {
  const CarrierNetworkCatalogLoadResult({
    required this.catalog,
    required this.source,
    this.warning,
  });

  final CarrierNetworkCatalog catalog;
  final CarrierNetworkCatalogSource source;
  final String? warning;
}

abstract interface class CarrierNetworkCatalogTransport {
  Future<String> get(Uri uri);
}

class HttpCarrierNetworkCatalogTransport
    implements CarrierNetworkCatalogTransport {
  static const _maxBytes = 3 * 1024 * 1024;

  @override
  Future<String> get(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'iesim/0.0.1-alpha carrier-catalog',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('数据源返回 ${response.statusCode}', uri: uri);
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBytes) {
          throw const FormatException('运营商数据超过大小限制');
        }
      }
      return utf8.decode(bytes);
    } finally {
      client.close(force: true);
    }
  }
}

typedef CarrierNetworkPreferencesLoader = Future<SharedPreferences> Function();

class CarrierNetworkCatalogService {
  CarrierNetworkCatalogService({
    CarrierNetworkCatalogTransport? transport,
    CarrierNetworkPreferencesLoader? preferencesLoader,
    Uri? mccMncUri,
    Uri? aospApnUri,
  }) : _transport = transport ?? HttpCarrierNetworkCatalogTransport(),
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
       mccMncUri = mccMncUri ?? mccMncSourceUri,
       aospApnUri = aospApnUri ?? aospApnSourceUri;

  static final mccMncSourceUri = Uri.parse(
    'https://www.mcc-mnc.net/mcc-mnc.json',
  );
  static final aospApnSourceUri = Uri.parse(
    'https://android.googlesource.com/device/sample/+/main/etc/'
    'apns-full-conf.xml?format=TEXT',
  );

  static const mccMncAttribution = 'MCC-MNC.net · MIT License';
  static const aospAttribution =
      'Android Open Source Project APN · Apache License 2.0';

  static const _mccCacheKey = 'carrier_network_mcc_mnc_v1';
  static const _apnCacheKey = 'carrier_network_aosp_apn_v1';

  final CarrierNetworkCatalogTransport _transport;
  final CarrierNetworkPreferencesLoader _preferencesLoader;
  final Uri mccMncUri;
  final Uri aospApnUri;

  Future<CarrierNetworkCatalogLoadResult> load() async {
    final preferences = await _preferencesLoader();
    final warnings = <String>[];
    var networkSources = 0;
    var cacheSources = 0;

    String mccBody;
    try {
      final body = await _transport.get(mccMncUri);
      CarrierNetworkCatalog.decode(
        mccMncJson: body,
        aospApnXml: _builtInApnXml,
      );
      await preferences.setString(_mccCacheKey, body);
      mccBody = body;
      networkSources++;
    } catch (error) {
      final cached = preferences.getString(_mccCacheKey);
      if (cached != null) {
        mccBody = cached;
        cacheSources++;
      } else {
        mccBody = _builtInMccMncJson;
      }
      warnings.add('MCC-MNC.net 暂不可用：$error');
    }

    String apnBody;
    try {
      final encoded = await _transport.get(aospApnUri);
      final normalized = encoded.replaceAll(RegExp(r'\s+'), '');
      final body = utf8.decode(base64Decode(normalized));
      XmlDocument.parse(body);
      await preferences.setString(_apnCacheKey, body);
      apnBody = body;
      networkSources++;
    } catch (error) {
      final cached = preferences.getString(_apnCacheKey);
      if (cached != null) {
        apnBody = cached;
        cacheSources++;
      } else {
        apnBody = _builtInApnXml;
      }
      warnings.add('AOSP APN 暂不可用：$error');
    }

    CarrierNetworkCatalog catalog;
    try {
      catalog = CarrierNetworkCatalog.decode(
        mccMncJson: mccBody,
        aospApnXml: apnBody,
      );
    } catch (error) {
      catalog = CarrierNetworkCatalog.decode(
        mccMncJson: _builtInMccMncJson,
        aospApnXml: _builtInApnXml,
      );
      warnings.add('在线目录格式无效，已改用内置目录：$error');
      networkSources = 0;
      cacheSources = 0;
    }

    final source = networkSources == 2
        ? CarrierNetworkCatalogSource.network
        : cacheSources == 2
        ? CarrierNetworkCatalogSource.cache
        : networkSources == 0 && cacheSources == 0
        ? CarrierNetworkCatalogSource.builtIn
        : CarrierNetworkCatalogSource.mixed;
    return CarrierNetworkCatalogLoadResult(
      catalog: catalog,
      source: source,
      warning: warnings.isEmpty ? null : warnings.join('\n'),
    );
  }

  static const _builtInMccMncJson = r'''
[
  {"MCC":"460","MNC":"00","ISO":"CN","Country":"China","Operator":"China Mobile","Brand":"China Mobile","Bands":""},
  {"MCC":"460","MNC":"01","ISO":"CN","Country":"China","Operator":"China Unicom","Brand":"China Unicom","Bands":""},
  {"MCC":"460","MNC":"03","ISO":"CN","Country":"China","Operator":"China Telecom","Brand":"China Telecom","Bands":""},
  {"MCC":"234","MNC":"10","ISO":"GB","Country":"United Kingdom","Operator":"Telefonica UK Limited","Brand":"O2","Bands":""},
  {"MCC":"234","MNC":"15","ISO":"GB","Country":"United Kingdom","Operator":"Vodafone Limited","Brand":"Vodafone","Bands":""},
  {"MCC":"262","MNC":"01","ISO":"DE","Country":"Germany","Operator":"Telekom Deutschland GmbH","Brand":"Telekom","Bands":""},
  {"MCC":"310","MNC":"260","ISO":"US","Country":"United States","Operator":"T-Mobile USA","Brand":"T-Mobile","Bands":""}
]
''';

  static const _builtInApnXml = r'''
<?xml version="1.0" encoding="UTF-8"?>
<apns version="1">
  <apn carrier="China Mobile" mcc="460" mnc="00" apn="cmnet" type="default,supl" protocol="IPV4V6" />
  <apn carrier="China Unicom" mcc="460" mnc="01" apn="3gnet" type="default,supl" protocol="IPV4V6" />
  <apn carrier="China Telecom" mcc="460" mnc="03" apn="ctnet" type="default,supl" protocol="IPV4V6" />
  <apn carrier="O2 UK" mcc="234" mnc="10" apn="mobile.o2.co.uk" type="default,supl" protocol="IPV4V6" />
  <apn carrier="Vodafone UK" mcc="234" mnc="15" apn="internet" type="default,supl" protocol="IPV4V6" />
  <apn carrier="Telekom DE" mcc="262" mnc="01" apn="internet.telekom" type="default,supl" protocol="IPV4V6" />
  <apn carrier="T-Mobile US" mcc="310" mnc="260" apn="fast.t-mobile.com" type="default,supl" protocol="IPV4V6" />
</apns>
''';
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String? _optionalAttribute(XmlElement element, String name) {
  final value = element.getAttribute(name)?.trim();
  return value == null || value.isEmpty ? null : value;
}

String _flag(String countryCode) =>
    String.fromCharCodes(countryCode.codeUnits.map((item) => item + 0x1F1A5));
