import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

import '../util/formatters.dart';
import 'activation_qr_view.dart';
import 'status_badge.dart';

class SubscriptionCard extends StatefulWidget {
  const SubscriptionCard({
    super.key,
    required this.subscription,
    required this.status,
    required this.onTap,
  });

  final Subscription subscription;
  final KeepAliveStatus status;
  final VoidCallback onTap;

  @override
  State<SubscriptionCard> createState() => _SubscriptionCardState();
}

class _SubscriptionCardState extends State<SubscriptionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final subscription = widget.subscription;
    final scheme = Theme.of(context).colorScheme;
    final accent =
        _parseColor(subscription.appearance.cardColorHex) ?? scheme.primary;
    final profileName = profileDisplayName(subscription);
    final deadline = _deadline(subscription);
    final lifecycleDate = switch (subscription.lifecycle.stage) {
      ProfileStage.pendingActivation =>
        subscription.lifecycle.activationDeadline,
      ProfileStage.museum => subscription.lifecycle.archivedAt,
      ProfileStage.active => deadline,
    };
    final lifecycleLabel = switch (subscription.lifecycle.stage) {
      ProfileStage.pendingActivation => '激活期限',
      ProfileStage.museum => '归档日期',
      ProfileStage.active => deadline == null ? '套餐到期' : '保号截止',
    };
    return Semantics(
      button: true,
      label:
          '${subscription.operator ?? '未知运营商'}，${displayProfileIdentity(subscription)}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 5, color: accent),
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
                              Row(
                                children: [
                                  if (subscription.appearance.flag != null) ...[
                                    Text(
                                      subscription.appearance.flag!,
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: Text(
                                      subscription.operator
                                                  ?.trim()
                                                  .isNotEmpty ==
                                              true
                                          ? subscription.operator!
                                          : '未填写运营商',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  if (subscription.details.isDormant) ...[
                                    const SizedBox(width: 7),
                                    Tooltip(
                                      message: '休眠卡（来自兼容数据）',
                                      child: Icon(
                                        Icons.bedtime_outlined,
                                        size: 17,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                displayProfileIdentity(subscription),
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .2,
                                    ),
                              ),
                              if (profileName != null &&
                                  !subscription.number.isUnknown) ...[
                                const SizedBox(height: 3),
                                Text(
                                  displayPhone(subscription.number),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (subscription.details.isPinned) ...[
                              Tooltip(
                                message: '已置顶',
                                child: Icon(
                                  Icons.push_pin_rounded,
                                  size: 19,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            _LifecycleBadge(
                              lifecycle: subscription.lifecycle,
                              status: widget.status,
                            ),
                          ],
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
                            icon: Icons.layers_outlined,
                            label: '套餐',
                            value: subscription.plan.name ?? '未设置',
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
                            icon: Icons.event_outlined,
                            label: lifecycleLabel,
                            value: lifecycleDate == null
                                ? subscription.lifecycle.stage ==
                                          ProfileStage.active
                                      ? _expiryLabel(subscription)
                                      : '未设置'
                                : formatZonedDate(
                                    lifecycleDate,
                                    subscription.timeZoneId,
                                  ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    if (subscription.tags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final tag in subscription.tags.take(3))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                '#$tag',
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (subscription.tags.length > 3)
                            Text(
                              '+${subscription.tags.length - 3}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    Divider(color: scheme.outlineVariant.withValues(alpha: .6)),
                    Semantics(
                      button: true,
                      expanded: _expanded,
                      child: InkWell(
                        key: ValueKey(
                          'profile-card-expander-${subscription.id}',
                        ),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Icon(
                                subscription.activation == null
                                    ? Icons.info_outline_rounded
                                    : Icons.qr_code_2_rounded,
                                size: 19,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  _expanded
                                      ? subscription.activation == null
                                            ? '收起其他信息'
                                            : '收起二维码与其他信息'
                                      : subscription.activation == null
                                      ? '展开其他信息'
                                      : '展开二维码与其他信息',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Icon(
                                _expanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_expanded) ...[
                      const SizedBox(height: 10),
                      _ProfileCardExtraInfo(subscription: subscription),
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

  static DateTime? _deadline(Subscription subscription) {
    final last = subscription.keepAlive.lastActivityAt;
    final days = subscription.keepAlive.cycleDays;
    if (!subscription.keepAlive.required || last == null || days == null) {
      return null;
    }
    return ZonedCalendar(subscription.timeZoneId).addDays(last, days);
  }

  static String _expiryLabel(Subscription subscription) {
    final expiry = subscription.plan.expiryDate;
    if (expiry == null) return '未知';
    return formatZonedDate(expiry, subscription.timeZoneId);
  }

  static Color? _parseColor(String? value) {
    if (value == null) return null;
    final hex = value.replaceFirst('#', '');
    if (hex.length != 6 && hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return Color(hex.length == 6 ? 0xFF000000 | parsed : parsed);
  }
}

class _ProfileCardExtraInfo extends StatelessWidget {
  const _ProfileCardExtraInfo({required this.subscription});

  final Subscription subscription;

  @override
  Widget build(BuildContext context) {
    final details = subscription.details;
    final activation = subscription.activation;
    final rows = <({String label, String value})>[
      if (!subscription.number.isUnknown)
        (label: '手机号', value: displayPhone(subscription.number)),
      if (subscription.iccid case final iccid?) (label: 'ICCID', value: iccid),
      if (details.countryName != null || details.countryCode != null)
        (
          label: '国家 / 地区',
          value: [
            details.countryName,
            details.countryCode,
          ].whereType<String>().join(' · '),
        ),
      if (details.mcc != null || details.mnc != null)
        (
          label: '移动网络代码',
          value: [
            if (details.mcc case final mcc?) 'MCC $mcc',
            if (details.mnc case final mnc?) 'MNC $mnc',
          ].join(' · '),
        ),
      if (details.apn case final apn?) (label: 'APN', value: apn),
      if (activation != null) ...[
        (label: 'SM-DP+', value: activation.smdpAddress),
        (label: '激活码', value: activation.redactedMatchingId),
      ],
      (label: '基准时区', value: subscription.timeZoneId),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('profile-card-extra-${subscription.id}'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activation != null) ...[
            ActivationQrView(activation: activation, size: 176, compact: true),
            const SizedBox(height: 16),
            Divider(color: scheme.outlineVariant),
            const SizedBox(height: 4),
          ],
          for (var index = 0; index < rows.length; index++) ...[
            _ExpandedInfoRow(
              label: rows[index].label,
              value: rows[index].value,
            ),
            if (index != rows.length - 1)
              Divider(color: scheme.outlineVariant.withValues(alpha: .7)),
          ],
        ],
      ),
    );
  }
}

class _ExpandedInfoRow extends StatelessWidget {
  const _ExpandedInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SelectableText(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _LifecycleBadge extends StatelessWidget {
  const _LifecycleBadge({required this.lifecycle, required this.status});

  final ProfileLifecycle lifecycle;
  final KeepAliveStatus status;

  @override
  Widget build(BuildContext context) {
    if (lifecycle.stage == ProfileStage.active) {
      return StatusBadge(status: status, compact: true);
    }
    final scheme = Theme.of(context).colorScheme;
    final museum = lifecycle.stage == ProfileStage.museum;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: museum
            ? scheme.surfaceContainerHighest
            : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            museum ? Icons.museum_outlined : Icons.pending_outlined,
            size: 14,
            color: museum
                ? scheme.onSurfaceVariant
                : scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 5),
          Text(
            museum ? '博物馆' : '待激活',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: museum
                  ? scheme.onSurfaceVariant
                  : scheme.onTertiaryContainer,
            ),
          ),
        ],
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
