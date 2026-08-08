import 'package:sqlite3/sqlite3.dart';

import '../model/assets.dart';
import '../result.dart';

class AssetRepository {
  AssetRepository(this._db);

  final Database _db;

  Result<AssetInventory> load() {
    try {
      return Ok(
        AssetInventory(
          devices: [
            for (final row in _db.select(
              'SELECT * FROM devices ORDER BY order_index, created_at',
            ))
              _deviceFromRow(row),
          ],
          slots: [
            for (final row in _db.select(
              'SELECT * FROM slots ORDER BY device_id, position',
            ))
              _slotFromRow(row),
          ],
          cards: [
            for (final row in _db.select(
              'SELECT * FROM cards ORDER BY created_at',
            ))
              _cardFromRow(row),
          ],
          eids: [
            for (final row in _db.select(
              'SELECT * FROM eids ORDER BY created_at',
            ))
              _eidFromRow(row),
          ],
          profiles: [
            for (final row in _db.select(
              'SELECT * FROM profiles ORDER BY created_at',
            ))
              _profileFromRow(row),
          ],
          events: [
            for (final row in _db.select(
              'SELECT * FROM asset_events ORDER BY occurred_at DESC',
            ))
              _eventFromRow(row),
          ],
        ),
      );
    } on SqliteException catch (error) {
      return Err(StoreError(error.message));
    } catch (error) {
      return Err(StoreError(error.toString()));
    }
  }

  Result<void> upsertDevice(DeviceAsset device) => _guard(() {
    _db.execute(
      '''INSERT INTO devices (
  id, name, kind, brand, note, region, usage, sim_capability,
  supports_sa_roaming, order_index, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  name = excluded.name,
  kind = excluded.kind,
  brand = excluded.brand,
  note = excluded.note,
  region = excluded.region,
  usage = excluded.usage,
  sim_capability = excluded.sim_capability,
  supports_sa_roaming = excluded.supports_sa_roaming,
  order_index = excluded.order_index,
  updated_at = excluded.updated_at''',
      [
        device.id,
        device.name,
        device.kind.name,
        device.brand,
        device.note,
        device.region,
        device.usage,
        device.simCapability.name,
        device.supportsSaRoaming ? 1 : 0,
        device.orderIndex,
        _iso(device.createdAt),
        _iso(device.updatedAt),
      ],
    );
  });

  Result<void> upsertSlot(SimSlot slot) => _guard(() {
    if (_db.select('SELECT id FROM devices WHERE id = ?', [
      slot.deviceId,
    ]).isEmpty) {
      throw const _AssetConstraint('卡槽所属设备不存在');
    }
    if (slot.cardId != null) {
      final rows = _db.select('SELECT * FROM cards WHERE id = ?', [
        slot.cardId,
      ]);
      if (rows.isEmpty) throw const _AssetConstraint('卡槽中的卡片不存在');
      final otherSlot = _db.select(
        'SELECT id FROM slots WHERE card_id = ? AND id <> ? LIMIT 1',
        [slot.cardId, slot.id],
      );
      if (otherSlot.isNotEmpty) throw const _AssetConstraint('卡片已在其他卡槽中');
      final placementError = AssetRules.placementError(
        _cardFromRow(rows.single),
        slot,
      );
      if (placementError != null) throw _AssetConstraint(placementError);
    }
    _db.execute(
      '''INSERT INTO slots (
  id, device_id, label, kind, position, card_id, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  device_id = excluded.device_id,
  label = excluded.label,
  kind = excluded.kind,
  position = excluded.position,
  card_id = excluded.card_id,
  updated_at = excluded.updated_at''',
      [
        slot.id,
        slot.deviceId,
        slot.label,
        slot.kind.name,
        slot.position,
        slot.cardId,
        _iso(slot.createdAt),
        _iso(slot.updatedAt),
      ],
    );
  });

