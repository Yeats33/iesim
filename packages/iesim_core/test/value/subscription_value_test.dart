import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  const calculator = SubscriptionValueCalculator();

  group('套餐剩余价值', () {
    test('固定期限过半时保留一半价值并给出可审计周期', () {
      final estimate = calculator.estimatePlan(
        Plan(
          cyclePrice: const Money(minorUnits: 10000, currencyCode: 'CNY'),
          startDate: DateTime.utc(2026, 8, 1),
          expiryDate: DateTime.utc(2026, 8, 31),
        ),
        nowUtc: DateTime.utc(2026, 8, 16),
      );

      expect(estimate.status, PlanValueStatus.available);
      expect(estimate.method, PlanValueMethod.fixedTerm);
      expect(estimate.remainingValue?.minorUnits, 5000);
      expect(estimate.remainingPercent, 50);
      expect(estimate.periodStartUtc, DateTime.utc(2026, 8, 1));
      expect(estimate.periodEndUtc, DateTime.utc(2026, 8, 31));
    });

    test('套餐开始前为全额，到期后为零', () {
      final plan = Plan(
        cyclePrice: const Money(minorUnits: 9900, currencyCode: 'USD'),
        startDate: DateTime.utc(2026, 9, 1),
        expiryDate: DateTime.utc(2026, 10, 1),
      );

      expect(
        calculator
            .estimatePlan(plan, nowUtc: DateTime.utc(2026, 8, 9))
            .remainingValue
            ?.minorUnits,
        9900,
      );
      expect(
        calculator
            .estimatePlan(plan, nowUtc: DateTime.utc(2026, 10, 1))
            .remainingValue
            ?.minorUnits,
        0,
      );
    });

    test('有周期与到期日时可反推当前周期', () {
      final estimate = calculator.estimatePlan(
        Plan(
          cyclePrice: const Money(minorUnits: 3000, currencyCode: 'GBP'),
          cycleDays: 30,
          expiryDate: DateTime.utc(2026, 8, 31),
        ),
        nowUtc: DateTime.utc(2026, 8, 16),
      );

      expect(estimate.method, PlanValueMethod.billingCycle);
      expect(estimate.remainingValue?.minorUnits, 1500);
      expect(estimate.periodStartUtc, DateTime.utc(2026, 8, 1));
    });

    test('长期周期套餐按当前计费周期而非全部历史摊销', () {
      final estimate = calculator.estimatePlan(
        Plan(
          cyclePrice: const Money(minorUnits: 3100, currencyCode: 'EUR'),
          cycleDays: 31,
          startDate: DateTime.utc(2026, 1, 1),
          isLongTerm: true,
        ),
        nowUtc: DateTime.utc(2026, 2, 16, 12),
      );

      expect(estimate.periodStartUtc, DateTime.utc(2026, 2, 1));
      expect(estimate.periodEndUtc, DateTime.utc(2026, 3, 4));
      expect(estimate.remainingValue?.minorUnits, 1550);
      expect(estimate.remainingPercent, 50);
    });

    test('价格存在但缺少周期时明确不可估算', () {
      final estimate = calculator.estimatePlan(
        Plan(cyclePrice: const Money(minorUnits: 1000, currencyCode: 'CNY')),
        nowUtc: DateTime.utc(2026, 8, 9),
      );

      expect(estimate.status, PlanValueStatus.missingPeriod);
      expect(estimate.remainingValue, isNull);
    });

    test('拒绝非 UTC 估值时刻', () {
      expect(
        () => calculator.estimatePlan(Plan(), nowUtc: DateTime(2026, 8, 9)),
        throwsArgumentError,
      );
    });
  });

  group('总价值看板汇总', () {
    test('余额与套餐残值按币种归集且不纳入博物馆', () {
      final summary = calculator.summarize([
        _subscription(
          id: 'cny',
          balance: const Money(minorUnits: 2500, currencyCode: 'CNY'),
          price: const Money(minorUnits: 10000, currencyCode: 'CNY'),
        ),
        _subscription(
          id: 'mixed',
          balance: const Money(minorUnits: 2000, currencyCode: 'USD'),
          price: const Money(minorUnits: 1000, currencyCode: 'EUR'),
        ),
        _subscription(
          id: 'museum',
          balance: const Money(minorUnits: 999999, currencyCode: 'CNY'),
          price: const Money(minorUnits: 999999, currencyCode: 'CNY'),
          stage: ProfileStage.museum,
        ),
      ], nowUtc: DateTime.utc(2026, 8, 16));

      expect(summary.currencies.map((item) => item.currencyCode), [
        'CNY',
        'EUR',
        'USD',
      ]);
      expect(summary.currencies[0].balanceMinorUnits, 2500);
      expect(summary.currencies[0].remainingPlanMinorUnits, 5000);
      expect(summary.currencies[0].total.minorUnits, 7500);
      expect(summary.currencies[1].total.minorUnits, 500);
      expect(summary.currencies[2].total.minorUnits, 2000);
      expect(summary.includedProfileCount, 2);
      expect(summary.profilesWithValueCount, 2);
      expect(summary.excludedMuseumCount, 1);
    });

    test('价格存在但无法估算的套餐单独计数', () {
      final summary = calculator.summarize([
        _subscription(
          id: 'incomplete',
          price: const Money(minorUnits: 1000, currencyCode: 'CNY'),
          includePeriod: false,
        ),
      ], nowUtc: DateTime.utc(2026, 8, 16));

      expect(summary.isEmpty, isTrue);
      expect(summary.unvaluedPlanCount, 1);
    });
  });

  test('单 Profile 跨币种时不产生错误合计', () {
    final breakdown = calculator.evaluate(
      _subscription(
        id: 'mixed',
        balance: const Money(minorUnits: 1000, currencyCode: 'USD'),
        price: const Money(minorUnits: 1000, currencyCode: 'EUR'),
      ),
      nowUtc: DateTime.utc(2026, 8, 16),
    );

    expect(breakdown.hasMixedCurrencies, isTrue);
    expect(breakdown.combinedValue, isNull);
  });
}

Subscription _subscription({
  required String id,
  Money? balance,
  Money? price,
  bool includePeriod = true,
  ProfileStage stage = ProfileStage.active,
}) => Subscription(
  id: id,
  number: const PhoneNumber.unknown(),
  plan: Plan(
    cyclePrice: price,
    startDate: includePeriod ? DateTime.utc(2026, 8, 1) : null,
    expiryDate: includePeriod ? DateTime.utc(2026, 8, 31) : null,
  ),
  keepAlive: KeepAlive(required: false),
  details: SubscriptionDetails(currentBalance: balance),
  lifecycle: ProfileLifecycle(stage: stage),
  timeZoneId: 'UTC',
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
);
