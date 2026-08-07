/// 保号状态。
///
/// 使用 sealed 类，UI 侧 switch 强制穷尽，遗漏分支在编译期报错。
sealed class KeepAliveStatus {
  const KeepAliveStatus();
}

/// 长期卡，无需保号。
class NotRequired extends KeepAliveStatus {
  const NotRequired();
}

/// 距截止尚有余裕。
class Safe extends KeepAliveStatus {
  final int daysLeft;

  /// 该判定基于推测的上次动作时间。
  final bool inferred;

  const Safe({required this.daysLeft, required this.inferred});
}

/// 临近截止，需要尽快处理。
class DueSoon extends KeepAliveStatus {
  final int daysLeft;
  final bool inferred;

  const DueSoon({required this.daysLeft, required this.inferred});
}

/// 已超过保号截止日。
class Overdue extends KeepAliveStatus {
  final int daysOver;
  final bool inferred;

  const Overdue({required this.daysOver, required this.inferred});
}

/// 数据不足以判定。
///
/// 缺失数据一律落入此状态，绝不呈现为「安全」——
/// 静默误判是保号工具最不可接受的失败模式。
class Unknown extends KeepAliveStatus {
  const Unknown();
}