  Result<void> upsertCard(SimCard card) => _guard(() {
    if (card case EmbeddedEuiccCard(embeddedDeviceId: final deviceId)) {
      if (_db.select('SELECT id FROM devices WHERE id = ?', [
        deviceId,
      ]).isEmpty) {
        throw const _AssetConstraint('内置 eUICC 所属设备不存在');
      }
    }
    final slotRows = _db.select('SELECT * FROM slots WHERE card_id = ?', [
      card.id,
    ]);
    if (slotRows.isNotEmpty) {
      final placementError = AssetRules.placementError(
        card,
        _slotFromRow(slotRows.single),
      );
      if (placementError != null) throw _AssetConstraint(placementError);
    }
    _db.execute(
      '''INSERT INTO cards (
  id, name, kind, physical_iccid, note, preset_id, embedded_device_id,
  created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  name = excluded.name,
  kind = excluded.kind,
  physical_iccid = excluded.physical_iccid,
  note = excluded.note,
  preset_id = excluded.preset_id,
  embedded_device_id = excluded.embedded_device_id,
  updated_at = excluded.updated_at''',
      [
        card.id,
        card.name,
        card.kind.name,
        card.physicalIccid,
        card.note,
        card.presetId,
        card.embeddedDeviceId,
        _iso(card.createdAt),
        _iso(card.updatedAt),
      ],
    );
  });

  Result<void> upsertEid(Euicc eid) => _guard(() {
    _db.execute(
      '''INSERT INTO eids (id, card_id, value, label, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  card_id = excluded.card_id,
  value = excluded.value,
  label = excluded.label,
  updated_at = excluded.updated_at''',
      [
        eid.id,
        eid.cardId,
        eid.value,
        eid.label,
        _iso(eid.createdAt),
        _iso(eid.updatedAt),
      ],
    );
  });

  Result<void> upsertProfile(EsimProfile profile) => _guard(() {
    _db.execute(
      '''INSERT INTO profiles (
  id, eid_id, iccid, operator_name, nickname, subscription_id, is_pinned,
  created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  eid_id = excluded.eid_id,
  iccid = excluded.iccid,
  operator_name = excluded.operator_name,
  nickname = excluded.nickname,
  subscription_id = excluded.subscription_id,
  is_pinned = excluded.is_pinned,
  updated_at = excluded.updated_at''',
      [
        profile.id,
        profile.eidId,
        _nullable(profile.iccid),
        _nullable(profile.operatorName),
        _nullable(profile.nickname),
        profile.subscriptionId,
        profile.isPinned ? 1 : 0,
        _iso(profile.createdAt),
        _iso(profile.updatedAt),
      ],
    );
  });

  Result<void> upsertEvent(AssetEvent event) => _guard(() {
    _insertEvent(event);
  });

  Result<void> deleteDevice(
    String id, {
    DateTime? deletedAtUtc,
  }) => _transactionGuard(() {
    final occupied = _db.select(
      'SELECT id FROM slots WHERE device_id = ? AND card_id IS NOT NULL LIMIT 1',
      [id],
    );
    if (occupied.isNotEmpty) {
      throw const _AssetConstraint('请先把设备中的卡片移至库存');
    }
    final embedded = _db.select(
      'SELECT id FROM cards WHERE embedded_device_id = ? LIMIT 1',
      [id],
    );
    if (embedded.isNotEmpty) {
      throw const _AssetConstraint('请先删除该设备的内置 eUICC');
    }
    final slots = _db.select('SELECT id FROM slots WHERE device_id = ?', [id]);
    _db.execute('DELETE FROM slots WHERE device_id = ?', [id]);
    _db.execute('DELETE FROM devices WHERE id = ?', [id]);
    if (deletedAtUtc != null) {
      for (final slot in slots) {
        _writeTombstone('slot', slot['id'] as String, deletedAtUtc);
      }
      _writeTombstone('device', id, deletedAtUtc);
    }
  });

