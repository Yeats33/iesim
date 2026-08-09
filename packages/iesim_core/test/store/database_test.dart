import 'dart:io';

import 'package:iesim_core/src/store/database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  group('openIesimStore / createSchema', () {
    test('新的开发基线一次建立全部业务表', () {
      final db = openIesimStore(':memory:');
      final names = db
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .map((row) => row['name'] as String)
          .toSet();
      expect(
        names,
        containsAll([
          'subscriptions',
          'activity_records',
          'devices',
          'slots',
          'cards',
          'eids',
          'profiles',
          'asset_events',
          'sync_tombstones',
          'sync_state',
          'sync_conflicts',
          'scheduled_reminders',
        ]),
      );
      db.close();
    });

    test('内部数据库从当前最佳结构重新编号为 v1', () {
      final db = openIesimStore(':memory:');
      expect(
        db.select('PRAGMA user_version').single.values.first,
        iesimDatabaseSchemaVersion,
      );
      final columns = db
          .select('PRAGMA table_info(subscriptions)')
          .map((row) => row['name']);
      expect(
        columns,
        containsAll([
          'keepalive_policy_json',
          'mcc',
          'mnc',
          'apn',
          'profile_name',
          'profile_class_code',
          'installed_profile_size_bytes',
        ]),
      );
      expect(
        columns,
        isNot(
          containsAll([
            'smdp_address',
            'activation_code',
            'activation_extra',
            'confirmation_code',
          ]),
        ),
      );
      db.close();
    });

    test('高频列表排序使用专用索引', () {
      final db = openIesimStore(':memory:');
      final subscriptionIndexes = db
          .select('PRAGMA index_list(subscriptions)')
          .map((row) => row['name']);
      final activityIndexes = db
          .select('PRAGMA index_list(activity_records)')
          .map((row) => row['name']);

      expect(subscriptionIndexes, contains('idx_subscriptions_order'));
      expect(activityIndexes, contains('idx_activity_sub_occ'));
      expect(activityIndexes, contains('idx_activity_occurred'));
      final subscriptionPlan = db
          .select(
            'EXPLAIN QUERY PLAN SELECT * FROM subscriptions '
            'ORDER BY order_index ASC, created_at ASC',
          )
          .map((row) => row['detail'].toString())
          .join(' ');
      final activityPlan = db
          .select(
            'EXPLAIN QUERY PLAN SELECT * FROM activity_records '
            'ORDER BY occurred_at ASC, id ASC',
          )
          .map((row) => row['detail'].toString())
          .join(' ');
      expect(subscriptionPlan, contains('idx_subscriptions_order'));
      expect(activityPlan, contains('idx_activity_occurred'));
      db.close();
    });

    test('开发期旧编号直接清空并重建，不执行迁移', () {
      final db = sqlite3.openInMemory();
      db.execute('''
CREATE TABLE subscriptions (id TEXT PRIMARY KEY, number TEXT NOT NULL);
INSERT INTO subscriptions (id, number) VALUES ('old', '10086');
PRAGMA user_version = 8;
''');

      createSchema(db);

      expect(db.select('SELECT * FROM subscriptions'), isEmpty);
      expect(
        db.select('PRAGMA user_version').single.values.first,
        iesimDatabaseSchemaVersion,
      );
      expect(
        db.select('PRAGMA table_info(subscriptions)').map((row) => row['name']),
        containsAll(['mcc', 'mnc', 'apn', 'keepalive_policy_json']),
      );
      db.close();
    });

    test('同为 v1 但结构属于早期开发版时也直接重建', () {
      final db = sqlite3.openInMemory();
      db.execute('''
CREATE TABLE subscriptions (id TEXT PRIMARY KEY, number TEXT NOT NULL);
INSERT INTO subscriptions (id, number) VALUES ('old-v1', '10010');
PRAGMA user_version = 1;
''');

      createSchema(db);

      expect(db.select('SELECT * FROM subscriptions'), isEmpty);
      expect(
        db.select('PRAGMA table_info(profiles)').map((row) => row['name']),
        containsAll([
          'nickname',
          'nekoko_tags_raw',
          'subscription_id',
          'updated_at',
        ]),
      );
      db.close();
    });

    test('createSchema 对当前 v1 幂等，不会清空有效数据', () {
      final db = openIesimStore(':memory:');
      db.execute(
        "INSERT INTO subscriptions "
        "(id, number, keepalive_required, keepalive_confidence, "
        "plan_is_long_term, tags_json, time_zone_id, created_at, updated_at) "
        "VALUES ('s1', '', 0, 'confirmed', 0, '[]', 'UTC', "
        "'2026-08-08T00:00:00.000Z', '2026-08-08T00:00:00.000Z')",
      );

      createSchema(db);

      expect(db.select('SELECT id FROM subscriptions').single['id'], 's1');
      db.close();
    });

    test('外键约束开启：孤儿动作记录被拒绝', () {
      final db = openIesimStore(':memory:');
      expect(
        () => db.execute(
          "INSERT INTO activity_records "
          "(id, subscription_id, type, occurred_at, updated_at) "
          "VALUES ('a', 'no-such-sub', 'topUp', "
          "'2026-08-07T00:00:00.000Z', '2026-08-07T00:00:00.000Z')",
        ),
        throwsA(isA<SqliteException>()),
      );
      db.close();
    });

    test('当前 v1 文件库关闭重开后数据仍在', () {
      final dir = Directory.systemTemp.createTempSync('iesim_store_test');
      final path = '${dir.path}/store.sqlite';
      try {
        var db = openIesimStore(path);
        db.execute(
          "INSERT INTO subscriptions "
          "(id, number, keepalive_required, keepalive_confidence, "
          "plan_is_long_term, tags_json, time_zone_id, created_at, updated_at) "
          "VALUES ('s1', '13800000000', 0, 'confirmed', 0, '[]', "
          "'Asia/Shanghai', '2026-08-07T00:00:00.000Z', "
          "'2026-08-07T00:00:00.000Z')",
        );
        db.close();

        db = openIesimStore(path);
        expect(db.select('SELECT id FROM subscriptions').single['id'], 's1');
        db.close();
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
