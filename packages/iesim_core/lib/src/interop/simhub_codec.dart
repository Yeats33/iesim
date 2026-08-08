import 'dart:convert';

import '../model/activity_record.dart';
import '../model/affiliate_offer.dart';
import '../model/appearance.dart';
import '../model/assets.dart';
import '../model/keep_alive.dart';
import '../model/plan.dart';
import '../model/profile_lifecycle.dart';
import '../model/subscription.dart';
import '../model/subscription_details.dart';
import '../time/calendar.dart';
import '../value/money.dart';
import '../value/phone_number.dart';
import 'lpa_activation.dart';

/// SimHub 批量导入中的一条可呈现问题。
///
/// [recordIndex] 从 1 开始；顶层 JSON 本身错误时为 null。
class SimHubImportIssue {
  final int? recordIndex;
  final String field;
  final String message;

  const SimHubImportIssue({
    required this.recordIndex,
    required this.field,
    required this.message,
  });
}

/// SimHub 导入结果。单条失败不会中断整批。
class SimHubImportReport {
  final List<Subscription> subscriptions;
  final List<ActivityRecord> activityRecords;
  final List<SimHubImportIssue> issues;
  final int sourceRecordCount;
  final AssetInventory assets;
  final int ignoredServiceCount;
  final int ignoredBindingCount;

  SimHubImportReport({
    required List<Subscription> subscriptions,
    required List<ActivityRecord> activityRecords,
    required List<SimHubImportIssue> issues,
    required this.sourceRecordCount,
    AssetInventory? assets,
    this.ignoredServiceCount = 0,
    this.ignoredBindingCount = 0,
  }) : subscriptions = List.unmodifiable(subscriptions),
       activityRecords = List.unmodifiable(activityRecords),
       issues = List.unmodifiable(issues),
       assets = assets ?? AssetInventory();

  int get importedCount => subscriptions.length;
  int get skippedCount => sourceRecordCount - importedCount;
}

/// SimHub / SimJ 交换 JSON 编解码器。
///
/// 兼容数组、单对象和 `{ "subscriptions": [...] }` 三种常见包裹方式；
/// `cardType` 与 `billingType` 双字段名均接受。iesim 扩展字段放在顶层，
/// 旧客户端会忽略它们。
class SimHubCodec {
  SimHubCodec({String Function()? idFactory, DateTime Function()? nowUtc})
    : _idFactory = idFactory ?? _fallbackId,
      _nowUtc = nowUtc ?? _systemNowUtc;

  final String Function() _idFactory;
  final DateTime Function() _nowUtc;

  /// 逐条解析，不因一条记录损坏丢弃整批数据。
  SimHubImportReport decode(
    String source, {
    required String defaultTimeZoneId,
  }) {
    initializeIesimTimeZones();
    final issues = <SimHubImportIssue>[];
    final payload = _decodeRoot(source, issues);
    final rawRecords = payload.records;
    final subscriptions = <Subscription>[];
    final activities = <ActivityRecord>[];
    final ids = <String>{};
    final iccids = <String>{};

    for (var index = 0; index < rawRecords.length; index++) {
      final raw = rawRecords[index];
      if (raw is! Map) {
        issues.add(_issue(index, r'$', '记录必须是 JSON 对象'));
        continue;
      }
      final map = Map<String, dynamic>.from(raw);
      final parsed = _decodeSubscription(map, index, defaultTimeZoneId, issues);
      if (parsed == null) continue;
      if (!ids.add(parsed.id)) {
        issues.add(_issue(index, 'id', 'ID 重复，本条已跳过'));
        continue;
      }
      final iccid = parsed.iccid;
      if (iccid != null && !iccids.add(iccid)) {
        issues.add(_issue(index, 'iccid', 'ICCID 重复，本条已跳过'));
        continue;
      }
      subscriptions.add(parsed);
      activities.addAll(
        _decodeActivities(map['activityRecords'], parsed, index, issues),
      );
    }

    final assets = _decodeAssets(
      payload.root,
      rawRecords,
      subscriptions,
      issues,
      defaultTimeZoneId,
    );
    return SimHubImportReport(
      subscriptions: subscriptions,
      activityRecords: activities,
      issues: issues,
      sourceRecordCount: rawRecords.length,
      assets: assets,
      ignoredServiceCount: payload.root?['services'] is List
          ? (payload.root!['services'] as List).length
          : 0,
      ignoredBindingCount: payload.root?['boundServices'] is List
          ? (payload.root!['boundServices'] as List).length
          : 0,
    );
  }

