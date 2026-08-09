import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  test('资产关系可按 ID 直接查找，且快照不受输入集合后续修改影响', () {
    final now = DateTime.utc(2026, 8, 9);
    final device = DeviceAsset(
      id: 'device-1',
      name: '测试手机',
      createdAt: now,
      updatedAt: now,
    );
    final card = RemovableEuiccCard(
      id: 'card-1',
      name: '测试 eUICC',
      createdAt: now,
      updatedAt: now,
    );
    final slot = SimSlot(
      id: 'slot-1',
      deviceId: device.id,
      label: 'SIM 1',
      kind: SimSlotKind.physical,
      position: 0,
      cardId: card.id,
      createdAt: now,
      updatedAt: now,
    );
    final eid = Euicc(
      id: 'eid-1',
      cardId: card.id,
      value: '89049032000000000000000000000001',
      createdAt: now,
      updatedAt: now,
    );
    final profile = EsimProfile(
      id: 'profile-1',
      eidId: eid.id,
      iccid: '8986000000000000001',
      createdAt: now,
      updatedAt: now,
    );
    final devices = [device];
    final inventory = AssetInventory(
      devices: devices,
      slots: [slot],
      cards: [card],
      eids: [eid],
      profiles: [profile],
    );
    devices.clear();

    expect(inventory.deviceById(device.id), same(device));
    expect(inventory.slotHolding(card.id), same(slot));
    expect(inventory.cardById(card.id), same(card));
    expect(inventory.eidById(eid.id), same(eid));
    expect(inventory.profileById(profile.id), same(profile));
    expect(inventory.slotsForDevice(device.id), [slot]);
    expect(inventory.eidsForCard(card.id), [eid]);
    expect(inventory.profilesForEid(eid.id), [profile]);
    expect(inventory.devices, [device]);
    expect(
      () => (inventory.profilesForEid(eid.id) as List<EsimProfile>).clear(),
      throwsUnsupportedError,
    );
  });
}
