import 'activity_record.dart';

/// 数据可信度。
///
/// 推测值必须在 UI 上可辨识，不得伪装为确凿数据。
enum DataConfidence {
  /// 用户明确填写，或由实际记录的动作推导而来。
  confirmed,

  /// 系统推测所得（如新建订阅时以创建时刻充当上次动作时间）。
  inferred,
}

/// 能重置保号周期的动作。
enum KeepAliveAction {
  mobileData,
  call,
  sms,
  topUp,
  planPurchase,
  renewal,
  balanceChange,
  other,
}

/// 周期规则之外的附加条件类型。
enum KeepAliveConstraintKind {
  firstUse,
  afterPlanExpiry,
  paidRetention,
  custom,
}

/// 附加条件的完成判定方式。
enum KeepAliveConstraintEvaluationMode {
  /// 由符合条件的活动记录自动完成。
  activity,

  /// 必须由用户确认完成，例如付费休眠或带地区限制的动作。
  manual,
}

class KeepAliveConstraint {
  KeepAliveConstraint({
    String? id,
    required this.kind,
    required this.title,
    required this.details,
    this.withinDays,
    List<String> regions = const [],
    KeepAliveConstraintEvaluationMode? evaluationMode,
    Set<KeepAliveAction> qualifyingActions = const {},
    this.anchorAt,
    this.completedAt,
    this.completionNote,
  }) : id = id ?? _legacyConstraintId(kind, title),
       regions = List.unmodifiable(regions),
       evaluationMode =
           evaluationMode ?? _defaultConstraintEvaluationMode(kind),
       qualifyingActions = Set.unmodifiable(qualifyingActions) {
    _requiredText(this.id, 'constraint.id', 80);
    _requiredText(title, 'constraint.title', 100);
    _requiredText(details, 'constraint.details', 1000);
    if (withinDays case final days? when days <= 0) {
      throw ArgumentError.value(days, 'withinDays', '必须为正数');
    }
    if (regions.length > 30) {
      throw const FormatException('单条附加条件的地区不能超过 30 个');
    }
    for (final region in regions) {
      _requiredText(region, 'constraint.regions', 40);
    }
    if (qualifyingActions.length > KeepAliveAction.values.length) {
      throw const FormatException('附加条件的有效动作数量无效');
    }
    if (anchorAt case final value? when !value.isUtc) {
      throw ArgumentError.value(value, 'anchorAt', '必须为 UTC 时刻');
    }
    if (completedAt case final value? when !value.isUtc) {
      throw ArgumentError.value(value, 'completedAt', '必须为 UTC 时刻');
    }
    _optionalText(completionNote, 'constraint.completionNote', 500);
  }

  /// 稳定规则 ID，用于提醒去重与手动完成状态。
  final String id;
  final KeepAliveConstraintKind kind;
  final String title;
  final String details;
  final int? withinDays;
  final List<String> regions;
  final KeepAliveConstraintEvaluationMode evaluationMode;

  /// 为空时继承策略级 [KeepAlivePolicy.qualifyingActions]。
  final Set<KeepAliveAction> qualifyingActions;

  /// 自定义或付费规则的起算时刻。首次使用和套餐到期规则使用业务锚点。
  final DateTime? anchorAt;

  /// 用户手动确认完成的时刻，也可覆盖需要地区证据的自动规则。
  final DateTime? completedAt;
  final String? completionNote;

