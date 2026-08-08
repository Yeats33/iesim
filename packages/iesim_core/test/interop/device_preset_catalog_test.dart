import 'dart:convert';

import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  Map<String, dynamic> validCatalog() => {
    'schemaVersion': 1,
    'catalogVersion': '2026.08.1',
    'updatedAt': '2026-08-08T00:00:00.000Z',
    'devices': [
      {
        'id': 'example-phone-cn',
        'brand': '示例品牌',
        'model': 'Phone 1',
        'variant': '中国大陆版',
        'kind': 'phone',
        'region': 'CN',
        'simCapability': 'dualPhysical',
        'supportsSaRoaming': true,
        'slots': [
          {'label': 'SIM 1', 'kind': 'physical'},
          {'label': 'SIM 2', 'kind': 'physical'},
        ],
        'aliases': ['P1', 'Model A'],
      },
    ],
  };

  test('解析、搜索并稳定往返设备预设', () {
    final catalog = DevicePresetCatalog.decode(jsonEncode(validCatalog()));

    expect(catalog.catalogVersion, '2026.08.1');
    expect(catalog.devices.single.displayName, 'Phone 1（中国大陆版）');
    expect(catalog.devices.single.slots, hasLength(2));
    expect(catalog.search('示例 CN'), hasLength(1));
    expect(catalog.search('model a'), hasLength(1));
    expect(catalog.search('不存在'), isEmpty);

    final roundTrip = DevicePresetCatalog.decode(catalog.encode());
    expect(roundTrip.devices.single.simCapability, SimCapability.dualPhysical);
    expect(roundTrip.devices.single.supportsSaRoaming, isTrue);
  });

  test('拒绝未知 schema 和未知枚举', () {
    final schema = validCatalog()..['schemaVersion'] = 2;
    expect(
      () => DevicePresetCatalog.decode(jsonEncode(schema)),
      throwsFormatException,
    );

    final capability = validCatalog();
    (capability['devices'] as List).single['simCapability'] = 'tripleSim';
    expect(
      () => DevicePresetCatalog.decode(jsonEncode(capability)),
      throwsFormatException,
    );
  });

  test('拒绝重复 id 和非 UTC 更新时间', () {
    final duplicate =
        jsonDecode(jsonEncode(validCatalog())) as Map<String, dynamic>;
    final devices = duplicate['devices'] as List<dynamic>;
    devices.add(jsonDecode(jsonEncode(devices.single)));
    expect(
      () => DevicePresetCatalog.decode(jsonEncode(duplicate)),
      throwsFormatException,
    );

    final localTime = validCatalog()..['updatedAt'] = '2026-08-08T08:00:00';
    expect(
      () => DevicePresetCatalog.decode(jsonEncode(localTime)),
      throwsFormatException,
    );
  });
}
