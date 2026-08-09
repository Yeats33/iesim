import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

import '../services/home_action_center.dart';
import '../util/formatters.dart';

class HomeActionCenterPanel extends StatelessWidget {
  const HomeActionCenterPanel({
    super.key,
    required this.actions,
    required this.subscriptionFor,
    required this.onOpen,
    required this.onViewAll,
  });

  final List<HomeActionItem> actions;
  final Subscription? Function(String id) subscriptionFor;
  final ValueChanged<HomeActionItem> onOpen;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (actions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: .52),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Icon(Icons.task_alt_rounded, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '行动中心已清空',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    '没有临近期限、待确认规则或缺失资料',
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

    final visible = actions.take(5).toList(growable: false);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 17, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.bolt_rounded,
                    color: scheme.onTertiaryContainer,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '行动中心',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${actions.length} 项按紧急程度排序',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(onPressed: onViewAll, child: const Text('全部提醒')),
              ],
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < visible.length; index++) ...[
              if (index > 0) Divider(color: scheme.outlineVariant),
              _ActionRow(
                action: visible[index],
                subscription: subscriptionFor(visible[index].subscriptionId),
                onTap: () => onOpen(visible[index]),
              ),
            ],
            if (actions.length > visible.length)
              Padding(
                padding: const EdgeInsets.only(top: 5, bottom: 4),
                child: Center(
                  child: TextButton(
                    onPressed: onViewAll,
                    child: Text('还有 ${actions.length - visible.length} 项'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.action,
    required this.subscription,
    required this.onTap,
  });

  final HomeActionItem action;
  final Subscription? subscription;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, foreground, background) = switch (action.urgency) {
      HomeActionUrgency.critical => (
        Icons.error_outline_rounded,
        scheme.error,
        scheme.errorContainer,
      ),
      HomeActionUrgency.warning => (
        Icons.schedule_rounded,
        scheme.tertiary,
        scheme.tertiaryContainer,
      ),
      HomeActionUrgency.confirmation => (
        Icons.fact_check_outlined,
        scheme.secondary,
        scheme.secondaryContainer,
      ),
      HomeActionUrgency.data => (
        Icons.edit_note_rounded,
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      ),
    };
    final item = subscription;
    final profileLabel = item == null
        ? 'Profile'
        : profileDisplayName(item) ??
              item.operator ??
              displayPhone(item.number);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: foreground, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$profileLabel · ${action.description}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
