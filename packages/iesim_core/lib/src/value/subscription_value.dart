import '../model/plan.dart';
import '../model/profile_lifecycle.dart';
import '../model/subscription.dart';
import 'money.dart';

/// 套餐剩余价值的计算方式。
enum PlanValueMethod {
  /// 有明确计费天数，按当前计费周期线性摊销。
  billingCycle,

  /// 没有计费天数，但有完整起止时间，按整个固定期限线性摊销。
  fixedTerm,
}

/// 套餐剩余价值的可计算状态。
enum PlanValueStatus {
  available,
  missingPrice,
  missingPeriod,
  invalidPrice,
  invalidPeriod,
}

/// 单个套餐在指定时刻的剩余价值估算。
///
/// ieSIM 不猜测折旧曲线，也不联网换汇；这里只对已记录的套餐价格按时间
/// 做线性摊销。[remainingValue] 以整数最小货币单位计算并四舍五入。
class PlanValueEstimate {
  const PlanValueEstimate({
    required this.status,
    this.method,
    this.remainingValue,
    this.periodStartUtc,
    this.periodEndUtc,
    this.totalMicroseconds,
    this.remainingMicroseconds,
  });

  final PlanValueStatus status;
  final PlanValueMethod? method;
  final Money? remainingValue;
  final DateTime? periodStartUtc;
  final DateTime? periodEndUtc;
  final int? totalMicroseconds;
  final int? remainingMicroseconds;

  bool get isAvailable => status == PlanValueStatus.available;

  /// 0 到 1 之间的剩余比例；不可估算时为 null。
  double? get remainingRatio {
    final total = totalMicroseconds;
    final remaining = remainingMicroseconds;
    if (!isAvailable || total == null || remaining == null || total <= 0) {
      return null;
    }
    return (remaining / total).clamp(0, 1).toDouble();
  }

  /// 四舍五入后的剩余百分比。
  int? get remainingPercent {
    final total = totalMicroseconds;
    final remaining = remainingMicroseconds;
    if (!isAvailable || total == null || remaining == null || total <= 0) {
      return null;
    }
    return ((remaining * 100 + total ~/ 2) ~/ total).clamp(0, 100);
  }
}

/// 一个 Profile 的余额与套餐剩余价值构成。
class SubscriptionValueBreakdown {
  const SubscriptionValueBreakdown({
    required this.subscriptionId,
    required this.balance,
    required this.plan,
  });

  final String subscriptionId;
  final Money? balance;
  final PlanValueEstimate plan;

  /// 余额与套餐残值币种一致时给出直接合计；否则保持分币种展示。
  Money? get combinedValue {
    final currentBalance = balance;
    final remainingPlanValue = plan.remainingValue;
    if (currentBalance == null) return remainingPlanValue;
    if (remainingPlanValue == null) return currentBalance;
    if (currentBalance.currencyCode != remainingPlanValue.currencyCode) {
      return null;
    }
    return currentBalance + remainingPlanValue;
  }

  bool get hasMixedCurrencies {
    final currentBalance = balance;
    final remainingPlanValue = plan.remainingValue;
    return currentBalance != null &&
        remainingPlanValue != null &&
        currentBalance.currencyCode != remainingPlanValue.currencyCode;
  }
}

/// 总价值看板中一种币种的汇总。
class CurrencyValueSummary {
  const CurrencyValueSummary({
    required this.currencyCode,
    required this.balanceMinorUnits,
    required this.remainingPlanMinorUnits,
    required this.balanceProfileCount,
    required this.planProfileCount,
  });

  final String currencyCode;
  final int balanceMinorUnits;
  final int remainingPlanMinorUnits;
  final int balanceProfileCount;
  final int planProfileCount;

  Money get balance =>
      Money(minorUnits: balanceMinorUnits, currencyCode: currencyCode);

  Money get remainingPlanValue =>
      Money(minorUnits: remainingPlanMinorUnits, currencyCode: currencyCode);

  Money get total => Money(
    minorUnits: balanceMinorUnits + remainingPlanMinorUnits,
    currencyCode: currencyCode,
  );
}

