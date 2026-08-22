import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/app/app_scope.dart';
import 'package:iesim/data/app_controller.dart';
import 'package:iesim/pages/webhook_settings_page.dart';
import 'package:iesim/services/webhook_notifications.dart';

void main() {
  testWidgets('用户可填写并保存完整 Webhook 配置', (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = MemoryWebhookNotificationGateway();
    final controller = AppController.inMemory(webhookNotifications: gateway);
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(home: WebhookSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'HTTPS Webhook 地址'),
      'https://webhook.ql.al/n/user-token',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '标题前缀'),
      '我的 ieSIM',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '默认标签'),
      'iesim, production',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '自定义 payload（JSON 对象）'),
      '{"environment":"production"}',
    );
    final save = find.widgetWithText(FilledButton, '保存配置');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(gateway.configuration?.endpointUrl, contains('user-token'));
    expect(gateway.configuration?.titlePrefix, '我的 ieSIM');
    expect(gateway.configuration?.tags, ['iesim', 'production']);
    expect(gateway.configuration?.customPayload, {'environment': 'production'});
    expect(find.text('Webhook 通知已启用。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('非 HTTPS 地址会在本地阻止保存和测试', (tester) async {
    final gateway = MemoryWebhookNotificationGateway();
    final controller = AppController.inMemory(webhookNotifications: gateway);
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: const MaterialApp(home: WebhookSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'HTTPS Webhook 地址'),
      'http://hooks.example.com/insecure',
    );
    final testButton = find.widgetWithText(OutlinedButton, '发送测试通知');
    await tester.ensureVisible(testButton);
    await tester.pumpAndSettle();
    await tester.tap(testButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('请输入不含用户凭据'), findsOneWidget);
    expect(gateway.sentNotifications, isEmpty);
    expect(gateway.configuration, isNull);
  });
}