  factory KeepAliveConstraint.fromJson(Map<String, dynamic> value) {
    final regions = value['regions'] ?? const <dynamic>[];
    final actions = value['qualifyingActions'] ?? const <dynamic>[];
    if (regions is! List) {
      throw const FormatException('constraint.regions 必须是数组');
    }
    if (actions is! List) {
      throw const FormatException('constraint.qualifyingActions 必须是数组');
    }
    return KeepAliveConstraint(
      id: _optionalString(value, 'id'),
      kind: _enumValue(
        KeepAliveConstraintKind.values,
        value['kind'],
        'constraint.kind',
      ),
      title: _string(value, 'title'),
      details: _string(value, 'details'),
      withinDays: _optionalInt(value, 'withinDays'),
      regions: [
        for (var index = 0; index < regions.length; index++)
          _listString(regions[index], 'constraint.regions[$index]'),
      ],
      evaluationMode: value['evaluationMode'] == null
          ? null
          : _enumValue(
              KeepAliveConstraintEvaluationMode.values,
              value['evaluationMode'],
              'constraint.evaluationMode',
            ),
      qualifyingActions: {
        for (var index = 0; index < actions.length; index++)
          _enumValue(
            KeepAliveAction.values,
            actions[index],
            'constraint.qualifyingActions[$index]',
          ),
      },
      anchorAt: _optionalUtc(value, 'anchorAt'),
      completedAt: _optionalUtc(value, 'completedAt'),
      completionNote: _optionalString(value, 'completionNote'),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'details': details,
    if (withinDays != null) 'withinDays': withinDays,
    if (regions.isNotEmpty) 'regions': regions,
    'evaluationMode': evaluationMode.name,
    if (qualifyingActions.isNotEmpty)
      'qualifyingActions': [
        for (final action in qualifyingActions) action.name,
      ],
    if (anchorAt != null) 'anchorAt': anchorAt!.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (completionNote != null) 'completionNote': completionNote,
  };

  KeepAliveConstraint copyWith({
    String? id,
    KeepAliveConstraintKind? kind,
    String? title,
    String? details,
    Object? withinDays = _notSet,
    List<String>? regions,
    KeepAliveConstraintEvaluationMode? evaluationMode,
    Set<KeepAliveAction>? qualifyingActions,
    Object? anchorAt = _notSet,
    Object? completedAt = _notSet,
    Object? completionNote = _notSet,
  }) => KeepAliveConstraint(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    details: details ?? this.details,
    withinDays: identical(withinDays, _notSet)
        ? this.withinDays
        : withinDays as int?,
    regions: regions ?? this.regions,
    evaluationMode: evaluationMode ?? this.evaluationMode,
    qualifyingActions: qualifyingActions ?? this.qualifyingActions,
    anchorAt: identical(anchorAt, _notSet)
        ? this.anchorAt
        : anchorAt as DateTime?,
    completedAt: identical(completedAt, _notSet)
        ? this.completedAt
        : completedAt as DateTime?,
    completionNote: identical(completionNote, _notSet)
        ? this.completionNote
        : completionNote as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is KeepAliveConstraint &&
      other.id == id &&
      other.kind == kind &&
      other.title == title &&
      other.details == details &&
      other.withinDays == withinDays &&
      _listEquals(other.regions, regions) &&
      other.evaluationMode == evaluationMode &&
      _setEquals(other.qualifyingActions, qualifyingActions) &&
      other.anchorAt == anchorAt &&
      other.completedAt == completedAt &&
      other.completionNote == completionNote;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    title,
    details,
    withinDays,
    Object.hashAll(regions),
    evaluationMode,
    Object.hashAllUnordered(qualifyingActions),
    anchorAt,
    completedAt,
    completionNote,
  );
}

/// 周期规则之外的可组合保号策略。
class KeepAlivePolicy {
  KeepAlivePolicy({
    Set<KeepAliveAction> qualifyingActions = legacyQualifyingActions,
    this.summary,
    List<KeepAliveConstraint> constraints = const [],
    this.presetId,
    this.sourceLabel,
    this.sourceUrl,
    this.sourceCheckedAt,
  }) : qualifyingActions = Set.unmodifiable(qualifyingActions),
       constraints = List.unmodifiable(constraints) {
    if (this.qualifyingActions.isEmpty) {
      throw const FormatException('至少选择一种可重置保号周期的动作');
    }
    if (this.qualifyingActions.length > KeepAliveAction.values.length) {
      throw const FormatException('保号动作数量无效');
    }
    _optionalText(summary, 'keepAlive.summary', 2000);
    _optionalText(presetId, 'keepAlive.presetId', 80);
    _optionalText(sourceLabel, 'keepAlive.sourceLabel', 160);
    _optionalText(sourceUrl, 'keepAlive.sourceUrl', 1000);
    if (sourceUrl case final value?) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
        throw const FormatException('保号规则来源必须是有效的 HTTPS 地址');
      }
    }
    if (sourceCheckedAt case final value? when !value.isUtc) {
      throw ArgumentError.value(value, 'sourceCheckedAt', '必须为 UTC 时刻');
    }
    if (constraints.length > 20) {
      throw const FormatException('附加保号条件不能超过 20 条');
    }
  }

  static const legacyQualifyingActions = <KeepAliveAction>{
    KeepAliveAction.topUp,
    KeepAliveAction.call,
    KeepAliveAction.sms,
    KeepAliveAction.renewal,
  };

  final Set<KeepAliveAction> qualifyingActions;
  final String? summary;
  final List<KeepAliveConstraint> constraints;
  final String? presetId;
  final String? sourceLabel;
  final String? sourceUrl;
  final DateTime? sourceCheckedAt;

  bool accepts(ActivityType type) => switch (type) {
    ActivityType.topUp => qualifyingActions.contains(KeepAliveAction.topUp),
    ActivityType.call => qualifyingActions.contains(KeepAliveAction.call),
    ActivityType.sms => qualifyingActions.contains(KeepAliveAction.sms),
    ActivityType.renewal => qualifyingActions.contains(KeepAliveAction.renewal),
    ActivityType.mobileData => qualifyingActions.contains(
      KeepAliveAction.mobileData,
    ),
    ActivityType.planPurchase => qualifyingActions.contains(
      KeepAliveAction.planPurchase,
    ),
    ActivityType.balanceChange => qualifyingActions.contains(
      KeepAliveAction.balanceChange,
    ),
    ActivityType.other => qualifyingActions.contains(KeepAliveAction.other),
  };

  factory KeepAlivePolicy.fromJson(Map<String, dynamic> value) {
    final actions = value['qualifyingActions'];
    final constraints = value['constraints'] ?? const <dynamic>[];
    if (actions is! List) {
      throw const FormatException('keepAlive.qualifyingActions 必须是数组');
    }
    if (constraints is! List) {
      throw const FormatException('keepAlive.constraints 必须是数组');
    }
    return KeepAlivePolicy(
      qualifyingActions: {
        for (var index = 0; index < actions.length; index++)
          _enumValue(
            KeepAliveAction.values,
            actions[index],
            'keepAlive.qualifyingActions[$index]',
          ),
      },
      summary: _optionalString(value, 'summary'),
      constraints: [
        for (var index = 0; index < constraints.length; index++)
          KeepAliveConstraint.fromJson(
            _map(constraints[index], 'keepAlive.constraints[$index]'),
          ),
      ],
      presetId: _optionalString(value, 'presetId'),
      sourceLabel: _optionalString(value, 'sourceLabel'),
      sourceUrl: _optionalString(value, 'sourceUrl'),
      sourceCheckedAt: _optionalUtc(value, 'sourceCheckedAt'),
    );
  }

  Map<String, Object?> toJson() => {
    'qualifyingActions': [for (final action in qualifyingActions) action.name],
    if (summary != null) 'summary': summary,
    if (constraints.isNotEmpty)
      'constraints': [
        for (final constraint in constraints) constraint.toJson(),
      ],
    if (presetId != null) 'presetId': presetId,
    if (sourceLabel != null) 'sourceLabel': sourceLabel,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
    if (sourceCheckedAt != null)
      'sourceCheckedAt': sourceCheckedAt!.toIso8601String(),
  };

  KeepAlivePolicy copyWith({
    Set<KeepAliveAction>? qualifyingActions,
    String? summary,
    List<KeepAliveConstraint>? constraints,
    String? presetId,
    String? sourceLabel,
    String? sourceUrl,
    DateTime? sourceCheckedAt,
  }) => KeepAlivePolicy(
    qualifyingActions: qualifyingActions ?? this.qualifyingActions,
    summary: summary ?? this.summary,
    constraints: constraints ?? this.constraints,
    presetId: presetId ?? this.presetId,
    sourceLabel: sourceLabel ?? this.sourceLabel,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    sourceCheckedAt: sourceCheckedAt ?? this.sourceCheckedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is KeepAlivePolicy &&
      _setEquals(other.qualifyingActions, qualifyingActions) &&
      other.summary == summary &&
      _listEquals(other.constraints, constraints) &&
      other.presetId == presetId &&
      other.sourceLabel == sourceLabel &&
      other.sourceUrl == sourceUrl &&
      other.sourceCheckedAt == sourceCheckedAt;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(qualifyingActions),
    summary,
    Object.hashAll(constraints),
    presetId,
    sourceLabel,
    sourceUrl,
    sourceCheckedAt,
  );
}

