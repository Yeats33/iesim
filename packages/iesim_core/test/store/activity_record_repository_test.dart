import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:iesim_core/src/model/activity_record.dart';
import 'package:iesim_core/src/model/keep_alive.dart';
import 'package:iesim_core/src/model/plan.dart';
import 'package:iesim_core/src/model/subscription.dart';
import 'package:iesim_core/src/result.dart';
import 'package:iesim_core/src/store/activity_record_repository.dart';
import 'package:iesim_core/src/store/database.dart';
import 'package:iesim_core/src/store/subscription_repository.dart';
import 'package:iesim_core/src/value/money.dart';
import 'package:iesim_core/src/value/phone_number.dart';

void main() {
  late Database db;
  late ActivityRecordRepository repo;
  late SubscriptionRepository subs;

  setUp(() {
    db = openIesimStore(':memory:');
    repo = ActivityRecordRepository(db);
    subs = SubscriptionRepository(db);
  });

  tearDown(() => db.close());

  void seedSubscription(String id) {
    subs.upsert(Subscription(
      id: id,
      number: PhoneNumber('13800000000'),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'Asia/Shanghai',
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
    ));
  }

  ActivityRecord record(String id, String subId, DateTime at) =>
      ActivityRecord(
        id: id,
        subscriptionId: subId,
        type: ActivityType.topUp,
        occurredAt: at,
        amount: const Money(minorUnits: 5000, currencyCode: 'CNY'),
      );

  group('ActivityRecordRepository', () {
    test('append 后 listBySubscription 按时间升序返回', () {
      seedSubscription('sub-1');
      repo.append(record('a', 'sub-1', DateTime.utc(2026, 8, 3)));
      repo.append(record('b', 'sub-1', DateTime.utc(2026, 8, 1)));
      repo.append(record('c', 'sub-1', DateTime.utc(2026, 8, 2)));
      final got = (repo.listBySubscription('sub-1') as Ok<List<ActivityRecord>>)
          .value
          .map((r) => r.id)
          .toList();
      expect(got, equals(['b', 'c', 'a']));
    });

    test('listAll 跨订阅返回全部记录', () {
      seedSubscription('sub-1');
      seedSubscription('sub-2');
      repo.append(record('a', 'sub-1', DateTime.utc(2026, 8, 1)));
      repo.append(record('b', 'sub-2', DateTime.utc(2026, 8, 2)));
      expect((repo.listAll() as Ok<List<ActivityRecord>>).value, hasLength(2));
    });

    test('字段往返一致', () {
      seedSubscription('sub-1');
      repo.append(record('a', 'sub-1', DateTime.utc(2026, 8, 1)));
      final got = (repo.listBySubscription('sub-1') as Ok<List<ActivityRecord>>)
          .value
          .single;
      expect(
        got,
        equals(record('a', 'sub-1', DateTime.utc(2026, 8, 1))),
      );
      expect(got.amount, equals(const Money(minorUnits: 5000, currencyCode: 'CNY')));
    });

    test('不存在的订阅 append 返回 Err(StoreError)（外键约束）', () {
      final result = repo.append(record('a', 'no-such-sub', DateTime.utc(2026, 8, 1)));
      expect(result, isA<Err<void>>());
      expect((result as Err).failure, isA<StoreError>());
    });

    test('删除订阅后其动作记录级联删除', () {
      seedSubscription('sub-1');
      repo.append(record('a', 'sub-1', DateTime.utc(2026, 8, 1)));
      subs.delete('sub-1');
      expect((repo.listBySubscription('sub-1') as Ok<List<ActivityRecord>>).value,
          isEmpty);
    });

    test('数据库关闭后操作返回 Err(StoreError)', () {
      db.close();
      expect(repo.listAll(), isA<Err<List<ActivityRecord>>>());
    });
  });
}