  Result<void> deleteSlot(String id, {DateTime? deletedAtUtc}) =>
      _transactionGuard(() {
        final row = _db.select('SELECT card_id FROM slots WHERE id = ?', [id]);
        if (row.isNotEmpty && row.single['card_id'] != null) {
          throw const _AssetConstraint('卡槽仍装有卡片，请先移至库存');
        }
        _db.execute('DELETE FROM slots WHERE id = ?', [id]);
        if (deletedAtUtc != null) _writeTombstone('slot', id, deletedAtUtc);
      });

  Result<void> deleteCard(
    String id, {
    DateTime? deletedAtUtc,
  }) => _transactionGuard(() {
    final occupied = _db.select(
      'SELECT id FROM slots WHERE card_id = ? LIMIT 1',
      [id],
    );
    if (occupied.isNotEmpty) {
      throw const _AssetConstraint('卡片仍在设备中，请先移至库存');
    }
    final eids = _db.select('SELECT id FROM eids WHERE card_id = ?', [id]);
    final profiles = _db.select(
      'SELECT id FROM profiles WHERE eid_id IN (SELECT id FROM eids WHERE card_id = ?)',
      [id],
    );
    _db.execute(
      'DELETE FROM profiles WHERE eid_id IN (SELECT id FROM eids WHERE card_id = ?)',
      [id],
    );
    _db.execute('DELETE FROM eids WHERE card_id = ?', [id]);
    _db.execute('DELETE FROM cards WHERE id = ?', [id]);
    if (deletedAtUtc != null) {
      for (final profile in profiles) {
        _writeTombstone('profile', profile['id'] as String, deletedAtUtc);
      }
      for (final eid in eids) {
        _writeTombstone('eid', eid['id'] as String, deletedAtUtc);
      }
      _writeTombstone('card', id, deletedAtUtc);
    }
  });

  Result<void> deleteEid(String id, {DateTime? deletedAtUtc}) =>
      _transactionGuard(() {
        final profiles = _db.select(
          'SELECT id FROM profiles WHERE eid_id = ? LIMIT 1',
          [id],
        );
        if (profiles.isNotEmpty) {
          throw const _AssetConstraint('该 EID 仍有 Profile，请先移动或删除 Profile');
        }
        _db.execute('DELETE FROM eids WHERE id = ?', [id]);
        if (deletedAtUtc != null) _writeTombstone('eid', id, deletedAtUtc);
      });

  /// Creates an embedded card, its first EID and its slot assignment as one
  /// atomic operation. [slot] may be a new empty slot or an existing one.
  Result<void> createEmbeddedEuicc({
    required EmbeddedEuiccCard card,
    required Euicc eid,
    required SimSlot slot,
    required String eventId,
    required DateTime occurredAt,
  }) {
    try {
      _db.execute('BEGIN IMMEDIATE');
      if (eid.cardId != card.id) {
        throw const _AssetConstraint('EID 与内置 eUICC 不匹配');
      }
      if (slot.cardId != null) {
        throw const _AssetConstraint('目标卡槽已有卡片');
      }
      final deviceExists = _db.select('SELECT id FROM devices WHERE id = ?', [
        card.embeddedDeviceId,
      ]);
      if (deviceExists.isEmpty) {
        throw const _AssetConstraint('内置 eUICC 所属设备不存在');
      }
      final placementError = AssetRules.placementError(card, slot);
      if (placementError != null) throw _AssetConstraint(placementError);
      _requireOk(upsertSlot(slot));
      _requireOk(upsertCard(card));
      _requireOk(upsertEid(eid));
      _db.execute('UPDATE slots SET card_id = ?, updated_at = ? WHERE id = ?', [
        card.id,
        _iso(occurredAt),
        slot.id,
      ]);
      _insertEvent(
        CardMoved(
          id: eventId,
          cardId: card.id,
          toSlotId: slot.id,
          occurredAt: occurredAt,
          note: '建立内置 eUICC',
        ),
      );
      _db.execute('COMMIT');
      return const Ok(null);
    } on _AssetConstraint catch (error) {
      _rollback();
      return Err(StoreError(error.message));
    } on SqliteException catch (error) {
      _rollback();
      return Err(StoreError(error.message));
    } catch (error) {
      _rollback();
      return Err(StoreError(error.toString()));
    }
  }

