import 'dart:convert';

import '../model/assets.dart';

/// A versioned, data-only catalog of device model presets.
class DevicePresetCatalog {
  DevicePresetCatalog({
    required this.catalogVersion,
    required this.updatedAt,
    required List<DevicePreset> devices,
  }) : devices = List.unmodifiable(devices) {
    _requiredText(catalogVersion, 'catalogVersion', maxLength: 80);
    if (!updatedAt.isUtc) {
      throw ArgumentError.value(updatedAt, 'updatedAt', '必须使用 UTC 时间');
    }
    if (devices.length > 5000) {
      throw const FormatException('设备预设不能超过 5000 条');
    }
    final ids = <String>{};
    for (final device in devices) {
      if (!ids.add(device.id)) {
        throw FormatException('设备预设 id 重复：${device.id}');
      }
    }
  }

  static const schemaVersion = 1;

  final String catalogVersion;
  final DateTime updatedAt;
  final List<DevicePreset> devices;

  factory DevicePresetCatalog.decode(String source) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('设备预设不是有效 JSON：${error.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('设备预设根节点必须是对象');
    }
    if (decoded['schemaVersion'] != schemaVersion) {
      throw FormatException(
        '不支持的设备预设 schemaVersion：${decoded['schemaVersion']}',
      );
    }
    final entries = decoded['devices'];
    if (entries is! List) {
      throw const FormatException('devices 必须是数组');
    }
    final updatedAt = DateTime.tryParse(_string(decoded, 'updatedAt'));
    if (updatedAt == null || !updatedAt.isUtc) {
      throw const FormatException('updatedAt 必须是带时区的 ISO 8601 UTC 时间');
    }
    return DevicePresetCatalog(
      catalogVersion: _string(decoded, 'catalogVersion'),
      updatedAt: updatedAt,
      devices: [
        for (var index = 0; index < entries.length; index++)
          DevicePreset.fromJson(_map(entries[index], 'devices[$index]')),
      ],
    );
  }

  String encode() => jsonEncode({
    'schemaVersion': schemaVersion,
    'catalogVersion': catalogVersion,
    'updatedAt': updatedAt.toIso8601String(),
    'devices': [for (final device in devices) device.toJson()],
  });

  List<DevicePreset> search(String query) {
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    if (terms.isEmpty) return devices;
    return [
      for (final device in devices)
        if (terms.every(device.matches)) device,
    ];
  }
}

