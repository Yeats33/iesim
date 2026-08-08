import 'dart:convert';

import '../model/keep_alive.dart';

/// Versioned carrier and keep-alive presets, suitable for GitHub hot updates.
class CarrierPresetCatalog {
  CarrierPresetCatalog({
    required this.catalogVersion,
    required this.updatedAt,
    required List<CarrierPreset> carriers,
  }) : carriers = List.unmodifiable(carriers) {
    _requiredText(catalogVersion, 'catalogVersion', 80);
    if (!updatedAt.isUtc) {
      throw ArgumentError.value(updatedAt, 'updatedAt', '必须使用 UTC 时间');
    }
    if (carriers.length > 5000) {
      throw const FormatException('运营商预设不能超过 5000 条');
    }
    final ids = <String>{};
    for (final carrier in carriers) {
      if (!ids.add(carrier.id)) {
        throw FormatException('运营商预设 id 重复：${carrier.id}');
      }
    }
  }

  static const schemaVersion = 1;

  final String catalogVersion;
  final DateTime updatedAt;
  final List<CarrierPreset> carriers;

  factory CarrierPresetCatalog.decode(String source) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('运营商预设不是有效 JSON：${error.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('运营商预设根节点必须是对象');
    }
    if (decoded['schemaVersion'] != schemaVersion) {
      throw FormatException(
        '不支持的运营商预设 schemaVersion：${decoded['schemaVersion']}',
      );
    }
    final entries = decoded['carriers'];
    if (entries is! List) throw const FormatException('carriers 必须是数组');
    final updatedAt = DateTime.tryParse(_string(decoded, 'updatedAt'));
    if (updatedAt == null || !updatedAt.isUtc) {
      throw const FormatException('updatedAt 必须是带时区的 ISO 8601 UTC 时间');
    }
    return CarrierPresetCatalog(
      catalogVersion: _string(decoded, 'catalogVersion'),
      updatedAt: updatedAt,
      carriers: [
        for (var index = 0; index < entries.length; index++)
          CarrierPreset.fromJson(_map(entries[index], 'carriers[$index]')),
      ],
    );
  }

  String encode() => jsonEncode({
    'schemaVersion': schemaVersion,
    'catalogVersion': catalogVersion,
    'updatedAt': updatedAt.toIso8601String(),
    'carriers': [for (final carrier in carriers) carrier.toJson()],
  });

  List<CarrierPreset> search(String query) {
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    if (terms.isEmpty) return carriers;
    return [
      for (final carrier in carriers)
        if (terms.every(carrier.matches)) carrier,
    ];
  }
}

class CarrierPreset {
  CarrierPreset({
    required this.id,
    required this.displayName,
    required this.operatorName,
    required this.countryCode,
    required this.countryName,
    required this.flag,
    required this.timeZoneId,
    required this.websiteUrl,
    required this.keepAliveDays,
    required this.keepAlivePolicy,
    List<String> aliases = const [],
  }) : aliases = List.unmodifiable(aliases) {
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{1,79}$').hasMatch(id)) {
      throw FormatException('运营商预设 id 格式无效：$id');
    }
    _requiredText(displayName, 'displayName', 120);
    _requiredText(operatorName, 'operatorName', 120);
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(countryCode)) {
      throw const FormatException('countryCode 必须是两位大写国家代码');
    }
    _requiredText(countryName, 'countryName', 80);
    _requiredText(flag, 'flag', 16);
    _requiredText(timeZoneId, 'timeZoneId', 80);
    final uri = Uri.tryParse(websiteUrl);
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw const FormatException('websiteUrl 必须是有效的 HTTPS 地址');
    }
    if (keepAliveDays <= 0) {
      throw ArgumentError.value(keepAliveDays, 'keepAliveDays', '必须为正数');
    }
    if (aliases.length > 30) throw const FormatException('别名不能超过 30 个');
    for (final alias in aliases) {
      _requiredText(alias, 'aliases', 120);
    }
  }

  final String id;
  final String displayName;
  final String operatorName;
  final String countryCode;
  final String countryName;
  final String flag;
  final String timeZoneId;
  final String websiteUrl;
  final int keepAliveDays;
  final KeepAlivePolicy keepAlivePolicy;
  final List<String> aliases;

  bool matches(String term) => <String>[
    id,
    displayName,
    operatorName,
    countryCode,
    countryName,
    ...aliases,
  ].join(' ').toLowerCase().contains(term);

  factory CarrierPreset.fromJson(Map<String, dynamic> value) {
    final aliases = value['aliases'] ?? const <dynamic>[];
    if (aliases is! List) throw const FormatException('aliases 必须是数组');
    final keepAlive = _map(value['keepAlive'], 'keepAlive');
    return CarrierPreset(
      id: _string(value, 'id'),
      displayName: _string(value, 'displayName'),
      operatorName: _string(value, 'operatorName'),
      countryCode: _string(value, 'countryCode'),
      countryName: _string(value, 'countryName'),
      flag: _string(value, 'flag'),
      timeZoneId: _string(value, 'timeZoneId'),
      websiteUrl: _string(value, 'websiteUrl'),
      keepAliveDays: _int(keepAlive, 'cycleDays'),
      keepAlivePolicy: KeepAlivePolicy.fromJson(keepAlive),
      aliases: [
        for (var index = 0; index < aliases.length; index++)
          _listString(aliases[index], 'aliases[$index]'),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'displayName': displayName,
    'operatorName': operatorName,
    'countryCode': countryCode,
    'countryName': countryName,
    'flag': flag,
    'timeZoneId': timeZoneId,
    'websiteUrl': websiteUrl,
    if (aliases.isNotEmpty) 'aliases': aliases,
    'keepAlive': {'cycleDays': keepAliveDays, ...keepAlivePolicy.toJson()},
  };
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw FormatException('$field 必须是对象');
}

String _string(Map<String, dynamic> value, String field) {
  final item = value[field];
  if (item is String) return item;
  throw FormatException('$field 必须是字符串');
}

int _int(Map<String, dynamic> value, String field) {
  final item = value[field];
  if (item is int) return item;
  throw FormatException('$field 必须是整数');
}

String _listString(Object? value, String field) {
  if (value is String) return value;
  throw FormatException('$field 必须是字符串');
}

void _requiredText(String value, String field, int maxLength) {
  if (value.trim().isEmpty || value.length > maxLength) {
    throw FormatException('$field 不能为空且不能超过 $maxLength 个字符');
  }
}
