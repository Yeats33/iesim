import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:iesim_core/iesim_core.dart';
import 'package:timezone/timezone.dart' as tz;

import '../util/formatters.dart';

abstract interface class ReminderNotificationGateway {
  Future<void> initialize();

  Future<bool> areNotificationsEnabled();

  Future<bool> requestPermission();

  Future<void> openSettings();

  Future<void> replaceAll(List<Subscription> subscriptions);

  Future<void> cancelAll();

  Stream<String> get selectedSubscriptionIds;

  Future<String?> initialSubscriptionId();

  void dispose();
}

class LocalReminderNotifications implements ReminderNotificationGateway {
  LocalReminderNotifications({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'iesim_deadlines_v1';
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Profile 截止提醒',
      channelDescription: '保号、套餐、激活期限和 Profile 服务到期前的本地提醒',
      icon: 'ic_stat_iesim',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
  );

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _selections = StreamController.broadcast();

  @override
  Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_iesim'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) _selections.add(payload);
      },
    );
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> areNotificationsEnabled() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    return await _android?.areNotificationsEnabled() ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> openSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _android?.openAppNotificationSettings();
  }

  @override
  Future<void> replaceAll(List<Subscription> subscriptions) async {
    await _plugin.cancelAll();
    final planner = ReminderPlanner(clock: const SystemClock());
    for (final subscription in subscriptions) {
      for (final reminder in planner.planFor(subscription)) {
        await _schedule(subscription, reminder);
      }
    }
  }

  Future<void> _schedule(
    Subscription subscription,
    ScheduledReminder reminder,
  ) async {
    final moment = ZonedCalendar(
      subscription.timeZoneId,
    ).momentAt(reminder.deadlineUtc);
    final date = '${moment.month}月${moment.day}日';
    final title = switch (reminder.kind) {
      ReminderKind.keepAlive => '保号截止提醒 · ${displayPhone(subscription.number)}',
      ReminderKind.planExpiry =>
        '套餐到期提醒 · ${displayPhone(subscription.number)}',
      ReminderKind.activationDeadline =>
        'Profile 激活期限 · ${displayPhone(subscription.number)}',
      ReminderKind.profileExpiry =>
        'Profile 服务到期 · ${displayPhone(subscription.number)}',
    };
    final operator = subscription.operator?.trim();
    final prefix = operator == null || operator.isEmpty ? '' : '$operator · ';
    final confidence = reminder.inferred ? '（日期由现有资料推测，请核对）' : '';
    final action = reminder.daysBefore == 0
        ? '今天截止'
        : '还有 ${reminder.daysBefore} 天';
    final body = '$prefix$date，$action$confidence';
    await _plugin.zonedSchedule(
      id: stableNotificationId(reminder.stableKey),
      title: title,
      body: body,
      payload: subscription.id,
      scheduledDate: tz.TZDateTime.from(reminder.fireAtUtc, tz.UTC),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Stream<String> get selectedSubscriptionIds => _selections.stream;

  @override
  Future<String?> initialSubscriptionId() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final payload = details?.notificationResponse?.payload;
    return payload == null || payload.isEmpty ? null : payload;
  }

  @override
  void dispose() => _selections.close();
}

class NoopReminderNotifications implements ReminderNotificationGateway {
  const NoopReminderNotifications();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> areNotificationsEnabled() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> replaceAll(List<Subscription> subscriptions) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Stream<String> get selectedSubscriptionIds => const Stream.empty();

  @override
  Future<String?> initialSubscriptionId() async => null;

  @override
  void dispose() {}
}

/// 32-bit FNV-1a；屏蔽符号位，得到 Android 通知所需的稳定正整数。
int stableNotificationId(String key) {
  var hash = 0x811c9dc5;
  for (final byte in key.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}