class DevicePreset {
  DevicePreset({
    required this.id,
    required this.brand,
    required this.model,
    this.variant,
    this.kind = DeviceKind.phone,
    this.region,
    this.note,
    this.simCapability = SimCapability.unknown,
    this.supportsSaRoaming = false,
    List<DevicePresetSlot> slots = const [],
    List<String> aliases = const [],
  }) : slots = List.unmodifiable(slots),
       aliases = List.unmodifiable(aliases) {
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{1,79}$').hasMatch(id)) {
      throw FormatException('设备预设 id 格式无效：$id');
    }
    _requiredText(brand, 'brand', maxLength: 80);
    _requiredText(model, 'model', maxLength: 120);
    _optionalText(variant, 'variant', maxLength: 120);
    _optionalText(region, 'region', maxLength: 40);
    _optionalText(note, 'note', maxLength: 1000);
    if (slots.length > 8) throw const FormatException('单个设备的卡槽不能超过 8 个');
    if (aliases.length > 20) throw const FormatException('单个设备的别名不能超过 20 个');
    for (final alias in aliases) {
      _requiredText(alias, 'aliases', maxLength: 120);
    }
  }

  final String id;
  final String brand;
  final String model;
  final String? variant;
  final DeviceKind kind;
  final String? region;
  final String? note;
  final SimCapability simCapability;
  final bool supportsSaRoaming;
  final List<DevicePresetSlot> slots;
  final List<String> aliases;

  String get displayName => switch (variant?.trim()) {
    final value? when value.isNotEmpty => '$model（$value）',
    _ => model,
  };

  bool matches(String term) => <String>[
    id,
    brand,
    model,
    ?variant,
    ?region,
    ...aliases,
  ].join(' ').toLowerCase().contains(term);

  factory DevicePreset.fromJson(Map<String, dynamic> value) {
    final slotValues = value['slots'] ?? const <dynamic>[];
    final aliasValues = value['aliases'] ?? const <dynamic>[];
    if (slotValues is! List) throw const FormatException('slots 必须是数组');
    if (aliasValues is! List) throw const FormatException('aliases 必须是数组');
    return DevicePreset(
      id: _string(value, 'id'),
      brand: _string(value, 'brand'),
      model: _string(value, 'model'),
      variant: _optionalString(value, 'variant'),
      kind: _enumValue(DeviceKind.values, value['kind'], 'kind'),
      region: _optionalString(value, 'region'),
      note: _optionalString(value, 'note'),
      simCapability: _enumValue(
        SimCapability.values,
        value['simCapability'],
        'simCapability',
      ),
      supportsSaRoaming: _optionalBool(value, 'supportsSaRoaming') ?? false,
      slots: [
        for (var index = 0; index < slotValues.length; index++)
          DevicePresetSlot.fromJson(_map(slotValues[index], 'slots[$index]')),
      ],
      aliases: [
        for (var index = 0; index < aliasValues.length; index++)
          _listString(aliasValues[index], 'aliases[$index]'),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'brand': brand,
    'model': model,
    if (variant != null) 'variant': variant,
    'kind': kind.name,
    if (region != null) 'region': region,
    if (note != null) 'note': note,
    'simCapability': simCapability.name,
    'supportsSaRoaming': supportsSaRoaming,
    'slots': [for (final slot in slots) slot.toJson()],
    if (aliases.isNotEmpty) 'aliases': aliases,
  };
}

class DevicePresetSlot {
  DevicePresetSlot({required this.label, required this.kind}) {
    _requiredText(label, 'slot.label', maxLength: 40);
  }

  final String label;
  final SimSlotKind kind;

  factory DevicePresetSlot.fromJson(Map<String, dynamic> value) =>
      DevicePresetSlot(
        label: _string(value, 'label'),
        kind: _enumValue(SimSlotKind.values, value['kind'], 'slot.kind'),
      );

  Map<String, dynamic> toJson() => {'label': label, 'kind': kind.name};
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$field 必须是对象');
}

String _string(Map<String, dynamic> value, String field) {
  final item = value[field];
  if (item is String) return item;
  throw FormatException('$field 必须是字符串');
}

String? _optionalString(Map<String, dynamic> value, String field) {
  final item = value[field];
  if (item == null) return null;
  if (item is String) return item;
  throw FormatException('$field 必须是字符串或 null');
}

String _listString(Object? value, String field) {
  if (value is String) return value;
  throw FormatException('$field 必须是字符串');
}

bool? _optionalBool(Map<String, dynamic> value, String field) {
  final item = value[field];
  if (item == null) return null;
  if (item is bool) return item;
  throw FormatException('$field 必须是布尔值或 null');
}

T _enumValue<T extends Enum>(List<T> values, Object? value, String field) {
  if (value is! String) throw FormatException('$field 必须是字符串');
  for (final item in values) {
    if (item.name == value) return item;
  }
  throw FormatException('$field 的值不受支持：$value');
}

void _requiredText(String value, String field, {required int maxLength}) {
  if (value.trim().isEmpty || value.length > maxLength) {
    throw FormatException('$field 不能为空且不能超过 $maxLength 个字符');
  }
}

void _optionalText(String? value, String field, {required int maxLength}) {
  if (value != null && (value.trim().isEmpty || value.length > maxLength)) {
    throw FormatException('$field 不能是空字符串且不能超过 $maxLength 个字符');
  }
}
