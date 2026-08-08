import '../value/money.dart';

/// 套餐信息。
///
/// 一订阅一套餐（spec §11）；多套餐叠加的卡片需建多条订阅表达。
/// 全部字段可空——导入数据常常不完整，空字段由 UI 呈现为「未知」。
class Plan {
  /// 套餐名称。
  final String? name;

  /// 每周期资费。
  final Money? cyclePrice;

  /// 计费周期天数。
  final int? cycleDays;

  /// 套餐开始时刻，UTC。
  final DateTime? startDate;

  /// 套餐到期时刻，UTC。
  final DateTime? expiryDate;

  /// 长期套餐（与「是否需保号」无关，见 KeepAlive.required）。
  final bool isLongTerm;

  Plan({
    this.name,
    this.cyclePrice,
    this.cycleDays,
    this.startDate,
    this.expiryDate,
    this.isLongTerm = false,
  }) {
    final cycle = cycleDays;
    if (cycle != null && cycle <= 0) {
      throw ArgumentError.value(cycle, 'cycleDays', '必须为正数');
    }
    if (startDate != null && !startDate!.isUtc) {
      throw ArgumentError.value(startDate, 'startDate', '必须为 UTC 时刻');
    }
    if (expiryDate != null && !expiryDate!.isUtc) {
      throw ArgumentError.value(expiryDate, 'expiryDate', '必须为 UTC 时刻');
    }
  }

  Plan copyWith({
    String? name,
    Money? cyclePrice,
    int? cycleDays,
    DateTime? startDate,
    DateTime? expiryDate,
    bool? isLongTerm,
  }) => Plan(
    name: name ?? this.name,
    cyclePrice: cyclePrice ?? this.cyclePrice,
    cycleDays: cycleDays ?? this.cycleDays,
    startDate: startDate ?? this.startDate,
    expiryDate: expiryDate ?? this.expiryDate,
    isLongTerm: isLongTerm ?? this.isLongTerm,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Plan &&
          other.name == name &&
          other.cyclePrice == cyclePrice &&
          other.cycleDays == cycleDays &&
          other.startDate == startDate &&
          other.expiryDate == expiryDate &&
          other.isLongTerm == isLongTerm;

  @override
  int get hashCode => Object.hash(
    name,
    cyclePrice,
    cycleDays,
    startDate,
    expiryDate,
    isLongTerm,
  );
}
