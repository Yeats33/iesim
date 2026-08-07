import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:iesim_core/src/store/database.dart';

void main() {
  group('openIesimStore / createSchema', () {
    test('内存库建表后七张业务表齐备', () {
      final db = openIesimStore(':memory:');
      final names = db
          .select("SELECT name FROM sqlite_master WHERE type='table' "
              "AND name NOT LIKE 'sqlite_%'")
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
        ]),
      );
      db.close();
    });

    test('user_version 为 1，为未来迁移留锚点', () {
      final db = openIesimStore(':memory:');
      expect(db.select('PRAGMA user_version').single.values.first, equals(1));
      db.close();
    });

    test('createSchema 幂等，重复调用不报错', () {
      final db = openIesimStore(':memory:');
      createSchema(db);
      createSchema(db);
      expect(
        db.select("SELECT COUNT(*) FROM sqlite_master WHERE type='table'"),
        isNotEmpty,
      );
      db.close();
    });

    test('外键约束开启：孤儿动作记录被拒绝', () {
      final db = openIesimStore(':memory:');
      expect(
        () => db.execute(
          "INSERT INTO activity_records (id, subscription_id, type, occurred_at) "
          "VALUES ('a', 'no-such-sub', 'topUp', '2026-08-07T00:00:00.000Z')",
        ),
        throwsA(isA<SqliteException>()),
      );
      db.close();
    });

    test('文件库可持久化：关闭重开后数据仍在', () {
      final dir = Directory.systemTemp.createTempSync('iesim_store_test');
      final path = '${dir.path}/store.sqlite';
      try {
        var db = openIesimStore(path);
        db.execute(
          "INSERT INTO subscriptions "
          "(id, number, keepalive_required, keepalive_confidence, "
          " plan_is_long_term, tags_json, time_zone_id, created_at, updated_at) "
          "VALUES ('s1', '13800000000', 0, 'confirmed', 0, '[]', "
          " 'Asia/Shanghai', '2026-08-07T00:00:00.000Z', '2026-08-07T00:00:00.000Z')",
        );
        db.close();

        db = openIesimStore(path);
        final rows = db.select('SELECT id FROM subscriptions');
        expect(rows.single['id'], equals('s1'));
        db.close();
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
