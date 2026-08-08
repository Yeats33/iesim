import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

import '../app/app_scope.dart';
import '../widgets/section_card.dart';

class ProfileLifecycleSettingsPage extends StatelessWidget {
  const ProfileLifecycleSettingsPage({super.key});

  static const _options = <int?>[null, 0, 30, 90, 180, 365];

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final subscriptions = controller.subscriptions;
    final active = subscriptions
        .where((item) => item.lifecycle.stage == ProfileStage.active)
        .length;
    final pending = subscriptions
        .where((item) => item.lifecycle.stage == ProfileStage.pendingActivation)
        .length;
    final museum = subscriptions
        .where((item) => item.lifecycle.stage == ProfileStage.museum)
        .length;
    final selected = controller.museumAutoArchiveDays;
    final selectedIsPreset = _options.contains(selected);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile 生命周期')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          MediaQuery.paddingOf(context).bottom + 36,
        ),
        children: [
          SectionCard(
            title: '三类 Profile',
            subtitle: '设备上的启用与停用都属于已激活',
            child: Row(
              children: [
                _StageCount(label: '已激活', value: active),
                _StageCount(label: '未激活', value: pending),
                _StageCount(label: '博物馆', value: museum),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: '自动进入博物馆',
            subtitle: '只依据 Profile 服务到期日，不依据套餐到期日',
            child: Column(
              children: [
                for (final days in _options) ...[
                  _ArchiveDelayTile(
                    days: days,
                    selected: selectedIsPreset && selected == days,
                    onTap: () => _setDelay(context, days),
                  ),
                  if (days != _options.last) const Divider(),
                ],
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('自定义天数'),
                  subtitle: !selectedIsPreset && selected != null
                      ? Text('当前：到期 $selected 天后')
                      : const Text('输入 1–3650 天'),
                  trailing: !selectedIsPreset && selected != null
                      ? const Icon(Icons.check_circle_rounded)
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: () => _customDelay(context, selected),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '自动归档在应用读取数据时执行。归档会保留 Profile、套餐、号码和历史动作，并停止为它安排新的提醒。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setDelay(BuildContext context, int? days) async {
    final error = await AppScope.of(context).setMuseumAutoArchiveDays(days);
    if (error != null && context.mounted) _message(context, error);
  }

  Future<void> _customDelay(BuildContext context, int? current) async {
    final input = TextEditingController(
      text: current != null && !_options.contains(current)
          ? current.toString()
          : '',
    );
    final days = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('自定义自动归档时间'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '到期后天数',
            suffixText: '天',
            helperText: '允许 1–3650 天',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(input.text.trim());
              if (value == null || value < 1 || value > 3650) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    input.dispose();
    if (days != null && context.mounted) await _setDelay(context, days);
  }

  static void _message(BuildContext context, String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
    );
  }
}

class _ArchiveDelayTile extends StatelessWidget {
  const _ArchiveDelayTile({
    required this.days,
    required this.selected,
    required this.onTap,
  });

  final int? days;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(days == null ? Icons.block_rounded : Icons.timer_outlined),
    title: Text(_label(days)),
    trailing: selected ? const Icon(Icons.check_circle_rounded) : null,
    onTap: onTap,
  );

  static String _label(int? days) => switch (days) {
    null => '永不自动归档',
    0 => '到期后立即归档',
    30 => '到期 30 天后',
    90 => '到期 90 天后（推荐）',
    180 => '到期 180 天后',
    365 => '到期 1 年后',
    _ => '到期 $days 天后',
  };
}

class _StageCount extends StatelessWidget {
  const _StageCount({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text('$value', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    ),
  );
}