  /// Replaces or removes the card in a slot without exposing an intermediate
  /// empty state to sync or to a failed second write.
  Result<void> replaceCardInSlot({
    required String slotId,
    required String? cardId,
    required String storedEventId,
    required String movedEventId,
    required DateTime occurredAt,
  }) {
    try {
      _db.execute('BEGIN IMMEDIATE');
      final slotRows = _db.select('SELECT * FROM slots WHERE id = ?', [slotId]);
      if (slotRows.isEmpty) throw const _AssetConstraint('目标卡槽不存在');
      final slot = _slotFromRow(slotRows.single);
      if (slot.cardId == cardId) {
        _db.execute('COMMIT');
        return const Ok(null);
      }
      SimCard? current;
      if (slot.cardId != null) {
        final currentRows = _db.select('SELECT * FROM cards WHERE id = ?', [
          slot.cardId,
        ]);
        if (currentRows.isNotEmpty) current = _cardFromRow(currentRows.single);
      }
      if (current is EmbeddedEuiccCard) {
        throw const _AssetConstraint('内置 eUICC 不能从所属卡槽移除');
      }
      SimCard? replacement;
      if (cardId != null) {
        final replacementRows = _db.select('SELECT * FROM cards WHERE id = ?', [
          cardId,
        ]);
        if (replacementRows.isEmpty) throw const _AssetConstraint('卡片不存在');
        replacement = _cardFromRow(replacementRows.single);
        final occupied = _db.select(
          'SELECT id FROM slots WHERE card_id = ? AND id <> ? LIMIT 1',
          [cardId, slotId],
        );
        if (occupied.isNotEmpty) throw const _AssetConstraint('卡片已在其他卡槽中');
        final placementError = AssetRules.placementError(replacement, slot);
        if (placementError != null) throw _AssetConstraint(placementError);
      }
      _db.execute('UPDATE slots SET card_id = ?, updated_at = ? WHERE id = ?', [
        cardId,
        _iso(occurredAt),
        slotId,
      ]);
      if (current != null) {
        _insertEvent(
          CardStored(
            id: storedEventId,
            cardId: current.id,
            fromSlotId: slotId,
            occurredAt: occurredAt,
          ),
        );
      }
      if (replacement != null) {
        _insertEvent(
          CardMoved(
            id: movedEventId,
            cardId: replacement.id,
            toSlotId: slotId,
            occurredAt: occurredAt,
          ),
        );
      }
      _db.execute('COMMIT');
      return const Ok(null);
    } on _AssetConstraint catch (error) {
      _rollback();
      return Err(StoreError(error.message));
    } on SqliteException catch (error) {
      _rollback();
      return Err(StoreError(error.message));
    } catch (error) {
      _rollback();
      return Err(StoreError(error.toString()));
    }
  }

