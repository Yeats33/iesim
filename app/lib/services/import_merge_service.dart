import 'package:iesim_core/iesim_core.dart';

enum ImportMatchKind { none, id, iccid, activation, phoneAndOperator }

enum ImportMergeAction { create, merge, replace, skip }

class ImportFieldDiff {
  const ImportFieldDiff({
    required this.key,
    required this.label,
    required this.currentValue,
    required this.incomingValue,
  });

  final String key;
  final String label;
  final String currentValue;
  final String incomingValue;
}

class ImportMergeCandidate {
  const ImportMergeCandidate({
    required this.incoming,
    required this.existing,
    required this.matchKind,
    required this.diffs,
    required this.defaultAction,
  });

  final Subscription incoming;
  final Subscription? existing;
  final ImportMatchKind matchKind;
  final List<ImportFieldDiff> diffs;
  final ImportMergeAction defaultAction;

  bool get isExactDuplicate => existing != null && diffs.isEmpty;
  bool get isWeakMatch => matchKind == ImportMatchKind.phoneAndOperator;

  List<ImportMergeAction> get availableActions {
    if (existing == null) {
      return const [ImportMergeAction.create, ImportMergeAction.skip];
    }
    if (isWeakMatch) {
      return const [
        ImportMergeAction.create,
        ImportMergeAction.merge,
        ImportMergeAction.replace,
        ImportMergeAction.skip,
      ];
    }
    return const [
      ImportMergeAction.merge,
      ImportMergeAction.replace,
      ImportMergeAction.skip,
    ];
  }
}

class ImportMergePlan {
  const ImportMergePlan({required this.candidates});

  final List<ImportMergeCandidate> candidates;

  Map<String, ImportMergeAction> get defaultActions => {
    for (final candidate in candidates)
      candidate.incoming.id: candidate.defaultAction,
  };

  int get newCount => candidates.where((item) => item.existing == null).length;
  int get matchedCount =>
      candidates.where((item) => item.existing != null).length;
  int get duplicateCount =>
      candidates.where((item) => item.isExactDuplicate).length;
  int get weakMatchCount => candidates.where((item) => item.isWeakMatch).length;
}

class ImportMergePlanner {
  ImportMergePlanner({
    required Iterable<Subscription> existingSubscriptions,
    required this.existingAssets,
  }) : existingSubscriptions = List.unmodifiable(existingSubscriptions) {
    for (final subscription in this.existingSubscriptions) {
      _subscriptionsById.putIfAbsent(subscription.id, () => subscription);
      final iccid = _normalizedIccid(subscription.iccid);
      if (iccid != null) {
        _subscriptionsByIccid.putIfAbsent(iccid, () => subscription);
      }
      final activation = subscription.activation;
      if (activation != null) {
        _subscriptionsByActivationKey.putIfAbsent(
          _activationKey(activation),
          () => subscription,
        );
      }
      final phoneOperatorKey = _phoneOperatorKey(subscription);
      if (phoneOperatorKey != null) {
        _subscriptionsByPhoneOperator.putIfAbsent(
          phoneOperatorKey,
          () => subscription,
        );
      }
    }
    for (final profile in existingAssets.profiles) {
      final subscriptionId = profile.subscriptionId;
      if (subscriptionId != null) {
        _profilesBySubscriptionId.putIfAbsent(subscriptionId, () => profile);
      }
      final iccid = _normalizedIccid(profile.iccid);
      if (iccid != null) {
        _profilesByIccid.putIfAbsent(iccid, () => profile);
      }
    }
  }

  final List<Subscription> existingSubscriptions;
  final AssetInventory existingAssets;
  final Map<String, Subscription> _subscriptionsById = {};
  final Map<String, Subscription> _subscriptionsByIccid = {};
  final Map<String, Subscription> _subscriptionsByActivationKey = {};
  final Map<String, Subscription> _subscriptionsByPhoneOperator = {};
  final Map<String, EsimProfile> _profilesBySubscriptionId = {};
  final Map<String, EsimProfile> _profilesByIccid = {};

  ImportMergePlan inspect(Iterable<Subscription> incoming) => ImportMergePlan(
    candidates: [for (final item in incoming) _inspectOne(item)],
  );

