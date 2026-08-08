import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../widgets/section_card.dart';

class DeveloperModePage extends StatefulWidget {
  const DeveloperModePage({super.key});

  static const password = 'yeats33';

  static Future<void> open(BuildContext context) async {
    final unlocked = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeveloperPasswordDialog(),
    );
    if (unlocked != true || !context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const DeveloperModePage()),
    );
  }

  @override
  State<DeveloperModePage> createState() => _DeveloperModePageState();
}

class _DeveloperModePageState extends State<DeveloperModePage> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('开发者模式')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          MediaQuery.paddingOf(context).bottom + 36,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.science_outlined, color: scheme.tertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '仅用于测试设备',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      const Text('密码只是防误触，不是安全加密。这里的操作只影响本机，不会删除 WebDAV 远端文件。'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: '当前测试状态',
            child: Column(
              children: [
                _DeveloperStat(
                  label: 'Profile / 订阅',
                  value: '${controller.subscriptions.length}',
                ),
                const Divider(),
                _DeveloperStat(
                  label: '动作记录',
                  value: '${controller.activities.length}',
                ),
                const Divider(),
                _DeveloperStat(
                  label: '设备 / 卡片 / EID',
                  value:
                      '${controller.assets.devices.length} / '
                      '${controller.assets.cards.length} / '
                      '${controller.assets.eids.length}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: '测试数据',
            subtitle: '固定 ID，可重复执行且不会重复堆叠',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _working ? null : _addTestData,
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: const Text('添加测试数据'),
                ),
                const SizedBox(height: 9),
                Text(
                  '会加入 3 个 Profile、套餐、保号状态、动作记录，以及设备 → 卡槽 → 卡片 → EID → Profile 关系。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: '危险操作',
            subtitle: '用于把测试机恢复到空白状态',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                  ),
                  onPressed: _working ? null : _clearData,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('清空数据'),
                ),
                const SizedBox(height: 9),
                Text(
                  '可分别选择 Profile 业务数据、设备资产和 WebDAV 本地配置；WebDAV 默认保留，远端文件永不删除。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addTestData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.science_outlined),
        title: const Text('添加测试数据？'),
        content: const Text('现有数据不会被删除；测试记录使用固定 ID，重复执行只会更新同一组记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    final error = await AppScope.of(context).addDeveloperTestData();
    if (!mounted) return;
    setState(() => _working = false);
    _message(error ?? '测试数据已添加');
  }

  Future<void> _clearData() async {
    final selection = await showDialog<_ClearDataSelection>(
      context: context,
      builder: (_) => const _ClearDataDialog(),
    );
    if (selection == null || !mounted) return;
    setState(() => _working = true);
    final error = await AppScope.of(context).clearDeveloperData(
      clearProfiles: selection.profiles,
      clearAssets: selection.assets,
      clearWebDavConfiguration: selection.webDavConfiguration,
    );
    if (!mounted) return;
    setState(() => _working = false);
    _message(
      error ??
          (selection.webDavConfiguration
              ? '所选本机数据已清空；WebDAV 远端文件未删除'
              : '所选本机数据已清空；WebDAV 本地配置已保留'),
    );
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
    );
  }
}

class _ClearDataSelection {
  const _ClearDataSelection({
    required this.profiles,
    required this.assets,
    required this.webDavConfiguration,
  });

  final bool profiles;
  final bool assets;
  final bool webDavConfiguration;
}

class _ClearDataDialog extends StatefulWidget {
  const _ClearDataDialog();

  @override
  State<_ClearDataDialog> createState() => _ClearDataDialogState();
}

class _ClearDataDialogState extends State<_ClearDataDialog> {
  bool _profiles = true;
  bool _assets = true;
  bool _webDavConfiguration = false;

  bool get _hasSelection => _profiles || _assets || _webDavConfiguration;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
      title: const Text('选择要清空的数据'),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('只清空已勾选的本机数据，操作不可撤销。'),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _profiles,
            onChanged: (value) => setState(() => _profiles = value ?? false),
            title: const Text('Profile 与业务记录'),
            subtitle: const Text('Profile、套餐、余额、动作记录与提醒'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _assets,
            onChanged: (value) => setState(() => _assets = value ?? false),
            title: const Text('设备资产'),
            subtitle: const Text('设备、卡槽、卡片、EID 与资产事件'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _webDavConfiguration,
            onChanged: (value) =>
                setState(() => _webDavConfiguration = value ?? false),
            title: const Text('WebDAV 本地配置（默认保留）'),
            subtitle: const Text('服务器地址、用户名和本机保存的密码'),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'WebDAV 远端文件永不删除。保留连接配置时，本地同步游标会重置，下次同步可能从远端恢复数据。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: _hasSelection
              ? () => Navigator.pop(
                  context,
                  _ClearDataSelection(
                    profiles: _profiles,
                    assets: _assets,
                    webDavConfiguration: _webDavConfiguration,
                  ),
                )
              : null,
          child: const Text('清空所选数据'),
        ),
      ],
    );
  }
}

class _DeveloperPasswordDialog extends StatefulWidget {
  const _DeveloperPasswordDialog();

  @override
  State<_DeveloperPasswordDialog> createState() =>
      _DeveloperPasswordDialogState();
}

class _DeveloperPasswordDialogState extends State<_DeveloperPasswordDialog> {
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.developer_mode_rounded),
    title: const Text('进入开发者模式'),
    content: TextField(
      controller: _password,
      autofocus: true,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: '开发者密码',
        errorText: _error,
        prefixIcon: const Icon(Icons.password_rounded),
      ),
      onSubmitted: (_) => _unlock(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _unlock, child: const Text('解锁')),
    ],
  );

  void _unlock() {
    if (_password.text.trim() == DeveloperModePage.password) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _error = '密码不正确');
  }
}

class _DeveloperStat extends StatelessWidget {
  const _DeveloperStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
