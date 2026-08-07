import '../value/money.dart';

/// 续存动作类型。
enum ActivityType {
  /// 充值。
  topUp,

  /// 通话。
  call,

  /// 短信。
  sms,

  /// 续费。
  renewal,
}

/// 订阅续存动作记录（spec §3.3 事件流之一）。
///
/// 回答「号码为何仍然有效」；资产物理变迁走另一条流（AssetEvent，v2）。
/// 含 [id] 以供同步墓碑配对（spec §6.5）。
class ActivityRecord {
  final String id;

  /// 所属订阅。
  final String subscriptionId;

  final ActivityType type;

  /// 动作发生时刻，UTC。
  final DateTime occurredAt;

  /// 金额；通话与短信等无金额动作留空。
  final Money? amount;

  ActivityRecord({
    required this.id,
    required this.subscriptionId,
    required this.type,
    required this.occurredAt,
    this.amount,
  }) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', '不能为空');
    }
    if (subscriptionId.isEmpty) {
      throw ArgumentError.value(subscriptionId, 'subscriptionId', '不能为空');
    }
    if (!occurredAt.isUtc) {
      throw ArgumentError.value(occurredAt, 'occurredAt', '必须为 UTC 时刻');
    }
  }

  ActivityRecord copyWith({
    String? id,
    String? subscriptionId,
    ActivityType? type,
    DateTime? occurredAt,
    Money? amount,
  }) =>
      ActivityRecord(
        id: id ?? this.id,
        subscriptionId: subscriptionId ?? this.subscriptionId,
        type: type ?? this.type,
        occurredAt: occurredAt ?? this.occurredAt,
        amount: amount ?? this.amount,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityRecord &&
          other.id == id &&
          other.subscriptionId == subscriptionId &&
          other.type == type &&
          other.occurredAt == occurredAt &&
          other.amount == amount;

  @override
  int get hashCode =>
      Object.hash(id, subscriptionId, type, occurredAt, amount);
}
