import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/data/app_controller.dart';
import 'package:iesim/services/webhook_notifications.dart';
import 'package:iesim_core/iesim_core.dart';

void main() {
  test('成功保存 Profile 后发送 Webhook，默认不泄露 Profile 详情', () async {
    final gateway = MemoryWebhookNotificationGateway()
      ..configuration = const WebhookConfiguration(
        endpointUrl: 'https://hooks.example.com/secret',
      );
    final controller = AppController.inMemory(webhookNotifications: gateway);
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final subscription = Subscription(
      id: 'private-subscription-id',
      number: PhoneNumber('+49123456789'),
      operator: 'Private Operator',
      details: const SubscriptionDetails(profileName: 'Private Profile'),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'UTC',
      createdAt: DateTime.utc(2026, 8, 22),
      updatedAt: DateTime.utc(2026, 8, 22),
    );

    expect(await controller.saveSubscription(subscription), isNull);
    await Future<void>.delayed(Duration.zero);

    expect(gateway.sentNotifications, hasLength(1));
    final notification = gateway.sentNotifications.single;
    expect(notification.event, 'profile.created');
    expect(notification.payload, isNot(contains('subscriptionId')));
    expect(notification.payload, isNot(contains('phoneNumber')));
    expect(notification.message, isNot(contains('Private')));
  });

  test('用户明确开启详情后，动作通知包含所选 Profile 身份', () async {
    final gateway = MemoryWebhookNotificationGateway()
      ..configuration = const WebhookConfiguration(
        endpointUrl: 'https://hooks.example.com/secret',
        includeProfileDetails: true,
      );
    final controller = AppController.inMemory(webhookNotifications: gateway);
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final subscription = Subscription(
      id: 'sub-activity',
      number: PhoneNumber('+49123456789'),
      operator: 'Test Operator',
      details: const SubscriptionDetails(profileName: '旅行卡'),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'UTC',
      createdAt: DateTime.utc(2026, 8, 22),
      updatedAt: DateTime.utc(2026, 8, 22),
    );
    expect(await controller.saveSubscription(subscription), isNull);
    await Future<void>.delayed(Duration.zero);
    gateway.sentNotifications.clear();

    expect(
      await controller.recordActivity(
        subscription: subscription,
        type: ActivityType.sms,
        occurredAt: DateTime.utc(2026, 8, 22, 13),
      ),
      isNull,
    );
    await Future<void>.delayed(Duration.zero);

    final notification = gateway.sentNotifications.single;
    expect(notification.event, 'activity.recorded');
    expect(notification.message, contains('旅行卡'));
    expect(notification.payload['subscriptionId'], 'sub-activity');
    expect(notification.payload['phoneNumber'], '+49123456789');
  });

  test('Webhook 发送失败不回滚本地业务操作', () async {
    final gateway = MemoryWebhookNotificationGateway()
      ..configuration = const WebhookConfiguration(
        endpointUrl: 'https://hooks.example.com/secret',
      )
      ..sendError = const WebhookNetworkException('测试网络不可用');
    final controller = AppController.inMemory(webhookNotifications: gateway);
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final subscription = Subscription(
      id: 'sub-offline',
      number: const PhoneNumber.unknown(),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'UTC',
      createdAt: DateTime.utc(2026, 8, 22),
      updatedAt: DateTime.utc(2026, 8, 22),
    );

    expect(await controller.saveSubscription(subscription), isNull);
    await Future<void>.delayed(Duration.zero);

    expect(controller.subscriptionById('sub-offline'), isNotNull);
    expect(controller.webhookLastError, '测试网络不可用');
  });

  test('测试通知可在自动发送关闭时单独发送', () async {
    final gateway = MemoryWebhookNotificationGateway();
    final controller = AppController.inMemory(webhookNotifications: gateway);
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    const configuration = WebhookConfiguration(
      endpointUrl: 'https://hooks.example.com/secret',
      enabled: false,
    );

    expect(await controller.testWebhook(configuration), isNull);
    expect(gateway.sentNotifications.single.event, 'webhook.test');
    expect(controller.webhookLastSentAtUtc, isNotNull);
  });
}
