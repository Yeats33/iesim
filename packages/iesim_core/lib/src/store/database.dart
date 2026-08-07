import 'package:sqlite3/sqlite3.dart';

/// 打开 iesim 存储数据库并应用 schema。
///
/// [path] 为 SQLite 文件路径；测试传 `:memory:` 获得内存库。
/// 每次打开均开启外键约束（SQLite 默认关闭）并幂等建表。
Database openIesimStore(String path) {
  final db = sqlite3.open(path);
  db.execute('PRAGMA foreign_keys = ON');
  createSchema(db);
  return db;
}

/// 幂等建表。
///
/// schema 版本记录于 `PRAGMA user_version`，后续迁移（计划 4 起）
/// 以此为锚点递增。
void createSchema(Database db) {
  db.execute('''
CREATE TABLE IF NOT EXISTS subscriptions (
  id TEXT PRIMARY KEY,
  iccid TEXT UNIQUE,
  number TEXT NOT NULL,
  operator TEXT,
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
  keepalive_confidence TEXT NOT NULL DEFAULT 'confirmed',
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

CREATE TABLE IF NOT EXISTS activity_records (
  id TEXT PRIMARY KEY,
  subscription_id TEXT NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  amount_minor INTEGER,
  amount_currency TEXT
);
CREATE INDEX IF NOT EXISTS idx_activity_sub_occ
  ON activity_records(subscription_id, occurred_at);

-- 资产域（v1 仅建表、不开放 UI，spec §9；类型约束由 v2 Dart 类型系统承担）
CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL DEFAULT 'phone',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS slots (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES devices(id),
  label TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL DEFAULT 'physical',
  position INTEGER NOT NULL DEFAULT 0,
  card_id TEXT UNIQUE REFERENCES cards(id),
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS cards (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  physical_iccid TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS eids (
  id TEXT PRIMARY KEY,
  card_id TEXT NOT NULL REFERENCES cards(id),
  value TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS profiles (
  id TEXT PRIMARY KEY,
  eid_id TEXT NOT NULL REFERENCES eids(id),
  iccid TEXT NOT NULL UNIQUE,
  operator_name TEXT,
  created_at TEXT NOT NULL
);

PRAGMA user_version = 1;
''');
}
