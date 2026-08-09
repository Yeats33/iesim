const _unsetPhoneAppBinding = Object();

/// 手机号码在 App 中承担的用途。
enum PhoneAppBindingPurpose {
  messaging,
  signIn,
  verification,
  recovery,
  payment,
  other,
}

/// App 验证这个号码时可能使用的通道。
enum PhoneVerificationChannel { sms, voiceCall, inApp }

/// 用户记录的号码绑定状态。
enum PhoneAppBindingStatus { pending, active, disabled }

/// 一个手机号与一个外部 App 的绑定关系。
///
/// 这只是用户维护的资产记录。ieSIM 不会读取短信、验证码或外部 App 账户。
class PhoneAppBinding {
  PhoneAppBinding({
    required this.id,
    required this.phoneNumber,
    required this.appName,
    this.presetId,
    this.developerName,
    this.accountLabel,
    this.status = PhoneAppBindingStatus.active,
    List<PhoneAppBindingPurpose> purposes = const [],
    List<PhoneVerificationChannel> verificationChannels = const [],
    this.verifiedAt,
    this.note,
    this.appStoreId,
    this.appStoreBundleId,
    this.appStoreUrl,
    this.googlePlayPackage,
    this.googlePlayUrl,
    this.iconUrl,
    this.websiteUrl,
    this.storeMetadataUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
  }) : purposes = List.unmodifiable(purposes),
       verificationChannels = List.unmodifiable(verificationChannels) {
    _requiredText(id, 'id', 120);
    _requiredText(phoneNumber, 'phoneNumber', 80);
    _requiredText(appName, 'appName', 160);
    _optionalText(presetId, 'presetId', 80);
    _optionalText(developerName, 'developerName', 160);
    _optionalText(accountLabel, 'accountLabel', 160);
    _optionalText(note, 'note', 500);
    _optionalText(appStoreId, 'appStoreId', 40);
    _optionalText(appStoreBundleId, 'appStoreBundleId', 160);
    _optionalText(googlePlayPackage, 'googlePlayPackage', 200);
    if (appStoreId != null && !RegExp(r'^\d{1,20}$').hasMatch(appStoreId!)) {
      throw const FormatException('appStoreId 必须是数字');
    }
    if (googlePlayPackage != null &&
        !RegExp(
          r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
        ).hasMatch(googlePlayPackage!)) {
      throw const FormatException('googlePlayPackage 格式无效');
    }
    _httpsUrl(appStoreUrl, 'appStoreUrl');
    _httpsUrl(googlePlayUrl, 'googlePlayUrl');
    _httpsUrl(iconUrl, 'iconUrl');
    _httpsUrl(websiteUrl, 'websiteUrl');
    _utc(verifiedAt, 'verifiedAt');
    _utc(storeMetadataUpdatedAt, 'storeMetadataUpdatedAt');
    _utc(createdAt, 'createdAt');
    _utc(updatedAt, 'updatedAt');
    if (purposes.toSet().length != purposes.length) {
      throw const FormatException('purposes 不能重复');
    }
    if (verificationChannels.toSet().length != verificationChannels.length) {
      throw const FormatException('verificationChannels 不能重复');
    }
  }

