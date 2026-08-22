import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../services/webhook_notifications.dart';
import '../widgets/section_card.dart';

class WebhookSettingsPage extends StatefulWidget {
  const WebhookSettingsPage({super.key});

  @override
  State<WebhookSettingsPage> createState() => _WebhookSettingsPageState();
}

class _WebhookSettingsPageState extends State<WebhookSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _endpointController = TextEditingController();
  final _titlePrefixController = TextEditingController(text: 'ieSIM');
  final _tagsController = TextEditingController(text: 'iesim');
  final _payloadController = TextEditingController(text: '{}');
  bool _initialized = false;
  bool _working = false;
  bool _obscureEndpoint = true;
  bool _enabled = true;
  int _priority = 3;
  bool _notifyProfileChanges = true;
  bool _notifyActivities = true;
  bool _notifySyncResults = true;
  bool _includeProfileDetails = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final configuration = AppScope.of(context).webhookConfiguration;
    if (configuration == null) return;
    _endpointController.text = configuration.endpointUrl;
    _titlePrefixController.text = configuration.titlePrefix;
    _tagsController.text = configuration.tags.join(', ');
    _payloadController.text = const JsonEncoder.withIndent(
      '  ',
    ).convert(configuration.customPayload);
    _enabled = configuration.enabled;
    _priority = configuration.priority;
    _notifyProfileChanges = configuration.notifyProfileChanges;
    _notifyActivities = configuration.notifyActivities;
    _notifySyncResults = configuration.notifySyncResults;
    _includeProfileDetails = configuration.includeProfileDetails;
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _titlePrefixController.dispose();
    _tagsController.dispose();
    _payloadController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final configuration = controller.webhookConfiguration;
    final active = configuration?.enabled ?? false;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Webhook 通知')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.paddingOf(context).bottom + 28,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  _WebhookHero(
                    configured: configuration != null,
                    active: active,
                    sending: controller.webhookSending,
                    lastSentAtUtc: controller.webhookLastSentAtUtc,
                  ),
                  if (controller.webhookLastError case final error?) ...[
                    const SizedBox(height: 14),
                    Card(
                      color: scheme.errorContainer,
                      child: ListTile(
                        leading: Icon(Icons.error_outline, color: scheme.error),
                        title: const Text('最近一次发送失败'),
                        subtitle: Text(error),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SectionCard(
                    title: configuration == null ? '连接 Webhook' : '通知配置',
                    subtitle: '发送标准 JSON：title、message、priority、tags、payload',
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('启用 Webhook 通知'),
                            subtitle: const Text('关闭后保留配置，但不自动发送'),
                            value: _enabled,
                            onChanged: _working
                                ? null
                                : (value) => setState(() => _enabled = value),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _endpointController,
                            obscureText: _obscureEndpoint,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: 'HTTPS Webhook 地址',
                              hintText: 'https://webhook.example.com/n/token',
                              prefixIcon: const Icon(Icons.link_rounded),
                              suffixIcon: IconButton(
                                tooltip: _obscureEndpoint ? '显示地址' : '隐藏地址',
                                onPressed: () => setState(
                                  () => _obscureEndpoint = !_obscureEndpoint,
                                ),
                                icon: Icon(
                                  _obscureEndpoint
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: _validateEndpoint,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _titlePrefixController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '标题前缀',
                              helperText: '例如：ieSIM · Profile 已更新',
                              prefixIcon: Icon(Icons.title_rounded),
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.isEmpty) return '请输入标题前缀';
                              if (text.length > 50) return '标题前缀不能超过 50 个字符';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _tagsController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '默认标签',
                              helperText: '用逗号分隔，最多 12 个；可以留空',
                              prefixIcon: Icon(Icons.sell_outlined),
                            ),
                            validator: _validateTags,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            '优先级 $_priority',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Slider(
                            value: _priority.toDouble(),
                            min: 1,
                            max: 5,
                            divisions: 4,
                            label: '$_priority',
                            onChanged: _working
                                ? null
                                : (value) =>
                                      setState(() => _priority = value.round()),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '1 · 低',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                '3 · 普通',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                '5 · 紧急',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _payloadController,
                            minLines: 4,
                            maxLines: 9,
                            keyboardType: TextInputType.multiline,
                            autocorrect: false,
                            enableSuggestions: false,
                            style: const TextStyle(fontFamily: 'monospace'),
                            decoration: const InputDecoration(
                              labelText: '自定义 payload（JSON 对象）',
                              helperText:
                                  '会合并进每次请求；event 与 occurredAt 由 ieSIM 写入',
                              alignLabelWithHint: true,
                              prefixIcon: Icon(Icons.data_object_rounded),
                            ),
                            validator: _validatePayload,
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _working ? null : _test,
                                  icon: const Icon(Icons.send_outlined),
                                  label: const Text('发送测试通知'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _working ? null : _save,
                                  icon: _working
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.save_outlined),
                                  label: const Text('保存配置'),
                                ),
                              ),
                            ],
                          ),
                          if (configuration != null) ...[
                            const SizedBox(height: 10),
                            Center(
                              child: TextButton.icon(
                                onPressed: _working ? null : _disconnect,
                                style: TextButton.styleFrom(
                                  foregroundColor: scheme.error,
                                ),
                                icon: const Icon(Icons.link_off_rounded),
                                label: const Text('移除此设备上的 Webhook 配置'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: '发送事件',
                    subtitle: '只在相关操作成功后发送；Webhook 失败不回滚本地数据',
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.sim_card_outlined),
                          title: const Text('Profile 变更'),
                          subtitle: const Text('新建、编辑、激活、归档或删除'),
                          value: _notifyProfileChanges,
                          onChanged: _working
                              ? null
                              : (value) => setState(
                                  () => _notifyProfileChanges = value,
                                ),
                        ),
                        const Divider(),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.receipt_long_outlined),
                          title: const Text('动作与余额'),
                          subtitle: const Text('充值、通话、短信、续费、余额等记录'),
                          value: _notifyActivities,
                          onChanged: _working
                              ? null
                              : (value) =>
                                    setState(() => _notifyActivities = value),
                        ),
                        const Divider(),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.cloud_sync_outlined),
                          title: const Text('WebDAV 同步结果'),
                          subtitle: const Text('成功、冲突数量与失败状态'),
                          value: _notifySyncResults,
                          onChanged: _working
                              ? null
                              : (value) =>
                                    setState(() => _notifySyncResults = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: '隐私与运行方式',
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.badge_outlined),
                          title: const Text('附带 Profile 详情'),
                          subtitle: const Text(
                            '开启后会发送 Profile ID、名称、号码和运营商；默认关闭',
                          ),
                          value: _includeProfileDetails,
                          onChanged: _working
                              ? null
                              : (value) => setState(
                                  () => _includeProfileDetails = value,
                                ),
                        ),
                        const Divider(),
                        const InfoRow(
                          label: '基础 payload',
                          value: '事件、UTC 时间、金额或同步聚合数量',
                          icon: Icons.data_object_rounded,
                        ),
                        const InfoRow(
                          label: '地址存储',
                          value: '仅保存在本机安全存储，不进入 WebDAV 快照',
                          icon: Icons.lock_outline_rounded,
                        ),
                        const InfoRow(
                          label: '后台限制',
                          value: '仅在应用执行操作时发送，不在后台轮询',
                          icon: Icons.battery_saver_outlined,
                        ),
                        const InfoRow(
                          label: '截止提醒',
                          value: '仍由系统本地预排程，应用关闭后也可提醒',
                          icon: Icons.notifications_active_outlined,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  WebhookConfiguration? _configurationFromForm() {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    final payloadSource = _payloadController.text.trim();
    final decoded = payloadSource.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(payloadSource);
    return WebhookConfiguration(
      endpointUrl: _endpointController.text.trim(),
      enabled: _enabled,
      priority: _priority,
      tags: _parseTags(_tagsController.text),
      titlePrefix: _titlePrefixController.text.trim(),
      customPayload: Map<String, Object?>.from(decoded as Map),
      notifyProfileChanges: _notifyProfileChanges,
      notifyActivities: _notifyActivities,
      notifySyncResults: _notifySyncResults,
      includeProfileDetails: _includeProfileDetails,
    );
  }

  Future<void> _test() async {
    final configuration = _configurationFromForm();
    if (configuration == null) return;
    setState(() => _working = true);
    final error = await AppScope.of(context).testWebhook(configuration);
    if (!mounted) return;
    setState(() => _working = false);
    _showResult(error, success: '测试通知已发送，请检查接收端。');
  }

  Future<void> _save() async {
    final configuration = _configurationFromForm();
    if (configuration == null) return;
    setState(() => _working = true);
    final error = await AppScope.of(
      context,
    ).saveWebhookConfiguration(configuration);
    if (!mounted) return;
    setState(() => _working = false);
    _showResult(error, success: _enabled ? 'Webhook 通知已启用。' : '配置已保存，自动发送已关闭。');
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除 Webhook 配置？'),
        content: const Text('只会删除此设备上的地址和发送选项，不会删除接收端的任何数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    final error = await AppScope.of(context).disconnectWebhook();
    if (!mounted) return;
    setState(() => _working = false);
    if (error == null) {
      _endpointController.clear();
      _showResult(null, success: 'Webhook 配置已从此设备移除。');
    } else {
      _showResult(error, success: '');
    }
  }

  void _showResult(String? error, {required String success}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? success),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static String? _validateEndpoint(String? value) {
    if (value == null || value.trim().isEmpty) return '请输入 Webhook 地址';
    try {
      WebhookConfiguration(endpointUrl: value).endpointUri;
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  static String? _validateTags(String? value) {
    final tags = _parseTags(value ?? '');
    if (tags.length > 12) return '最多填写 12 个标签';
    if (tags.any((tag) => tag.length > 40)) return '每个标签不能超过 40 个字符';
    return null;
  }

  static String? _validatePayload(String? value) {
    final source = value?.trim() ?? '';
    if (source.isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return 'payload 必须是 JSON 对象';
      if (utf8.encode(jsonEncode(decoded)).length > 16 * 1024) {
        return '自定义 payload 不能超过 16 KB';
      }
      return null;
    } on FormatException {
      return '请输入有效的 JSON 对象';
    }
  }

  static List<String> _parseTags(String source) => source
      .split(RegExp(r'[,，\n]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

class _WebhookHero extends StatelessWidget {
  const _WebhookHero({
    required this.configured,
    required this.active,
    required this.sending,
    required this.lastSentAtUtc,
  });

  final bool configured;
  final bool active;
  final bool sending;
  final DateTime? lastSentAtUtc;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = active ? Colors.white : scheme.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: active
              ? [scheme.primary, const Color(0xFF27627A)]
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
            child: sending
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: active ? Colors.white : scheme.primary,
                    ),
                  )
                : Icon(
                    active ? Icons.webhook_rounded : Icons.webhook_outlined,
                    color: active ? Colors.white : scheme.onSurfaceVariant,
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active
                      ? 'Webhook 已启用'
                      : configured
                      ? 'Webhook 已暂停'
                      : '尚未配置 Webhook',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: foreground),
                ),
                const SizedBox(height: 4),
                Text(
                  sending
                      ? '正在发送通知…'
                      : lastSentAtUtc == null
                      ? '配置后可将应用事件发送到你的服务'
                      : '最近发送：${_formatMoment(lastSentAtUtc!)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: active
                        ? Colors.white.withValues(alpha: .78)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatMoment(DateTime utc) {
    final value = utc.toLocal();
    String two(int item) => item.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}
