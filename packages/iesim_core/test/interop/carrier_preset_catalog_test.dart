import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  const source = '''
{
  "schemaVersion": 1,
  "catalogVersion": "2026.08.1",
  "updatedAt": "2026-08-08T00:00:00.000Z",
  "carriers": [
    {
      "id": "carrier-uk",
      "displayName": "Carrier UK",
      "operatorName": "Carrier",
      "countryCode": "GB",
      "countryName": "英国",
      "flag": "🇬🇧",
      "timeZoneId": "Europe/London",
      "websiteUrl": "https://example.com/terms",
      "aliases": ["Example"],
      "keepAlive": {
        "cycleDays": 90,
        "qualifyingActions": ["mobileData", "topUp"],
        "summary": "90 天内使用",
        "constraints": [
          {
            "kind": "firstUse",
            "title": "首次使用",
            "details": "激活后在英国使用",
            "withinDays": 10,
            "regions": ["英国"]
          }
        ],
        "presetId": "carrier-uk",
        "sourceLabel": "官网",
        "sourceUrl": "https://example.com/terms",
        "sourceCheckedAt": "2026-08-08T00:00:00.000Z"
      }
    }
  ]
}
''';

  test('解析、搜索并稳定往返运营商复杂保号预设', () {
    final catalog = CarrierPresetCatalog.decode(source);
    final carrier = catalog.search('example').single;

    expect(carrier.keepAliveDays, 90);
    expect(
      carrier.keepAlivePolicy.qualifyingActions,
      containsAll([KeepAliveAction.mobileData, KeepAliveAction.topUp]),
    );
    expect(carrier.keepAlivePolicy.constraints.single.withinDays, 10);
    expect(
      CarrierPresetCatalog.decode(catalog.encode()).encode(),
      catalog.encode(),
    );
  });

  test('拒绝非 HTTPS 的规则来源', () {
    expect(
      () => CarrierPresetCatalog.decode(
        source.replaceFirst(
          'https://example.com/terms',
          'http://example.com/terms',
        ),
      ),
      throwsFormatException,
    );
  });
}
