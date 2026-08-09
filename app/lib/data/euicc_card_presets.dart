import 'dart:convert';

import 'package:iesim_core/iesim_core.dart';

import 'builtin_affiliate_offers.dart';

enum EuiccManagementMethod { stk, lpa, omapi, ccid, vendorApp }

class EuiccCardPreset {
  const EuiccCardPreset({
    required this.id,
    required this.brand,
    required this.model,
    required this.storageLabel,
    required this.storageBytes,
    required this.profileCapacityLabel,
    required this.maxProfileCount,
    required this.managementLabel,
    required this.managementMethods,
    required this.description,
    required this.officialUrl,
    required this.affiliateOffer,
  });

  final String id;
  final String brand;
  final String model;
  final String storageLabel;
  final int? storageBytes;
  final String profileCapacityLabel;
  final int? maxProfileCount;
  final String managementLabel;
  final Set<EuiccManagementMethod> managementMethods;
  final String description;
  final String officialUrl;
  final AffiliateOffer affiliateOffer;

  String get displayName => '$brand $model';

  String get specificationSummary =>
      '$storageLabel · $profileCapacityLabel · $managementLabel';

  factory EuiccCardPreset.fromJson(Map<String, dynamic> value) {
    final methods = value['managementMethods'];
    if (methods is! List || methods.isEmpty || methods.length > 8) {
      throw const FormatException('managementMethods 必须是 1–8 项的数组');
    }
    final storageBytes = _requiredInt(value, 'storageBytes');
    if (storageBytes <= 0 || storageBytes > 16 * 1024 * 1024) {
      throw const FormatException('storageBytes 必须在 1 字节至 16 MiB 之间');
    }
    final maxProfileCount = _optionalInt(value, 'maxProfileCount');
    if (maxProfileCount != null &&
        (maxProfileCount <= 0 || maxProfileCount > 500)) {
      throw const FormatException('maxProfileCount 必须在 1–500 之间');
    }
    final id = _requiredText(value, 'id', 80);
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{1,79}$').hasMatch(id)) {
      throw FormatException('eUICC 预设 id 格式无效：$id');
    }
    final officialUrl = _requiredText(value, 'officialUrl', 500);
    final uri = Uri.tryParse(officialUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('officialUrl 必须是 HTTPS 地址');
    }
    final affiliateOfferId = _requiredText(value, 'affiliateOfferId', 80);
    final affiliateOffer = switch (affiliateOfferId) {
      'builtin-9esim' => nineEsimAffiliateOffer,
      'builtin-estk' => estkAffiliateOffer,
      _ => throw FormatException('不支持的 affiliateOfferId：$affiliateOfferId'),
    };
    return EuiccCardPreset(
      id: id,
      brand: _requiredText(value, 'brand', 80),
      model: _requiredText(value, 'model', 120),
      storageLabel: _requiredText(value, 'storageLabel', 80),
      storageBytes: storageBytes,
      profileCapacityLabel: _requiredText(value, 'profileCapacityLabel', 160),
      maxProfileCount: maxProfileCount,
      managementLabel: _requiredText(value, 'managementLabel', 160),
      managementMethods: {
        for (var index = 0; index < methods.length; index++)
          _enumValue(
            EuiccManagementMethod.values,
            methods[index],
            'managementMethods[$index]',
          ),
      },
      description: _requiredText(value, 'description', 1000),
      officialUrl: officialUrl,
      affiliateOffer: affiliateOffer,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'brand': brand,
    'model': model,
    'storageLabel': storageLabel,
    'storageBytes': storageBytes,
    'profileCapacityLabel': profileCapacityLabel,
    'maxProfileCount': maxProfileCount,
    'managementLabel': managementLabel,
    'managementMethods': managementMethods.map((item) => item.name).toList(),
    'description': description,
    'officialUrl': officialUrl,
    'affiliateOfferId': affiliateOffer.id,
  };
}

