import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/compatibility_assistant.dart';
import 'package:iesim_core/iesim_core.dart';

void main() {
  test('设备、可拆卸 eUICC、EID 和已知 Profile 容量均兼容', () {
    final target = _subscription('target', size: 96 * 1024);
    final assessment = EuiccCompatibilityAssistant(
      inventory: _inventory(),
      subscriptions: [target],
    ).assess(eidId: 'eid-1', subscription: target);

    expect(assessment.severity, CompatibilitySeverity.compatible);
    expect(assessment.canProceed, isTrue);
    expect(assessment.device?.name, 'Pixel');
    expect(assessment.card?.presetId, '9esim-v0');
    expect(assessment.projectedProfileCount, 1);
    expect(assessment.projectedStorageBytes, 96 * 1024);
  });

  test('投影后已知容量超过卡片时阻止放置', () {
    final existing = _subscription('existing', size: 430 * 1024);
    final target = _subscription('target', size: 100 * 1024);
    final inventory = _inventory(
      profiles: [
        _assetProfile(
          id: 'profile-existing',
          subscriptionId: existing.id,
          iccid: existing.iccid,
        ),
      ],
    );

    final assessment = EuiccCompatibilityAssistant(
      inventory: inventory,
      subscriptions: [existing, target],
    ).assess(eidId: 'eid-1', subscription: target);

    expect(assessment.severity, CompatibilitySeverity.blocked);
    expect(
      assessment.findings.map((item) => item.code),
      contains('storage-exceeded'),
    );
  });

  test('普通实体 SIM 即使导入了 EID 也不能承载 Profile', () {
    final now = DateTime.utc(2026, 8, 8);
    final physical = PhysicalSimCard(
      id: 'card-physical',
      name: '实体 SIM',
      physicalIccid: '89000001',
      createdAt: now,
      updatedAt: now,
    );
    final assessment = EuiccCompatibilityAssistant(
      inventory: _inventory(
        card: physical,
        eid: Euicc(
          id: 'eid-physical',
          cardId: physical.id,
          value: '89049032000000000000000000000009',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      subscriptions: const [],
    ).assess(eidId: 'eid-physical');

    expect(assessment.severity, CompatibilitySeverity.blocked);
    expect(
      assessment.findings.map((item) => item.code),
      contains('physical-sim-cannot-host-profile'),
    );
  });

  test('相同 ICCID 已在同一卡片时阻止重复写入', () {
    final existing = _subscription('existing', iccid: '8900-DUPLICATE');
    final target = _subscription('target', iccid: '8900-DUPLICATE');
    final assessment = EuiccCompatibilityAssistant(
      inventory: _inventory(
        profiles: [
          _assetProfile(
            id: 'profile-existing',
            subscriptionId: existing.id,
            iccid: existing.iccid,
          ),
        ],
      ),
      subscriptions: [existing, target],
    ).assess(eidId: 'eid-1', subscription: target);

    expect(assessment.severity, CompatibilitySeverity.blocked);
    expect(
      assessment.findings.map((item) => item.code),
      contains('duplicate-iccid'),
    );
  });

  test('卡片在库存且 Profile 大小未知时要求用户确认', () {
    final inventory = _inventory(installed: false);
    final assessment = EuiccCompatibilityAssistant(
      inventory: inventory,
      subscriptions: const [],
    ).assess(eidId: 'eid-1');

    expect(assessment.severity, CompatibilitySeverity.caution);
    expect(
      assessment.findings.map((item) => item.code),
      containsAll(['card-not-installed', 'unknown-profile-size']),
    );
  });
}

AssetInventory _inventory({
  SimCard? card,
  Euicc? eid,
  Iterable<EsimProfile> profiles = const [],
  bool installed = true,
}) {
  final now = DateTime.utc(2026, 8, 8);
  final selectedCard =
      card ??
      RemovableEuiccCard(
        id: 'card-1',
        name: '9eSIM V0',
        presetId: '9esim-v0',
        createdAt: now,
        updatedAt: now,
      );
  final selectedEid =
      eid ??
      Euicc(
        id: 'eid-1',
        cardId: selectedCard.id,
        value: '89049032000000000000000000000001',
        createdAt: now,
        updatedAt: now,
      );
  return AssetInventory(
    devices: [
      DeviceAsset(
        id: 'device-1',
        name: 'Pixel',
        simCapability: SimCapability.physicalPlusEsim,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    slots: installed
        ? [
            SimSlot(
              id: 'slot-1',
              deviceId: 'device-1',
              label: 'SIM 1',
              kind: SimSlotKind.physical,
              position: 0,
              cardId: selectedCard.id,
              createdAt: now,
              updatedAt: now,
            ),
          ]
        : const [],
    cards: [selectedCard],
    eids: [selectedEid],
    profiles: profiles,
  );
}

Subscription _subscription(String id, {int? size, String? iccid}) =>
    Subscription(
      id: id,
      iccid: iccid ?? '89-$id',
      number: const PhoneNumber.unknown(),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      details: SubscriptionDetails(installedProfileSizeBytes: size),
      timeZoneId: 'UTC',
      createdAt: DateTime.utc(2026, 8, 8),
      updatedAt: DateTime.utc(2026, 8, 8),
    );

EsimProfile _assetProfile({
  required String id,
  required String subscriptionId,
  required String? iccid,
}) => EsimProfile(
  id: id,
  eidId: 'eid-1',
  iccid: iccid,
  subscriptionId: subscriptionId,
  createdAt: DateTime.utc(2026, 8, 8),
  updatedAt: DateTime.utc(2026, 8, 8),
);