  Result<void> moveCard({
    required String cardId,
    required String? toSlotId,
    required String eventId,
    required DateTime occurredAt,
    String? note,
  }) {
    try {
      _db.execute('BEGIN IMMEDIATE');
      final cardRows = _db.select('SELECT * FROM cards WHERE id = ?', [cardId]);
      if (cardRows.isEmpty) throw const _AssetConstraint('卡片不存在');
      final card = _cardFromRow(cardRows.single);
      final fromRows = _db.select('SELECT * FROM slots WHERE card_id = ?', [
        cardId,
      ]);
      final from = fromRows.isEmpty ? null : _slotFromRow(fromRows.single);
      SimSlot? to;
      if (toSlotId != null) {
        final targetRows = _db.select('SELECT * FROM slots WHERE id = ?', [
          toSlotId,
        ]);
        if (targetRows.isEmpty) throw const _AssetConstraint('目标卡槽不存在');
        to = _slotFromRow(targetRows.single);
        if (to.cardId != null && to.cardId != cardId) {
          throw const _AssetConstraint('目标卡槽已有卡片');
        }
      }
      if (to == null && card is EmbeddedEuiccCard) {
        throw const _AssetConstraint('内置 eUICC 不能移出所属设备');
      }
      if (to != null) {
        final placementError = AssetRules.placementError(card, to);
        if (placementError != null) throw _AssetConstraint(placementError);
      }
      if (from?.id == to?.id) {
        _db.execute('COMMIT');
        return const Ok(null);
      }
      if (from != null) {
        _db.execute(
          'UPDATE slots SET card_id = NULL, updated_at = ? WHERE id = ?',
          [_iso(occurredAt), from.id],
        );
      }
      if (to != null) {
        _db.execute(
          'UPDATE slots SET card_id = ?, updated_at = ? WHERE id = ?',
          [cardId, _iso(occurredAt), to.id],
        );
        _insertEvent(
          CardMoved(
            id: eventId,
            cardId: cardId,
            fromSlotId: from?.id,
            toSlotId: to.id,
            occurredAt: occurredAt,
            note: note,
          ),
        );
      } else if (from != null) {
        _insertEvent(
          CardStored(
            id: eventId,
            cardId: cardId,
            fromSlotId: from.id,
            occurredAt: occurredAt,
            note: note,
          ),
        );
      }
      _db.execute('COMMIT');
      return const Ok(null);
    } on _AssetConstraint catch (error) {
      _rollback();
      return Err(StoreError(error.message));
    } on SqliteException catch (error) {
      _rollback();
      return Err(StoreError(error.message));
    } catch (error) {
      _rollback();
      return Err(StoreError(error.toString()));
    }
  }

  Result<void> moveProfile({
    required String profileId,
    required String toEidId,
    required String eventId,
    required DateTime occurredAt,
    String? note,
  }) {
    try {
      _db.execute('BEGIN IMMEDIATE');
      final rows = _db.select('SELECT * FROM profiles WHERE id = ?', [
        profileId,
      ]);
      if (rows.isEmpty) throw const _AssetConstraint('Profile 不存在');
      final profile = _profileFromRow(rows.single);
      if (_db.select('SELECT id FROM eids WHERE id = ?', [toEidId]).isEmpty) {
        throw const _AssetConstraint('目标 EID 不存在');
      }
      if (profile.eidId == toEidId) {
        _db.execute('COMMIT');
        return const Ok(null);
      }
      _db.execute(
        'UPDATE profiles SET eid_id = ?, updated_at = ? WHERE id = ?',
        [toEidId, _iso(occurredAt), profileId],
      );
      _insertEvent(
        ProfileMoved(
          id: eventId,
          profileId: profileId,
          fromEidId: profile.eidId,
          toEidId: toEidId,
          occurredAt: occurredAt,
          note: note,
        ),
      );
      _db.execute('COMMIT');
      return const Ok(null);
    } on _AssetConstraint catch (error) {
      _rollback();
      return Err(StoreError(error.message));
    } on SqliteException catch (error) {
      _rollback();
      return Err(StoreError(error.message));
    } catch (error) {
      _rollback();
      return Err(StoreError(error.toString()));
    }
  }

