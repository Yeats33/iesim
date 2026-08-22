import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/webhook_notifications.dart';

void main() {
  test('按约定生成 title message priority tags payload 请求体', () {
    const configuration = WebhookConfiguration(
      endpointUrl: 'https://webhook.ql.al/n/example-token',
      priority: 3,
      tags: ['deploy', 'production'],
      titlePrefix: 'ieSIM',
      customPayload: {'environment': 'production', 'commit': 'a1b2c3d'},
    );
    final notification = WebhookNotification(
      title: 'Deploy finished',
      message: 'App v2.1.0 deployed to production',
      event: 'deploy.finished',
      occurredAtUtc: DateTime.utc(2026, 8, 22, 12),
      payload: const {'version': '2.1.0'},
    );

    expect(configuration.endpointUri.host, 'webhook.ql.al');
    expect(notification.requestBody(configuration), {
      'title': 'ieSIM · Deploy finished',
      'message': 'App v2.1.0 deployed to production',
      'priority': 3,
      'tags': ['deploy', 'production'],
      'payload': {
        'environment': 'production',
        'commit': 'a1b2c3d',
        'version': '2.1.0',
        'event': 'deploy.finished',
        'occurredAt': '2026-08-22T12:00:00.000Z',
      },
    });
  });

  test('配置 JSON 完整往返并保留事件开关', () {
    const original = WebhookConfiguration(
      endpointUrl: 'https://hooks.example.com/a?key=b',
      enabled: false,
      priority: 5,
      tags: ['iesim', 'sync'],
      titlePrefix: '我的卡片',
      customPayload: {'device': 'phone-a'},
      notifyProfileChanges: false,
      notifyActivities: true,
      notifySyncResults: false,
      includeProfileDetails: true,
    );

    final restored = WebhookConfiguration.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );
    expect(restored.endpointUrl, original.endpointUrl);
    expect(restored.enabled, isFalse);
    expect(restored.priority, 5);
    expect(restored.tags, ['iesim', 'sync']);
    expect(restored.customPayload, {'device': 'phone-a'});
    expect(restored.notifyProfileChanges, isFalse);
    expect(restored.notifyActivities, isTrue);
    expect(restored.notifySyncResults, isFalse);
    expect(restored.includeProfileDetails, isTrue);
  });

  test('只接受不含用户凭据和片段的 HTTPS 地址', () {
    for (final source in [
      'http://hooks.example.com/a',
      'https://user:secret@hooks.example.com/a',
      'https://hooks.example.com/a#token',
      'not-a-url',
    ]) {
      expect(
        () => WebhookConfiguration(endpointUrl: source).endpointUri,
        throwsFormatException,
      );
    }
    expect(
      const WebhookConfiguration(
        endpointUrl: 'https://hooks.example.com/a?token=secret',
      ).endpointUri.queryParameters['token'],
      'secret',
    );
  });

  test('事件字段覆盖同名自定义 payload，避免伪造系统事件', () {
    const configuration = WebhookConfiguration(
      endpointUrl: 'https://hooks.example.com/a',
      customPayload: {'event': 'custom', 'occurredAt': 'custom', 'tenant': 7},
    );
    final notification = WebhookNotification(
      title: '完成',
      message: '已完成',
      event: 'profile.updated',
      occurredAtUtc: DateTime.utc(2026, 8, 22),
    );

    final payload = notification.requestBody(configuration)['payload'] as Map;
    expect(payload['event'], 'profile.updated');
    expect(payload['occurredAt'], '2026-08-22T00:00:00.000Z');
    expect(payload['tenant'], 7);
  });
}