/// 首页总价值看板的数据；每种币种独立汇总。
class PortfolioValueSummary {
  PortfolioValueSummary({
    required List<CurrencyValueSummary> currencies,
    required this.includedProfileCount,
    required this.profilesWithValueCount,
    required this.unvaluedPlanCount,
    required this.excludedMuseumCount,
  }) : currencies = List.unmodifiable(currencies);

  final List<CurrencyValueSummary> currencies;
  final int includedProfileCount;
  final int profilesWithValueCount;

  /// 已记录价格、但周期资料不足或无效，因而无法估算套餐残值的数量。
  final int unvaluedPlanCount;
  final int excludedMuseumCount;

  bool get isEmpty => currencies.isEmpty;
}

/// 余额与套餐剩余价值计算器。
class SubscriptionValueCalculator {
  const SubscriptionValueCalculator();

  SubscriptionValueBreakdown evaluate(
    Subscription subscription, {
    required DateTime nowUtc,
  }) {
    _requireUtc(nowUtc);
    return SubscriptionValueBreakdown(
      subscriptionId: subscription.id,
      balance: subscription.details.currentBalance,
      plan: estimatePlan(subscription.plan, nowUtc: nowUtc),
    );
  }

  PlanValueEstimate estimatePlan(Plan plan, {required DateTime nowUtc}) {
    _requireUtc(nowUtc);
    final price = plan.cyclePrice;
    if (price == null) {
      return const PlanValueEstimate(status: PlanValueStatus.missingPrice);
    }
    if (price.minorUnits < 0) {
      return const PlanValueEstimate(status: PlanValueStatus.invalidPrice);
    }

    final cycleDays = plan.cycleDays;
    if (cycleDays != null) {
      return _estimateBillingCycle(plan, price, nowUtc, cycleDays);
    }

    final start = plan.startDate;
    final end = plan.expiryDate;
    if (start == null || end == null) {
      return const PlanValueEstimate(status: PlanValueStatus.missingPeriod);
    }
    if (!end.isAfter(start)) {
      return const PlanValueEstimate(status: PlanValueStatus.invalidPeriod);
    }
    return _estimatePeriod(
      price: price,
      startUtc: start,
      endUtc: end,
      nowUtc: nowUtc,
      method: PlanValueMethod.fixedTerm,
    );
  }

  PortfolioValueSummary summarize(
    Iterable<Subscription> subscriptions, {
    required DateTime nowUtc,
    bool includeMuseum = false,
  }) {
    _requireUtc(nowUtc);
    final accumulators = <String, _CurrencyAccumulator>{};
    var included = 0;
    var withValue = 0;
    var unvaluedPlans = 0;
    var excludedMuseums = 0;

    for (final subscription in subscriptions) {
      if (!includeMuseum &&
          subscription.lifecycle.stage == ProfileStage.museum) {
        excludedMuseums++;
        continue;
      }
      included++;
      final breakdown = evaluate(subscription, nowUtc: nowUtc);
      var contributed = false;
      final balance = breakdown.balance;
      if (balance != null) {
        final accumulator = accumulators.putIfAbsent(
          balance.currencyCode,
          _CurrencyAccumulator.new,
        );
        accumulator.balanceMinorUnits += balance.minorUnits;
        accumulator.balanceProfileCount++;
        contributed = true;
      }
      final planValue = breakdown.plan.remainingValue;
      if (planValue != null) {
        final accumulator = accumulators.putIfAbsent(
          planValue.currencyCode,
          _CurrencyAccumulator.new,
        );
        accumulator.remainingPlanMinorUnits += planValue.minorUnits;
        accumulator.planProfileCount++;
        contributed = true;
      } else if (subscription.plan.cyclePrice != null) {
        unvaluedPlans++;
      }
      if (contributed) withValue++;
    }

    final currencyCodes = accumulators.keys.toList()..sort();
    return PortfolioValueSummary(
      currencies: [
        for (final currencyCode in currencyCodes)
          CurrencyValueSummary(
            currencyCode: currencyCode,
            balanceMinorUnits: accumulators[currencyCode]!.balanceMinorUnits,
            remainingPlanMinorUnits:
                accumulators[currencyCode]!.remainingPlanMinorUnits,
            balanceProfileCount:
                accumulators[currencyCode]!.balanceProfileCount,
            planProfileCount: accumulators[currencyCode]!.planProfileCount,
          ),
      ],
      includedProfileCount: included,
      profilesWithValueCount: withValue,
      unvaluedPlanCount: unvaluedPlans,
      excludedMuseumCount: excludedMuseums,
    );
  }

