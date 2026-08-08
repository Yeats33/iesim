import 'package:flutter/material.dart' hide KeepAlive;
import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/app/app_scope.dart';
import 'package:iesim/data/app_controller.dart';
import 'package:iesim/pages/subscription_detail_page.dart';
import 'package:iesim/widgets/subscription_card.dart';
import 'package:iesim_core/iesim_core.dart';

void main() {
  testWidgets('主页 Profile 默认折叠并可展开二维码与其他信息', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var openedDetails = false;
    final subscription = _subscription();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SubscriptionCard(
                subscription: subscription,
                status: const NotRequired(),
                onTap: () => openedDetails = true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('展开二维码与其他信息'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('activation-qr-rsp.example.test')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('profile-card-expander-profile-with-qr')),
    );
    await tester.pumpAndSettle();

    expect(openedDetails, isFalse);
    expect(find.text('收起二维码与其他信息'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('activation-qr-rsp.example.test')),
      findsOneWidget,
    );
    expect(find.text('SM-DP+'), findsOneWidget);
    expect(find.text('••••1234'), findsOneWidget);
    expect(find.text('internet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Profile 详情存在 LPA 凭据时展示二维码', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController.inMemory();
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final subscription = _subscription();
    expect(await controller.saveSubscription(subscription), isNull);

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          home: SubscriptionDetailPage(subscriptionId: subscription.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('eSIM 二维码'), findsOneWidget);
    expect(find.textContaining('二维码包含完整激活凭据'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('activation-qr-rsp.example.test')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Subscription _subscription() {
  final now = DateTime.utc(2026, 8, 8);
  return Subscription(
    id: 'profile-with-qr',
    iccid: '8944000000000000002',
    number: const PhoneNumber.unknown(),
    operator: '旅行数据 eSIM',
    activation: LpaActivation(
      smdpAddress: 'rsp.example.test',
      matchingId: 'MATCH-SECRET-1234',
    ),
    plan: Plan(name: '欧洲 10 GB'),
    keepAlive: KeepAlive.notRequired(),
    details: const SubscriptionDetails(
      profileName: '欧洲旅行 Profile',
      countryCode: 'DE',
      countryName: 'Germany',
      mcc: '262',
      mnc: '01',
      apn: 'internet',
    ),
    timeZoneId: 'UTC',
    createdAt: now,
    updatedAt: now,
  );
}
