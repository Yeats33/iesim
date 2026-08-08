/// 首页 Profile 的业务生命周期。
///
/// [active] 同时包含设备侧 enabled / disabled；对运营商而言二者都已经激活。
enum ProfileStage { active, pendingActivation, museum }

/// eSIM 在设备上的运行状态，只描述本机状态，不改变业务生命周期。
enum ProfileDeviceState { unknown, enabled, disabled }

/// Profile 进入过期博物馆的原因。
enum ProfileArchiveReason { manual, deleted, expired, imported }

/// Profile 生命周期资料。全部时刻均为 UTC。
class ProfileLifecycle {
  const ProfileLifecycle({
    this.stage = ProfileStage.active,
    this.deviceState = ProfileDeviceState.unknown,
    this.activationDeadline,
    this.activationRequirements,
    this.serviceExpiresAt,
    this.activatedAt,
    this.archivedAt,
    this.archiveReason,
  });

  final ProfileStage stage;
  final ProfileDeviceState deviceState;

  /// 未激活 Profile 最晚应在何时完成激活。
  final DateTime? activationDeadline;

  /// 激活前必须满足的文本要求，例如“首次下载需位于购买国家”。
  final String? activationRequirements;

  /// 运营商侧 Profile 服务有效期；自动归档只依据此字段。
  final DateTime? serviceExpiresAt;

  final DateTime? activatedAt;
  final DateTime? archivedAt;
  final ProfileArchiveReason? archiveReason;

  ProfileLifecycle activate(DateTime nowUtc) {
    _requireUtc(nowUtc, 'nowUtc');
    return ProfileLifecycle(
      stage: ProfileStage.active,
      deviceState: deviceState,
      activationDeadline: activationDeadline,
      activationRequirements: activationRequirements,
      serviceExpiresAt: serviceExpiresAt,
      activatedAt: nowUtc,
    );
  }

  ProfileLifecycle archive(
    DateTime nowUtc, {
    required ProfileArchiveReason reason,
  }) {
    _requireUtc(nowUtc, 'nowUtc');
    return ProfileLifecycle(
      stage: ProfileStage.museum,
      deviceState: deviceState,
      activationDeadline: activationDeadline,
      activationRequirements: activationRequirements,
      serviceExpiresAt: serviceExpiresAt,
      activatedAt: activatedAt,
      archivedAt: nowUtc,
      archiveReason: reason,
    );
  }

  ProfileLifecycle copyWith({
    ProfileStage? stage,
    ProfileDeviceState? deviceState,
    Object? activationDeadline = _unset,
    Object? activationRequirements = _unset,
    Object? serviceExpiresAt = _unset,
    Object? activatedAt = _unset,
    Object? archivedAt = _unset,
    Object? archiveReason = _unset,
  }) => ProfileLifecycle(
    stage: stage ?? this.stage,
    deviceState: deviceState ?? this.deviceState,
    activationDeadline: identical(activationDeadline, _unset)
        ? this.activationDeadline
        : activationDeadline as DateTime?,
    activationRequirements: identical(activationRequirements, _unset)
        ? this.activationRequirements
        : activationRequirements as String?,
    serviceExpiresAt: identical(serviceExpiresAt, _unset)
        ? this.serviceExpiresAt
        : serviceExpiresAt as DateTime?,
    activatedAt: identical(activatedAt, _unset)
        ? this.activatedAt
        : activatedAt as DateTime?,
    archivedAt: identical(archivedAt, _unset)
        ? this.archivedAt
        : archivedAt as DateTime?,
    archiveReason: identical(archiveReason, _unset)
        ? this.archiveReason
        : archiveReason as ProfileArchiveReason?,
  );

  static void _requireUtc(DateTime value, String name) {
    if (!value.isUtc) throw ArgumentError.value(value, name, '必须为 UTC 时刻');
  }

  @override
  bool operator ==(Object other) =>
      other is ProfileLifecycle &&
      other.stage == stage &&
      other.deviceState == deviceState &&
      other.activationDeadline == activationDeadline &&
      other.activationRequirements == activationRequirements &&
      other.serviceExpiresAt == serviceExpiresAt &&
      other.activatedAt == activatedAt &&
      other.archivedAt == archivedAt &&
      other.archiveReason == archiveReason;

  @override
  int get hashCode => Object.hash(
    stage,
    deviceState,
    activationDeadline,
    activationRequirements,
    serviceExpiresAt,
    activatedAt,
    archivedAt,
    archiveReason,
  );
}

const _unset = Object();
