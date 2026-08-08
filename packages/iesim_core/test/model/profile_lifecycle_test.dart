import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  test('enabled 与 disabled 都属于已激活 Profile', () {
    const enabled = ProfileLifecycle(deviceState: ProfileDeviceState.enabled);
    const disabled = ProfileLifecycle(deviceState: ProfileDeviceState.disabled);
    expect(enabled.stage, ProfileStage.active);
    expect(disabled.stage, ProfileStage.active);
  });

  test('未激活 Profile 可激活并保留激活要求', () {
    final deadline = DateTime.utc(2027, 1, 1);
    final activatedAt = DateTime.utc(2026, 8, 8);
    final pending = ProfileLifecycle(
      stage: ProfileStage.pendingActivation,
      activationDeadline: deadline,
      activationRequirements: '购买后 180 天内激活',
    );
    final active = pending.activate(activatedAt);
    expect(active.stage, ProfileStage.active);
    expect(active.activatedAt, activatedAt);
    expect(active.activationDeadline, deadline);
    expect(active.activationRequirements, '购买后 180 天内激活');
    expect(active.archivedAt, isNull);
  });

  test('归档会记录进入博物馆的时间与原因', () {
    final archivedAt = DateTime.utc(2026, 8, 8);
    final museum = const ProfileLifecycle(
      deviceState: ProfileDeviceState.disabled,
    ).archive(archivedAt, reason: ProfileArchiveReason.deleted);
    expect(museum.stage, ProfileStage.museum);
    expect(museum.deviceState, ProfileDeviceState.disabled);
    expect(museum.archivedAt, archivedAt);
    expect(museum.archiveReason, ProfileArchiveReason.deleted);
  });
}
