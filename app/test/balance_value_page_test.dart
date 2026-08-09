import 'package:flutter/material.dart' hide KeepAlive;
import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/app/app_scope.dart';
import 'package:iesim/data/app_controller.dart';
import 'package:iesim/pages/balance_management_page.dart';
import 'package:iesim_core/iesim_core.dart';

void main() {
  testWidgets('余额页展示账面余额、套餐残值和当前合计', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController.inMemory();
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final midpoint = DateTime.now().toUtc();
    final subscription = Subscription(
      id: 'valued-profile',
      number: const PhoneNumber.unknown(),
      operator: 'Value Mobile',
      plan: Plan(
        name: '20 天套餐',
        cyclePrice: const Money(minorUnits: 10000, currencyCode: 'CNY'),
        startDate: midpoint.subtract(const Duration(days: 10)),
        expiryDate: midpoint.add(const Duration(days: 10)),
      ),
      keepAlive: KeepAlive.notRequired(),
      details: const SubscriptionDetails(
        currentBalance: Money(minorUnits: 2000, currencyCode: 'CNY'),
      ),
      timeZoneId: 'UTC',
      createdAt: midpoint,
      updatedAt: midpoint,
    );
    expect(await controller.saveSubscription(subscription), isNull);

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(
          home: BalanceManagementPage(subscriptionId: 'valued-profile'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('余额与价值'), findsOneWidget);
    expect(find.text('CNY 70.00'), findsOneWidget);
    expect(find.text('账面余额'), findsOneWidget);
    expect(find.text('CNY 20.00'), findsOneWidget);
    expect(find.text('套餐剩余价值'), findsOneWidget);
    expect(find.text('CNY 50.00'), findsWidgets);
    expect(find.text('剩余 50%'), findsOneWidget);
    expect(find.textContaining('完整有效期剩余时间比例'), findsOneWidget);
    expect(find.text('编辑套餐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