  SimHubImportReport resolveSimHub({
    required SimHubImportReport report,
    required ImportMergePlan plan,
    required Map<String, ImportMergeAction> actions,
    String? targetEidId,
    required DateTime nowUtc,
  }) {
    final resolved = _resolveSubscriptions(plan, actions, nowUtc);
    return SimHubImportReport(
      subscriptions: resolved.subscriptions,
      activityRecords: [
        for (final activity in report.activityRecords)
          if (resolved.includedIncomingIds.contains(activity.subscriptionId))
            activity.copyWith(
              subscriptionId:
                  resolved.idRemap[activity.subscriptionId] ??
                  activity.subscriptionId,
            ),
      ],
      issues: report.issues,
      sourceRecordCount: report.sourceRecordCount,
      assets: _resolveAssets(
        report.assets,
        resolved,
        actions,
        targetEidId: targetEidId,
        nowUtc: nowUtc,
      ),
      ignoredServiceCount: report.ignoredServiceCount,
      ignoredBindingCount: report.ignoredBindingCount,
    );
  }

  NekokoImportReport resolveNekoko({
    required NekokoImportReport report,
    required ImportMergePlan plan,
    required Map<String, ImportMergeAction> actions,
    String? targetEidId,
    required DateTime nowUtc,
  }) {
    final resolved = _resolveSubscriptions(plan, actions, nowUtc);
    return NekokoImportReport(
      sourceProfileCount: report.sourceProfileCount,
      subscriptions: resolved.subscriptions,
      assets: _resolveAssets(
        report.assets,
        resolved,
        actions,
        targetEidId: targetEidId,
        nowUtc: nowUtc,
      ),
      issues: report.issues,
    );
  }

  ImportMergeCandidate _inspectOne(Subscription incoming) {
    final match = _findMatch(incoming);
    final diffs = match == null
        ? const <ImportFieldDiff>[]
        : _diff(match.$1, incoming);
    final defaultAction = switch ((match?.$2, diffs.isEmpty)) {
      (null, _) => ImportMergeAction.create,
      (ImportMatchKind.phoneAndOperator, _) => ImportMergeAction.create,
      (_, true) => ImportMergeAction.skip,
      _ => ImportMergeAction.merge,
    };
    return ImportMergeCandidate(
      incoming: incoming,
      existing: match?.$1,
      matchKind: match?.$2 ?? ImportMatchKind.none,
      diffs: List.unmodifiable(diffs),
      defaultAction: defaultAction,
    );
  }

  (Subscription, ImportMatchKind)? _findMatch(Subscription incoming) {
    final byId = _subscriptionsById[incoming.id];
    if (byId != null) return (byId, ImportMatchKind.id);
    final iccid = _normalizedIccid(incoming.iccid);
    final byIccid = iccid == null ? null : _subscriptionsByIccid[iccid];
    if (byIccid != null) return (byIccid, ImportMatchKind.iccid);
    final activation = incoming.activation;
    if (activation != null) {
      final byActivation =
          _subscriptionsByActivationKey[_activationKey(activation)];
      if (byActivation != null) {
        return (byActivation, ImportMatchKind.activation);
      }
    }
    final phoneOperatorKey = _phoneOperatorKey(incoming);
    final byPhoneOperator = phoneOperatorKey == null
        ? null
        : _subscriptionsByPhoneOperator[phoneOperatorKey];
    if (byPhoneOperator != null) {
      return (byPhoneOperator, ImportMatchKind.phoneAndOperator);
    }
    return null;
  }

