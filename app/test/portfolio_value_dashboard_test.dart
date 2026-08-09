import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/widgets/portfolio_value_dashboard.dart';
import 'package:iesim_core/iesim_core.dart';

void main() {
  testWidgets('总价值看板在窄屏按币种展示余额和套餐残值', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = PortfolioValueSummary(
      currencies: const [
        CurrencyValueSummary(
          currencyCode: 'CNY',
          balanceMinorUnits: 2500,
          remainingPlanMinorUnits: 5000,
          balanceProfileCount: 1,
          planProfileCount: 1,
        ),
        CurrencyValueSummary(
          currencyCode: 'USD',
          balanceMinorUnits: 1200,
          remainingPlanMinorUnits: 0,
          balanceProfileCount: 1,
          planProfileCount: 0,
        ),
      ],
      includedProfileCount: 3,
      profilesWithValueCount: 2,
      unvaluedPlanCount: 1,
      excludedMuseumCount: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: PortfolioValueDashboard(summary: summary),
          ),
        ),
      ),
    );

    expect(find.text('总价值'), findsOneWidget);
    expect(find.text('CNY 总计'), findsOneWidget);
    expect(find.text('CNY 75.00'), findsOneWidget);
    expect(find.text('USD 总计'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
    expect(find.textContaining('1 个套餐待补充周期资料'), findsOneWidget);
    expect(find.textContaining('已排除 1 个过期博物馆'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空看板提示补全估值资料', (tester) async {
    final summary = PortfolioValueSummary(
      currencies: const [],
      includedProfileCount: 1,
      profilesWithValueCount: 0,
      unvaluedPlanCount: 1,
      excludedMuseumCount: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PortfolioValueDashboard(summary: summary)),
      ),
    );

    expect(find.textContaining('周期资料不足'), findsOneWidget);
  });
}