  Result<void> wipeProfile({
    required String profileId,
    required String eventId,
    required DateTime occurredAt,
    String? note,
  }) {
    try {
      _db.execute('BEGIN IMMEDIATE');
      final rows = _db.select('SELECT * FROM profiles WHERE id = ?', [
        profileId,
      ]);
      if (rows.isEmpty) throw const _AssetConstraint('Profile 不存在');
      final profile = _profileFromRow(rows.single);
      _db.execute('DELETE FROM profiles WHERE id = ?', [profileId]);
      _writeTombstone('profile', profileId, occurredAt);
      _insertEvent(
        ProfileWiped(
          id: eventId,
          profileId: profileId,
          fromEidId: profile.eidId,
          occurredAt: occurredAt,
          note: note,
        ),
      );
      _db.execute('COMMIT');
      return const Ok(null);
    } on _AssetConstraint catch (error) {
      _rollback();
      return Err(StoreError(error.message));
    } on SqliteException catch (error) {
      _rollback();
      return Err(StoreError(error.message));
    } catch (error) {
      _rollback();
      return Err(StoreError(error.toString()));
    }
  }

  Result<void> _guard(void Function() operation) {
    try {
      operation();
      return const Ok(null);
    } on _AssetConstraint catch (error) {
      return Err(StoreError(error.message));
    } on SqliteException catch (error) {
      return Err(StoreError(error.message));
    } catch (error) {
      return Err(StoreError(error.toString()));
    }
  }

  Result<void> _transactionGuard(void Function() operation) {
    try {
      _db.execute('BEGIN IMMEDIATE');
      operation();
      _db.execute('COMMIT');
      return const Ok(null);
    } on _AssetConstraint catch (error) {
      _rollback();
      return Err(StoreError(error.message));
    } on SqliteException catch (error) {
      _rollback();
      return Err(StoreError(error.message));
    } catch (error) {
      _rollback();
      return Err(StoreError(error.toString()));
    }
  }

