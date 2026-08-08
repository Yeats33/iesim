import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../widgets/section_card.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with WidgetsBindingObserver {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).refreshNotificationPermission();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      AppScope.of(context).refreshNotificationPermission(reschedule: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final active =
        controller.remindersEnabled && controller.notificationPermissionGranted;
    return Scaffold(
      appBar: AppBar(title: const Text('本地通知')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.paddingOf(context).bottom + 28,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: active
                    ? [scheme.primary, const Color(0xFF1E6B63)]
                    : [scheme.surfaceContainerHighest, scheme.surfaceContainer],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white.withValues(alpha: .16)
                        : scheme.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    active
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_off_outlined,
                    color: active ? Colors.white : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        active ? '提醒已开启' : '提醒尚未开启',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: active ? Colors.white : scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active
                            ? '已计算 ${controller.scheduledReminderCount} 个未来提醒'
                            : '开启后，截止提醒会直接保存在系统中',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: active
                              ? Colors.white.withValues(alpha: .78)
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: active,
                  onChanged: _busy ? null : (value) => _toggle(value),
                ),
              ],
            ),
          ),
          if (controller.notificationError != null) ...[
            const SizedBox(height: 14),
            Card(
              color: scheme.errorContainer,
              child: ListTile(
                leading: Icon(Icons.error_outline, color: scheme.error),
                title: const Text('部分提醒未能排程'),
                subtitle: Text(controller.notificationError!),
              ),
            ),
          ],
          const SizedBox(height: 18),
          SectionCard(
            title: '提醒节奏',
            subtitle: '保号截止与套餐到期分别计算，互不覆盖',
            child: Column(
              children: const [
                _RuleRow(days: '提前 7 天', detail: '留出充值或续费时间'),
                Divider(),
                _RuleRow(days: '提前 3 天', detail: '再次确认处理进度'),
                Divider(),
                _RuleRow(days: '提前 1 天', detail: '临近截止提醒'),
                Divider(),
                _RuleRow(days: '截止当天', detail: '当天 09:00 提醒'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: '可靠性与隐私',
            child: Column(
              children: [
                const InfoRow(
                  label: '运行方式',
                  value: '系统预排程，无需后台常驻',
                  icon: Icons.battery_saver_outlined,
                ),
                const InfoRow(
                  label: '时间基准',
                  value: '每条订阅自己的时区',
                  icon: Icons.public_rounded,
                ),
                const InfoRow(
                  label: '数据去向',
                  value: '仅保存在本机',
                  icon: Icons.lock_outline_rounded,
                ),
                if (!controller.notificationPermissionGranted) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: controller.openNotificationSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('打开系统通知设置'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    final controller = AppScope.of(context);
    final accepted = await controller.setRemindersEnabled(value);
    if (!mounted) return;
    setState(() => _busy = false);
    if (value && !accepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('需要系统通知权限才能开启提醒'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.days, required this.detail});

  final String days;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 19,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 11),
          SizedBox(
            width: 80,
            child: Text(
              days,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              detail,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
