import 'package:iesim_core/iesim_core.dart';

import '../data/euicc_card_presets.dart';

enum CompatibilitySeverity { compatible, caution, blocked }

class CompatibilityFinding {
  const CompatibilityFinding({
    required this.code,
    required this.severity,
    required this.title,
    required this.detail,
  });

  final String code;
  final CompatibilitySeverity severity;
  final String title;
  final String detail;
}

class CompatibilityAssessment {
  const CompatibilityAssessment({
    required this.findings,
    this.device,
    this.card,
    this.eid,
    this.preset,
    this.projectedProfileCount,
    this.projectedStorageBytes,
  });

  final List<CompatibilityFinding> findings;
  final DeviceAsset? device;
  final SimCard? card;
  final Euicc? eid;
  final EuiccCardPreset? preset;
  final int? projectedProfileCount;
  final int? projectedStorageBytes;

  CompatibilitySeverity get severity {
    if (findings.any(
      (finding) => finding.severity == CompatibilitySeverity.blocked,
    )) {
      return CompatibilitySeverity.blocked;
    }
    if (findings.any(
      (finding) => finding.severity == CompatibilitySeverity.caution,
    )) {
      return CompatibilitySeverity.caution;
    }
    return CompatibilitySeverity.compatible;
  }

  bool get canProceed => severity != CompatibilitySeverity.blocked;

  String get shortLabel => switch (severity) {
    CompatibilitySeverity.compatible => '兼容',
    CompatibilitySeverity.caution => '需确认',
    CompatibilitySeverity.blocked => '不可放置',
  };

  String get primaryMessage => findings.isEmpty
      ? '未发现兼容性问题'
      : findings
            .firstWhere(
              (finding) => finding.severity == severity,
              orElse: () => findings.first,
            )
            .detail;
}

/// 对“设备 → 卡槽 → 卡片 → EID → Profile”整条链路做可执行检查。
class EuiccCompatibilityAssistant {
  EuiccCompatibilityAssistant({
    required this.inventory,
    required Iterable<Subscription> subscriptions,
    Iterable<EuiccCardPreset> presets = builtinEuiccCardPresets,
  }) : subscriptions = List.unmodifiable(subscriptions),
       presets = List.unmodifiable(presets) {
    _subscriptionsById = Map.unmodifiable({
      for (final item in this.subscriptions) item.id: item,
    });
    _presetsById = Map.unmodifiable({
      for (final item in this.presets) item.id: item,
    });
    _profilesBySubscriptionId = Map.unmodifiable({
      for (final item in inventory.profiles)
        if (item.subscriptionId != null) item.subscriptionId!: item,
    });
  }

  final AssetInventory inventory;
  final List<Subscription> subscriptions;
  final List<EuiccCardPreset> presets;
  late final Map<String, Subscription> _subscriptionsById;
  late final Map<String, EuiccCardPreset> _presetsById;
  late final Map<String, EsimProfile> _profilesBySubscriptionId;

