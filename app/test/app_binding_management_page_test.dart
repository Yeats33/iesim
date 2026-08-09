import 'package:flutter/material.dart' hide KeepAlive;
import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/app/app_scope.dart';
import 'package:iesim/data/app_controller.dart';
import 'package:iesim/pages/app_binding_management_page.dart';
import 'package:iesim_core/iesim_core.dart';

void main() {
  testWidgets('号码绑定页展示 App、号码、状态和隐私边界', (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController.inMemory();
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final now = DateTime.utc(2026, 8, 9);
    expect(
      await controller.saveSubscription(
        Subscription(
          id: 'profile-with-binding',
          number: PhoneNumber('+37257633333'),
          operator: '测试运营商',
          plan: Plan(name: '测试套餐'),
          keepAlive: KeepAlive.notRequired(),
          details: SubscriptionDetails(
            profileName: '测试 Profile',
            appBindings: [
              PhoneAppBinding(
                id: 'binding-1',
                phoneNumber: '+37257633333',
                appName: 'WhatsApp Messenger',
                status: PhoneAppBindingStatus.active,
                purposes: const [PhoneAppBindingPurpose.messaging],
                createdAt: now,
                updatedAt: now,
              ),
            ],
          ),
          timeZoneId: 'UTC',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      isNull,
    );

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(
          home: AppBindingManagementPage(
            subscriptionId: 'profile-with-binding',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('号码绑定'), findsOneWidget);
    expect(find.text('1 个号码 · 1 个 App 绑定'), findsOneWidget);
    expect(find.text('WhatsApp Messenger'), findsOneWidget);
    expect(find.text('+37257633333'), findsOneWidget);
    expect(find.text('使用中'), findsOneWidget);
    expect(find.textContaining('不读取短信、验证码或 App 内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
