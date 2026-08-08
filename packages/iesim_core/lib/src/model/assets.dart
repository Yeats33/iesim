import 'dart:collection';

enum DeviceKind {
  phone,
  mobileRouter,
  tablet,
  watch,
  laptop,
  esimWriter,
  other,
}

enum SimCapability {
  physicalOnly,
  esimOnly,
  physicalPlusEsim,
  dualPhysical,
  multiEsim,
  unknown,
}

enum SimSlotKind { physical, embeddedEuicc }

enum SimCardKind { physicalSim, removableEuicc, embeddedEuicc }

/// Placement rules shared by imports, repositories and UI filtering.
abstract final class AssetRules {
  static bool canPlace(SimCard card, SimSlot slot) =>
      placementError(card, slot) == null;

  static String? placementError(SimCard card, SimSlot slot) {
    if (card is EmbeddedEuiccCard) {
      if (slot.kind != SimSlotKind.embeddedEuicc ||
          slot.deviceId != card.embeddedDeviceId) {
        return '内置 eUICC 不能移出所属设备';
      }
      return null;
    }
    if (slot.kind == SimSlotKind.embeddedEuicc) {
      return '只有该设备的内置 eUICC 可以使用内置 eSIM 卡槽';
    }
    return null;
  }
}

class DeviceAsset {
  DeviceAsset({
    required this.id,
    required String name,
    this.kind = DeviceKind.phone,
    this.brand,
    this.note,
    this.region,
    this.usage,
    this.simCapability = SimCapability.unknown,
    this.supportsSaRoaming = false,
    this.orderIndex = 0,
    required this.createdAt,
    required this.updatedAt,
  }) : name = name.trim() {
    _requireId(id, 'id');
    if (this.name.isEmpty) throw ArgumentError.value(name, 'name', '不能为空');
    _requireUtc(createdAt, 'createdAt');
    _requireUtc(updatedAt, 'updatedAt');
  }

  final String id;
  final String name;
  final DeviceKind kind;
  final String? brand;
  final String? note;
  final String? region;
  final String? usage;
  final SimCapability simCapability;
  final bool supportsSaRoaming;
  final int orderIndex;
  final DateTime createdAt;
  final DateTime updatedAt;

  DeviceAsset copyWith({
    String? name,
    DeviceKind? kind,
    String? brand,
    String? note,
    String? region,
    String? usage,
    SimCapability? simCapability,
    bool? supportsSaRoaming,
    int? orderIndex,
    DateTime? updatedAt,
  }) => DeviceAsset(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    brand: brand ?? this.brand,
    note: note ?? this.note,
    region: region ?? this.region,
    usage: usage ?? this.usage,
    simCapability: simCapability ?? this.simCapability,
    supportsSaRoaming: supportsSaRoaming ?? this.supportsSaRoaming,
    orderIndex: orderIndex ?? this.orderIndex,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is DeviceAsset &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.brand == brand &&
      other.note == note &&
      other.region == region &&
      other.usage == usage &&
      other.simCapability == simCapability &&
      other.supportsSaRoaming == supportsSaRoaming &&
      other.orderIndex == orderIndex &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    brand,
    note,
    region,
    usage,
    simCapability,
    supportsSaRoaming,
    orderIndex,
    createdAt,
    updatedAt,
  );
}

class SimSlot {
  SimSlot({
    required this.id,
    required this.deviceId,
    required String label,
    required this.kind,
    required this.position,
    this.cardId,
    required this.createdAt,
    required this.updatedAt,
  }) : label = label.trim() {
    _requireId(id, 'id');
    _requireId(deviceId, 'deviceId');
    if (this.label.isEmpty) {
      throw ArgumentError.value(label, 'label', '不能为空');
    }
    if (position < 0) {
      throw ArgumentError.value(position, 'position', '不能为负数');
    }
    _requireUtc(createdAt, 'createdAt');
    _requireUtc(updatedAt, 'updatedAt');
  }

  final String id;
  final String deviceId;
  final String label;
  final SimSlotKind kind;
  final int position;
  final String? cardId;
  final DateTime createdAt;
  final DateTime updatedAt;

  SimSlot copyWith({
    String? label,
    SimSlotKind? kind,
    int? position,
    String? cardId,
    bool clearCard = false,
    DateTime? updatedAt,
  }) => SimSlot(
    id: id,
    deviceId: deviceId,
    label: label ?? this.label,
    kind: kind ?? this.kind,
    position: position ?? this.position,
    cardId: clearCard ? null : cardId ?? this.cardId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is SimSlot &&
      other.id == id &&
      other.deviceId == deviceId &&
      other.label == label &&
      other.kind == kind &&
      other.position == position &&
      other.cardId == cardId &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    deviceId,
    label,
    kind,
    position,
    cardId,
    createdAt,
    updatedAt,
  );
}