  PlanValueEstimate _estimateBillingCycle(
    Plan plan,
    Money price,
    DateTime nowUtc,
    int cycleDays,
  ) {
    final cycle = Duration(days: cycleDays);
    final cycleMicros = cycle.inMicroseconds;
    final anchor = plan.startDate;
    final expiry = plan.expiryDate;

    if (anchor == null) {
      if (expiry == null) {
        return const PlanValueEstimate(status: PlanValueStatus.missingPeriod);
      }
      return _estimatePeriod(
        price: price,
        startUtc: expiry.subtract(cycle),
        endUtc: expiry,
        nowUtc: nowUtc,
        method: PlanValueMethod.billingCycle,
      );
    }
    if (expiry != null && !expiry.isAfter(anchor)) {
      return const PlanValueEstimate(status: PlanValueStatus.invalidPeriod);
    }

    if (nowUtc.isBefore(anchor)) {
      final naturalEnd = anchor.add(cycle);
      final end = expiry != null && expiry.isBefore(naturalEnd)
          ? expiry
          : naturalEnd;
      return _estimatePeriod(
        price: price,
        startUtc: anchor,
        endUtc: end,
        nowUtc: nowUtc,
        method: PlanValueMethod.billingCycle,
      );
    }

    if (expiry != null && !nowUtc.isBefore(expiry)) {
      final elapsedToExpiry = expiry.difference(anchor).inMicroseconds;
      final lastCycleIndex = (elapsedToExpiry - 1) ~/ cycleMicros;
      final periodStart = anchor.add(
        Duration(microseconds: lastCycleIndex * cycleMicros),
      );
      return _estimatePeriod(
        price: price,
        startUtc: periodStart,
        endUtc: expiry,
        nowUtc: nowUtc,
        method: PlanValueMethod.billingCycle,
      );
    }

    final elapsed = nowUtc.difference(anchor).inMicroseconds;
    final cycleIndex = elapsed ~/ cycleMicros;
    final periodStart = anchor.add(
      Duration(microseconds: cycleIndex * cycleMicros),
    );
    final naturalEnd = periodStart.add(cycle);
    final periodEnd = expiry != null && expiry.isBefore(naturalEnd)
        ? expiry
        : naturalEnd;
    return _estimatePeriod(
      price: price,
      startUtc: periodStart,
      endUtc: periodEnd,
      nowUtc: nowUtc,
      method: PlanValueMethod.billingCycle,
    );
  }

  PlanValueEstimate _estimatePeriod({
    required Money price,
    required DateTime startUtc,
    required DateTime endUtc,
    required DateTime nowUtc,
    required PlanValueMethod method,
  }) {
    final total = endUtc.difference(startUtc).inMicroseconds;
    if (total <= 0) {
      return const PlanValueEstimate(status: PlanValueStatus.invalidPeriod);
    }
    final remaining = nowUtc.isBefore(startUtc)
        ? total
        : !nowUtc.isBefore(endUtc)
        ? 0
        : endUtc.difference(nowUtc).inMicroseconds;
    final remainingMinorUnits = _roundedProration(
      price.minorUnits,
      remaining,
      total,
    );
    return PlanValueEstimate(
      status: PlanValueStatus.available,
      method: method,
      remainingValue: Money(
        minorUnits: remainingMinorUnits,
        currencyCode: price.currencyCode,
      ),
      periodStartUtc: startUtc,
      periodEndUtc: endUtc,
      totalMicroseconds: total,
      remainingMicroseconds: remaining,
    );
  }

  static int _roundedProration(int price, int remaining, int total) {
    final denominator = BigInt.from(total);
    final numerator = BigInt.from(price) * BigInt.from(remaining);
    return ((numerator + denominator ~/ BigInt.two) ~/ denominator).toInt();
  }

  static void _requireUtc(DateTime value) {
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'nowUtc', '必须为 UTC 时刻');
    }
  }
}

class _CurrencyAccumulator {
  int balanceMinorUnits = 0;
  int remainingPlanMinorUnits = 0;
  int balanceProfileCount = 0;
  int planProfileCount = 0;
}