/// 保号策略。
///
/// 周期截止日 = lastActivityAt + cycleDays；动作集合与附加条件放在 [policy]。
class KeepAlive {
  final bool required;
  final int? cycleDays;
  final DateTime? lastActivityAt;
  final DataConfidence confidence;
  final KeepAlivePolicy policy;

  KeepAlive({
    required this.required,
    this.cycleDays,
    this.lastActivityAt,
    this.confidence = DataConfidence.confirmed,
    KeepAlivePolicy? policy,
  }) : policy = policy ?? KeepAlivePolicy() {
    final activity = lastActivityAt;
    if (activity != null && !activity.isUtc) {
      throw ArgumentError.value(activity, 'lastActivityAt', '必须为 UTC 时刻');
    }
    final cycle = cycleDays;
    if (cycle != null && cycle <= 0) {
      throw ArgumentError.value(cycle, 'cycleDays', '必须为正数');
    }
  }

  factory KeepAlive.notRequired() => KeepAlive(required: false);

  factory KeepAlive.inferredFrom(
    DateTime createdAtUtc,
    int cycleDays, {
    KeepAlivePolicy? policy,
  }) => KeepAlive(
    required: true,
    cycleDays: cycleDays,
    lastActivityAt: createdAtUtc,
    confidence: DataConfidence.inferred,
    policy: policy,
  );