class EuiccCardPresetCatalog {
  EuiccCardPresetCatalog({
    required this.catalogVersion,
    required this.updatedAt,
    required Iterable<EuiccCardPreset> cards,
  }) : cards = List.unmodifiable(cards) {
    if (catalogVersion.trim().isEmpty || catalogVersion.length > 80) {
      throw const FormatException('catalogVersion 不能为空且不能超过 80 个字符');
    }
    if (!updatedAt.isUtc) {
      throw const FormatException('updatedAt 必须是 UTC 时间');
    }
    if (this.cards.length > 1000) {
      throw const FormatException('eUICC 卡片预设不能超过 1000 条');
    }
    final ids = <String>{};
    for (final card in this.cards) {
      if (!ids.add(card.id)) throw FormatException('eUICC 预设 id 重复：${card.id}');
    }
  }

  static const schemaVersion = 1;

  final String catalogVersion;
  final DateTime updatedAt;
  final List<EuiccCardPreset> cards;

  factory EuiccCardPresetCatalog.decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('eUICC 预设不是有效 JSON：${error.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('eUICC 预设根节点必须是对象');
    }
    if (decoded['schemaVersion'] != schemaVersion) {
      throw FormatException(
        '不支持的 eUICC 预设 schemaVersion：${decoded['schemaVersion']}',
      );
    }
    final updatedAt = DateTime.tryParse(
      _requiredText(decoded, 'updatedAt', 80),
    );
    if (updatedAt == null || !updatedAt.isUtc) {
      throw const FormatException('updatedAt 必须是带 Z 的 UTC 时间');
    }
    final cards = decoded['cards'];
    if (cards is! List) throw const FormatException('cards 必须是数组');
    return EuiccCardPresetCatalog(
      catalogVersion: _requiredText(decoded, 'catalogVersion', 80),
      updatedAt: updatedAt,
      cards: [
        for (var index = 0; index < cards.length; index++)
          EuiccCardPreset.fromJson(_map(cards[index], 'cards[$index]')),
      ],
    );
  }

  String encode() => jsonEncode({
    'schemaVersion': schemaVersion,
    'catalogVersion': catalogVersion,
    'updatedAt': updatedAt.toIso8601String(),
    'cards': [for (final card in cards) card.toJson()],
  });

  List<EuiccCardPreset> search(String query) {
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) return cards;
    return [
      for (final card in cards)
        if (terms.every(
          (term) => <String>[
            card.id,
            card.brand,
            card.model,
            card.storageLabel,
            card.managementLabel,
          ].join(' ').toLowerCase().contains(term),
        ))
          card,
    ];
  }
}

