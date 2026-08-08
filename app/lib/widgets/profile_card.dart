import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.profile,
    required this.eid,
    required this.onTap,
  });

  final EsimProfile profile;
  final Euicc? eid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nickname = _plainNickname(profile.nickname);
    final tags = _tags(profile.nickname);
    final provider = _provider(profile);
    return Semantics(
      button: true,
      label: '$provider，eSIM Profile',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 5, color: scheme.tertiary),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                provider,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                nickname ?? 'eSIM Profile',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .1,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (profile.isPinned) ...[
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 13,
                                  color: scheme.onTertiaryContainer,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                profile.isPinned ? '置顶' : 'Profile',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: scheme.onTertiaryContainer,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Divider(color: scheme.outlineVariant.withValues(alpha: .6)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _Meta(
                            icon: Icons.sim_card_outlined,
                            label: 'ICCID',
                            value: _ending(profile.iccid),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 32,
                          color: scheme.outlineVariant,
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: _Meta(
                            icon: Icons.memory_rounded,
                            label: 'eUICC',
                            value: eid?.label ?? '已关联 EID',
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final tag in tags.take(3))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.tertiary.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                  color: scheme.tertiary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (tags.length > 3)
                            Text(
                              '+${tags.length - 3}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileDetailsSheet extends StatelessWidget {
  const ProfileDetailsSheet({
    super.key,
    required this.profile,
    this.eid,
    this.onTogglePin,
  });

  final EsimProfile profile;
  final Euicc? eid;
  final Future<void> Function()? onTogglePin;

  @override
  Widget build(BuildContext context) {
    final nickname = _plainNickname(profile.nickname);
    final tags = _tags(profile.nickname);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _provider(profile),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (onTogglePin != null)
                  IconButton.filledTonal(
                    tooltip: profile.isPinned ? '取消置顶' : '置顶 Profile',
                    onPressed: onTogglePin,
                    icon: Icon(
                      profile.isPinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                    ),
                  ),
              ],
            ),
            if (nickname != null) ...[
              const SizedBox(height: 4),
              Text(
                nickname,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 22),
            _DetailRow(label: 'ICCID', value: profile.iccid ?? '未提供'),
            const SizedBox(height: 14),
            _DetailRow(label: 'EID', value: eid?.value ?? '已关联，暂无可显示信息'),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Nekoko 标签', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final tag in tags) Chip(label: Text(tag))],
              ),
            ],
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text('手机号是可选资料。没有号码的流量型或旅行型 Profile 也可以正常保存和管理。'),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 17, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 3),
      SelectableText(value, style: Theme.of(context).textTheme.bodyLarge),
    ],
  );
}

String _provider(EsimProfile profile) {
  final value = profile.operatorName?.trim();
  return value == null || value.isEmpty ? '未识别运营商' : value;
}

String? _plainNickname(String? nickname) {
  if (nickname == null) return null;
  final value = NekokoTagCodec.replaceTags(nickname, const []).trim();
  return value.isEmpty ? null : value;
}

List<String> _tags(String? nickname) {
  if (nickname == null || nickname.trim().isEmpty) return const [];
  return [
    for (final tag in NekokoTagCodec.decode(nickname).tags)
      switch (tag) {
        NekokoTextTag(value: final value) => value,
        NekokoDateTag(date: final date, note: final note) =>
          '${date.year.toString().padLeft(4, '0')}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}'
              '${note == null ? '' : ' · $note'}',
      },
  ];
}

String _ending(String? value) {
  if (value == null || value.trim().isEmpty) return '未提供';
  final normalized = value.trim();
  return normalized.length <= 8
      ? normalized
      : '•••• ${normalized.substring(normalized.length - 8)}';
}
