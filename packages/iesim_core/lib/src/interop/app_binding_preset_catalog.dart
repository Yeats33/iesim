import 'dart:convert';

import '../model/phone_app_binding.dart';

/// 可由独立 GitHub 仓库热更新的 App 绑定预设目录。
class AppBindingPresetCatalog {
  AppBindingPresetCatalog({
    required this.catalogVersion,
    required this.updatedAt,
    required List<AppBindingPreset> apps,
  }) : apps = List.unmodifiable(apps) {
    _requiredText(catalogVersion, 'catalogVersion', 80);
    if (!updatedAt.isUtc) {
      throw ArgumentError.value(updatedAt, 'updatedAt', '必须使用 UTC 时间');
    }
    if (apps.length > 5000) throw const FormatException('App 预设不能超过 5000 条');
    final ids = <String>{};
    for (final app in apps) {
      if (!ids.add(app.id)) throw FormatException('App 预设 id 重复：${app.id}');
    }
  }

  static const schemaVersion = 1;

  final String catalogVersion;
  final DateTime updatedAt;
  final List<AppBindingPreset> apps;

  factory AppBindingPresetCatalog.decode(String source) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('App 绑定预设不是有效 JSON：${error.message}');
    }
    if (decoded is! Map) throw const FormatException('App 绑定预设根节点必须是对象');
    final root = Map<String, dynamic>.from(decoded);
    if (root['schemaVersion'] != schemaVersion) {
      throw FormatException(
        '不支持的 App 绑定预设 schemaVersion：${root['schemaVersion']}',
      );
    }
    final entries = root['apps'];
    if (entries is! List) throw const FormatException('apps 必须是数组');
    final updatedAt = DateTime.tryParse(_string(root, 'updatedAt'));
    if (updatedAt == null || !updatedAt.isUtc) {
      throw const FormatException('updatedAt 必须是带时区的 UTC 时间');
    }
    return AppBindingPresetCatalog(
      catalogVersion: _string(root, 'catalogVersion'),
      updatedAt: updatedAt,
      apps: [
        for (var index = 0; index < entries.length; index++)
          AppBindingPreset.fromJson(_map(entries[index], 'apps[$index]')),
      ],
    );
  }

  String encode() => jsonEncode({
    'schemaVersion': schemaVersion,
    'catalogVersion': catalogVersion,
    'updatedAt': updatedAt.toIso8601String(),
    'apps': apps.map((item) => item.toJson()).toList(),
  });

  List<AppBindingPreset> search(String query) {
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    if (terms.isEmpty) return apps;
    return [
      for (final app in apps)
        if (terms.every(app.matches)) app,
    ];
  }
}

