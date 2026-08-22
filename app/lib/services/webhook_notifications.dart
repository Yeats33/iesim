import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum WebhookEventCategory { profile, activity, sync }

class WebhookConfiguration {
  const WebhookConfiguration({
    required this.endpointUrl,
    this.enabled = true,
    this.priority = 3,
    this.tags = const ['iesim'],
    this.titlePrefix = 'ieSIM',
    this.customPayload = const {},
    this.notifyProfileChanges = true,
    this.notifyActivities = true,
    this.notifySyncResults = true,
    this.includeProfileDetails = false,
  });

  final String endpointUrl;
  final bool enabled;
  final int priority;
  final List<String> tags;
  final String titlePrefix;
  final Map<String, Object?> customPayload;
  final bool notifyProfileChanges;
  final bool notifyActivities;
  final bool notifySyncResults;
  final bool includeProfileDetails;

  Uri get endpointUri {
    final uri = Uri.parse(endpointUrl.trim());
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException('请输入不含用户凭据或片段的 HTTPS Webhook 地址');
    }
    return uri;
  }

  void validate() {
    endpointUri;
    if (priority < 1 || priority > 5) {
      throw const FormatException('优先级必须在 1 到 5 之间');
    }
    final prefix = titlePrefix.trim();
    if (prefix.isEmpty || prefix.length > 50) {
      throw const FormatException('标题前缀应为 1 到 50 个字符');
    }
    if (tags.length > 12 ||
        tags.any((tag) => tag.trim().isEmpty || tag.trim().length > 40)) {
      throw const FormatException('最多填写 12 个非空标签，每个不超过 40 个字符');
    }
    if (utf8.encode(jsonEncode(customPayload)).length > 16 * 1024) {
      throw const FormatException('自定义 payload 不能超过 16 KB');
    }
  }

  bool allows(WebhookEventCategory category) =>
      enabled &&
      switch (category) {
        WebhookEventCategory.profile => notifyProfileChanges,
        WebhookEventCategory.activity => notifyActivities,
        WebhookEventCategory.sync => notifySyncResults,
      };

  WebhookConfiguration copyWith({
    String? endpointUrl,
    bool? enabled,
    int? priority,
    List<String>? tags,
    String? titlePrefix,
    Map<String, Object?>? customPayload,
    bool? notifyProfileChanges,
    bool? notifyActivities,
    bool? notifySyncResults,
    bool? includeProfileDetails,
  }) => WebhookConfiguration(
    endpointUrl: endpointUrl ?? this.endpointUrl,
    enabled: enabled ?? this.enabled,
    priority: priority ?? this.priority,
    tags: tags ?? this.tags,
    titlePrefix: titlePrefix ?? this.titlePrefix,
    customPayload: customPayload ?? this.customPayload,
    notifyProfileChanges: notifyProfileChanges ?? this.notifyProfileChanges,
    notifyActivities: notifyActivities ?? this.notifyActivities,
    notifySyncResults: notifySyncResults ?? this.notifySyncResults,
    includeProfileDetails: includeProfileDetails ?? this.includeProfileDetails,
  );

  Map<String, Object?> toJson() => {
    'endpointUrl': endpointUrl.trim(),
    'enabled': enabled,
    'priority': priority,
    'tags': [for (final tag in tags) tag.trim()],
    'titlePrefix': titlePrefix.trim(),
    'customPayload': customPayload,
    'notifyProfileChanges': notifyProfileChanges,
    'notifyActivities': notifyActivities,
    'notifySyncResults': notifySyncResults,
    'includeProfileDetails': includeProfileDetails,
  };

  factory WebhookConfiguration.fromJson(Map<String, dynamic> value) {
    final endpointUrl = value['endpointUrl'];
    final enabled = value['enabled'];
    final priority = value['priority'];
    final tags = value['tags'];
    final titlePrefix = value['titlePrefix'];
    final customPayload = value['customPayload'];
    final notifyProfileChanges = value['notifyProfileChanges'];
    final notifyActivities = value['notifyActivities'];
    final notifySyncResults = value['notifySyncResults'];
    final includeProfileDetails = value['includeProfileDetails'];
    if (endpointUrl is! String ||
        enabled is! bool ||
        priority is! int ||
        tags is! List ||
        !tags.every((item) => item is String) ||
        titlePrefix is! String ||
        customPayload is! Map<String, dynamic> ||
        notifyProfileChanges is! bool ||
        notifyActivities is! bool ||
        notifySyncResults is! bool ||
        includeProfileDetails is! bool) {
      throw const FormatException('本机 Webhook 配置格式无效');
    }
    final configuration = WebhookConfiguration(
      endpointUrl: endpointUrl,
      enabled: enabled,
      priority: priority,
      tags: tags.cast<String>(),
      titlePrefix: titlePrefix,
      customPayload: Map<String, Object?>.from(customPayload),
      notifyProfileChanges: notifyProfileChanges,
      notifyActivities: notifyActivities,
      notifySyncResults: notifySyncResults,
      includeProfileDetails: includeProfileDetails,
    );
    configuration.validate();
    return configuration;
  }
}

