import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

const _source = r'''
mcc = "234"
country = "United Kingdom"
iso = "GB"

[[operators]]
mnc = "10"
plmn = "23410"
operator = "Telefonica Europe"
brand = "O2 (UK)"
icon = "o2"
icon_scope = "234"

[[operators.gids]]
gid1 = ""
gid2 = ""
profile_provider_names = ["generic"]
profile_names = []

[[operators.gids]]
gid1 = "508f"
gid2 = "ffff"
profile_provider_names = ["giffgaff"]
profile_names = ["giffgaff profile"]
icon = "giffgaff"
icon_scope = "234"

[[operators]]
mnc = "10"
operator = "Example MVNO"
brand = "Example"
icon = "example"
icon_scope = "234"
''';

void main() {
  test('按 MNC、名称及 GID 排序，并读取 GID 专用图标', () {
    final catalog = OperatorCatalog.decode(_source, expectedMcc: '234');

    final match = catalog.resolve(
      mnc: '10',
      gid1: '508F',
      gid2: 'FFFF',
      profileName: 'giffgaff profile',
      serviceProviderName: 'giffgaff',
    );

    expect(match, isNotNull);
    expect(match!.operatorName, 'Telefonica Europe');
    expect(match.brand, 'O2 (UK)');
    expect(match.displayName, 'giffgaff');
    expect(match.score, 150);
    expect(match.icon, 'giffgaff');
    expect(match.iconScope, '234');
  });

  test('短 MNC 会同时尝试两位和三位补零形式', () {
    final catalog = OperatorCatalog(
      mcc: '234',
      country: 'United Kingdom',
      iso: 'GB',
      operators: const [
        OperatorCatalogEntry(
          mnc: '010',
          operatorName: 'Telefonica Europe',
          brand: 'O2 (UK)',
          icon: 'o2',
          iconScope: '234',
        ),
      ],
    );
    expect(catalog.resolve(mnc: '10')?.displayName, 'O2 (UK)');
  });

  test('拒绝与请求 MCC 不一致的目录', () {
    expect(
      () => OperatorCatalog.decode(_source, expectedMcc: '460'),
      throwsFormatException,
    );
  });
}
