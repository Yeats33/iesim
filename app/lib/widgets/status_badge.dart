import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

enum StatusTone { safe, warning, danger, neutral, info }

class StatusInfo {
  const StatusInfo({
    required this.label,
    required this.description,
    required this.tone,
    required this.icon,
    this.inferred = false,
  });

  final String label;
  final String description;
  final StatusTone tone;
  final IconData icon;
  final bool inferred;
}

StatusInfo describeStatus(KeepAliveStatus status) => switch (status) {
  Safe(daysLeft: final days, inferred: final inferred) => StatusInfo(
    label: '安全 · $days 天',
    description: '距离下一次保号动作还有 $days 天',
    tone: StatusTone.safe,
    icon: Icons.shield_rounded,
    inferred: inferred,
  ),
  DueSoon(daysLeft: final days, inferred: final inferred) => StatusInfo(
    label: days == 0 ? '今天截止' : '$days 天后截止',
    description: days == 0 ? '建议今天完成保号动作' : '临近保号期限，请尽快处理',
    tone: StatusTone.warning,
    icon: Icons.schedule_rounded,
    inferred: inferred,
  ),
  Overdue(daysOver: final days, inferred: final inferred) => StatusInfo(
    label: '已逾期 $days 天',
    description: '保号期限已过，请立即核实号码状态',
    tone: StatusTone.danger,
    icon: Icons.error_rounded,
    inferred: inferred,
  ),
  NotRequired() => const StatusInfo(
    label: '无需保号',
    description: '此 Profile 没有周期性保号要求',
    tone: StatusTone.info,
    icon: Icons.all_inclusive_rounded,
  ),
  Unknown() => const StatusInfo(
    label: '状态未知',
    description: '补充保号周期与上次动作时间后可计算',
    tone: StatusTone.neutral,
    icon: Icons.help_rounded,
  ),
};

({Color foreground, Color background}) statusColors(
  BuildContext context,
  StatusTone tone,
) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (tone) {
    StatusTone.safe => (
      foreground: dark ? const Color(0xFF83D8B5) : const Color(0xFF167451),
      background: dark ? const Color(0xFF153A2D) : const Color(0xFFE0F3EA),
    ),
    StatusTone.warning => (
      foreground: dark ? const Color(0xFFFFC86D) : const Color(0xFF985C00),
      background: dark ? const Color(0xFF493513) : const Color(0xFFFFEBC7),
    ),
    StatusTone.danger => (
      foreground: dark ? const Color(0xFFFFA48F) : const Color(0xFFA73924),
      background: dark ? const Color(0xFF4D241D) : const Color(0xFFFFE1DA),
    ),
    StatusTone.neutral => (
      foreground: Theme.of(context).colorScheme.onSurfaceVariant,
      background: Theme.of(context).colorScheme.surfaceContainerHighest,
    ),
    StatusTone.info => (
      foreground: dark ? const Color(0xFF9FC9FF) : const Color(0xFF245C9E),
      background: dark ? const Color(0xFF1B3554) : const Color(0xFFE3EEFC),
    ),
  };
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.compact = false});

  final KeepAliveStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final info = describeStatus(status);
    final colors = statusColors(context, info.tone);
    return Semantics(
      label: '${info.label}${info.inferred ? '，推测值' : ''}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(info.icon, size: compact ? 14 : 16, color: colors.foreground),
            const SizedBox(width: 6),
            Text(
              info.label,
              style: TextStyle(
                color: colors.foreground,
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (info.inferred) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: '根据创建时间推测，请确认',
                child: Icon(
                  Icons.help_outline_rounded,
                  size: compact ? 13 : 15,
                  color: colors.foreground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