  List<ImportFieldDiff> _diff(Subscription current, Subscription incoming) {
    final result = <ImportFieldDiff>[];
    void add(String key, String label, Object? left, Object? right) {
      if (_equivalent(left, right)) return;
      result.add(
        ImportFieldDiff(
          key: key,
          label: label,
          currentValue: _display(left),
          incomingValue: _display(right),
        ),
      );
    }

    add('iccid', 'ICCID', current.iccid, incoming.iccid);
    add('number', '手机号', current.number.value, incoming.number.value);
    add('operator', '运营商', current.operator, incoming.operator);
    add(
      'profileName',
      'Profile 名称',
      current.details.profileName,
      incoming.details.profileName,
    );
    add(
      'stage',
      '生命周期',
      current.lifecycle.stage.name,
      incoming.lifecycle.stage.name,
    );
    add(
      'deviceState',
      '设备状态',
      current.lifecycle.deviceState.name,
      incoming.lifecycle.deviceState.name,
    );
    add(
      'country',
      '国家/地区',
      current.details.countryName,
      incoming.details.countryName,
    );
    add('mcc', 'MCC', current.details.mcc, incoming.details.mcc);
    add('mnc', 'MNC', current.details.mnc, incoming.details.mnc);
    add('apn', 'APN', current.details.apn, incoming.details.apn);
    add('planName', '套餐', current.plan.name, incoming.plan.name);
    add(
      'cyclePrice',
      '周期价格',
      current.plan.cyclePrice,
      incoming.plan.cyclePrice,
    );
    add('cycleDays', '套餐周期', current.plan.cycleDays, incoming.plan.cycleDays);
    add(
      'expiryDate',
      '套餐到期',
      current.plan.expiryDate,
      incoming.plan.expiryDate,
    );
    add(
      'balance',
      '余额',
      current.details.currentBalance,
      incoming.details.currentBalance,
    );
    add(
      'keepAlive',
      '保号周期',
      current.keepAlive.required ? current.keepAlive.cycleDays : '不需要',
      incoming.keepAlive.required ? incoming.keepAlive.cycleDays : '不需要',
    );
    add('tags', '标签', [...current.tags]..sort(), [...incoming.tags]..sort());
    add(
      'profileSize',
      'Profile 占用',
      current.details.installedProfileSizeBytes ??
          current.details.declaredProfileSizeBytes,
      incoming.details.installedProfileSizeBytes ??
          incoming.details.declaredProfileSizeBytes,
    );
    if (current.activation != incoming.activation) {
      result.add(
        ImportFieldDiff(
          key: 'activation',
          label: 'LPA 激活凭据',
          currentValue: current.activation == null ? '未提供' : '已保存（已遮盖）',
          incomingValue: incoming.activation == null ? '未提供' : '导入文件包含（已遮盖）',
        ),
      );
    }
    final normalizedIncoming = incoming.copyWith(
      id: current.id,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt,
    );
    if (result.isEmpty && current != normalizedIncoming) {
      result.add(
        const ImportFieldDiff(
          key: 'otherMetadata',
          label: '其他元数据',
          currentValue: '本地值',
          incomingValue: '导入文件中存在其他变化',
        ),
      );
    }
    return result;
  }

  _ResolvedSubscriptions _resolveSubscriptions(
    ImportMergePlan plan,
    Map<String, ImportMergeAction> actions,
    DateTime nowUtc,
  ) {
    final subscriptions = <Subscription>[];
    final idRemap = <String, String>{};
    final includedIncomingIds = <String>{};
    final candidatesById = <String, ImportMergeCandidate>{};
    for (final candidate in plan.candidates) {
      candidatesById[candidate.incoming.id] = candidate;
      final action = actions[candidate.incoming.id] ?? candidate.defaultAction;
      if (!candidate.availableActions.contains(action)) {
        throw FormatException('导入动作与匹配类型不兼容：${candidate.incoming.id}');
      }
      if (action == ImportMergeAction.skip) continue;
      final existing = candidate.existing;
      final resolved = switch (action) {
        ImportMergeAction.create => candidate.incoming,
        ImportMergeAction.merge => _mergePreferLocal(
          existing!,
          candidate.incoming,
          nowUtc,
        ),
        ImportMergeAction.replace => _replaceMetadata(
          existing!,
          candidate.incoming,
          nowUtc,
        ),
        ImportMergeAction.skip => throw StateError('已在上方处理'),
      };
      subscriptions.add(resolved);
      includedIncomingIds.add(candidate.incoming.id);
      idRemap[candidate.incoming.id] = resolved.id;
    }
    return _ResolvedSubscriptions(
      subscriptions: subscriptions,
      idRemap: idRemap,
      includedIncomingIds: includedIncomingIds,
      candidatesById: candidatesById,
    );
  }

