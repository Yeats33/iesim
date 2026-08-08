import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iesim_core/iesim_core.dart';

import '../app/app_scope.dart';
import '../util/formatters.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';

class NekokoTagsPage extends StatefulWidget {
  const NekokoTagsPage({super.key});

  @override
  State<NekokoTagsPage> createState() => _NekokoTagsPageState();
}

class _NekokoTagsPageState extends State<NekokoTagsPage> {
  final _nickname = TextEditingController();
  String? _subscriptionId;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscriptionId ??= _preferredSubscription()?.id;
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final subscriptions = controller.subscriptions;
    if (subscriptions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nekoko 标签')),
        body: const EmptyState(
          icon: Icons.label_outline_rounded,
          title: '先添加一条订阅',
          message: 'Nekoko 标签通过 ICCID 与订阅关联。',
        ),
      );
    }
    final decoded = NekokoTagCodec.decode(_nickname.text);
    final selected = _selectedSubscription();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Nekoko 标签')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.paddingOf(context).bottom + 36,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded, color: scheme.primary, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '粘贴 Nekoko Profile nickname，可读取标签；也可把 ieSIM 标签生成回 nickname。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: '关联订阅',
            subtitle: '优先选择已填写 ICCID 的记录',
            child: DropdownButtonFormField<String>(
              initialValue: _subscriptionId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '订阅 / ICCID',
                prefixIcon: Icon(Icons.sim_card_outlined),
              ),
              items: [
                for (final subscription in subscriptions)
                  DropdownMenuItem(
                    value: subscription.id,
                    child: Text(
                      '${subscription.operator ?? '未知运营商'} · '
                      '${displayPhone(subscription.number)}'
                      '${subscription.iccid == null ? '' : ' · ${subscription.iccid}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _subscriptionId = value),
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Profile nickname',
            subtitle: '支持 t:文本 与 d:YYMMDD:备注',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nickname,
                  minLines: 3,
                  maxLines: 7,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Main Profile t:旅行卡 d:260808:续费',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _paste,
                        icon: const Icon(Icons.content_paste_rounded),
                        label: const Text('粘贴'),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: selected == null ? null : _generate,
                        icon: const Icon(Icons.auto_fix_high_rounded),
                        label: const Text('从订阅生成'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: '解析结果',
            subtitle: decoded.tags.isEmpty
                ? '尚未识别到结构化标签'
                : '${decoded.tags.length} 个标签',
            trailing: decoded.issues.isEmpty
                ? null
                : Tooltip(
                    message: decoded.issues.join('\n'),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: scheme.error,
                    ),
                  ),
            child: decoded.tags.isEmpty
                ? Text(
                    '普通昵称文字会原样保留。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in decoded.tags) _TagChip(tag: tag),
                        ],
                      ),
                      if (decoded.issues.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        for (final issue in decoded.issues)
                          Text(
                            '• $issue',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.error),
                          ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _saving || selected == null
                            ? null
                            : () => _applyTags(selected, decoded),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_done_rounded),
                        label: const Text('应用文本标签到订阅'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Subscription? _preferredSubscription() {
    final subscriptions = AppScope.of(context).subscriptions;
    for (final subscription in subscriptions) {
      if (subscription.iccid != null) return subscription;
    }
    return subscriptions.isEmpty ? null : subscriptions.first;
  }

  Subscription? _selectedSubscription() {
    final id = _subscriptionId;
    return id == null ? null : AppScope.of(context).subscriptionById(id);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    _nickname.text = data!.text!;
    setState(() {});
  }

  Future<void> _generate() async {
    final subscription = _selectedSubscription();
    if (subscription == null) return;
    final tags = <NekokoTag>[
      for (final tag in subscription.tags) NekokoTextTag(tag),
    ];
    final expiry = subscription.plan.expiryDate;
    if (expiry != null) {
      final local = ZonedCalendar(subscription.timeZoneId).momentAt(expiry);
      tags.add(
        NekokoDateTag(
          date: DateTime.utc(local.year, local.month, local.day),
          note: '套餐到期',
        ),
      );
    }
    final keepAlive = subscription.keepAlive;
    if (keepAlive.required &&
        keepAlive.lastActivityAt != null &&
        keepAlive.cycleDays != null) {
      final deadline = ZonedCalendar(
        subscription.timeZoneId,
      ).addDays(keepAlive.lastActivityAt!, keepAlive.cycleDays!);
      final local = ZonedCalendar(subscription.timeZoneId).momentAt(deadline);
      tags.add(
        NekokoDateTag(
          date: DateTime.utc(local.year, local.month, local.day),
          note: '保号截止',
        ),
      );
    }
    final nickname = NekokoTagCodec.replaceTags(_nickname.text, tags);
    _nickname.text = nickname;
    await Clipboard.setData(ClipboardData(text: nickname));
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已生成并复制到剪贴板'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _applyTags(
    Subscription subscription,
    NekokoDecodeResult decoded,
  ) async {
    setState(() => _saving = true);
    final tags = [
      for (final tag in decoded.tags)
        if (tag case NekokoTextTag(value: final value)) value,
    ];
    final error = await AppScope.of(context).saveSubscription(
      subscription.copyWith(tags: tags, updatedAt: DateTime.now().toUtc()),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? '已更新 ${tags.length} 个订阅标签'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag});

  final NekokoTag tag;

  @override
  Widget build(BuildContext context) {
    return switch (tag) {
      NekokoTextTag(value: final value) => Chip(
        avatar: const Icon(Icons.label_outline_rounded, size: 17),
        label: Text(value),
      ),
      NekokoDateTag(date: final date, note: final note) => Chip(
        avatar: const Icon(Icons.event_outlined, size: 17),
        label: Text(
          '${date.year}-${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}'
          '${note == null ? '' : ' · $note'}',
        ),
      ),
    };
  }
}