sealed class SimCard {
  SimCard({
    required this.id,
    required String name,
    this.note,
    this.physicalIccid,
    this.presetId,
    required this.createdAt,
    required this.updatedAt,
  }) : name = name.trim() {
    _requireId(id, 'id');
    if (this.name.isEmpty) throw ArgumentError.value(name, 'name', '不能为空');
    _requireUtc(createdAt, 'createdAt');
    _requireUtc(updatedAt, 'updatedAt');
  }

  final String id;
  final String name;
  final String? note;
  final String? physicalIccid;
  final String? presetId;
  final DateTime createdAt;
  final DateTime updatedAt;

  SimCardKind get kind;
  String? get embeddedDeviceId => null;

  @override
  bool operator ==(Object other) =>
      other is SimCard &&
      other.runtimeType == runtimeType &&
      other.id == id &&
      other.name == name &&
      other.note == note &&
      other.physicalIccid == physicalIccid &&
      other.presetId == presetId &&
      other.embeddedDeviceId == embeddedDeviceId &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    name,
    note,
    physicalIccid,
    presetId,
    embeddedDeviceId,
    createdAt,
    updatedAt,
  );
}

final class PhysicalSimCard extends SimCard {
  PhysicalSimCard({
    required super.id,
    required super.name,
    super.note,
    super.presetId,
    required String super.physicalIccid,
    required super.createdAt,
    required super.updatedAt,
  });

  @override
  SimCardKind get kind => SimCardKind.physicalSim;
}

final class RemovableEuiccCard extends SimCard {
  RemovableEuiccCard({
    required super.id,
    required super.name,
    super.note,
    super.physicalIccid,
    super.presetId,
    required super.createdAt,
    required super.updatedAt,
  });

  @override
  SimCardKind get kind => SimCardKind.removableEuicc;
}

final class EmbeddedEuiccCard extends SimCard {
  EmbeddedEuiccCard({
    required super.id,
    required super.name,
    super.note,
    super.presetId,
    required String embeddedDeviceId,
    required super.createdAt,
    required super.updatedAt,
  }) : _embeddedDeviceId = embeddedDeviceId {
    _requireId(embeddedDeviceId, 'embeddedDeviceId');
  }

  final String _embeddedDeviceId;

  @override
  String get embeddedDeviceId => _embeddedDeviceId;

  @override
  SimCardKind get kind => SimCardKind.embeddedEuicc;
}

class Euicc {
  Euicc({
    required this.id,
    required this.cardId,
    required String value,
    this.label,
    required this.createdAt,
    required this.updatedAt,
  }) : value = value.trim() {
    _requireId(id, 'id');
    _requireId(cardId, 'cardId');
    if (this.value.isEmpty) throw ArgumentError.value(value, 'value', '不能为空');
    _requireUtc(createdAt, 'createdAt');
    _requireUtc(updatedAt, 'updatedAt');
  }

  final String id;
  final String cardId;
  final String value;
  final String? label;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is Euicc &&
      other.id == id &&
      other.cardId == cardId &&
      other.value == value &&
      other.label == label &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, cardId, value, label, createdAt, updatedAt);
}

class EsimProfile {
  EsimProfile({
    required this.id,
    required this.eidId,
    this.iccid,
    this.operatorName,
    this.nickname,
    this.subscriptionId,
    this.isPinned = false,
    required this.createdAt,
    required this.updatedAt,
  }) {
    _requireId(id, 'id');
    _requireId(eidId, 'eidId');
    if ((iccid == null || iccid!.trim().isEmpty) && subscriptionId == null) {
      throw ArgumentError('Profile 至少需要 ICCID 或关联订阅');
    }
    _requireUtc(createdAt, 'createdAt');
    _requireUtc(updatedAt, 'updatedAt');
  }

  final String id;
  final String eidId;
  final String? iccid;
  final String? operatorName;
  final String? nickname;
  final String? subscriptionId;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  EsimProfile copyWith({
    String? eidId,
    String? iccid,
    String? operatorName,
    String? nickname,
    String? subscriptionId,
    bool clearSubscription = false,
    bool? isPinned,
    DateTime? updatedAt,
  }) => EsimProfile(
    id: id,
    eidId: eidId ?? this.eidId,
    iccid: iccid ?? this.iccid,
    operatorName: operatorName ?? this.operatorName,
    nickname: nickname ?? this.nickname,
    subscriptionId: clearSubscription
        ? null
        : subscriptionId ?? this.subscriptionId,
    isPinned: isPinned ?? this.isPinned,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is EsimProfile &&
      other.id == id &&
      other.eidId == eidId &&
      other.iccid == iccid &&
      other.operatorName == operatorName &&
      other.nickname == nickname &&
      other.subscriptionId == subscriptionId &&
      other.isPinned == isPinned &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    eidId,
    iccid,
    operatorName,
    nickname,
    subscriptionId,
    isPinned,
    createdAt,
    updatedAt,
  );
}

