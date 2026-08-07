import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:iesim_core/src/model/appearance.dart';
import 'package:iesim_core/src/model/keep_alive.dart';
import 'package:iesim_core/src/model/plan.dart';
import 'package:iesim_core/src/model/subscription.dart';
import 'package:iesim_core/src/result.dart';
import 'package:iesim_core/src/store/database.dart';
import 'package:iesim_core/src/store/subscription_repository.dart';
import 'package:iesim_core/src/value/money.dart';
import 'package:iesim_core/src/value/phone_number.dart';

void main() {
  late Database db;
  late SubscriptionRepository repo;

  setUp(() {
    db = openIesimStore(':memory:');
    repo = SubscriptionRepository(db);
  });

  tearDown(() => db.close());

  Subscription full() => Subscription(
        id: 'sub-1',
        iccid: '89000000000000000001',
        number: PhoneNumber('+8613800000000'),
        operator: '中国移动',
        plan: Plan(
          name: '畅享 5G',
          cyclePrice: const Money(minorUnits: 2900, currencyCode: 'CNY'),
          cycleDays: 30,
          startDate: DateTime.utc(2026, 8, 1),
          expiryDate: DateTime.utc(2026, 8, 31),
          isLongTerm: false,
        ),
        keepAlive: KeepAlive(
          required: true,
          cycleDays: 90,
          lastActivityAt: DateTime.utc(2026, 7, 7, 16, 0),
          confidence: DataConfidence.inferred,
        ),
        tags: const ['主力号', 'eSIM'],
        appearance: const Appearance(flag: '🇨🇳', cardColorHex: '#0a84ff'),
        timeZoneId: 'Asia/Shanghai',
        createdAt: DateTime.utc(2026, 8, 1, 4, 0),
        updatedAt: DateTime.utc(2026, 8, 7, 4, 0),
      );

  group('SubscriptionRepository', () {
    test('空库 listAll 返回空列表', () {
      expect(repo.listAll(), isA<Ok<List<Subscription>>>());
      expect((repo.listAll() as Ok<List<Subscription>>).value, isEmpty);
    });

    test('upsert 后 get 全字段往返一致', () {
      expect(repo.upsert(full()), isA<Ok<void>>());
      final got = (repo.get('sub-1') as Ok<Subscription?>).value!;
      expect(got, equals(full()));
      expect(got.iccid, equals('89000000000000000001'));
      expect(got.plan.cyclePrice, equals(const Money(minorUnits: 2900, currencyCode: 'CNY')));
      expect(got.keepAlive.confidence, equals(DataConfidence.inferred));
      expect(got.appearance.cardColorHex, equals('#0a84ff'));
      expect(got.tags, equals(['主力号', 'eSIM']));
    });

    test('未存在的 id 返回 null', () {
      expect((repo.get('nope') as Ok<Subscription?>).value, isNull);
    });

    test('再次 upsert 覆盖旧值', () {
      repo.upsert(full());
      final updated = full().copyWith(
        operator: '中国联通',
        updatedAt: DateTime.utc(2026, 8, 8, 4, 0),
      );
      repo.upsert(updated);
      final got = (repo.get('sub-1') as Ok<Subscription?>).value!;
      expect(got.operator, equals('中国联通'));
      expect(got.updatedAt, equals(DateTime.utc(2026, 8, 8, 4, 0)));
    });

    test('listAll 按创建时间升序', () {
      final early = full().copyWith(
        id: 'sub-0',
        createdAt: DateTime.utc(2026, 7, 1),
        updatedAt: DateTime.utc(2026, 7, 1),
      );
      repo.upsert(early);
      repo.upsert(full());
      final ids = (repo.listAll() as Ok<List<Subscription>>)
          .value
          .map((s) => s.id)
          .toList();
      expect(ids, equals(['sub-0', 'sub-1']));
    });

    test('delete 后 get 返回 null', () {
      repo.upsert(full());
      expect(repo.delete('sub-1'), isA<Ok<void>>());
      expect((repo.get('sub-1') as Ok<Subscription?>).value, isNull);
    });

    test('数据库关闭后操作返回 Err(StoreError)', () {
      db.close();
      final result = repo.upsert(full());
      expect(result, isA<Err<void>>());
      expect((result as Err).failure, isA<StoreError>());
    });
  });
}