  /// 导出为 SimHub 可读取的 JSON 数组，同时写入 iesim 扩展字段。
  String encode(
    Iterable<Subscription> subscriptions, {
    Iterable<ActivityRecord> activityRecords = const [],
    bool pretty = true,
  }) {
    initializeIesimTimeZones();
    final activitiesBySubscription = <String, List<ActivityRecord>>{};
    for (final record in activityRecords) {
      (activitiesBySubscription[record.subscriptionId] ??= []).add(record);
    }
    final records = [
      for (final subscription in subscriptions)
        _encodeSubscription(
          subscription,
          activitiesBySubscription[subscription.id] ?? const [],
        ),
    ];
    return (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
        .convert(records);
  }

  /// 导出包含设备关系的 SimHub v5 备份。SimJ 等只接受扁平数组的客户端
  /// 仍应使用 [encode]。
  String encodeV5(
    Iterable<Subscription> subscriptions, {
    required AssetInventory assets,
    Iterable<ActivityRecord> activityRecords = const [],
    bool pretty = true,
  }) {
    initializeIesimTimeZones();
    final activityList = activityRecords.toList(growable: false);
    final activitiesBySubscription = <String, List<ActivityRecord>>{};
    for (final record in activityList) {
      (activitiesBySubscription[record.subscriptionId] ??= []).add(record);
    }
    final records = <Map<String, dynamic>>[];
    for (final subscription in subscriptions) {
      final record = _encodeSubscription(
        subscription,
        activitiesBySubscription[subscription.id] ?? const [],
      );
      record['_iesimDormant'] =
          subscription.lifecycle.stage == ProfileStage.museum ||
          subscription.details.isDormant;
      EsimProfile? profile;
      for (final candidate in assets.profiles) {
        if (candidate.subscriptionId == subscription.id ||
            (subscription.iccid != null &&
                candidate.iccid == subscription.iccid)) {
          profile = candidate;
          break;
        }
      }
      if (profile != null) {
        final eid = assets.eids.where((item) => item.id == profile!.eidId);
        if (eid.isNotEmpty) {
          record['eid'] = eid.single.value;
          final slot = assets.slotHolding(eid.single.cardId);
          if (slot != null) {
            final device = assets.devices.where(
              (item) => item.id == slot.deviceId,
            );
            if (device.isNotEmpty) {
              record['deviceID'] = _externalDeviceId(device.single.id);
            }
          }
        }
      } else {
        SimCard? card;
        for (final candidate in assets.cards) {
          if ((subscription.iccid != null &&
                  candidate.physicalIccid == subscription.iccid) ||
              candidate.id == 'simhub-card:${subscription.id}') {
            card = candidate;
            break;
          }
        }
        if (card != null) {
          final slot = assets.slotHolding(card.id);
          if (slot != null) {
            final device = assets.devices.where(
              (item) => item.id == slot.deviceId,
            );
            if (device.isNotEmpty) {
              record['deviceID'] = _externalDeviceId(device.single.id);
            }
          }
        }
      }
      records.add(record);
    }

    final devices = <Map<String, dynamic>>[];
    for (final device in assets.devices) {
      Euicc? deviceEid;
      SimCard? euiccCard;
      for (final slot in assets.slotsForDevice(device.id)) {
        final card = slot.cardId == null ? null : assets.cardById(slot.cardId!);
        if (card == null) continue;
        final eids = assets.eidsForCard(card.id);
        if (eids.isNotEmpty) {
          deviceEid = eids.first;
          euiccCard = card;
          break;
        }
      }
      devices.add({
        'id': _externalDeviceId(device.id),
        'name': device.name,
        'brand': device.brand ?? '',
        'note': device.note ?? '',
        'deviceTypeRaw': _encodeDeviceKind(device.kind),
        'simCapabilityRaw': _encodeSimCapability(device.simCapability),
        'regionRaw': device.region ?? '',
        'usageRaw': device.usage ?? '',
        'supportsSARoaming': device.supportsSaRoaming,
        'removableESIM': euiccCard is RemovableEuiccCard,
        'eid': deviceEid?.value ?? '',
        'orderIndex': device.orderIndex,
        'createdAt': device.createdAt.toIso8601String(),
        'updatedAt': device.updatedAt.toIso8601String(),
      });
    }
    final dormant = <Map<String, dynamic>>[];
    final active = <Map<String, dynamic>>[];
    for (final record in records) {
      final isDormant = record.remove('_iesimDormant') == true;
      if (isDormant) {
        dormant.add({'card': record});
      } else {
        active.add(record);
      }
    }
    final root = {
      'formatVersion': 5,
      'exportedAt': _nowUtc().toUtc().toIso8601String(),
      'esimCards': active,
      'dormantCards': dormant,
      'devices': devices,
      'services': const <Object>[],
      'boundServices': const <Object>[],
    };
    return (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
        .convert(root);
  }

  _RootPayload _decodeRoot(String source, List<SimHubImportIssue> issues) {
    final dynamic root;
    try {
      root = jsonDecode(source);
    } on FormatException catch (error) {
      issues.add(
        SimHubImportIssue(
          recordIndex: null,
          field: r'$',
          message: 'JSON 格式错误：${error.message}',
        ),
      );
      return const _RootPayload([]);
    }
    if (root is List) return _RootPayload(root);
    if (root is Map) {
      final rootMap = Map<String, dynamic>.from(root);
      final esimCards = root['esimCards'];
      if (esimCards is List) {
        final records = <dynamic>[...esimCards];
        final dormantCards = root['dormantCards'];
        if (dormantCards is List) {
          for (final dormant in dormantCards) {
            if (dormant is Map && dormant['card'] is Map) {
              final card = Map<String, dynamic>.from(dormant['card'] as Map);
              card['_iesimDormant'] = true;
              records.add(card);
            }
          }
        }
        return _RootPayload(records, rootMap);
      }
      final records = root['subscriptions'];
      if (records is List) return _RootPayload(records, rootMap);
      if (_looksLikeRecord(root)) return _RootPayload([root], rootMap);
    }
    issues.add(
      const SimHubImportIssue(
        recordIndex: null,
        field: r'$',
        message: '顶层必须是记录数组、单条记录、SimHub v5 备份或包含 subscriptions 数组的对象',
      ),
    );
    return const _RootPayload([]);
  }

  AssetInventory _decodeAssets(
    Map<String, dynamic>? root,
    List<dynamic> rawRecords,
    List<Subscription> subscriptions,
    List<SimHubImportIssue> issues,
    String defaultTimeZoneId,
  ) {
    if (root == null || root['devices'] is! List) return AssetInventory();
    final devices = <DeviceAsset>[];
    final slots = <SimSlot>[];
    final cards = <SimCard>[];
    final eids = <Euicc>[];
    final profiles = <EsimProfile>[];
    final deviceBySourceId = <String, DeviceAsset>{};
    final eidByValue = <String, Euicc>{};
    final now = _nowUtc().toUtc();

    SimSlot ensureSlot(
      String deviceId, {
      required SimSlotKind preferredKind,
      required String cardId,
    }) {
      for (var index = 0; index < slots.length; index++) {
        final slot = slots[index];
        if (slot.deviceId == deviceId &&
            slot.kind == preferredKind &&
            slot.cardId == null) {
          final occupied = slot.copyWith(cardId: cardId, updatedAt: now);
          slots[index] = occupied;
          return occupied;
        }
      }
      final position = slots.where((slot) => slot.deviceId == deviceId).length;
      final slot = SimSlot(
        id: 'simhub-slot:$deviceId:$position',
        deviceId: deviceId,
        label: preferredKind == SimSlotKind.embeddedEuicc
            ? 'eSIM ${position + 1}'
            : 'SIM ${position + 1}',
        kind: preferredKind,
        position: position,
        cardId: cardId,
        createdAt: now,
        updatedAt: now,
      );
      slots.add(slot);
      return slot;
    }

    final rawDevices = root['devices'] as List;
    for (var index = 0; index < rawDevices.length; index++) {
      final raw = rawDevices[index];
      if (raw is! Map) {
        issues.add(_globalIssue('devices[$index]', '设备记录必须是对象，已忽略'));
        continue;
      }
      final map = Map<String, dynamic>.from(raw);
      final sourceId = _nonEmpty(map['id']);
      final name = _nonEmpty(map['name']);
      if (sourceId == null || name == null) {
        issues.add(_globalIssue('devices[$index]', '缺少设备 ID 或名称，已忽略'));
        continue;
      }
      if (deviceBySourceId.containsKey(sourceId)) {
        issues.add(_globalIssue('devices[$index].id', '设备 ID 重复，已忽略'));
        continue;
      }
      final createdAt =
          _parseAssetDate(
            _nonEmpty(map['createdAt']),
            defaultTimeZoneId,
            'devices[$index].createdAt',
            issues,
          ) ??
          now;
      final updatedAt =
          _parseAssetDate(
            _nonEmpty(map['updatedAt']),
            defaultTimeZoneId,
            'devices[$index].updatedAt',
            issues,
          ) ??
          createdAt;
      final capability = _simCapability(_nonEmpty(map['simCapabilityRaw']));
      final device = DeviceAsset(
        id: 'simhub-device:$sourceId',
        name: name,
        kind: _deviceKind(_nonEmpty(map['deviceTypeRaw'])),
        brand: _nonEmpty(map['brand']),
        note: _nonEmpty(map['note']),
        region: _nonEmpty(map['regionRaw']),
        usage: _nonEmpty(map['usageRaw']),
        simCapability: capability,
        supportsSaRoaming: _boolean(map['supportsSARoaming']) ?? false,
        orderIndex: _int(map['orderIndex']) ?? index,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
      devices.add(device);
      deviceBySourceId[sourceId] = device;
      final specs = _slotSpecs(capability);
      for (var position = 0; position < specs.length; position++) {
        final spec = specs[position];
        slots.add(
          SimSlot(
            id: 'simhub-slot:${device.id}:$position',
            deviceId: device.id,
            label: spec.$1,
            kind: spec.$2,
            position: position,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
        );
      }

      final eidValue = _nonEmpty(map['eid']);
      if (eidValue != null && !eidByValue.containsKey(eidValue)) {
        final removable = _boolean(map['removableESIM']) ?? false;
        final cardId = 'simhub-euicc:${device.id}';
        final card = removable
            ? RemovableEuiccCard(
                id: cardId,
                name: '${device.name} eUICC',
                note: '由 SimHub 设备资料导入',
                createdAt: createdAt,
                updatedAt: updatedAt,
              )
            : EmbeddedEuiccCard(
                id: cardId,
                name: '${device.name} 内置 eUICC',
                note: '由 SimHub 设备资料导入',
                embeddedDeviceId: device.id,
                createdAt: createdAt,
                updatedAt: updatedAt,
              );
        cards.add(card);
        final eid = Euicc(
          id: 'simhub-eid:${device.id}',
          cardId: cardId,
          value: eidValue,
          label: device.name,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );
        eids.add(eid);
        eidByValue[eidValue] = eid;
        ensureSlot(
          device.id,
          preferredKind: removable
              ? SimSlotKind.physical
              : SimSlotKind.embeddedEuicc,
          cardId: cardId,
        );
      }
    }

    final subscriptionById = {
      for (final subscription in subscriptions) subscription.id: subscription,
    };
    for (final raw in rawRecords) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final sourceId = _nonEmpty(map['id']);
      if (sourceId == null) continue;
      final subscription = subscriptionById[sourceId];
      if (subscription == null) continue;
      final eidValue = _nonEmpty(map['eid']);
      final sourceDeviceId = _nonEmpty(map['deviceID']);
      final device = sourceDeviceId == null
          ? null
          : deviceBySourceId[sourceDeviceId];
      Euicc? eid = eidValue == null ? null : eidByValue[eidValue];
      if (eidValue != null && eid == null) {
        final cardId = 'simhub-euicc:${subscription.id}';
        cards.add(
          RemovableEuiccCard(
            id: cardId,
            name: '${subscription.operator ?? '未命名'} eUICC',
            note: '由 SimHub 卡片资料导入',
            createdAt: subscription.createdAt,
            updatedAt: subscription.updatedAt,
          ),
        );
        eid = Euicc(
          id: 'simhub-eid:${subscription.id}',
          cardId: cardId,
          value: eidValue,
          label: subscription.operator,
          createdAt: subscription.createdAt,
          updatedAt: subscription.updatedAt,
        );
        eids.add(eid);
        eidByValue[eidValue] = eid;
        if (device != null) {
          ensureSlot(
            device.id,
            preferredKind: SimSlotKind.physical,
            cardId: cardId,
          );
        }
      }
      if (eid != null) {
        profiles.add(
          EsimProfile(
            id: 'simhub-profile:${subscription.id}',
            eidId: eid.id,
            iccid: subscription.iccid,
            operatorName: subscription.operator,
            nickname: _nonEmpty(map['plan']),
            subscriptionId: subscription.id,
            isPinned: subscription.details.isPinned,
            createdAt: subscription.createdAt,
            updatedAt: subscription.updatedAt,
          ),
        );
        continue;
      }
      if (device == null) continue;
      final cardId = 'simhub-card:${subscription.id}';
      final card = subscription.iccid == null
          ? RemovableEuiccCard(
              id: cardId,
              name: subscription.operator ?? '未命名卡片',
              note: 'SimHub 未提供 EID / ICCID',
              createdAt: subscription.createdAt,
              updatedAt: subscription.updatedAt,
            )
          : PhysicalSimCard(
              id: cardId,
              name: subscription.operator ?? '实体 SIM',
              physicalIccid: subscription.iccid!,
              createdAt: subscription.createdAt,
              updatedAt: subscription.updatedAt,
            );
      cards.add(card);
      ensureSlot(
        device.id,
        preferredKind: SimSlotKind.physical,
        cardId: cardId,
      );
    }

    return AssetInventory(
      devices: devices,
      slots: slots,
      cards: cards,
      eids: eids,
      profiles: profiles,
    );
  }

  Subscription? _decodeSubscription(
    Map<String, dynamic> map,
    int index,
    String defaultTimeZoneId,
    List<SimHubImportIssue> issues,
  ) {
    final activation = _decodeActivation(map, index, issues);
    final phoneText = _string(map['phoneNumber']) ?? _string(map['number']);
    final PhoneNumber phone;
    if (phoneText == null || phoneText.trim().isEmpty) {
      if (activation == null) {
        issues.add(_issue(index, 'phoneNumber', '缺少号码和 LPA 凭据，本条已跳过'));
        return null;
      }
      phone = const PhoneNumber.unknown();
    } else {
      try {
        phone = PhoneNumber(phoneText);
      } on ArgumentError {
        issues.add(_issue(index, 'phoneNumber', '号码格式无效，本条已跳过'));
        return null;
      }
    }

    final timeZoneId = _nonEmpty(map['timeZoneId']) ?? defaultTimeZoneId.trim();
    try {
      ZonedCalendar(timeZoneId);
    } on ArgumentError {
      issues.add(_issue(index, 'timeZoneId', '未知时区，本条已跳过'));
      return null;
    }

    final now = _nowUtc().toUtc();
    final createdRaw = _nonEmpty(map['createdAt']);
    final createdAt =
        _parseDate(createdRaw, timeZoneId, index, 'createdAt', issues) ?? now;
    final updatedAt =
        _parseDate(
          _nonEmpty(map['updatedAt']),
          timeZoneId,
          index,
          'updatedAt',
          issues,
        ) ??
        createdAt;
    final expiryDate = _parseDate(
      _nonEmpty(map['expiryDate']),
      timeZoneId,
      index,
      'expiryDate',
      issues,
    );
    final isLongTerm = _boolean(map['isLongTerm']) ?? false;
    final billingType =
        _nonEmpty(map['cardType']) ?? _nonEmpty(map['billingType']);
    final planDays = _positiveInt(map['renewDays'], index, 'renewDays', issues);
    final keepAliveDays =
        _positiveInt(
          map['keepAliveCycleDays'],
          index,
          'keepAliveCycleDays',
          issues,
        ) ??
        planDays;
    final keepAliveRequired =
        _boolean(map['keepAliveRequired']) ??
        (billingType == null
            ? !isLongTerm
            : billingType.toLowerCase() == 'prepaid');
    final lastActivity = _parseDate(
      _nonEmpty(map['lastActivityAt']),
      timeZoneId,
      index,
      'lastActivityAt',
      issues,
    );
    final confidenceText = _nonEmpty(map['activityConfidence']);
    final confidence = confidenceText == DataConfidence.inferred.name
        ? DataConfidence.inferred
        : DataConfidence.confirmed;
    var keepAlivePolicy = KeepAlivePolicy();
    if (map['keepAlivePolicy'] is Map) {
      try {
        keepAlivePolicy = KeepAlivePolicy.fromJson(
          Map<String, dynamic>.from(map['keepAlivePolicy'] as Map),
        );
      } on FormatException catch (error) {
        issues.add(
          _issue(index, 'keepAlivePolicy', '${error.message}，已使用默认规则'),
        );
      }
    }

    final KeepAlive keepAlive;
    if (!keepAliveRequired) {
      keepAlive = KeepAlive.notRequired();
    } else if (lastActivity != null) {
      keepAlive = KeepAlive(
        required: true,
        cycleDays: keepAliveDays,
        lastActivityAt: lastActivity,
        confidence: confidence,
        policy: keepAlivePolicy,
      );
    } else if (createdRaw != null && keepAliveDays != null) {
      keepAlive = KeepAlive.inferredFrom(
        createdAt,
        keepAliveDays,
        policy: keepAlivePolicy,
      );
    } else {
      keepAlive = KeepAlive(
        required: true,
        cycleDays: keepAliveDays,
        confidence: DataConfidence.confirmed,
        policy: keepAlivePolicy,
      );
    }

    final cyclePrice = _decodeMoney(map, index, issues);
    final tags = _decodeTags(map['tags'], index, issues);
    final id = _nonEmpty(map['id']) ?? _idFactory();
    final lifecycle = _decodeProfileLifecycle(
      map,
      index,
      issues,
      timeZoneId,
      updatedAt,
    );
    return Subscription(
      id: id,
      iccid: _nonEmpty(map['iccid']),
      number: phone,
      operator: _nonEmpty(map['carrier']) ?? _nonEmpty(map['operator']),
      lifecycle: lifecycle,
      activation: activation,
      plan: Plan(
        name: _nonEmpty(map['plan']),
        cyclePrice: cyclePrice,
        cycleDays: planDays,
        expiryDate: expiryDate,
        isLongTerm: isLongTerm,
      ),
      keepAlive: keepAlive,
      tags: tags,
      appearance: Appearance(
        flag: _nonEmpty(map['flag']),
        cardColorHex: _nonEmpty(map['cardColorHex']),
        cardBackgroundAssetName: _nonEmpty(map['cardBackgroundAssetName']),
        websiteURL: _nonEmpty(map['websiteURL']),
        customPrompt: _nonEmpty(map['customPrompt']),
      ),
      details: SubscriptionDetails(
        profileName: _nonEmpty(map['_iesimProfileName']),
        profileClassCode: _int(map['_iesimProfileClassCode']),
        declaredProfileSizeBytes: _int(map['_iesimDeclaredProfileSizeBytes']),
        installedProfileSizeBytes: _int(map['_iesimInstalledProfileSizeBytes']),
        gid1: _nonEmpty(map['_iesimGid1']),
        gid2: _nonEmpty(map['_iesimGid2']),
        countryCode: _nonEmpty(map['countryCode']),
        countryName: _nonEmpty(map['countryName']),
        mcc: _nonEmpty(map['mcc']),
        mnc: _nonEmpty(map['mnc']),
        apn: _nonEmpty(map['apn']),
        secondaryPhoneNumber: _nonEmpty(map['secondaryPhoneNumber']),
        secondaryPhoneNumberEnabled:
            _boolean(map['secondaryPhoneNumberEnabled']) ?? false,
        activationDate: _parseDate(
          _nonEmpty(map['activationDate']),
          timeZoneId,
          index,
          'activationDate',
          issues,
        ),
        currentBalance: _decodeCurrentBalance(map, index, issues),
        affiliateOffers: _decodeAffiliateOffers(
          map['_iesimAffiliateOffers'],
          index,
          issues,
        ),
        autoTopUpEnabled: _boolean(map['autoTopUpEnabled']) ?? false,
        topUpCycleUnit: _nonEmpty(map['topUpCycleUnit']),
        renewalIntervalValue: _positiveInt(
          map['renewalIntervalValue'],
          index,
          'renewalIntervalValue',
          issues,
        ),
        renewalUnit: _nonEmpty(map['renewalUnit']),
        transactionNotes: _nonEmpty(map['transactionNotes']),
        carrierAppName: _nonEmpty(map['carrierAppName']),
        carrierAppStoreUrl: _nonEmpty(map['carrierAppStoreURLString']),
        carrierAppIconUrl: _nonEmpty(map['carrierAppIconURLString']),
        keepAliveModeRaw: _nonEmpty(map['keepAliveModeRaw']),
        orderIndex: _int(map['orderIndex']) ?? 0,
        isDormant: _boolean(map['_iesimDormant']) ?? false,
        isPinned: _boolean(map['_iesimPinned']) ?? false,
      ),
      timeZoneId: timeZoneId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  List<ActivityRecord> _decodeActivities(
    dynamic raw,
    Subscription subscription,
    int subscriptionIndex,
    List<SimHubImportIssue> issues,
  ) {
    if (raw == null) return const [];
    if (raw is! List) {
      issues.add(_issue(subscriptionIndex, 'activityRecords', '必须是数组，已忽略'));
      return const [];
    }
    final result = <ActivityRecord>[];
    for (var activityIndex = 0; activityIndex < raw.length; activityIndex++) {
      final item = raw[activityIndex];
      final field = 'activityRecords[$activityIndex]';
      if (item is! Map) {
        issues.add(_issue(subscriptionIndex, field, '必须是对象，已忽略'));
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final type = _activityType(_nonEmpty(map['type']));
      if (type == null) {
        issues.add(_issue(subscriptionIndex, '$field.type', '动作类型无效，已忽略'));
        continue;
      }
      final occurredAt = _parseDate(
        _nonEmpty(map['occurredAt']),
        subscription.timeZoneId,
        subscriptionIndex,
        '$field.occurredAt',
        issues,
      );
      if (occurredAt == null) {
        issues.add(_issue(subscriptionIndex, field, '缺少有效发生时间，已忽略'));
        continue;
      }
      final updatedAt =
          _parseDate(
            _nonEmpty(map['updatedAt']),
            subscription.timeZoneId,
            subscriptionIndex,
            '$field.updatedAt',
            issues,
          ) ??
          occurredAt;
      final minor = _int(map['amountMinorUnits']);
      final currency = _nonEmpty(map['amountCurrency']);
      final balanceAfterMinor = _int(map['balanceAfterMinorUnits']);
      final balanceAfterCurrency = _nonEmpty(map['balanceAfterCurrency']);
      result.add(
        ActivityRecord(
          id: _nonEmpty(map['id']) ?? _idFactory(),
          subscriptionId: subscription.id,
          type: type,
          occurredAt: occurredAt,
          updatedAt: updatedAt,
          amount: minor == null || currency == null
              ? null
              : Money(minorUnits: minor, currencyCode: currency.toUpperCase()),
          balanceAfter:
              balanceAfterMinor == null || balanceAfterCurrency == null
              ? null
              : Money(
                  minorUnits: balanceAfterMinor,
                  currencyCode: balanceAfterCurrency.toUpperCase(),
                ),
          note: _nonEmpty(map['note']),
        ),
      );
    }
    return result;
  }

  Map<String, dynamic> _encodeSubscription(
    Subscription subscription,
    List<ActivityRecord> activities,
  ) {
    final plan = subscription.plan;
    final keepAlive = subscription.keepAlive;
    return {
      'id': subscription.id,
      'phoneNumber': subscription.number.value,
      'carrier': subscription.operator,
      '_iesimProfileStage': subscription.lifecycle.stage.name,
      '_iesimProfileDeviceState': subscription.lifecycle.deviceState.name,
      '_iesimActivationDeadline': subscription.lifecycle.activationDeadline
          ?.toIso8601String(),
      '_iesimActivationRequirements':
          subscription.lifecycle.activationRequirements,
      '_iesimServiceExpiresAt': subscription.lifecycle.serviceExpiresAt
          ?.toIso8601String(),
      '_iesimActivatedAt': subscription.lifecycle.activatedAt
          ?.toIso8601String(),
      '_iesimArchivedAt': subscription.lifecycle.archivedAt?.toIso8601String(),
      '_iesimArchiveReason': subscription.lifecycle.archiveReason?.name,
      '_iesimProfileName': subscription.details.profileName,
      '_iesimPinned': subscription.details.isPinned,
      '_iesimProfileClassCode': subscription.details.profileClassCode,
      '_iesimDeclaredProfileSizeBytes':
          subscription.details.declaredProfileSizeBytes,
      '_iesimInstalledProfileSizeBytes':
          subscription.details.installedProfileSizeBytes,
      '_iesimGid1': subscription.details.gid1,
      '_iesimGid2': subscription.details.gid2,
      'countryCode': subscription.details.countryCode,
      'countryName': subscription.details.countryName,
      'mcc': subscription.details.mcc,
      'mnc': subscription.details.mnc,
      'apn': subscription.details.apn,
      'secondaryPhoneNumber': subscription.details.secondaryPhoneNumber,
      'secondaryPhoneNumberEnabled':
          subscription.details.secondaryPhoneNumberEnabled,
      'activationDate': subscription.details.activationDate == null
          ? null
          : _zonedDate(
              subscription.details.activationDate!,
              subscription.timeZoneId,
            ),
      'smdpAddress': subscription.activation?.smdpAddress,
      'activationCode': subscription.activation?.matchingId,
      'activationExtra': subscription.activation?.extra,
      'confirmationCode': subscription.activation?.confirmationCode,
      'flag': subscription.appearance.flag,
      'expiryDate': plan.expiryDate == null
          ? null
          : _zonedDate(plan.expiryDate!, subscription.timeZoneId),
      'createdAt': _zonedDate(subscription.createdAt, subscription.timeZoneId),
      'plan': plan.name,
      'cyclePaymentMinorUnits': plan.cyclePrice?.minorUnits,
      'price': _moneyText(plan.cyclePrice),
      'currencyCode':
          plan.cyclePrice?.currencyCode ??
          subscription.details.currentBalance?.currencyCode,
      'currentBalanceMinorUnits':
          subscription.details.currentBalance?.minorUnits,
      'currentBalance': _moneyText(subscription.details.currentBalance),
      '_iesimAffiliateOffers': subscription.details.affiliateOffers
          .map((offer) => offer.toJson())
          .toList(),
      'autoTopUpEnabled': subscription.details.autoTopUpEnabled,
      'topUpCycleUnit': subscription.details.topUpCycleUnit,
      'renewalIntervalValue': subscription.details.renewalIntervalValue,
      'renewalUnit': subscription.details.renewalUnit,
      'renewDays': plan.cycleDays,
      'isLongTerm': plan.isLongTerm,
      'tags': subscription.tags,
      'cardType': keepAlive.required ? 'prepaid' : 'subscription',
      'cardColorHex': subscription.appearance.cardColorHex,
      'cardBackgroundAssetName':
          subscription.appearance.cardBackgroundAssetName,
      'websiteURL': subscription.appearance.websiteURL,
      'customPrompt': subscription.appearance.customPrompt,
      'transactionNotes': subscription.details.transactionNotes,
      'carrierAppName': subscription.details.carrierAppName,
      'carrierAppStoreURLString': subscription.details.carrierAppStoreUrl,
      'carrierAppIconURLString': subscription.details.carrierAppIconUrl,
      'keepAliveModeRaw': subscription.details.keepAliveModeRaw,
      'orderIndex': subscription.details.orderIndex,
      'iccid': subscription.iccid,
      'lastActivityAt': keepAlive.lastActivityAt?.toIso8601String(),
      'activityConfidence': keepAlive.confidence.name,
      'keepAliveRequired': keepAlive.required,
      'keepAliveCycleDays': keepAlive.cycleDays,
      'keepAlivePolicy': keepAlive.policy.toJson(),
      'timeZoneId': subscription.timeZoneId,
      'updatedAt': subscription.updatedAt.toIso8601String(),
      'activityRecords': [
        for (final record in activities)
          {
            'id': record.id,
            'type': record.type.name,
            'occurredAt': record.occurredAt.toIso8601String(),
            'updatedAt': record.updatedAt.toIso8601String(),
            'amountMinorUnits': record.amount?.minorUnits,
            'amountCurrency': record.amount?.currencyCode,
            'balanceAfterMinorUnits': record.balanceAfter?.minorUnits,
            'balanceAfterCurrency': record.balanceAfter?.currencyCode,
            'note': record.note,
          },
      ],
    };
  }

  Money? _decodeMoney(
    Map<String, dynamic> map,
    int index,
    List<SimHubImportIssue> issues,
  ) {
    final minor =
        _int(map['cyclePaymentMinorUnits']) ?? _decimalMinor(map['price']);
    if (minor == null) return null;
    final currency = _nonEmpty(map['currencyCode']);
    if (currency == null || currency.length != 3) {
      issues.add(_issue(index, 'currencyCode', '金额存在但币种无效，金额已忽略'));
      return null;
    }
    return Money(minorUnits: minor, currencyCode: currency.toUpperCase());
  }

  Money? _decodeCurrentBalance(
    Map<String, dynamic> map,
    int index,
    List<SimHubImportIssue> issues,
  ) {
    final minor =
        _int(map['currentBalanceMinorUnits']) ??
        _decimalMinor(map['currentBalance']);
    if (minor == null) return null;
    final currency = _nonEmpty(map['currencyCode']);
    if (currency == null || currency.length != 3) {
      issues.add(_issue(index, 'currencyCode', '余额存在但币种无效，余额已忽略'));
      return null;
    }
    return Money(minorUnits: minor, currencyCode: currency.toUpperCase());
  }

  static int? _decimalMinor(dynamic value) {
    if (value == null) return null;
    final source = switch (value) {
      num() => value.toString(),
      String() => value.trim().replaceAll(',', '.'),
      _ => '',
    };
    final match = RegExp(r'^(-?)(\d+)(?:\.(\d+))?$').firstMatch(source);
    if (match == null) return null;
    final sign = match.group(1) == '-' ? -1 : 1;
    final whole = int.parse(match.group(2)!);
    final decimal = (match.group(3) ?? '').padRight(2, '0');
    return sign * (whole * 100 + int.parse(decimal.substring(0, 2)));
  }

  static String? _moneyText(Money? value) {
    if (value == null) return null;
    final negative = value.minorUnits < 0 ? '-' : '';
    final absolute = value.minorUnits.abs();
    return '$negative${absolute ~/ 100}.'
        '${(absolute % 100).toString().padLeft(2, '0')}';
  }

  List<String> _decodeTags(
    dynamic raw,
    int index,
    List<SimHubImportIssue> issues,
  ) {
    if (raw == null) return const [];
    if (raw is String) {
      return raw
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false);
    }
    if (raw is! List) {
      issues.add(_issue(index, 'tags', '必须是字符串数组，已忽略'));
      return const [];
    }
    final tags = <String>[];
    for (final value in raw) {
      if (value is String && value.trim().isNotEmpty) {
        tags.add(value.trim());
      } else {
        issues.add(_issue(index, 'tags', '已忽略非字符串标签'));
      }
    }
    return tags;
  }

  List<AffiliateOffer> _decodeAffiliateOffers(
    dynamic raw,
    int index,
    List<SimHubImportIssue> issues,
  ) {
    if (raw == null) return const [];
    if (raw is! List) {
      issues.add(_issue(index, '_iesimAffiliateOffers', '必须是数组，已忽略'));
      return const [];
    }
    final offers = <AffiliateOffer>[];
    for (var offerIndex = 0; offerIndex < raw.length; offerIndex++) {
      try {
        offers.add(
          AffiliateOffer.fromJson(
            Map<String, dynamic>.from(raw[offerIndex] as Map),
          ),
        );
      } catch (_) {
        issues.add(
          _issue(index, '_iesimAffiliateOffers[$offerIndex]', '推荐项目格式无效，已忽略'),
        );
      }
    }
    return offers;
  }

  LpaActivation? _decodeActivation(
    Map<String, dynamic> map,
    int index,
    List<SimHubImportIssue> issues,
  ) {
    final smdp = _nonEmpty(map['smdpAddress']);
    final code = _nonEmpty(map['activationCode']);
    if (smdp == null && code == null) return null;

    if (code != null &&
        (code.toUpperCase().startsWith('LPA:') || code.startsWith(r'1$'))) {
      try {
        final parsed = LpaActivation.parse(code);
        if (smdp != null && parsed.smdpAddress != smdp.toLowerCase()) {
          issues.add(_issue(index, 'smdpAddress', '与 LPA 激活码不一致，已采用 LPA 内地址'));
        }
        return LpaActivation(
          smdpAddress: parsed.smdpAddress,
          matchingId: parsed.matchingId,
          extra: parsed.extra,
          confirmationCode: _nonEmpty(map['confirmationCode']),
        );
      } on FormatException {
        issues.add(_issue(index, 'activationCode', 'LPA 激活码无效，已忽略'));
        return null;
      } on ArgumentError {
        issues.add(_issue(index, 'activationCode', 'LPA 激活码无效，已忽略'));
        return null;
      }
    }

    if (smdp == null || code == null) {
      issues.add(_issue(index, 'activationCode', 'SM-DP+ 与激活码必须同时存在，已忽略'));
      return null;
    }
    try {
      return LpaActivation(
        smdpAddress: smdp,
        matchingId: code,
        extra: _nonEmpty(map['activationExtra']),
        confirmationCode: _nonEmpty(map['confirmationCode']),
      );
    } on ArgumentError {
      issues.add(_issue(index, 'activationCode', 'eSIM 激活字段无效，已忽略'));
      return null;
    }
  }

  ProfileLifecycle _decodeProfileLifecycle(
    Map<String, dynamic> map,
    int index,
    List<SimHubImportIssue> issues,
    String timeZoneId,
    DateTime updatedAt,
  ) {
    final stageRaw = _nonEmpty(map['_iesimProfileStage']);
    ProfileStage stage;
    if (stageRaw == null) {
      stage = _boolean(map['_iesimDormant']) == true
          ? ProfileStage.museum
          : ProfileStage.active;
    } else {
      try {
        stage = ProfileStage.values.byName(stageRaw);
      } on ArgumentError {
        issues.add(_issue(index, '_iesimProfileStage', '生命周期无效，已按已激活导入'));
        stage = ProfileStage.active;
      }
    }

    final deviceStateRaw = _nonEmpty(map['_iesimProfileDeviceState']);
    var deviceState = ProfileDeviceState.unknown;
    if (deviceStateRaw != null) {
      try {
        deviceState = ProfileDeviceState.values.byName(deviceStateRaw);
      } on ArgumentError {
        issues.add(_issue(index, '_iesimProfileDeviceState', '设备状态无效，已按未知导入'));
      }
    }

    final reasonRaw = _nonEmpty(map['_iesimArchiveReason']);
    ProfileArchiveReason? reason;
    if (reasonRaw != null) {
      try {
        reason = ProfileArchiveReason.values.byName(reasonRaw);
      } on ArgumentError {
        issues.add(_issue(index, '_iesimArchiveReason', '归档原因无效，已按导入归档处理'));
      }
    }
    if (stage == ProfileStage.museum) {
      reason ??= ProfileArchiveReason.imported;
    }

    return ProfileLifecycle(
      stage: stage,
      deviceState: deviceState,
      activationDeadline: _parseDate(
        _nonEmpty(map['_iesimActivationDeadline']),
        timeZoneId,
        index,
        '_iesimActivationDeadline',
        issues,
      ),
      activationRequirements: _nonEmpty(map['_iesimActivationRequirements']),
      serviceExpiresAt: _parseDate(
        _nonEmpty(map['_iesimServiceExpiresAt']),
        timeZoneId,
        index,
        '_iesimServiceExpiresAt',
        issues,
      ),
      activatedAt: _parseDate(
        _nonEmpty(map['_iesimActivatedAt']),
        timeZoneId,
        index,
        '_iesimActivatedAt',
        issues,
      ),
      archivedAt:
          _parseDate(
            _nonEmpty(map['_iesimArchivedAt']),
            timeZoneId,
            index,
            '_iesimArchivedAt',
            issues,
          ) ??
          (stage == ProfileStage.museum ? updatedAt : null),
      archiveReason: reason,
    );
  }

  DateTime? _parseDate(
    String? source,
    String timeZoneId,
    int index,
    String field,
    List<SimHubImportIssue> issues,
  ) {
    if (source == null) return null;
    try {
      final dateMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(source);
      if (dateMatch == null) throw const FormatException();
      final sourceYear = int.parse(dateMatch.group(1)!);
      final sourceMonth = int.parse(dateMatch.group(2)!);
      final sourceDay = int.parse(dateMatch.group(3)!);
      final checkedDate = DateTime.utc(sourceYear, sourceMonth, sourceDay);
      if (checkedDate.year != sourceYear ||
          checkedDate.month != sourceMonth ||
          checkedDate.day != sourceDay) {
        throw const FormatException();
      }
      final hasOffset = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(source);
      if (hasOffset) return DateTime.parse(source).toUtc();
      final parsed = DateTime.parse(source);
      return ZonedCalendar(timeZoneId).utcFromParts(
        year: parsed.year,
        month: parsed.month,
        day: parsed.day,
        hour: parsed.hour,
        minute: parsed.minute,
      );
    } on FormatException {
      issues.add(_issue(index, field, '日期格式无效，该字段已留空'));
      return null;
    }
  }

  static String _zonedDate(DateTime utc, String timeZoneId) {
    final moment = ZonedCalendar(timeZoneId).momentAt(utc);
    return '${moment.year.toString().padLeft(4, '0')}-'
        '${moment.month.toString().padLeft(2, '0')}-'
        '${moment.day.toString().padLeft(2, '0')}';
  }

  static bool _looksLikeRecord(Map<dynamic, dynamic> value) =>
      value.containsKey('phoneNumber') ||
      value.containsKey('number') ||
      value.containsKey('smdpAddress') ||
      value.containsKey('activationCode');

  static String? _string(dynamic value) => value is String ? value : null;

  static String? _nonEmpty(dynamic value) {
    final string = _string(value)?.trim();
    return string == null || string.isEmpty ? null : string;
  }

  static int? _int(dynamic value) => switch (value) {
    int() => value,
    String() => int.tryParse(value.trim()),
    _ => null,
  };

  static int? _positiveInt(
    dynamic value,
    int index,
    String field,
    List<SimHubImportIssue> issues,
  ) {
    if (value == null) return null;
    final parsed = _int(value);
    if (parsed == null || parsed <= 0) {
      issues.add(_issue(index, field, '必须是正整数，该字段已留空'));
      return null;
    }
    return parsed;
  }

  static bool? _boolean(dynamic value) => switch (value) {
    bool() => value,
    int() => value != 0,
    String() when value.toLowerCase() == 'true' => true,
    String() when value.toLowerCase() == 'false' => false,
    _ => null,
  };

  static ActivityType? _activityType(String? value) => switch (value
      ?.toLowerCase()) {
    'topup' || 'top_up' || 'recharge' => ActivityType.topUp,
    'call' => ActivityType.call,
    'sms' || 'message' => ActivityType.sms,
    'renewal' || 'renew' => ActivityType.renewal,
    'mobiledata' || 'mobile_data' || 'data' => ActivityType.mobileData,
    'planpurchase' || 'plan_purchase' || 'bundle' => ActivityType.planPurchase,
    'balancechange' || 'balance_change' => ActivityType.balanceChange,
    'other' => ActivityType.other,
    _ => null,
  };

  static DeviceKind _deviceKind(String? value) =>
      switch (value?.toLowerCase()) {
        'phone' => DeviceKind.phone,
        'mifi' || 'mobilerouter' || 'mobile_router' => DeviceKind.mobileRouter,
        'tablet' => DeviceKind.tablet,
        'watch' => DeviceKind.watch,
        'laptop' => DeviceKind.laptop,
        'esimwriter' || 'esim_writer' => DeviceKind.esimWriter,
        _ => DeviceKind.other,
      };

  static String _encodeDeviceKind(DeviceKind value) => switch (value) {
    DeviceKind.phone => 'phone',
    DeviceKind.mobileRouter => 'mifi',
    DeviceKind.tablet => 'tablet',
    DeviceKind.watch => 'watch',
    DeviceKind.laptop => 'laptop',
    DeviceKind.esimWriter => 'esimWriter',
    DeviceKind.other => 'other',
  };

  static SimCapability _simCapability(String? value) =>
      switch (value?.toLowerCase()) {
        'physicalonly' || 'physical_only' => SimCapability.physicalOnly,
        'esimonly' || 'esim_only' => SimCapability.esimOnly,
        'physicalplusesim' ||
        'physical_plus_esim' => SimCapability.physicalPlusEsim,
        'dualphysical' || 'dual_physical' => SimCapability.dualPhysical,
        'multiesim' || 'multi_esim' => SimCapability.multiEsim,
        _ => SimCapability.unknown,
      };

  static String _encodeSimCapability(SimCapability value) => switch (value) {
    SimCapability.physicalOnly => 'physicalOnly',
    SimCapability.esimOnly => 'esimOnly',
    SimCapability.physicalPlusEsim => 'physicalPlusESIM',
    SimCapability.dualPhysical => 'dualPhysical',
    SimCapability.multiEsim => 'multiESIM',
    SimCapability.unknown => 'unknown',
  };

  static String _externalDeviceId(String id) => id.startsWith('simhub-device:')
      ? id.substring('simhub-device:'.length)
      : id;

  static List<(String, SimSlotKind)> _slotSpecs(SimCapability capability) =>
      switch (capability) {
        SimCapability.physicalOnly => const [('SIM 1', SimSlotKind.physical)],
        SimCapability.esimOnly => const [
          ('内置 eSIM', SimSlotKind.embeddedEuicc),
        ],
        SimCapability.physicalPlusEsim => const [
          ('SIM 1', SimSlotKind.physical),
          ('内置 eSIM', SimSlotKind.embeddedEuicc),
        ],
        SimCapability.dualPhysical => const [
          ('SIM 1', SimSlotKind.physical),
          ('SIM 2', SimSlotKind.physical),
        ],
        SimCapability.multiEsim => const [('eSIM', SimSlotKind.embeddedEuicc)],
        SimCapability.unknown => const [],
      };

  DateTime? _parseAssetDate(
    String? source,
    String timeZoneId,
    String field,
    List<SimHubImportIssue> issues,
  ) {
    if (source == null) return null;
    try {
      final parsed = DateTime.parse(source);
      final hasOffset = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(source);
      if (hasOffset) return parsed.toUtc();
      return ZonedCalendar(timeZoneId).utcFromParts(
        year: parsed.year,
        month: parsed.month,
        day: parsed.day,
        hour: parsed.hour,
        minute: parsed.minute,
      );
    } on FormatException {
      issues.add(_globalIssue(field, '日期格式无效，已使用导入时间'));
      return null;
    }
  }

  static SimHubImportIssue _globalIssue(String field, String message) =>
      SimHubImportIssue(recordIndex: null, field: field, message: message);

  static SimHubImportIssue _issue(
    int zeroBasedIndex,
    String field,
    String message,
  ) => SimHubImportIssue(
    recordIndex: zeroBasedIndex + 1,
    field: field,
    message: message,
  );

  static DateTime _systemNowUtc() => DateTime.now().toUtc();

  static int _fallbackCounter = 0;
  static String _fallbackId() =>
      'import-${DateTime.now().microsecondsSinceEpoch}-${_fallbackCounter++}';
}

class _RootPayload {
  const _RootPayload(this.records, [this.root]);

  final List<dynamic> records;
  final Map<String, dynamic>? root;
}