  void _insertEvent(AssetEvent event) {
    String? cardId;
    String? profileId;
    String? fromSlotId;
    String? toSlotId;
    String? fromEidId;
    String? toEidId;
    switch (event) {
      case CardMoved():
        cardId = event.cardId;
        fromSlotId = event.fromSlotId;
        toSlotId = event.toSlotId;
      case CardStored():
        cardId = event.cardId;
        fromSlotId = event.fromSlotId;
      case ProfileMoved():
        profileId = event.profileId;
        fromEidId = event.fromEidId;
        toEidId = event.toEidId;
      case ProfileWiped():
        profileId = event.profileId;
        fromEidId = event.fromEidId;
    }
    _db.execute(
      '''INSERT OR IGNORE INTO asset_events (
  id, type, card_id, profile_id, from_slot_id, to_slot_id,
  from_eid_id, to_eid_id, occurred_at, note
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        event.id,
        event.type.name,
        cardId,
        profileId,
        fromSlotId,
        toSlotId,
        fromEidId,
        toEidId,
        _iso(event.occurredAt),
        event.note,
      ],
    );
  }

  void _rollback() {
    try {
      _db.execute('ROLLBACK');
    } catch (_) {}
  }

  void _writeTombstone(String type, String id, DateTime deletedAtUtc) {
    _db.execute(
      '''INSERT INTO sync_tombstones (entity_type, entity_id, deleted_at)
VALUES (?, ?, ?)
ON CONFLICT(entity_type, entity_id) DO UPDATE SET
  deleted_at = excluded.deleted_at''',
      [type, id, _iso(deletedAtUtc)],
    );
  }

  static void _requireOk(Result<void> result) {
    if (result case Err(failure: StoreError(message: final message))) {
      throw _AssetConstraint(message);
    }
    if (result case Err(failure: final failure)) {
      throw _AssetConstraint(failure.toString());
    }
  }
}

DeviceAsset _deviceFromRow(Row row) => DeviceAsset(
  id: row['id'] as String,
  name: row['name'] as String,
  kind: DeviceKind.values.byName(row['kind'] as String),
  brand: row['brand'] as String?,
  note: row['note'] as String?,
  region: row['region'] as String?,
  usage: row['usage'] as String?,
  simCapability: SimCapability.values.byName(row['sim_capability'] as String),
  supportsSaRoaming: row['supports_sa_roaming'] == 1,
  orderIndex: row['order_index'] as int,
  createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
  updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
);

SimSlot _slotFromRow(Row row) => SimSlot(
  id: row['id'] as String,
  deviceId: row['device_id'] as String,
  label: row['label'] as String,
  kind: SimSlotKind.values.byName(row['kind'] as String),
  position: row['position'] as int,
  cardId: row['card_id'] as String?,
  createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
  updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
);

SimCard _cardFromRow(Row row) {
  final common = (
    id: row['id'] as String,
    name: row['name'] as String,
    note: row['note'] as String?,
    presetId: row['preset_id'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
    updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
  );
  return switch (SimCardKind.values.byName(row['kind'] as String)) {
    SimCardKind.physicalSim => PhysicalSimCard(
      id: common.id,
      name: common.name,
      note: common.note,
      presetId: common.presetId,
      physicalIccid: row['physical_iccid'] as String,
      createdAt: common.createdAt,
      updatedAt: common.updatedAt,
    ),
    SimCardKind.removableEuicc => RemovableEuiccCard(
      id: common.id,
      name: common.name,
      note: common.note,
      presetId: common.presetId,
      physicalIccid: row['physical_iccid'] as String?,
      createdAt: common.createdAt,
      updatedAt: common.updatedAt,
    ),
    SimCardKind.embeddedEuicc => EmbeddedEuiccCard(
      id: common.id,
      name: common.name,
      note: common.note,
      presetId: common.presetId,
      embeddedDeviceId: row['embedded_device_id'] as String,
      createdAt: common.createdAt,
      updatedAt: common.updatedAt,
    ),
  };
}

Euicc _eidFromRow(Row row) => Euicc(
  id: row['id'] as String,
  cardId: row['card_id'] as String,
  value: row['value'] as String,
  label: row['label'] as String?,
  createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
  updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
);

EsimProfile _profileFromRow(Row row) => EsimProfile(
  id: row['id'] as String,
  eidId: row['eid_id'] as String,
  iccid: row['iccid'] as String?,
  operatorName: row['operator_name'] as String?,
  nickname: row['nickname'] as String?,
  subscriptionId: row['subscription_id'] as String?,
  isPinned: row['is_pinned'] == 1,
  createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
  updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
);

AssetEvent _eventFromRow(Row row) {
  final id = row['id'] as String;
  final occurredAt = DateTime.parse(row['occurred_at'] as String).toUtc();
  final note = row['note'] as String?;
  return switch (AssetEventType.values.byName(row['type'] as String)) {
    AssetEventType.cardMoved => CardMoved(
      id: id,
      cardId: row['card_id'] as String,
      fromSlotId: row['from_slot_id'] as String?,
      toSlotId: row['to_slot_id'] as String,
      occurredAt: occurredAt,
      note: note,
    ),
    AssetEventType.cardStored => CardStored(
      id: id,
      cardId: row['card_id'] as String,
      fromSlotId: row['from_slot_id'] as String,
      occurredAt: occurredAt,
      note: note,
    ),
    AssetEventType.profileMoved => ProfileMoved(
      id: id,
      profileId: row['profile_id'] as String,
      fromEidId: row['from_eid_id'] as String,
      toEidId: row['to_eid_id'] as String,
      occurredAt: occurredAt,
      note: note,
    ),
    AssetEventType.profileWiped => ProfileWiped(
      id: id,
      profileId: row['profile_id'] as String,
      fromEidId: row['from_eid_id'] as String,
      occurredAt: occurredAt,
      note: note,
    ),
  };
}

String _iso(DateTime value) => value.toUtc().toIso8601String();

String? _nullable(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

class _AssetConstraint implements Exception {
  const _AssetConstraint(this.message);

  final String message;
}