  AssetInventory _resolveAssets(
    AssetInventory incoming,
    _ResolvedSubscriptions resolved,
    Map<String, ImportMergeAction> actions, {
    required String? targetEidId,
    required DateTime nowUtc,
  }) {
    if (targetEidId != null) _validateTargetEid(targetEidId);
    final profiles = <String, EsimProfile>{};
    final resolvedIdsWithIncomingProfiles = <String>{};

    for (final profile in incoming.profiles) {
      final incomingSubscriptionId = profile.subscriptionId;
      if (incomingSubscriptionId == null) {
        profiles[profile.id] = profile;
        continue;
      }
      if (!resolved.includedIncomingIds.contains(incomingSubscriptionId)) {
        continue;
      }
      final resolvedSubscriptionId =
          resolved.idRemap[incomingSubscriptionId] ?? incomingSubscriptionId;
      resolvedIdsWithIncomingProfiles.add(resolvedSubscriptionId);
      final candidate = resolved.candidatesById[incomingSubscriptionId];
      final action =
          actions[incomingSubscriptionId] ?? candidate?.defaultAction;
      final existingProfile = _existingProfileFor(
        resolvedSubscriptionId,
        profile.iccid,
      );
      final preserveLocalPlacement =
          existingProfile != null && action == ImportMergeAction.merge;
      final output = EsimProfile(
        id: existingProfile?.id ?? profile.id,
        eidId: preserveLocalPlacement ? existingProfile.eidId : profile.eidId,
        iccid: profile.iccid ?? existingProfile?.iccid,
        operatorName: preserveLocalPlacement
            ? existingProfile.operatorName ?? profile.operatorName
            : profile.operatorName ?? existingProfile?.operatorName,
        nickname: preserveLocalPlacement
            ? existingProfile.nickname ?? profile.nickname
            : profile.nickname ?? existingProfile?.nickname,
        subscriptionId: resolvedSubscriptionId,
        isPinned: preserveLocalPlacement
            ? existingProfile.isPinned
            : profile.isPinned,
        createdAt: existingProfile?.createdAt ?? profile.createdAt,
        updatedAt: _latest(profile.updatedAt, existingProfile?.updatedAt),
      );
      profiles[output.id] = output;
    }

    if (targetEidId != null) {
      for (final subscription in resolved.subscriptions) {
        if (resolvedIdsWithIncomingProfiles.contains(subscription.id)) {
          continue;
        }
        final existingProfile = _existingProfileFor(
          subscription.id,
          subscription.iccid,
        );
        if (existingProfile != null) continue;
        final profile = EsimProfile(
          id: 'import-profile:${subscription.id}',
          eidId: targetEidId,
          iccid: subscription.iccid,
          operatorName: subscription.operator,
          nickname: subscription.details.profileName,
          subscriptionId: subscription.id,
          isPinned: subscription.details.isPinned,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        );
        profiles[profile.id] = profile;
      }
    }

    return AssetInventory(
      devices: incoming.devices,
      slots: incoming.slots,
      cards: incoming.cards,
      eids: incoming.eids,
      profiles: profiles.values,
      events: incoming.events,
    );
  }

  void _validateTargetEid(String targetEidId) {
    final eid = existingAssets.eidById(targetEidId);
    if (eid == null) throw const FormatException('目标 EID 已不存在');
    final card = existingAssets.cardById(eid.cardId);
    if (card == null) throw const FormatException('目标 EID 没有所属卡片');
    if (card is PhysicalSimCard) {
      throw const FormatException('普通实体 SIM 不能承载 eSIM Profile');
    }
  }

  EsimProfile? _existingProfileFor(String subscriptionId, String? iccid) {
    final bySubscription = _profilesBySubscriptionId[subscriptionId];
    if (bySubscription != null) return bySubscription;
    final normalizedIccid = _normalizedIccid(iccid);
    return normalizedIccid == null ? null : _profilesByIccid[normalizedIccid];
  }