  KeepAlive copyWith({
    bool? required,
    int? cycleDays,
    DateTime? lastActivityAt,
    DataConfidence? confidence,
    KeepAlivePolicy? policy,
  }) => KeepAlive(
    required: required ?? this.required,
    cycleDays: cycleDays ?? this.cycleDays,
    lastActivityAt: lastActivityAt ?? this.lastActivityAt,
    confidence: confidence ?? this.confidence,
    policy: policy ?? this.policy,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeepAlive &&
          other.required == required &&
          other.cycleDays == cycleDays &&
          other.lastActivityAt == lastActivityAt &&
          other.confidence == confidence &&
          other.policy == policy;

  @override
  int get hashCode =>
      Object.hash(required, cycleDays, lastActivityAt, confidence, policy);
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

String? _optionalString(Map<String, dynamic> value, String field) {
  final item = value[field];
  if (item == null) return null;
  if (item is String) return item;
  throw FormatException('$field 必须是字符串或 null');
}

int? _optionalInt(Map<String, dynamic> value, String field) {
  final item = value[field];
  if (item == null) return null;
  if (item is int) return item;
  throw FormatException('$field 必须是整数或 null');
}

DateTime? _optionalUtc(Map<String, dynamic> value, String field) {
  final item = _optionalString(value, field);
  if (item == null) return null;
  final parsed = DateTime.tryParse(item);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$field 必须是带时区的 ISO 8601 UTC 时间');
  }
  return parsed;
}

String _listString(Object? value, String field) {
  if (value is String) return value;
  throw FormatException('$field 必须是字符串');
}

T _enumValue<T extends Enum>(List<T> values, Object? value, String field) {
  if (value is! String) throw FormatException('$field 必须是字符串');
  for (final item in values) {
    if (item.name == value) return item;
  }
  throw FormatException('$field 的值不受支持：$value');
}

void _requiredText(String value, String field, int maxLength) {
  if (value.trim().isEmpty || value.length > maxLength) {
    throw FormatException('$field 不能为空且不能超过 $maxLength 个字符');
  }
}

void _optionalText(String? value, String field, int maxLength) {
  if (value != null && (value.trim().isEmpty || value.length > maxLength)) {
    throw FormatException('$field 不能是空字符串且不能超过 $maxLength 个字符');
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _setEquals<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);

KeepAliveConstraintEvaluationMode _defaultConstraintEvaluationMode(
  KeepAliveConstraintKind kind,
) => switch (kind) {
  KeepAliveConstraintKind.firstUse || KeepAliveConstraintKind.afterPlanExpiry =>
    KeepAliveConstraintEvaluationMode.activity,
  KeepAliveConstraintKind.paidRetention ||
  KeepAliveConstraintKind.custom => KeepAliveConstraintEvaluationMode.manual,
};

String _legacyConstraintId(KeepAliveConstraintKind kind, String title) {
  var hash = 0x811c9dc5;
  for (final unit in '${kind.name}:$title'.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return 'rule-${kind.name}-${hash.toRadixString(16).padLeft(8, '0')}';
}

const _notSet = Object();
