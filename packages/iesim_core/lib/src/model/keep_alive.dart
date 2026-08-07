/// 数据可信度。
///
/// 推测值必须在 UI 上可辨识，不得伪装为确凿数据。
enum DataConfidence {
  /// 用户明确填写，或由实际记录的动作推导而来。
  confirmed,

  /// 系统推测所得（如新建订阅时以创建时刻充当上次动作时间）。
  inferred,
}

/// 保号策略。
///
/// 预付费号码需定期产生动作（充值、通话、短信）以免被运营商回收。
/// 保号截止日 = lastActivityAt + cycleDays，与套餐到期日相互独立。
class KeepAlive {
  /// 是否需要保号。长期卡为 false。
  final bool required;

  /// 保号周期天数。required 为 true 时应当提供。
  final int? cycleDays;

  /// 上次动作时刻，UTC。
  final DateTime? lastActivityAt;

  /// lastActivityAt 的可信度。
  final DataConfidence confidence;

  KeepAlive({
    required this.required,
    this.cycleDays,
    this.lastActivityAt,
    this.confidence = DataConfidence.confirmed,
  }) {
    final activity = lastActivityAt;
    if (activity != null && !activity.isUtc) {
      throw ArgumentError.value(
        activity,
        'lastActivityAt',
        '必须为 UTC 时刻',
      );
    }
    final cycle = cycleDays;
    if (cycle != null && cycle <= 0) {
      throw ArgumentError.value(cycle, 'cycleDays', '必须为正数');
    }
  }

  /// 长期卡，无需保号。
  factory KeepAlive.notRequired() => KeepAlive(required: false);

  /// 以创建时刻推测上次动作时间。
  ///
  /// 依据：多数用户在充值后才录入记录，「创建即最近一次动作」通常成立。
  /// 该值标记为 inferred，UI 须以问号角标等方式区分显示。
  factory KeepAlive.inferredFrom(DateTime createdAtUtc, int cycleDays) =>
      KeepAlive(
        required: true,
        cycleDays: cycleDays,
        lastActivityAt: createdAtUtc,
        confidence: DataConfidence.inferred,
      );

  KeepAlive copyWith({
    bool? required,
    int? cycleDays,
    DateTime? lastActivityAt,
    DataConfidence? confidence,
  }) =>
      KeepAlive(
        required: required ?? this.required,
        cycleDays: cycleDays ?? this.cycleDays,
        lastActivityAt: lastActivityAt ?? this.lastActivityAt,
        confidence: confidence ?? this.confidence,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeepAlive &&
          other.required == required &&
          other.cycleDays == cycleDays &&
          other.lastActivityAt == lastActivityAt &&
          other.confidence == confidence;

  @override
  int get hashCode =>
      Object.hash(required, cycleDays, lastActivityAt, confidence);
}
