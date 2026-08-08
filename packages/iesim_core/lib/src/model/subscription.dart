import 'appearance.dart';
import 'keep_alive.dart';
import 'plan.dart';
import 'profile_lifecycle.dart';
import 'subscription_details.dart';
import '../value/phone_number.dart';
import '../interop/lpa_activation.dart';

/// 订阅聚合根。
///
/// 商业属性跟随号码而非硬件（spec §3.1 决定 3）：订阅挂在 Profile 下，
/// 这里建模为独立聚合，由 [iccid] 与资产域关联。
///
/// 全部字段不可变；时间戳一律 UTC。
/// 时区标识不在构造时校验（校验需时区数据库，构造保持无副作用），
/// 由 KeepAliveEvaluator / ZonedCalendar 在使用时以 ArgumentError 暴露问题。
class Subscription {
  final String id;

  /// 与 Nekoko 关联的键（spec §5.2），也作 SimHub JSON 扩展字段。
  final String? iccid;

  final PhoneNumber number;

  /// 运营商名称。
  final String? operator;

  /// eSIM QR / LPA 导入的激活凭据。UI 必须遮盖 [LpaActivation.matchingId]。
  final LpaActivation? activation;

  final Plan plan;

  final KeepAlive keepAlive;

  /// 标签，不可变。
  final List<String> tags;

  final Appearance appearance;

  final SubscriptionDetails details;

  /// Profile 的业务生命周期；与设备侧 Profile 是否 enabled 相互独立。
  final ProfileLifecycle lifecycle;

  /// IANA 基准时区标识，如 Asia/Shanghai（spec §4.3）。
  final String timeZoneId;

  /// 创建时刻，UTC。SimHub JSON 往返（spec §5.1）与 KeepAlive 推测基准用。
  final DateTime createdAt;

  /// 最后修改时刻，UTC。同步 last-write-wins 比较用（spec §6.2）。
  final DateTime updatedAt;

  Subscription({
    required this.id,
    this.iccid,
    required this.number,
    this.operator,
    this.activation,
    required this.plan,
    required this.keepAlive,
    List<String>? tags,
    this.appearance = const Appearance(),
    this.details = const SubscriptionDetails(),
    this.lifecycle = const ProfileLifecycle(),
    required this.timeZoneId,
    required this.createdAt,
    required this.updatedAt,
  }) : tags = List.unmodifiable(tags ?? const []) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', '不能为空');
    }
    if (timeZoneId.isEmpty) {
      throw ArgumentError.value(timeZoneId, 'timeZoneId', '不能为空');
    }
    if (!createdAt.isUtc) {
      throw ArgumentError.value(createdAt, 'createdAt', '必须为 UTC 时刻');
    }
    if (!updatedAt.isUtc) {
      throw ArgumentError.value(updatedAt, 'updatedAt', '必须为 UTC 时刻');
    }
  }

  Subscription copyWith({
    String? id,
    String? iccid,
    PhoneNumber? number,
    String? operator,
    LpaActivation? activation,
    Plan? plan,
    KeepAlive? keepAlive,
    List<String>? tags,
    Appearance? appearance,
    SubscriptionDetails? details,
    ProfileLifecycle? lifecycle,
    String? timeZoneId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Subscription(
    id: id ?? this.id,
    iccid: iccid ?? this.iccid,
    number: number ?? this.number,
    operator: operator ?? this.operator,
    activation: activation ?? this.activation,
    plan: plan ?? this.plan,
    keepAlive: keepAlive ?? this.keepAlive,
    tags: tags ?? this.tags,
    appearance: appearance ?? this.appearance,
    details: details ?? this.details,
    lifecycle: lifecycle ?? this.lifecycle,
    timeZoneId: timeZoneId ?? this.timeZoneId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Subscription &&
          other.id == id &&
          other.iccid == iccid &&
          other.number == number &&
          other.operator == operator &&
          other.activation == activation &&
          other.plan == plan &&
          other.keepAlive == keepAlive &&
          _listEquals(other.tags, tags) &&
          other.appearance == appearance &&
          other.details == details &&
          other.lifecycle == lifecycle &&
          other.timeZoneId == timeZoneId &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    iccid,
    number,
    operator,
    activation,
    plan,
    keepAlive,
    Object.hashAll(tags),
    appearance,
    details,
    lifecycle,
    timeZoneId,
    createdAt,
    updatedAt,
  );
}