  CompatibilityAssessment assess({
    required String eidId,
    Subscription? subscription,
    String? currentAssetProfileId,
  }) {
    final findings = <CompatibilityFinding>[];
    final eid = inventory.eidById(eidId);
    if (eid == null) {
      return CompatibilityAssessment(
        findings: const [
          CompatibilityFinding(
            code: 'missing-eid',
            severity: CompatibilitySeverity.blocked,
            title: 'EID 不存在',
            detail: '目标 EID 已被删除，请重新选择。',
          ),
        ],
      );
    }

    final card = inventory.cardById(eid.cardId);
    if (card == null) {
      return CompatibilityAssessment(
        eid: eid,
        findings: const [
          CompatibilityFinding(
            code: 'missing-card',
            severity: CompatibilitySeverity.blocked,
            title: '卡片不存在',
            detail: '该 EID 没有可用的所属卡片。',
          ),
        ],
      );
    }

    final preset = card.presetId == null ? null : _presetsById[card.presetId];
    final slot = inventory.slotHolding(card.id);
    final device = slot == null ? null : inventory.deviceById(slot.deviceId);

    if (card is PhysicalSimCard) {
      findings.add(
        const CompatibilityFinding(
          code: 'physical-sim-cannot-host-profile',
          severity: CompatibilitySeverity.blocked,
          title: '卡片类型不兼容',
          detail: '普通实体 SIM 不能承载可下载 eSIM Profile。',
        ),
      );
    } else if (slot == null) {
      findings.add(
        CompatibilityFinding(
          code: 'card-not-installed',
          severity: card is EmbeddedEuiccCard
              ? CompatibilitySeverity.blocked
              : CompatibilitySeverity.caution,
          title: '卡片尚未安装',
          detail: card is EmbeddedEuiccCard
              ? '内置 eUICC 必须位于所属设备的内置卡槽。'
              : '卡片目前在库存中；写入或使用前需放入兼容设备或读卡器。',
        ),
      );
    } else {
      final placementError = AssetRules.placementError(card, slot);
      if (placementError != null) {
        findings.add(
          CompatibilityFinding(
            code: 'invalid-slot-placement',
            severity: CompatibilitySeverity.blocked,
            title: '卡槽放置无效',
            detail: placementError,
          ),
        );
      }
      if (device == null) {
        findings.add(
          const CompatibilityFinding(
            code: 'missing-device',
            severity: CompatibilitySeverity.blocked,
            title: '设备记录缺失',
            detail: '卡槽没有可用的所属设备。',
          ),
        );
      } else {
        _checkDeviceCapability(findings, device, card);
      }
    }

    final cardEidIds = inventory
        .eidsForCard(card.id)
        .map((item) => item.id)
        .toSet();
    final cardProfiles = [
      for (final cardEidId in cardEidIds)
        ...inventory.profilesForEid(cardEidId),
    ];
    final currentProfile = currentAssetProfileId != null
        ? inventory.profileById(currentAssetProfileId)
        : subscription == null
        ? null
        : _profilesBySubscriptionId[subscription.id];
    final alreadyOnCard =
        currentProfile != null && cardEidIds.contains(currentProfile.eidId);
    final projectedCount = cardProfiles.length + (alreadyOnCard ? 0 : 1);

    if (subscription?.iccid case final iccid? when iccid.trim().isNotEmpty) {
      final duplicate = cardProfiles.any(
        (profile) => profile.id != currentProfile?.id && profile.iccid == iccid,
      );
      if (duplicate) {
        findings.add(
          const CompatibilityFinding(
            code: 'duplicate-iccid',
            severity: CompatibilitySeverity.blocked,
            title: 'ICCID 重复',
            detail: '该卡片上已有相同 ICCID 的 Profile，不应重复写入。',
          ),
        );
      }
    }

    final subscriptionsById = {..._subscriptionsById};
    if (subscription != null) {
      subscriptionsById[subscription.id] = subscription;
    }
    var knownBytes = 0;
    var unknownSizeCount = 0;
    for (final profile in cardProfiles) {
      if (profile.id == currentProfile?.id) continue;
      final linked = profile.subscriptionId == null
          ? null
          : subscriptionsById[profile.subscriptionId];
      final size = _profileSize(linked);
      if (size == null) {
        unknownSizeCount++;
      } else {
        knownBytes += size;
      }
    }
    final targetSize = _profileSize(subscription);
    if (targetSize == null) {
      unknownSizeCount++;
    } else {
      knownBytes += targetSize;
    }

    if (preset == null) {
      findings.add(
        const CompatibilityFinding(
          code: 'unknown-card-capacity',
          severity: CompatibilitySeverity.caution,
          title: '卡片容量未知',
          detail: '自定义卡片没有容量预设，无法精确判断剩余空间。',
        ),
      );
    } else {
      final maxCount = preset.maxProfileCount;
      if (maxCount != null && projectedCount > maxCount) {
        findings.add(
          CompatibilityFinding(
            code: 'profile-count-exceeded',
            severity: CompatibilitySeverity.blocked,
            title: 'Profile 数量超限',
            detail:
                '预计将有 $projectedCount 个 Profile，超过 ${preset.displayName} 的约 $maxCount 个上限。',
          ),
        );
      }
      final capacity = preset.storageBytes;
      if (capacity != null && knownBytes > capacity) {
        findings.add(
          CompatibilityFinding(
            code: 'storage-exceeded',
            severity: CompatibilitySeverity.blocked,
            title: '容量不足',
            detail:
                '已知 Profile 合计 ${_formatBytes(knownBytes)}，超过卡片 ${preset.storageLabel} 容量。',
          ),
        );
      } else if (capacity != null && knownBytes * 100 >= capacity * 85) {
        findings.add(
          CompatibilityFinding(
            code: 'storage-near-capacity',
            severity: CompatibilitySeverity.caution,
            title: '剩余空间较少',
            detail:
                '已知 Profile 将占用约 ${_formatBytes(knownBytes)} / ${preset.storageLabel}。',
          ),
        );
      } else if (capacity != null && unknownSizeCount == 0) {
        findings.add(
          CompatibilityFinding(
            code: 'storage-compatible',
            severity: CompatibilitySeverity.compatible,
            title: '容量可用',
            detail:
                '已知 Profile 将占用约 ${_formatBytes(knownBytes)} / ${preset.storageLabel}。',
          ),
        );
      }
      if (unknownSizeCount > 0) {
        findings.add(
          CompatibilityFinding(
            code: 'unknown-profile-size',
            severity: CompatibilitySeverity.caution,
            title: 'Profile 大小不完整',
            detail:
                '有 $unknownSizeCount 个 Profile 没有容量数据，写入前仍需以卡片管理工具的实际剩余空间为准。',
          ),
        );
      }
    }

    if (subscription != null) {
      if (subscription.lifecycle.stage == ProfileStage.pendingActivation &&
          subscription.activation == null) {
        findings.add(
          const CompatibilityFinding(
            code: 'missing-activation-credential',
            severity: CompatibilitySeverity.caution,
            title: '缺少激活凭据',
            detail: '这是未激活 Profile，但尚未保存 LPA / 二维码激活信息。',
          ),
        );
      }
      if (subscription.lifecycle.stage == ProfileStage.museum) {
        findings.add(
          const CompatibilityFinding(
            code: 'museum-profile',
            severity: CompatibilitySeverity.caution,
            title: '博物馆 Profile',
            detail: '该 Profile 已归档；确认仍需在 eUICC 上保留它。',
          ),
        );
      }
    }

    if (findings.isEmpty) {
      findings.add(
        const CompatibilityFinding(
          code: 'compatible',
          severity: CompatibilitySeverity.compatible,
          title: '兼容性通过',
          detail: '未发现设备、卡片、EID 或 Profile 层面的冲突。',
        ),
      );
    }

    return CompatibilityAssessment(
      findings: List.unmodifiable(findings),
      device: device,
      card: card,
      eid: eid,
      preset: preset,
      projectedProfileCount: projectedCount,
      projectedStorageBytes: knownBytes,
    );
  }

  static void _checkDeviceCapability(
    List<CompatibilityFinding> findings,
    DeviceAsset device,
    SimCard card,
  ) {
    final inconsistent = switch ((card.kind, device.simCapability)) {
      (
        SimCardKind.removableEuicc,
        SimCapability.esimOnly || SimCapability.multiEsim,
      ) =>
        true,
      (
        SimCardKind.embeddedEuicc,
        SimCapability.physicalOnly || SimCapability.dualPhysical,
      ) =>
        true,
      _ => false,
    };
    findings.add(
      CompatibilityFinding(
        code: inconsistent ? 'device-capability-conflict' : 'device-compatible',
        severity: inconsistent
            ? CompatibilitySeverity.caution
            : CompatibilitySeverity.compatible,
        title: inconsistent ? '设备能力记录冲突' : '设备与卡槽可用',
        detail: inconsistent
            ? '${device.name} 的 SIM 能力标注与当前卡槽/卡片关系不一致，请先核对设备型号。'
            : '${device.name} 已有可承载该卡片的卡槽。',
      ),
    );
  }

  static int? _profileSize(Subscription? subscription) =>
      subscription?.details.installedProfileSizeBytes ??
      subscription?.details.declaredProfileSizeBytes;

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KiB';
  }
}
