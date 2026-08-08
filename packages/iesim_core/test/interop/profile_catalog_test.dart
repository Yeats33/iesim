import 'dart:convert';

import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  test('按 SM-DP+ 精确匹配并去除重复行', () {
    final catalog = ProfileCatalog.decode(
      jsonEncode({
        'reference_eum': '89044045',
        'results': [
          {
            'plmn': '00101',
            'serviceProviderName': 'Provider A',
            'rsp': 'rsp.example.com',
            'names': ['Profile A'],
            'reference_size': 39008,
            'eum_sizes': {'89044045': 39008, '89049032': 41175},
          },
          {
            'plmn': '00101',
            'serviceProviderName': 'Provider A',
            'rsp': 'rsp.example.com',
            'names': ['Profile A'],
            'reference_size': 39008,
            'eum_sizes': {'89044045': 39008, '89049032': 41175},
          },
          {
            'plmn': '00102',
            'serviceProviderName': 'Provider B',
            'rsp': 'rsp.example.com',
          },
          {
            'plmn': '99999',
            'serviceProviderName': 'Wrong host',
            'rsp': 'other.example.com',
          },
        ],
      }),
    );

    final match = catalog.match(
      LpaActivation.parse(r'LPA:1$rsp.example.com$CODE'),
    );
    expect(match.candidates, hasLength(2));
    expect(match.providerNames, ['Provider A', 'Provider B']);
    expect(match.unambiguousProvider, isNull);
    expect(match.referenceEum, '89044045');
    final providerA = match.candidates.first;
    expect(providerA.referenceSizeBytes, 39008);
    expect(providerA.sizeForEum('89049032'), 41175);
    expect(providerA.minimumSizeBytes, 39008);
    expect(providerA.maximumSizeBytes, 41175);
  });

  test('唯一服务商可作为自动填充建议', () {
    final catalog = ProfileCatalog([
      const ProfileCatalogEntry(
        plmn: '00101',
        serviceProviderName: 'Provider A',
        rsp: 'rsp.example.com',
      ),
    ]);

    final match = catalog.match(
      LpaActivation.parse(r'LPA:1$rsp.example.com$CODE'),
    );
    expect(match.unambiguousProvider, 'Provider A');
  });
}