class AppBindingPreset {
  AppBindingPreset({
    required this.id,
    required this.displayName,
    required this.developerName,
    required this.description,
    required this.websiteUrl,
    required this.iconUrl,
    this.appStoreId,
    this.appStoreBundleId,
    this.appStoreUrl,
    this.googlePlayPackage,
    this.googlePlayUrl,
    List<String> aliases = const [],
    List<PhoneAppBindingPurpose> defaultPurposes = const [],
    List<PhoneVerificationChannel> verificationChannels = const [],
    this.verificationNote,
  }) : aliases = List.unmodifiable(aliases),
       defaultPurposes = List.unmodifiable(defaultPurposes),
       verificationChannels = List.unmodifiable(verificationChannels) {
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{1,79}$').hasMatch(id)) {
      throw FormatException('App 预设 id 格式无效：$id');
    }
    _requiredText(displayName, 'displayName', 160);
    _requiredText(developerName, 'developerName', 160);
    _requiredText(description, 'description', 500);
    _https(websiteUrl, 'websiteUrl');
    _https(iconUrl, 'iconUrl');
    if (appStoreId == null && googlePlayPackage == null) {
      throw const FormatException('App 预设至少需要一个商店标识');
    }
    if (appStoreId != null) {
      _requiredText(appStoreId!, 'appStoreId', 40);
      _requiredText(appStoreBundleId ?? '', 'appStoreBundleId', 160);
      _https(appStoreUrl ?? '', 'appStoreUrl');
    } else if (appStoreBundleId != null || appStoreUrl != null) {
      throw const FormatException('App Store 资料必须完整填写');
    }
    if (googlePlayPackage != null) {
      _requiredText(googlePlayPackage!, 'googlePlayPackage', 200);
      _https(googlePlayUrl ?? '', 'googlePlayUrl');
    } else if (googlePlayUrl != null) {
      throw const FormatException('Google Play 资料必须完整填写');
    }
    if (aliases.length > 40) throw const FormatException('aliases 不能超过 40 个');
    for (final alias in aliases) {
      _requiredText(alias, 'aliases', 160);
    }
    if (defaultPurposes.toSet().length != defaultPurposes.length) {
      throw const FormatException('defaultPurposes 不能重复');
    }
    if (verificationChannels.toSet().length != verificationChannels.length) {
      throw const FormatException('verificationChannels 不能重复');
    }
    if (verificationNote != null) {
      _requiredText(verificationNote!, 'verificationNote', 500);
    }
  }

  final String id;
  final String displayName;
  final String developerName;
  final String description;
  final String websiteUrl;
  final String iconUrl;
  final String? appStoreId;
  final String? appStoreBundleId;
  final String? appStoreUrl;
  final String? googlePlayPackage;
  final String? googlePlayUrl;
  final List<String> aliases;
  final List<PhoneAppBindingPurpose> defaultPurposes;
  final List<PhoneVerificationChannel> verificationChannels;
  final String? verificationNote;

  bool matches(String term) => <String>[
    id,
    displayName,
    developerName,
    ?appStoreBundleId,
    ?googlePlayPackage,
    ...aliases,
  ].join(' ').toLowerCase().contains(term);

  factory AppBindingPreset.fromJson(Map<String, dynamic> value) {
    final appStore = _optionalMap(value['appStore'], 'appStore');
    final googlePlay = _optionalMap(value['googlePlay'], 'googlePlay');
    return AppBindingPreset(
      id: _string(value, 'id'),
      displayName: _string(value, 'displayName'),
      developerName: _string(value, 'developerName'),
      description: _string(value, 'description'),
      websiteUrl: _string(value, 'websiteUrl'),
      iconUrl: _string(value, 'iconUrl'),
      appStoreId: appStore == null ? null : _string(appStore, 'appId'),
      appStoreBundleId: appStore == null ? null : _string(appStore, 'bundleId'),
      appStoreUrl: appStore == null ? null : _string(appStore, 'url'),
      googlePlayPackage: googlePlay == null
          ? null
          : _string(googlePlay, 'packageName'),
      googlePlayUrl: googlePlay == null ? null : _string(googlePlay, 'url'),
      aliases: _stringList(value['aliases'], 'aliases'),
      defaultPurposes: _enumList(
        value['defaultPurposes'],
        'defaultPurposes',
        PhoneAppBindingPurpose.values,
      ),
      verificationChannels: _enumList(
        value['verificationChannels'],
        'verificationChannels',
        PhoneVerificationChannel.values,
      ),
      verificationNote: _optionalString(value, 'verificationNote'),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'displayName': displayName,
    'developerName': developerName,
    'description': description,
    'websiteUrl': websiteUrl,
    'iconUrl': iconUrl,
    'aliases': aliases,
    'defaultPurposes': defaultPurposes.map((item) => item.name).toList(),
    'verificationChannels': verificationChannels
        .map((item) => item.name)
        .toList(),
    'verificationNote': verificationNote,
    if (appStoreId != null)
      'appStore': {
        'appId': appStoreId,
        'bundleId': appStoreBundleId,
        'url': appStoreUrl,
      },
    if (googlePlayPackage != null)
      'googlePlay': {'packageName': googlePlayPackage, 'url': googlePlayUrl},
  };
}

List<String> _stringList(Object? raw, String field) {
  if (raw is! List) throw FormatException('$field 必须是数组');
  return [
    for (var index = 0; index < raw.length; index++)
      if (raw[index] is String)
        raw[index] as String
      else
        throw FormatException('$field[$index] 必须是字符串'),
  ];
}

List<T> _enumList<T extends Enum>(Object? raw, String field, List<T> values) {
  final names = _stringList(raw, field);
  return [
    for (var index = 0; index < names.length; index++)
      _enumValue(names[index], '$field[$index]', values),
  ];
}

T _enumValue<T extends Enum>(String raw, String field, List<T> values) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw FormatException('$field 枚举值无效：$raw');
}

Map<String, dynamic> _map(Object? raw, String field) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  throw FormatException('$field 必须是对象');
}

Map<String, dynamic>? _optionalMap(Object? raw, String field) {
  if (raw == null) return null;
  return _map(raw, field);
}

String _string(Map<String, dynamic> value, String field) {
  final raw = value[field];
  if (raw is String) return raw;
  throw FormatException('$field 必须是字符串');
}

String? _optionalString(Map<String, dynamic> value, String field) {
  final raw = value[field];
  if (raw == null) return null;
  if (raw is String) return raw;
  throw FormatException('$field 必须是字符串或 null');
}

void _requiredText(String value, String field, int maxLength) {
  if (value.trim().isEmpty || value.length > maxLength) {
    throw FormatException('$field 不能为空且不能超过 $maxLength 个字符');
  }
}

void _https(String value, String field) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
    throw FormatException('$field 必须是有效的 HTTPS 地址');
  }
}