  final String id;
  final String phoneNumber;
  final String appName;
  final String? presetId;
  final String? developerName;
  final String? accountLabel;
  final PhoneAppBindingStatus status;
  final List<PhoneAppBindingPurpose> purposes;
  final List<PhoneVerificationChannel> verificationChannels;
  final DateTime? verifiedAt;
  final String? note;
  final String? appStoreId;
  final String? appStoreBundleId;
  final String? appStoreUrl;
  final String? googlePlayPackage;
  final String? googlePlayUrl;
  final String? iconUrl;
  final String? websiteUrl;
  final DateTime? storeMetadataUpdatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  PhoneAppBinding copyWith({
    String? id,
    String? phoneNumber,
    String? appName,
    Object? presetId = _unsetPhoneAppBinding,
    Object? developerName = _unsetPhoneAppBinding,
    Object? accountLabel = _unsetPhoneAppBinding,
    PhoneAppBindingStatus? status,
    List<PhoneAppBindingPurpose>? purposes,
    List<PhoneVerificationChannel>? verificationChannels,
    Object? verifiedAt = _unsetPhoneAppBinding,
    Object? note = _unsetPhoneAppBinding,
    Object? appStoreId = _unsetPhoneAppBinding,
    Object? appStoreBundleId = _unsetPhoneAppBinding,
    Object? appStoreUrl = _unsetPhoneAppBinding,
    Object? googlePlayPackage = _unsetPhoneAppBinding,
    Object? googlePlayUrl = _unsetPhoneAppBinding,
    Object? iconUrl = _unsetPhoneAppBinding,
    Object? websiteUrl = _unsetPhoneAppBinding,
    Object? storeMetadataUpdatedAt = _unsetPhoneAppBinding,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => PhoneAppBinding(
    id: id ?? this.id,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    appName: appName ?? this.appName,
    presetId: identical(presetId, _unsetPhoneAppBinding)
        ? this.presetId
        : presetId as String?,
    developerName: identical(developerName, _unsetPhoneAppBinding)
        ? this.developerName
        : developerName as String?,
    accountLabel: identical(accountLabel, _unsetPhoneAppBinding)
        ? this.accountLabel
        : accountLabel as String?,
    status: status ?? this.status,
    purposes: purposes ?? this.purposes,
    verificationChannels: verificationChannels ?? this.verificationChannels,
    verifiedAt: identical(verifiedAt, _unsetPhoneAppBinding)
        ? this.verifiedAt
        : verifiedAt as DateTime?,
    note: identical(note, _unsetPhoneAppBinding) ? this.note : note as String?,
    appStoreId: identical(appStoreId, _unsetPhoneAppBinding)
        ? this.appStoreId
        : appStoreId as String?,
    appStoreBundleId: identical(appStoreBundleId, _unsetPhoneAppBinding)
        ? this.appStoreBundleId
        : appStoreBundleId as String?,
    appStoreUrl: identical(appStoreUrl, _unsetPhoneAppBinding)
        ? this.appStoreUrl
        : appStoreUrl as String?,
    googlePlayPackage: identical(googlePlayPackage, _unsetPhoneAppBinding)
        ? this.googlePlayPackage
        : googlePlayPackage as String?,
    googlePlayUrl: identical(googlePlayUrl, _unsetPhoneAppBinding)
        ? this.googlePlayUrl
        : googlePlayUrl as String?,
    iconUrl: identical(iconUrl, _unsetPhoneAppBinding)
        ? this.iconUrl
        : iconUrl as String?,
    websiteUrl: identical(websiteUrl, _unsetPhoneAppBinding)
        ? this.websiteUrl
        : websiteUrl as String?,
    storeMetadataUpdatedAt:
        identical(storeMetadataUpdatedAt, _unsetPhoneAppBinding)
        ? this.storeMetadataUpdatedAt
        : storeMetadataUpdatedAt as DateTime?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory PhoneAppBinding.fromJson(Map<String, dynamic> value) {
    final purposes = _enumList(
      value['purposes'],
      'purposes',
      PhoneAppBindingPurpose.values,
    );
    final channels = _enumList(
      value['verificationChannels'],
      'verificationChannels',
      PhoneVerificationChannel.values,
    );
    return PhoneAppBinding(
      id: _string(value, 'id'),
      phoneNumber: _string(value, 'phoneNumber'),
      appName: _string(value, 'appName'),
      presetId: _optionalString(value, 'presetId'),
      developerName: _optionalString(value, 'developerName'),
      accountLabel: _optionalString(value, 'accountLabel'),
      status: _enumValue(
        _string(value, 'status'),
        'status',
        PhoneAppBindingStatus.values,
      ),
      purposes: purposes.cast<PhoneAppBindingPurpose>(),
      verificationChannels: channels.cast<PhoneVerificationChannel>(),
      verifiedAt: _optionalUtc(value, 'verifiedAt'),
      note: _optionalString(value, 'note'),
      appStoreId: _optionalString(value, 'appStoreId'),
      appStoreBundleId: _optionalString(value, 'appStoreBundleId'),
      appStoreUrl: _optionalString(value, 'appStoreUrl'),
      googlePlayPackage: _optionalString(value, 'googlePlayPackage'),
      googlePlayUrl: _optionalString(value, 'googlePlayUrl'),
      iconUrl: _optionalString(value, 'iconUrl'),
      websiteUrl: _optionalString(value, 'websiteUrl'),
      storeMetadataUpdatedAt: _optionalUtc(value, 'storeMetadataUpdatedAt'),
      createdAt: _requiredUtc(value, 'createdAt'),
      updatedAt: _requiredUtc(value, 'updatedAt'),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'phoneNumber': phoneNumber,
    'appName': appName,
    'presetId': presetId,
    'developerName': developerName,
    'accountLabel': accountLabel,
    'status': status.name,
    'purposes': purposes.map((item) => item.name).toList(),
    'verificationChannels': verificationChannels
        .map((item) => item.name)
        .toList(),
    'verifiedAt': verifiedAt?.toIso8601String(),
    'note': note,
    'appStoreId': appStoreId,
    'appStoreBundleId': appStoreBundleId,
    'appStoreUrl': appStoreUrl,
    'googlePlayPackage': googlePlayPackage,
    'googlePlayUrl': googlePlayUrl,
    'iconUrl': iconUrl,
    'websiteUrl': websiteUrl,
    'storeMetadataUpdatedAt': storeMetadataUpdatedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is PhoneAppBinding &&
      other.id == id &&
      other.phoneNumber == phoneNumber &&
      other.appName == appName &&
      other.presetId == presetId &&
      other.developerName == developerName &&
      other.accountLabel == accountLabel &&
      other.status == status &&
      _listEquals(other.purposes, purposes) &&
      _listEquals(other.verificationChannels, verificationChannels) &&
      other.verifiedAt == verifiedAt &&
      other.note == note &&
      other.appStoreId == appStoreId &&
      other.appStoreBundleId == appStoreBundleId &&
      other.appStoreUrl == appStoreUrl &&
      other.googlePlayPackage == googlePlayPackage &&
      other.googlePlayUrl == googlePlayUrl &&
      other.iconUrl == iconUrl &&
      other.websiteUrl == websiteUrl &&
      other.storeMetadataUpdatedAt == storeMetadataUpdatedAt &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll([
    id,
    phoneNumber,
    appName,
    presetId,
    developerName,
    accountLabel,
    status,
    Object.hashAll(purposes),
    Object.hashAll(verificationChannels),
    verifiedAt,
    note,
    appStoreId,
    appStoreBundleId,
    appStoreUrl,
    googlePlayPackage,
    googlePlayUrl,
    iconUrl,
    websiteUrl,
    storeMetadataUpdatedAt,
    createdAt,
    updatedAt,
  ]);
}

List<T> _enumList<T extends Enum>(Object? raw, String field, List<T> values) {
  if (raw is! List) throw FormatException('$field 必须是数组');
  return [
    for (var index = 0; index < raw.length; index++)
      _enumValue(raw[index], '$field[$index]', values),
  ];
}

T _enumValue<T extends Enum>(Object? raw, String field, List<T> values) {
  if (raw is! String) throw FormatException('$field 必须是字符串');
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw FormatException('$field 枚举值无效：$raw');
}

String _string(Map<String, dynamic> value, String field) {
  final raw = value[field];
  if (raw is String && raw.trim().isNotEmpty) return raw;
  throw FormatException('$field 必须是非空字符串');
}

String? _optionalString(Map<String, dynamic> value, String field) {
  final raw = value[field];
  if (raw == null) return null;
  if (raw is String) return raw;
  throw FormatException('$field 必须是字符串或 null');
}

DateTime _requiredUtc(Map<String, dynamic> value, String field) {
  final raw = _string(value, field);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$field 必须是 UTC 时间');
  }
  return parsed;
}

DateTime? _optionalUtc(Map<String, dynamic> value, String field) {
  final raw = _optionalString(value, field);
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$field 必须是 UTC 时间或 null');
  }
  return parsed;
}

void _requiredText(String value, String field, int maxLength) {
  if (value.trim().isEmpty || value.length > maxLength) {
    throw FormatException('$field 不能为空且不能超过 $maxLength 个字符');
  }
}

void _optionalText(String? value, String field, int maxLength) {
  if (value != null && (value.trim().isEmpty || value.length > maxLength)) {
    throw FormatException('$field 不能为空且不能超过 $maxLength 个字符');
  }
}

void _httpsUrl(String? value, String field) {
  if (value == null) return;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
    throw FormatException('$field 必须是有效的 HTTPS 地址');
  }
}

void _utc(DateTime? value, String field) {
  if (value != null && !value.isUtc) {
    throw ArgumentError.value(value, field, '必须是 UTC 时间');
  }
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