const builtinEuiccCardPresets = <EuiccCardPreset>[
  EuiccCardPreset(
    id: '9esim-v0',
    brand: '9eSIM',
    model: 'V0',
    storageLabel: '480 KB',
    storageBytes: 480 * 1024,
    profileCapacityLabel: '最多约 15 个 Profile',
    maxProfileCount: 15,
    managementLabel: 'STK 切换 · ECP OS',
    managementMethods: {
      EuiccManagementMethod.stk,
      EuiccManagementMethod.lpa,
      EuiccManagementMethod.ccid,
    },
    description: '入门型号；可重复擦写，需要设备具有实体 SIM 卡槽。',
    officialUrl: 'https://www.9esim.com/',
    affiliateOffer: nineEsimAffiliateOffer,
  ),
  EuiccCardPreset(
    id: '9esim-v0-max',
    brand: '9eSIM',
    model: 'V0 Max',
    storageLabel: '1.1 MB',
    storageBytes: 1100 * 1024,
    profileCapacityLabel: '最多约 30 个 Profile',
    maxProfileCount: 30,
    managementLabel: 'STK 切换 · ECP OS',
    managementMethods: {
      EuiccManagementMethod.stk,
      EuiccManagementMethod.lpa,
      EuiccManagementMethod.ccid,
    },
    description: 'V0 的大容量版本；可重复擦写，需要设备具有实体 SIM 卡槽。',
    officialUrl: 'https://www.9esim.com/',
    affiliateOffer: nineEsimAffiliateOffer,
  ),
  EuiccCardPreset(
    id: '9esim-v3',
    brand: '9eSIM',
    model: 'V3',
    storageLabel: '1.5 MB',
    storageBytes: 1500 * 1024,
    profileCapacityLabel: '最多约 50 个 Profile',
    maxProfileCount: 50,
    managementLabel: 'STK 切换 · Kigen OS',
    managementMethods: {
      EuiccManagementMethod.stk,
      EuiccManagementMethod.lpa,
      EuiccManagementMethod.ccid,
    },
    description: '旗舰型号；英国制造，支持通过 STK 菜单快速切换已写入的 Profile。',
    officialUrl: 'https://www.9esim.com/',
    affiliateOffer: nineEsimAffiliateOffer,
  ),
  EuiccCardPreset(
    id: 'estk-c-beta',
    brand: 'eSTK.me',
    model: 'C (Beta)',
    storageLabel: '512 KiB',
    storageBytes: 512 * 1024,
    profileCapacityLabel: '数量取决于 Profile 大小',
    maxProfileCount: null,
    managementLabel: '跨平台 App · OMAPI / CCID',
    managementMethods: {
      EuiccManagementMethod.vendorApp,
      EuiccManagementMethod.stk,
      EuiccManagementMethod.omapi,
      EuiccManagementMethod.ccid,
    },
    description: '日常使用的软塑料卡基入门型号；当前由官方标记为 Beta。',
    officialUrl: 'https://store.estk.me/products',
    affiliateOffer: estkAffiliateOffer,
  ),
  EuiccCardPreset(
    id: 'estk-plus',
    brand: 'eSTK.me',
    model: 'Plus+',
    storageLabel: '1024 KiB',
    storageBytes: 1024 * 1024,
    profileCapacityLabel: '约 13–26 个 Profile',
    maxProfileCount: 26,
    managementLabel: '跨平台 App · OMAPI / CCID',
    managementMethods: {
      EuiccManagementMethod.vendorApp,
      EuiccManagementMethod.stk,
      EuiccManagementMethod.omapi,
      EuiccManagementMethod.ccid,
    },
    description: '工业级一体封装的主流容量型号，适合经常切换运营商的用户。',
    officialUrl: 'https://store.estk.me/products',
    affiliateOffer: estkAffiliateOffer,
  ),
  EuiccCardPreset(
    id: 'estk-max',
    brand: 'eSTK.me',
    model: 'Max',
    storageLabel: '1600 KiB',
    storageBytes: 1600 * 1024,
    profileCapacityLabel: '最多约 60 个 Profile',
    maxProfileCount: 60,
    managementLabel: '跨平台 App · OMAPI / CCID',
    managementMethods: {
      EuiccManagementMethod.vendorApp,
      EuiccManagementMethod.stk,
      EuiccManagementMethod.omapi,
      EuiccManagementMethod.ccid,
    },
    description: '工业级一体封装的大容量型号；实际可写入数量取决于每个 Profile 大小。',
    officialUrl: 'https://store.estk.me/products',
    affiliateOffer: estkAffiliateOffer,
  ),
];

final builtInEuiccCardPresetCatalog = EuiccCardPresetCatalog(
  catalogVersion: '2026.08.09.1',
  updatedAt: DateTime.utc(2026, 8, 9),
  cards: builtinEuiccCardPresets,
);

EuiccCardPreset? euiccCardPresetById(
  String? id, {
  Iterable<EuiccCardPreset> presets = builtinEuiccCardPresets,
}) {
  if (id == null) return null;
  for (final preset in presets) {
    if (preset.id == id) return preset;
  }
  return null;
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$field 必须是对象');
}

String _requiredText(Map<String, dynamic> value, String field, int maxLength) {
  final item = value[field];
  if (item is! String || item.trim().isEmpty || item.length > maxLength) {
    throw FormatException('$field 必须是 1–$maxLength 个字符的字符串');
  }
  return item;
}

int _requiredInt(Map<String, dynamic> value, String field) {
  final item = value[field];
  if (item is int) return item;
  throw FormatException('$field 必须是整数');
}

int? _optionalInt(Map<String, dynamic> value, String field) {
  final item = value[field];
  if (item == null) return null;
  if (item is int) return item;
  throw FormatException('$field 必须是整数或 null');
}

T _enumValue<T extends Enum>(List<T> values, Object? value, String field) {
  if (value is! String) throw FormatException('$field 必须是字符串');
  for (final item in values) {
    if (item.name == value) return item;
  }
  throw FormatException('$field 的值不受支持：$value');
}