  static Subscription _mergePreferLocal(
    Subscription local,
    Subscription incoming,
    DateTime nowUtc,
  ) => local.copyWith(
    iccid: local.iccid ?? incoming.iccid,
    number: local.number.isUnknown ? incoming.number : local.number,
    operator: local.operator ?? incoming.operator,
    activation: local.activation ?? incoming.activation,
    plan: Plan(
      name: local.plan.name ?? incoming.plan.name,
      cyclePrice: local.plan.cyclePrice ?? incoming.plan.cyclePrice,
      cycleDays: local.plan.cycleDays ?? incoming.plan.cycleDays,
      startDate: local.plan.startDate ?? incoming.plan.startDate,
      expiryDate: local.plan.expiryDate ?? incoming.plan.expiryDate,
      isLongTerm: local.plan.isLongTerm || incoming.plan.isLongTerm,
    ),
    tags: {...local.tags, ...incoming.tags}.toList(growable: false),
    appearance: Appearance(
      flag: local.appearance.flag ?? incoming.appearance.flag,
      cardColorHex:
          local.appearance.cardColorHex ?? incoming.appearance.cardColorHex,
      cardBackgroundAssetName:
          local.appearance.cardBackgroundAssetName ??
          incoming.appearance.cardBackgroundAssetName,
      websiteURL: local.appearance.websiteURL ?? incoming.appearance.websiteURL,
      customPrompt:
          local.appearance.customPrompt ?? incoming.appearance.customPrompt,
    ),
    details: local.details.copyWith(
      profileName: local.details.profileName ?? incoming.details.profileName,
      profileClassCode:
          local.details.profileClassCode ?? incoming.details.profileClassCode,
      declaredProfileSizeBytes:
          local.details.declaredProfileSizeBytes ??
          incoming.details.declaredProfileSizeBytes,
      installedProfileSizeBytes:
          local.details.installedProfileSizeBytes ??
          incoming.details.installedProfileSizeBytes,
      gid1: local.details.gid1 ?? incoming.details.gid1,
      gid2: local.details.gid2 ?? incoming.details.gid2,
      countryCode: local.details.countryCode ?? incoming.details.countryCode,
      countryName: local.details.countryName ?? incoming.details.countryName,
      mcc: local.details.mcc ?? incoming.details.mcc,
      mnc: local.details.mnc ?? incoming.details.mnc,
      apn: local.details.apn ?? incoming.details.apn,
      secondaryPhoneNumber:
          local.details.secondaryPhoneNumber ??
          incoming.details.secondaryPhoneNumber,
      activationDate:
          local.details.activationDate ?? incoming.details.activationDate,
      currentBalance:
          local.details.currentBalance ?? incoming.details.currentBalance,
      affiliateOffers: local.details.affiliateOffers.isEmpty
          ? incoming.details.affiliateOffers
          : local.details.affiliateOffers,
      appBindings: local.details.appBindings.isEmpty
          ? incoming.details.appBindings
          : local.details.appBindings,
      topUpCycleUnit:
          local.details.topUpCycleUnit ?? incoming.details.topUpCycleUnit,
      renewalIntervalValue:
          local.details.renewalIntervalValue ??
          incoming.details.renewalIntervalValue,
      renewalUnit: local.details.renewalUnit ?? incoming.details.renewalUnit,
      transactionNotes:
          local.details.transactionNotes ?? incoming.details.transactionNotes,
      carrierAppName:
          local.details.carrierAppName ?? incoming.details.carrierAppName,
      carrierAppStoreUrl:
          local.details.carrierAppStoreUrl ??
          incoming.details.carrierAppStoreUrl,
      carrierAppIconUrl:
          local.details.carrierAppIconUrl ?? incoming.details.carrierAppIconUrl,
      keepAliveModeRaw:
          local.details.keepAliveModeRaw ?? incoming.details.keepAliveModeRaw,
    ),
    lifecycle: local.lifecycle.copyWith(
      deviceState: local.lifecycle.deviceState == ProfileDeviceState.unknown
          ? incoming.lifecycle.deviceState
          : local.lifecycle.deviceState,
      activationDeadline:
          local.lifecycle.activationDeadline ??
          incoming.lifecycle.activationDeadline,
      activationRequirements:
          local.lifecycle.activationRequirements ??
          incoming.lifecycle.activationRequirements,
      serviceExpiresAt:
          local.lifecycle.serviceExpiresAt ??
          incoming.lifecycle.serviceExpiresAt,
      activatedAt:
          local.lifecycle.activatedAt ?? incoming.lifecycle.activatedAt,
    ),
    updatedAt: _latest(nowUtc, _latest(local.updatedAt, incoming.updatedAt)),
  );

  static Subscription _replaceMetadata(
    Subscription local,
    Subscription incoming,
    DateTime nowUtc,
  ) => incoming.copyWith(
    id: local.id,
    activation: incoming.activation ?? local.activation,
    createdAt: local.createdAt,
    updatedAt: _latest(nowUtc, incoming.updatedAt),
  );

  static DateTime _latest(DateTime value, DateTime? other) =>
      other != null && other.isAfter(value) ? other : value;

  static String _display(Object? value) {
    if (value == null || value == '') return '未提供';
    if (value is DateTime) return value.toIso8601String();
    if (value is List) return value.isEmpty ? '无' : value.join('、');
    return '$value';
  }

  static bool _equivalent(Object? left, Object? right) {
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (left[index] != right[index]) return false;
      }
      return true;
    }
    return left == right;
  }

  static String? _normalizedIccid(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String _activationKey(LpaActivation activation) =>
      '${activation.smdpAddress}\u0000${activation.matchingId}\u0000${activation.extra ?? ''}';

  static String? _phoneOperatorKey(Subscription subscription) {
    if (subscription.number.isUnknown) return null;
    final operator = subscription.operator?.trim().toLowerCase();
    if (operator == null || operator.isEmpty) return null;
    return '${subscription.number.value}\u0000$operator';
  }
}

class _ResolvedSubscriptions {
  _ResolvedSubscriptions({
    required this.subscriptions,
    required this.idRemap,
    required this.includedIncomingIds,
    required this.candidatesById,
  });

  final List<Subscription> subscriptions;
  final Map<String, String> idRemap;
  final Set<String> includedIncomingIds;
  final Map<String, ImportMergeCandidate> candidatesById;
}
