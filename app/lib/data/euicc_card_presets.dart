import 'package:iesim_core/iesim_core.dart';

import 'builtin_affiliate_offers.dart';

class EuiccCardPreset {
  const EuiccCardPreset({
    required this.id,
    required this.brand,
    required this.displayName,
    required this.description,
    required this.officialUrl,
    required this.affiliateOffer,
  });

  final String id;
  final String brand;
  final String displayName;
  final String description;
  final String officialUrl;
  final AffiliateOffer affiliateOffer;
}

const builtinEuiccCardPresets = <EuiccCardPreset>[
  EuiccCardPreset(
    id: '9esim-removable',
    brand: '9eSIM',
    displayName: '9eSIM 可拆卸 eUICC',
    description: '可重复写入 Profile；需要设备具有实体 SIM 卡槽。',
    officialUrl: 'https://www.9esim.com/',
    affiliateOffer: nineEsimAffiliateOffer,
  ),
  EuiccCardPreset(
    id: 'estk-removable',
    brand: 'eSTK.me',
    displayName: 'eSTK.me 可拆卸 eUICC',
    description: '可通过支持 OMAPI 的 Android 设备或标准 CCID 读卡器管理。',
    officialUrl: 'https://www.estk.me/',
    affiliateOffer: estkAffiliateOffer,
  ),
];

EuiccCardPreset? euiccCardPresetById(String? id) {
  if (id == null) return null;
  for (final preset in builtinEuiccCardPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