class WebhookNotification {
  const WebhookNotification({
    required this.title,
    required this.message,
    required this.event,
    required this.occurredAtUtc,
    this.payload = const {},
  });

  final String title;
  final String message;
  final String event;
  final DateTime occurredAtUtc;
  final Map<String, Object?> payload;

  Map<String, Object?> requestBody(WebhookConfiguration configuration) {
    if (!occurredAtUtc.isUtc) {
      throw const FormatException('Webhook 事件时间必须为 UTC');
    }
    return {
      'title': '${configuration.titlePrefix.trim()} · $title',
      'message': message,
      'priority': configuration.priority,
      'tags': [for (final tag in configuration.tags) tag.trim()],
      'payload': {
        ...configuration.customPayload,
        ...payload,
        'event': event,
        'occurredAt': occurredAtUtc.toIso8601String(),
      },
    };
  }
}

abstract interface class WebhookNotificationGateway {
  Future<WebhookConfiguration?> loadConfiguration();

  Future<void> saveConfiguration(WebhookConfiguration configuration);

  Future<void> clearConfiguration();

  Future<void> send(
    WebhookConfiguration configuration,
    WebhookNotification notification,
  );
}

class AppWebhookNotificationService implements WebhookNotificationGateway {
  const AppWebhookNotificationService([
    this._storage = const FlutterSecureStorage(),
  ]);

  static const _configurationKey = 'webhook.configuration.v1';
  static const _maximumResponseBytes = 64 * 1024;

  final FlutterSecureStorage _storage;

  @override
  Future<WebhookConfiguration?> loadConfiguration() async {
    final source = await _storage.read(key: _configurationKey);
    if (source == null) return null;
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('本机 Webhook 配置格式无效');
    }
    return WebhookConfiguration.fromJson(value);
  }

  @override
  Future<void> saveConfiguration(WebhookConfiguration configuration) async {
    configuration.validate();
    await _storage.write(
      key: _configurationKey,
      value: jsonEncode(configuration.toJson()),
    );
  }

  @override
  Future<void> clearConfiguration() => _storage.delete(key: _configurationKey);

  @override
  Future<void> send(
    WebhookConfiguration configuration,
    WebhookNotification notification,
  ) async {
    configuration.validate();
    final body = utf8.encode(
      jsonEncode(notification.requestBody(configuration)),
    );
    if (body.length > 64 * 1024) {
      throw const FormatException('Webhook 请求体不能超过 64 KB');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .postUrl(configuration.endpointUri)
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'iesim-android/1.0');
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      var responseBytes = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        responseBytes += chunk.length;
        if (responseBytes > _maximumResponseBytes) {
          throw const FormatException('Webhook 响应超过 64 KB');
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw WebhookHttpException(response.statusCode);
      }
    } on TimeoutException {
      throw const WebhookNetworkException('请求超时');
    } on SocketException catch (error) {
      throw WebhookNetworkException('无法连接服务器：${error.message}');
    } finally {
      client.close(force: true);
    }
  }
}

class WebhookHttpException implements Exception {
  const WebhookHttpException(this.statusCode);

  final int statusCode;

  @override
  String toString() => '服务器返回 HTTP $statusCode';
}

class WebhookNetworkException implements Exception {
  const WebhookNetworkException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MemoryWebhookNotificationGateway implements WebhookNotificationGateway {
  WebhookConfiguration? configuration;
  final List<WebhookNotification> sentNotifications = [];
  Object? sendError;

  @override
  Future<WebhookConfiguration?> loadConfiguration() async => configuration;

  @override
  Future<void> saveConfiguration(WebhookConfiguration value) async {
    value.validate();
    configuration = value;
  }

  @override
  Future<void> clearConfiguration() async => configuration = null;

  @override
  Future<void> send(
    WebhookConfiguration configuration,
    WebhookNotification notification,
  ) async {
    if (sendError case final error?) throw error;
    sentNotifications.add(notification);
  }
}

class NoopWebhookNotificationGateway implements WebhookNotificationGateway {
  const NoopWebhookNotificationGateway();

  @override
  Future<WebhookConfiguration?> loadConfiguration() async => null;

  @override
  Future<void> saveConfiguration(WebhookConfiguration configuration) async {}

  @override
  Future<void> clearConfiguration() async {}

  @override
  Future<void> send(
    WebhookConfiguration configuration,
    WebhookNotification notification,
  ) async {}
}
