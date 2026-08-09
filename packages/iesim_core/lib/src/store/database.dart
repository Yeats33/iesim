import 'package:sqlite3/sqlite3.dart';

const iesimDatabaseSchemaVersion = 1;

/// 打开 ieSIM 本地数据库并建立当前开发基线。
///
/// alpha 阶段不迁移开发期数据库。检测到旧编号或旧结构时直接清空旧 schema，
/// 再按当前最佳结构建立全新的 v1。
Database openIesimStore(String path) {
  final db = sqlite3.open(path);
  db.execute('PRAGMA foreign_keys = ON');
  createSchema(db);
  return db;
}

/// 幂等建立当前完整 schema；不承担未发布开发版本的数据兼容。
void createSchema(Database db) {
  final version = db.select('PRAGMA user_version').single.values.first as int;
  final hasExistingSchema = db
      .select(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name IN ('subscriptions', 'activity_records', 'devices', 'slots', "
        "'cards', 'eids', 'profiles', 'asset_events')",
      )
      .isNotEmpty;
  final current =
      version == iesimDatabaseSchemaVersion && _matchesCurrentSchema(db);
  if (hasExistingSchema && !current) _dropDevelopmentSchema(db);

  db.execute('''
CREATE TABLE IF NOT EXISTS subscriptions (
  id TEXT PRIMARY KEY,
  iccid TEXT UNIQUE,
  number TEXT NOT NULL,
  operator TEXT,
  profile_stage TEXT NOT NULL DEFAULT 'active',
  profile_device_state TEXT NOT NULL DEFAULT 'unknown',
  activation_deadline TEXT,
  activation_requirements TEXT,
  service_expires_at TEXT,
  profile_activated_at TEXT,
  profile_archived_at TEXT,
  profile_archive_reason TEXT,
  profile_name TEXT,
  profile_class_code INTEGER,
  declared_profile_size_bytes INTEGER,
  installed_profile_size_bytes INTEGER,
  gid1 TEXT,
  gid2 TEXT,
  country_code TEXT,
  country_name TEXT,
  mcc TEXT,
  mnc TEXT,
  apn TEXT,
  secondary_phone_number TEXT,
  secondary_phone_enabled INTEGER NOT NULL DEFAULT 0,
  activation_date TEXT,
  current_balance_minor INTEGER,
  current_balance_currency TEXT,
  affiliate_offers_json TEXT NOT NULL DEFAULT '[]',
  app_bindings_json TEXT NOT NULL DEFAULT '[]',
  auto_top_up_enabled INTEGER NOT NULL DEFAULT 0,
  top_up_cycle_unit TEXT,
  renewal_interval_value INTEGER,
  renewal_unit TEXT,
  transaction_notes TEXT,
  carrier_app_name TEXT,
  carrier_app_store_url TEXT,
  carrier_app_icon_url TEXT,
  keep_alive_mode_raw TEXT,
  order_index INTEGER NOT NULL DEFAULT 0,
  is_dormant INTEGER NOT NULL DEFAULT 0,
  is_pinned INTEGER NOT NULL DEFAULT 0,
  plan_name TEXT,
  plan_cycle_minor INTEGER,
  plan_cycle_currency TEXT,
  plan_cycle_days INTEGER,
  plan_start TEXT,
  plan_expiry TEXT,
  plan_is_long_term INTEGER NOT NULL DEFAULT 0,
  keepalive_required INTEGER NOT NULL,
  keepalive_cycle_days INTEGER,
  keepalive_last_activity_at TEXT,
  keepalive_confidence TEXT NOT NULL,
  keepalive_policy_json TEXT NOT NULL DEFAULT '{}',
  tags_json TEXT NOT NULL DEFAULT '[]',
  appearance_flag TEXT,
  appearance_color_hex TEXT,
  appearance_background_asset TEXT,
  appearance_website_url TEXT,
  appearance_custom_prompt TEXT,
  time_zone_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_subscriptions_order
  ON subscriptions(order_index, created_at);

CREATE TABLE IF NOT EXISTS activity_records (
  id TEXT PRIMARY KEY,
  subscription_id TEXT NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  amount_minor INTEGER,
  amount_currency TEXT,
  balance_after_minor INTEGER,
  balance_after_currency TEXT,
  note TEXT
);
CREATE INDEX IF NOT EXISTS idx_activity_sub_occ
  ON activity_records(subscription_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_activity_occurred
  ON activity_records(occurred_at, id);

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL DEFAULT 'phone',
  brand TEXT,
  note TEXT,
  region TEXT,
  usage TEXT,
  sim_capability TEXT NOT NULL DEFAULT 'unknown',
  supports_sa_roaming INTEGER NOT NULL DEFAULT 0,
  order_index INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS cards (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL,
  physical_iccid TEXT,
  note TEXT,
  preset_id TEXT,
  embedded_device_id TEXT REFERENCES devices(id),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS slots (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  label TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL DEFAULT 'physical',
  position INTEGER NOT NULL DEFAULT 0,
  card_id TEXT UNIQUE REFERENCES cards(id) ON DELETE SET NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS eids (
  id TEXT PRIMARY KEY,
  card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
  value TEXT NOT NULL UNIQUE,
  label TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS profiles (
  id TEXT PRIMARY KEY,
  eid_id TEXT NOT NULL REFERENCES eids(id) ON DELETE CASCADE,
  iccid TEXT UNIQUE,
  operator_name TEXT,
  nickname TEXT,
  nekoko_tags_raw TEXT,
  subscription_id TEXT UNIQUE REFERENCES subscriptions(id) ON DELETE SET NULL,
  is_pinned INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS asset_events (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  card_id TEXT,
  profile_id TEXT,
  from_slot_id TEXT,
  to_slot_id TEXT,
  from_eid_id TEXT,
  to_eid_id TEXT,
  occurred_at TEXT NOT NULL,
  note TEXT
);
CREATE INDEX IF NOT EXISTS idx_slots_device_position
  ON slots(device_id, position);
CREATE INDEX IF NOT EXISTS idx_eids_card ON eids(card_id);
CREATE INDEX IF NOT EXISTS idx_profiles_eid ON profiles(eid_id);
CREATE INDEX IF NOT EXISTS idx_asset_events_occurred
  ON asset_events(occurred_at DESC);

CREATE TABLE IF NOT EXISTS sync_tombstones (
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  deleted_at TEXT NOT NULL,
  PRIMARY KEY (entity_type, entity_id)
);
CREATE TABLE IF NOT EXISTS sync_state (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  etag TEXT,
  last_synced_at TEXT
);
INSERT OR IGNORE INTO sync_state (singleton) VALUES (1);
CREATE TABLE IF NOT EXISTS sync_conflicts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  local_updated_at TEXT NOT NULL,
  remote_updated_at TEXT NOT NULL,
  winner TEXT NOT NULL,
  recorded_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sync_conflicts_recorded
  ON sync_conflicts(recorded_at DESC);

CREATE TABLE IF NOT EXISTS scheduled_reminders (
  stable_key TEXT PRIMARY KEY,
  subscription_id TEXT NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  slot TEXT NOT NULL,
  fire_at TEXT NOT NULL,
  deadline TEXT NOT NULL,
  days_before INTEGER NOT NULL,
  inferred INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_scheduled_reminders_subscription
  ON scheduled_reminders(subscription_id);

PRAGMA user_version = 1;
''');
}

bool _matchesCurrentSchema(Database db) {
  const expected = <String, Set<String>>{
    'subscriptions': {
      'id',
      'iccid',
      'number',
      'operator',
      'profile_stage',
      'profile_device_state',
      'activation_deadline',
      'activation_requirements',
      'service_expires_at',
      'profile_activated_at',
      'profile_archived_at',
      'profile_archive_reason',
      'profile_name',
      'profile_class_code',
      'declared_profile_size_bytes',
      'installed_profile_size_bytes',
      'gid1',
      'gid2',
      'country_code',
      'country_name',
      'mcc',
      'mnc',
      'apn',
      'secondary_phone_number',
      'secondary_phone_enabled',
      'activation_date',
      'current_balance_minor',
      'current_balance_currency',
      'affiliate_offers_json',
      'app_bindings_json',
      'auto_top_up_enabled',
      'top_up_cycle_unit',
      'renewal_interval_value',
      'renewal_unit',
      'transaction_notes',
      'carrier_app_name',
      'carrier_app_store_url',
      'carrier_app_icon_url',
      'keep_alive_mode_raw',
      'order_index',
      'is_dormant',
      'is_pinned',
      'plan_name',
      'plan_cycle_minor',
      'plan_cycle_currency',
      'plan_cycle_days',
      'plan_start',
      'plan_expiry',
      'plan_is_long_term',
      'keepalive_required',
      'keepalive_cycle_days',
      'keepalive_last_activity_at',
      'keepalive_confidence',
      'keepalive_policy_json',
      'tags_json',
      'appearance_flag',
      'appearance_color_hex',
      'appearance_background_asset',
      'appearance_website_url',
      'appearance_custom_prompt',
      'time_zone_id',
      'created_at',
      'updated_at',
    },
    'activity_records': {
      'id',
      'subscription_id',
      'type',
      'occurred_at',
      'updated_at',
      'amount_minor',
      'amount_currency',
      'balance_after_minor',
      'balance_after_currency',
      'note',
    },
    'devices': {
      'id',
      'name',
      'kind',
      'brand',
      'note',
      'region',
      'usage',
      'sim_capability',
      'supports_sa_roaming',
      'order_index',
      'created_at',
      'updated_at',
    },
    'cards': {
      'id',
      'name',
      'kind',
      'physical_iccid',
      'note',
      'preset_id',
      'embedded_device_id',
      'created_at',
      'updated_at',
    },
    'slots': {
      'id',
      'device_id',
      'label',
      'kind',
      'position',
      'card_id',
      'created_at',
      'updated_at',
    },
    'eids': {'id', 'card_id', 'value', 'label', 'created_at', 'updated_at'},
    'profiles': {
      'id',
      'eid_id',
      'iccid',
      'operator_name',
      'nickname',
      'nekoko_tags_raw',
      'subscription_id',
      'is_pinned',
      'created_at',
      'updated_at',
    },
    'asset_events': {
      'id',
      'type',
      'card_id',
      'profile_id',
      'from_slot_id',
      'to_slot_id',
      'from_eid_id',
      'to_eid_id',
      'occurred_at',
      'note',
    },
    'sync_tombstones': {'entity_type', 'entity_id', 'deleted_at'},
    'sync_state': {'singleton', 'etag', 'last_synced_at'},
    'sync_conflicts': {
      'id',
      'entity_type',
      'entity_id',
      'local_updated_at',
      'remote_updated_at',
      'winner',
      'recorded_at',
    },
    'scheduled_reminders': {
      'stable_key',
      'subscription_id',
      'kind',
      'slot',
      'fire_at',
      'deadline',
      'days_before',
      'inferred',
    },
  };
  for (final table in expected.entries) {
    final columns = db
        .select('PRAGMA table_info(${table.key})')
        .map((row) => row['name'] as String)
        .toSet();
    if (!_sameSet(columns, table.value)) return false;
  }
  return true;
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

void _dropDevelopmentSchema(Database db) {
  db.execute('''
DROP TABLE IF EXISTS scheduled_reminders;
DROP TABLE IF EXISTS sync_conflicts;
DROP TABLE IF EXISTS sync_state;
DROP TABLE IF EXISTS sync_tombstones;
DROP TABLE IF EXISTS asset_events;
DROP TABLE IF EXISTS profiles;
DROP TABLE IF EXISTS profiles_before_v5;
DROP TABLE IF EXISTS eids;
DROP TABLE IF EXISTS slots;
DROP TABLE IF EXISTS cards;
DROP TABLE IF EXISTS devices;
DROP TABLE IF EXISTS activity_records;
DROP TABLE IF EXISTS subscriptions;
''');
}
