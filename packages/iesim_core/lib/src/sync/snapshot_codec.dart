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
import '../interop/lpa_activation.dart';
import '../result.dart';
import '../value/money.dart';
import '../value/phone_number.dart';
import 'sync_snapshot.dart';

class SyncSnapshotCodec {
  const SyncSnapshotCodec();

  String encode(
    SyncSnapshot snapshot,
  ) => const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': snapshot.schemaVersion,
    'generatedAt': snapshot.generatedAtUtc.toIso8601String(),
    'subscriptions': snapshot.subscriptions.map(_encodeSubscription).toList(),
    'activityRecords': snapshot.activityRecords.map(_encodeActivity).toList(),
    'assets': {
      'devices': snapshot.assets.devices.map(_encodeDevice).toList(),
      'slots': snapshot.assets.slots.map(_encodeSlot).toList(),
      'cards': snapshot.assets.cards.map(_encodeCard).toList(),
      'eids': snapshot.assets.eids.map(_encodeEid).toList(),
      'profiles': snapshot.assets.profiles.map(_encodeProfile).toList(),
      'events': snapshot.assets.events.map(_encodeAssetEvent).toList(),
    },
    'tombstones': snapshot.tombstones
        .map(
          (tombstone) => {
            'entityType': tombstone.entityType.name,
            'id': tombstone.entityId,
            'deletedAt': tombstone.deletedAtUtc.toIso8601String(),
          },
        )
        .toList(),
  });

  Result<SyncSnapshot> decode(String source) {
    try {
      final root = jsonDecode(source);
      if (root is! Map<String, dynamic>) {
        throw const FormatException('快照顶层必须是 JSON 对象');
      }
      final version = _requiredInt(root, 'schemaVersion');
      if (version != SyncSnapshot.currentSchemaVersion) {
        return Err(SchemaError('远端快照是开发期旧格式 v$version；当前只接受新基线 v1'));
      }
      final subscriptions = _list(root, 'subscriptions')
          .map((value) => _decodeSubscription(_map(value, 'subscription')))
          .toList();
      final activities = _list(
        root,
        'activityRecords',
      ).map((value) => _decodeActivity(_map(value, 'activityRecord'))).toList();
      final assets = _decodeAssets(_requiredMap(root, 'assets'));
      final tombstones = _list(
        root,
        'tombstones',
      ).map((value) => _decodeTombstone(_map(value, 'tombstone'))).toList();
      _requireUnique(subscriptions.map((item) => item.id), '订阅 id');
      _requireUnique(activities.map((item) => item.id), '动作记录 id');
      _requireUnique(assets.devices.map((item) => item.id), '设备 id');
      _requireUnique(assets.slots.map((item) => item.id), '卡槽 id');
      _requireUnique(assets.cards.map((item) => item.id), '卡片 id');
      _requireUnique(assets.eids.map((item) => item.id), 'EID id');
      _requireUnique(assets.profiles.map((item) => item.id), 'Profile id');
      _requireUnique(assets.events.map((item) => item.id), '资产事件 id');
      _requireUnique(
        tombstones.map((item) => '${item.entityType.name}:${item.entityId}'),
        '墓碑 id',
      );
      return Ok(
        SyncSnapshot(
          schemaVersion: version,
          generatedAtUtc: _requiredUtc(root, 'generatedAt'),
          subscriptions: subscriptions,
          activityRecords: activities,
          assets: assets,
          tombstones: tombstones,
        ),
      );
    } on FormatException catch (error) {
      return Err(SchemaError(error.message));
    } on ArgumentError catch (error) {
      return Err(SchemaError(error.message?.toString() ?? error.toString()));
    } catch (error) {
      return Err(SchemaError('快照无法解析：$error'));
    }
  }

  static Map<String, Object?> _encodeSubscription(Subscription item) => {
    'id': item.id,
    'iccid': item.iccid,
    'number': item.number.value,
    'operator': item.operator,
    'lifecycle': {
      'stage': item.lifecycle.stage.name,
      'deviceState': item.lifecycle.deviceState.name,
      'activationDeadline': item.lifecycle.activationDeadline
          ?.toIso8601String(),
      'activationRequirements': item.lifecycle.activationRequirements,
      'serviceExpiresAt': item.lifecycle.serviceExpiresAt?.toIso8601String(),
      'activatedAt': item.lifecycle.activatedAt?.toIso8601String(),
      'archivedAt': item.lifecycle.archivedAt?.toIso8601String(),
      'archiveReason': item.lifecycle.archiveReason?.name,
    },
    'activation': item.activation == null
        ? null
        : {
            'smdpAddress': item.activation!.smdpAddress,
            'matchingId': item.activation!.matchingId,
            'extra': item.activation!.extra,
            'confirmationCode': item.activation!.confirmationCode,
          },
    'plan': {
      'name': item.plan.name,
      'cyclePrice': _encodeMoney(item.plan.cyclePrice),
      'cycleDays': item.plan.cycleDays,
      'startDate': item.plan.startDate?.toIso8601String(),
      'expiryDate': item.plan.expiryDate?.toIso8601String(),
      'isLongTerm': item.plan.isLongTerm,
    },
    'keepAlive': {
      'required': item.keepAlive.required,
      'cycleDays': item.keepAlive.cycleDays,
      'lastActivityAt': item.keepAlive.lastActivityAt?.toIso8601String(),
      'confidence': item.keepAlive.confidence.name,
      'policy': item.keepAlive.policy.toJson(),
    },
    'tags': item.tags,
    'appearance': {
      'flag': item.appearance.flag,
      'cardColorHex': item.appearance.cardColorHex,
      'cardBackgroundAssetName': item.appearance.cardBackgroundAssetName,
      'websiteURL': item.appearance.websiteURL,
      'customPrompt': item.appearance.customPrompt,
    },
    'details': {
      'profileName': item.details.profileName,
      'profileClassCode': item.details.profileClassCode,
      'declaredProfileSizeBytes': item.details.declaredProfileSizeBytes,
      'installedProfileSizeBytes': item.details.installedProfileSizeBytes,
      'gid1': item.details.gid1,
      'gid2': item.details.gid2,
      'countryCode': item.details.countryCode,
      'countryName': item.details.countryName,
      'mcc': item.details.mcc,
      'mnc': item.details.mnc,
      'apn': item.details.apn,
      'secondaryPhoneNumber': item.details.secondaryPhoneNumber,
      'secondaryPhoneNumberEnabled': item.details.secondaryPhoneNumberEnabled,
      'activationDate': item.details.activationDate?.toIso8601String(),
      'currentBalance': _encodeMoney(item.details.currentBalance),
      'affiliateOffers': item.details.affiliateOffers
          .map((offer) => offer.toJson())
          .toList(),
      'autoTopUpEnabled': item.details.autoTopUpEnabled,
      'topUpCycleUnit': item.details.topUpCycleUnit,
      'renewalIntervalValue': item.details.renewalIntervalValue,
      'renewalUnit': item.details.renewalUnit,
      'transactionNotes': item.details.transactionNotes,
      'carrierAppName': item.details.carrierAppName,
      'carrierAppStoreUrl': item.details.carrierAppStoreUrl,
      'carrierAppIconUrl': item.details.carrierAppIconUrl,
      'keepAliveModeRaw': item.details.keepAliveModeRaw,
      'orderIndex': item.details.orderIndex,
      'isDormant': item.details.isDormant,
      'isPinned': item.details.isPinned,
    },
    'timeZoneId': item.timeZoneId,
    'createdAt': item.createdAt.toIso8601String(),
    'updatedAt': item.updatedAt.toIso8601String(),
  };

  static Subscription _decodeSubscription(Map<String, dynamic> value) {
    final plan = _requiredMap(value, 'plan');
    final keepAlive = _requiredMap(value, 'keepAlive');
    final appearance = _requiredMap(value, 'appearance');
    final details = _requiredMap(value, 'details');
    final lifecycle = _requiredMap(value, 'lifecycle');
    final activation = value['activation'] is Map
        ? Map<String, dynamic>.from(value['activation'] as Map)
        : null;
    return Subscription(
      id: _requiredString(value, 'id'),
      iccid: _optionalString(value, 'iccid'),
      number: _decodePhoneNumber(_requiredString(value, 'number')),
      operator: _optionalString(value, 'operator'),
      lifecycle: ProfileLifecycle(
        stage: ProfileStage.values.byName(_requiredString(lifecycle, 'stage')),
        deviceState: ProfileDeviceState.values.byName(
          _requiredString(lifecycle, 'deviceState'),
        ),
        activationDeadline: _optionalUtc(lifecycle, 'activationDeadline'),
        activationRequirements: _optionalString(
          lifecycle,
          'activationRequirements',
        ),
        serviceExpiresAt: _optionalUtc(lifecycle, 'serviceExpiresAt'),
        activatedAt: _optionalUtc(lifecycle, 'activatedAt'),
        archivedAt: _optionalUtc(lifecycle, 'archivedAt'),
        archiveReason: switch (_optionalString(lifecycle, 'archiveReason')) {
          final raw? => ProfileArchiveReason.values.byName(raw),
          null => null,
        },
      ),
      activation: activation == null
          ? null
          : LpaActivation(
              smdpAddress: _requiredString(activation, 'smdpAddress'),
              matchingId: _requiredString(activation, 'matchingId'),
              extra: _optionalString(activation, 'extra'),
              confirmationCode: _optionalString(activation, 'confirmationCode'),
            ),
      plan: Plan(
        name: _optionalString(plan, 'name'),
        cyclePrice: _decodeMoney(plan['cyclePrice']),
        cycleDays: _optionalInt(plan, 'cycleDays'),
        startDate: _optionalUtc(plan, 'startDate'),
        expiryDate: _optionalUtc(plan, 'expiryDate'),
        isLongTerm: _requiredBool(plan, 'isLongTerm'),
      ),
      keepAlive: KeepAlive(
        required: _requiredBool(keepAlive, 'required'),
        cycleDays: _optionalInt(keepAlive, 'cycleDays'),
        lastActivityAt: _optionalUtc(keepAlive, 'lastActivityAt'),
        confidence: DataConfidence.values.byName(
          _requiredString(keepAlive, 'confidence'),
        ),
        policy: KeepAlivePolicy.fromJson(_requiredMap(keepAlive, 'policy')),
      ),
      tags: _list(value, 'tags').map((item) {
        if (item is! String) throw const FormatException('tags 必须为字符串数组');
        return item;
      }).toList(),
      appearance: Appearance(
        flag: _optionalString(appearance, 'flag'),
        cardColorHex: _optionalString(appearance, 'cardColorHex'),
        cardBackgroundAssetName: _optionalString(
          appearance,
          'cardBackgroundAssetName',
        ),
        websiteURL: _optionalString(appearance, 'websiteURL'),
        customPrompt: _optionalString(appearance, 'customPrompt'),
      ),
      details: SubscriptionDetails(
        profileName: _optionalString(details, 'profileName'),
        profileClassCode: _optionalInt(details, 'profileClassCode'),
        declaredProfileSizeBytes: _optionalInt(
          details,
          'declaredProfileSizeBytes',
        ),
        installedProfileSizeBytes: _optionalInt(
          details,
          'installedProfileSizeBytes',
        ),
        gid1: _optionalString(details, 'gid1'),
        gid2: _optionalString(details, 'gid2'),
        countryCode: _optionalString(details, 'countryCode'),
        countryName: _optionalString(details, 'countryName'),
        mcc: _optionalString(details, 'mcc'),
        mnc: _optionalString(details, 'mnc'),
        apn: _optionalString(details, 'apn'),
        secondaryPhoneNumber: _optionalString(details, 'secondaryPhoneNumber'),
        secondaryPhoneNumberEnabled: _requiredBool(
          details,
          'secondaryPhoneNumberEnabled',
        ),
        activationDate: _optionalUtc(details, 'activationDate'),
        currentBalance: _decodeMoney(details['currentBalance']),
        affiliateOffers: _list(details, 'affiliateOffers')
            .map(
              (value) => AffiliateOffer.fromJson(_map(value, 'affiliateOffer')),
            )
            .toList(growable: false),
        autoTopUpEnabled: _requiredBool(details, 'autoTopUpEnabled'),
        topUpCycleUnit: _optionalString(details, 'topUpCycleUnit'),
        renewalIntervalValue: _optionalInt(details, 'renewalIntervalValue'),
        renewalUnit: _optionalString(details, 'renewalUnit'),
        transactionNotes: _optionalString(details, 'transactionNotes'),
        carrierAppName: _optionalString(details, 'carrierAppName'),
        carrierAppStoreUrl: _optionalString(details, 'carrierAppStoreUrl'),
        carrierAppIconUrl: _optionalString(details, 'carrierAppIconUrl'),
        keepAliveModeRaw: _optionalString(details, 'keepAliveModeRaw'),
        orderIndex: _requiredInt(details, 'orderIndex'),
        isDormant: _requiredBool(details, 'isDormant'),
        isPinned: _requiredBool(details, 'isPinned'),
      ),
      timeZoneId: _requiredString(value, 'timeZoneId'),
      createdAt: _requiredUtc(value, 'createdAt'),
      updatedAt: _requiredUtc(value, 'updatedAt'),
    );
  }

  static Map<String, Object?> _encodeActivity(ActivityRecord item) => {
    'id': item.id,
    'subscriptionId': item.subscriptionId,
    'type': item.type.name,
    'occurredAt': item.occurredAt.toIso8601String(),
    'updatedAt': item.updatedAt.toIso8601String(),
    'amount': _encodeMoney(item.amount),
    'balanceAfter': _encodeMoney(item.balanceAfter),
    'note': item.note,
  };

  static ActivityRecord _decodeActivity(Map<String, dynamic> value) =>
      ActivityRecord(
        id: _requiredString(value, 'id'),
        subscriptionId: _requiredString(value, 'subscriptionId'),
        type: ActivityType.values.byName(_requiredString(value, 'type')),
        occurredAt: _requiredUtc(value, 'occurredAt'),
        updatedAt: _requiredUtc(value, 'updatedAt'),
        amount: _decodeMoney(value['amount']),
        balanceAfter: _decodeMoney(value['balanceAfter']),
        note: _optionalString(value, 'note'),
      );

  static Map<String, Object?> _encodeDevice(DeviceAsset item) => {
    'id': item.id,
    'name': item.name,
    'kind': item.kind.name,
    'brand': item.brand,
    'note': item.note,
    'region': item.region,
    'usage': item.usage,
    'simCapability': item.simCapability.name,
    'supportsSaRoaming': item.supportsSaRoaming,
    'orderIndex': item.orderIndex,
    'createdAt': item.createdAt.toIso8601String(),
    'updatedAt': item.updatedAt.toIso8601String(),
  };

  static DeviceAsset _decodeDevice(Map<String, dynamic> value) => DeviceAsset(
    id: _requiredString(value, 'id'),
    name: _requiredString(value, 'name'),
    kind: DeviceKind.values.byName(_requiredString(value, 'kind')),
    brand: _optionalString(value, 'brand'),
    note: _optionalString(value, 'note'),
    region: _optionalString(value, 'region'),
    usage: _optionalString(value, 'usage'),
    simCapability: SimCapability.values.byName(
      _requiredString(value, 'simCapability'),
    ),
    supportsSaRoaming: _requiredBool(value, 'supportsSaRoaming'),
    orderIndex: _requiredInt(value, 'orderIndex'),
    createdAt: _requiredUtc(value, 'createdAt'),
    updatedAt: _requiredUtc(value, 'updatedAt'),
  );

  static Map<String, Object?> _encodeSlot(SimSlot item) => {
    'id': item.id,
    'deviceId': item.deviceId,
    'label': item.label,
    'kind': item.kind.name,
    'position': item.position,
    'cardId': item.cardId,
    'createdAt': item.createdAt.toIso8601String(),
    'updatedAt': item.updatedAt.toIso8601String(),
  };

  static SimSlot _decodeSlot(Map<String, dynamic> value) => SimSlot(
    id: _requiredString(value, 'id'),
    deviceId: _requiredString(value, 'deviceId'),
    label: _requiredString(value, 'label'),
    kind: SimSlotKind.values.byName(_requiredString(value, 'kind')),
    position: _requiredInt(value, 'position'),
    cardId: _optionalString(value, 'cardId'),
    createdAt: _requiredUtc(value, 'createdAt'),
    updatedAt: _requiredUtc(value, 'updatedAt'),
  );

  static Map<String, Object?> _encodeCard(SimCard item) => {
    'id': item.id,
    'name': item.name,
    'kind': item.kind.name,
    'note': item.note,
    'physicalIccid': item.physicalIccid,
    'presetId': item.presetId,
    'embeddedDeviceId': item.embeddedDeviceId,
    'createdAt': item.createdAt.toIso8601String(),
    'updatedAt': item.updatedAt.toIso8601String(),
  };

  static SimCard _decodeCard(Map<String, dynamic> value) {
    final common = (
      id: _requiredString(value, 'id'),
      name: _requiredString(value, 'name'),
      note: _optionalString(value, 'note'),
      presetId: _optionalString(value, 'presetId'),
      createdAt: _requiredUtc(value, 'createdAt'),
      updatedAt: _requiredUtc(value, 'updatedAt'),
    );
    return switch (SimCardKind.values.byName(_requiredString(value, 'kind'))) {
      SimCardKind.physicalSim => PhysicalSimCard(
        id: common.id,
        name: common.name,
        note: common.note,
        presetId: common.presetId,
        physicalIccid: _requiredString(value, 'physicalIccid'),
        createdAt: common.createdAt,
        updatedAt: common.updatedAt,
      ),
      SimCardKind.removableEuicc => RemovableEuiccCard(
        id: common.id,
        name: common.name,
        note: common.note,
        presetId: common.presetId,
        physicalIccid: _optionalString(value, 'physicalIccid'),
        createdAt: common.createdAt,
        updatedAt: common.updatedAt,
      ),
      SimCardKind.embeddedEuicc => EmbeddedEuiccCard(
        id: common.id,
        name: common.name,
        note: common.note,
        presetId: common.presetId,
        embeddedDeviceId: _requiredString(value, 'embeddedDeviceId'),
        createdAt: common.createdAt,
        updatedAt: common.updatedAt,
      ),
    };
  }

  static Map<String, Object?> _encodeEid(Euicc item) => {
    'id': item.id,
    'cardId': item.cardId,
    'value': item.value,
    'label': item.label,
    'createdAt': item.createdAt.toIso8601String(),
    'updatedAt': item.updatedAt.toIso8601String(),
  };

  static Euicc _decodeEid(Map<String, dynamic> value) => Euicc(
    id: _requiredString(value, 'id'),
    cardId: _requiredString(value, 'cardId'),
    value: _requiredString(value, 'value'),
    label: _optionalString(value, 'label'),
    createdAt: _requiredUtc(value, 'createdAt'),
    updatedAt: _requiredUtc(value, 'updatedAt'),
  );

  static Map<String, Object?> _encodeProfile(EsimProfile item) => {
    'id': item.id,
    'eidId': item.eidId,
    'iccid': item.iccid,
    'operatorName': item.operatorName,
    'nickname': item.nickname,
    'subscriptionId': item.subscriptionId,
    'isPinned': item.isPinned,
    'createdAt': item.createdAt.toIso8601String(),
    'updatedAt': item.updatedAt.toIso8601String(),
  };

  static EsimProfile _decodeProfile(Map<String, dynamic> value) => EsimProfile(
    id: _requiredString(value, 'id'),
    eidId: _requiredString(value, 'eidId'),
    iccid: _optionalString(value, 'iccid'),
    operatorName: _optionalString(value, 'operatorName'),
    nickname: _optionalString(value, 'nickname'),
    subscriptionId: _optionalString(value, 'subscriptionId'),
    isPinned: _requiredBool(value, 'isPinned'),
    createdAt: _requiredUtc(value, 'createdAt'),
    updatedAt: _requiredUtc(value, 'updatedAt'),
  );

  static Map<String, Object?> _encodeAssetEvent(AssetEvent item) {
    String? cardId;
    String? profileId;
    String? fromSlotId;
    String? toSlotId;
    String? fromEidId;
    String? toEidId;
    switch (item) {
      case CardMoved():
        cardId = item.cardId;
        fromSlotId = item.fromSlotId;
        toSlotId = item.toSlotId;
      case CardStored():
        cardId = item.cardId;
        fromSlotId = item.fromSlotId;
      case ProfileMoved():
        profileId = item.profileId;
        fromEidId = item.fromEidId;
        toEidId = item.toEidId;
      case ProfileWiped():
        profileId = item.profileId;
        fromEidId = item.fromEidId;
    }
    return {
      'id': item.id,
      'type': item.type.name,
      'cardId': cardId,
      'profileId': profileId,
      'fromSlotId': fromSlotId,
      'toSlotId': toSlotId,
      'fromEidId': fromEidId,
      'toEidId': toEidId,
      'occurredAt': item.occurredAt.toIso8601String(),
      'note': item.note,
    };
  }

  static AssetEvent _decodeAssetEvent(Map<String, dynamic> value) {
    final id = _requiredString(value, 'id');
    final occurredAt = _requiredUtc(value, 'occurredAt');
    final note = _optionalString(value, 'note');
    return switch (AssetEventType.values.byName(
      _requiredString(value, 'type'),
    )) {
      AssetEventType.cardMoved => CardMoved(
        id: id,
        cardId: _requiredString(value, 'cardId'),
        fromSlotId: _optionalString(value, 'fromSlotId'),
        toSlotId: _requiredString(value, 'toSlotId'),
        occurredAt: occurredAt,
        note: note,
      ),
      AssetEventType.cardStored => CardStored(
        id: id,
        cardId: _requiredString(value, 'cardId'),
        fromSlotId: _requiredString(value, 'fromSlotId'),
        occurredAt: occurredAt,
        note: note,
      ),
      AssetEventType.profileMoved => ProfileMoved(
        id: id,
        profileId: _requiredString(value, 'profileId'),
        fromEidId: _requiredString(value, 'fromEidId'),
        toEidId: _requiredString(value, 'toEidId'),
        occurredAt: occurredAt,
        note: note,
      ),
      AssetEventType.profileWiped => ProfileWiped(
        id: id,
        profileId: _requiredString(value, 'profileId'),
        fromEidId: _requiredString(value, 'fromEidId'),
        occurredAt: occurredAt,
        note: note,
      ),
    };
  }

  static AssetInventory _decodeAssets(
    Map<String, dynamic> value,
  ) => AssetInventory(
    devices: _list(
      value,
      'devices',
    ).map((item) => _decodeDevice(_map(item, 'device'))),
    slots: _list(value, 'slots').map((item) => _decodeSlot(_map(item, 'slot'))),
    cards: _list(value, 'cards').map((item) => _decodeCard(_map(item, 'card'))),
    eids: _list(value, 'eids').map((item) => _decodeEid(_map(item, 'eid'))),
    profiles: _list(
      value,
      'profiles',
    ).map((item) => _decodeProfile(_map(item, 'profile'))),
    events: _list(
      value,
      'events',
    ).map((item) => _decodeAssetEvent(_map(item, 'assetEvent'))),
  );

  static PhoneNumber _decodePhoneNumber(String value) =>
      value.isEmpty ? const PhoneNumber.unknown() : PhoneNumber(value);

  static SyncTombstone _decodeTombstone(Map<String, dynamic> value) =>
      SyncTombstone(
        entityType: SyncEntityType.values.byName(
          _requiredString(value, 'entityType'),
        ),
        entityId: _requiredString(value, 'id'),
        deletedAtUtc: _requiredUtc(value, 'deletedAt'),
      );

  static Map<String, Object?>? _encodeMoney(Money? money) => money == null
      ? null
      : {'minorUnits': money.minorUnits, 'currencyCode': money.currencyCode};

  static Money? _decodeMoney(Object? value) {
    if (value == null) return null;
    final map = _map(value, 'money');
    return Money(
      minorUnits: _requiredInt(map, 'minorUnits'),
      currencyCode: _requiredString(map, 'currencyCode'),
    );
  }

  static Map<String, dynamic> _map(Object? value, String label) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('$label 必须是对象');
    }
    return value;
  }

  static Map<String, dynamic> _requiredMap(
    Map<String, dynamic> value,
    String key,
  ) => _map(value[key], key);

  static List<dynamic> _list(Map<String, dynamic> value, String key) {
    final result = value[key];
    if (result is! List) throw FormatException('$key 必须是数组');
    return result;
  }

  static String _requiredString(Map<String, dynamic> value, String key) {
    final result = value[key];
    if (result is! String || result.isEmpty) {
      throw FormatException('$key 必须是非空字符串');
    }
    return result;
  }

  static String? _optionalString(Map<String, dynamic> value, String key) {
    final result = value[key];
    if (result == null) return null;
    if (result is! String) throw FormatException('$key 必须是字符串或 null');
    return result;
  }

  static int _requiredInt(Map<String, dynamic> value, String key) {
    final result = value[key];
    if (result is! int) throw FormatException('$key 必须是整数');
    return result;
  }

  static int? _optionalInt(Map<String, dynamic> value, String key) {
    final result = value[key];
    if (result == null) return null;
    if (result is! int) throw FormatException('$key 必须是整数或 null');
    return result;
  }

  static bool _requiredBool(Map<String, dynamic> value, String key) {
    final result = value[key];
    if (result is! bool) throw FormatException('$key 必须是布尔值');
    return result;
  }

  static DateTime _requiredUtc(Map<String, dynamic> value, String key) {
    final source = _requiredString(value, key);
    final result = DateTime.tryParse(source);
    if (result == null || !result.isUtc) {
      throw FormatException('$key 必须是带时区的 UTC ISO 时间');
    }
    return result;
  }

  static DateTime? _optionalUtc(Map<String, dynamic> value, String key) {
    if (value[key] == null) return null;
    return _requiredUtc(value, key);
  }

  static void _requireUnique(Iterable<String> values, String label) {
    final seen = <String>{};
    for (final value in values) {
      if (!seen.add(value)) throw FormatException('$label 重复：$value');
    }
  }
}