enum AssetEventType { cardMoved, cardStored, profileMoved, profileWiped }

sealed class AssetEvent {
  AssetEvent({required this.id, required this.occurredAt, this.note}) {
    _requireId(id, 'id');
    _requireUtc(occurredAt, 'occurredAt');
  }

  final String id;
  final DateTime occurredAt;
  final String? note;
  AssetEventType get type;

  List<Object?> get equalityFields;

  @override
  bool operator ==(Object other) =>
      other is AssetEvent &&
      other.runtimeType == runtimeType &&
      _objectsEqual(other.equalityFields, equalityFields);

  @override
  int get hashCode => Object.hashAll([runtimeType, ...equalityFields]);
}

final class CardMoved extends AssetEvent {
  CardMoved({
    required super.id,
    required this.cardId,
    this.fromSlotId,
    required this.toSlotId,
    required super.occurredAt,
    super.note,
  });

  final String cardId;
  final String? fromSlotId;
  final String toSlotId;

  @override
  AssetEventType get type => AssetEventType.cardMoved;

  @override
  List<Object?> get equalityFields => [
    id,
    cardId,
    fromSlotId,
    toSlotId,
    occurredAt,
    note,
  ];
}

final class CardStored extends AssetEvent {
  CardStored({
    required super.id,
    required this.cardId,
    required this.fromSlotId,
    required super.occurredAt,
    super.note,
  });

  final String cardId;
  final String fromSlotId;

  @override
  AssetEventType get type => AssetEventType.cardStored;

  @override
  List<Object?> get equalityFields => [
    id,
    cardId,
    fromSlotId,
    occurredAt,
    note,
  ];
}

final class ProfileMoved extends AssetEvent {
  ProfileMoved({
    required super.id,
    required this.profileId,
    required this.fromEidId,
    required this.toEidId,
    required super.occurredAt,
    super.note,
  });

  final String profileId;
  final String fromEidId;
  final String toEidId;

  @override
  AssetEventType get type => AssetEventType.profileMoved;

  @override
  List<Object?> get equalityFields => [
    id,
    profileId,
    fromEidId,
    toEidId,
    occurredAt,
    note,
  ];
}

final class ProfileWiped extends AssetEvent {
  ProfileWiped({
    required super.id,
    required this.profileId,
    required this.fromEidId,
    required super.occurredAt,
    super.note,
  });

  final String profileId;
  final String fromEidId;

  @override
  AssetEventType get type => AssetEventType.profileWiped;

  @override
  List<Object?> get equalityFields => [
    id,
    profileId,
    fromEidId,
    occurredAt,
    note,
  ];
}

class AssetInventory {
  AssetInventory({
    Iterable<DeviceAsset> devices = const [],
    Iterable<SimSlot> slots = const [],
    Iterable<SimCard> cards = const [],
    Iterable<Euicc> eids = const [],
    Iterable<EsimProfile> profiles = const [],
    Iterable<AssetEvent> events = const [],
  }) : devices = UnmodifiableListView(devices),
       slots = UnmodifiableListView(slots),
       cards = UnmodifiableListView(cards),
       eids = UnmodifiableListView(eids),
       profiles = UnmodifiableListView(profiles),
       events = UnmodifiableListView(events);

  final UnmodifiableListView<DeviceAsset> devices;
  final UnmodifiableListView<SimSlot> slots;
  final UnmodifiableListView<SimCard> cards;
  final UnmodifiableListView<Euicc> eids;
  final UnmodifiableListView<EsimProfile> profiles;
  final UnmodifiableListView<AssetEvent> events;

  Iterable<SimSlot> slotsForDevice(String deviceId) =>
      slots.where((slot) => slot.deviceId == deviceId);

  SimSlot? slotHolding(String cardId) {
    for (final slot in slots) {
      if (slot.cardId == cardId) return slot;
    }
    return null;
  }

  SimCard? cardById(String id) {
    for (final card in cards) {
      if (card.id == id) return card;
    }
    return null;
  }

  Iterable<Euicc> eidsForCard(String cardId) =>
      eids.where((eid) => eid.cardId == cardId);

  Iterable<EsimProfile> profilesForEid(String eidId) =>
      profiles.where((profile) => profile.eidId == eidId);
}

void _requireId(String value, String name) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, name, '不能为空');
}

void _requireUtc(DateTime value, String name) {
  if (!value.isUtc) throw ArgumentError.value(value, name, '必须为 UTC 时刻');
}

bool _objectsEqual(List<Object?> left, List<Object?> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
