import 'package:flutter/material.dart' hide KeepAlive;
import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/data/app_controller.dart';
import 'package:iesim/main.dart';
import 'package:iesim_core/iesim_core.dart';

void main() {
  testWidgets('置顶 Profile 排在同分类顶部并可在详情取消', (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'UTC');

    expect(
      await controller.saveSubscription(
        _subscription(
          id: 'normal-profile',
          name: '普通 Profile',
          updatedAt: DateTime.utc(2026, 8, 8),
        ),
      ),
      isNull,
    );
    expect(
      await controller.saveSubscription(
        _subscription(
          id: 'pinned-profile',
          name: '置顶 Profile',
          updatedAt: DateTime.utc(2026, 1, 1),
          isPinned: true,
        ),
      ),
      isNull,
    );

    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byTooltip('已置顶'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('置顶 Profile')).dy,
      lessThan(tester.getTopLeft(find.text('普通 Profile')).dy),
    );

    await tester.tap(find.text('置顶 Profile'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('取消置顶'), findsOneWidget);
    await tester.tap(find.byTooltip('取消置顶'));
    await tester.pumpAndSettle();

    expect(
      controller.subscriptionById('pinned-profile')!.details.isPinned,
      isFalse,
    );
    expect(find.byTooltip('置顶 Profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Subscription _subscription({
  required String id,
  required String name,
  required DateTime updatedAt,
  bool isPinned = false,
}) => Subscription(
  id: id,
  number: const PhoneNumber.unknown(),
  operator: '测试运营商',
  plan: Plan(name: '测试套餐'),
  keepAlive: KeepAlive.notRequired(),
  details: SubscriptionDetails(profileName: name, isPinned: isPinned),
  timeZoneId: 'UTC',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: updatedAt,
);
