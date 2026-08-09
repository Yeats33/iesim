import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

import '../app/app_scope.dart';
import '../util/formatters.dart';
import '../widgets/activation_qr_view.dart';
import '../widgets/empty_state.dart';
import '../widgets/operator_identity_line.dart';
import '../widgets/section_card.dart';
import '../widgets/status_badge.dart';
import 'affiliate_management_page.dart';
import 'app_binding_management_page.dart';
import 'balance_management_page.dart';
import 'subscription_form_page.dart';

class SubscriptionDetailPage extends StatelessWidget {
  const SubscriptionDetailPage({super.key, required this.subscriptionId});

  final String subscriptionId;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final subscription = controller.subscriptionById(subscriptionId);
    if (subscription == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.sim_card_alert_outlined,
          title: 'Profile 不存在',
          message: '它可能已经在其他页面被删除。',
        ),
      );
    }

    final status = controller.statusOf(subscription);
    final assetProfile = controller.assetProfileForSubscription(subscription);
    final keepAliveEvaluation = controller.keepAliveEvaluationOf(subscription);
    final records = controller.activitiesFor(subscription.id);
    final scheme = Theme.of(context).colorScheme;
    final accent =
        _parseColor(subscription.appearance.cardColorHex) ?? scheme.primary;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(
              profileDisplayName(subscription) ??
                  subscription.operator ??
                  'Profile 详情',
            ),
            backgroundColor: accent.withValues(alpha: .12),
            actions: [
              IconButton(
                tooltip: subscription.details.isPinned ? '取消置顶' : '置顶 Profile',
                onPressed: () => _togglePinned(context, subscription),
                icon: Icon(
                  subscription.details.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                ),
              ),
              IconButton(
                tooltip: '编辑',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SubscriptionFormPage(subscription: subscription),
                  ),
                ),
                icon: const Icon(Icons.edit_outlined),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (value) {
                  switch (value) {
                    case 'activate':
                      _activate(context, subscription);
                      break;
                    case 'archive':
                      _archive(context, subscription);
                      break;
                    case 'restore':
                      _activate(context, subscription);
                      break;
                    case 'delete':
                      _delete(context, subscription);
                      break;
                  }
                },
                itemBuilder: (_) => _menuItems(subscription.lifecycle.stage),
              ),
              const SizedBox(width: 6),
            ],
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.paddingOf(context).bottom + 40,
            ),
            sliver: SliverList.list(
              children: [
                _IdentityHero(
                  subscription: subscription,
                  status: status,
                  accent: accent,
                ),
                const SizedBox(height: 16),
                _LifecycleCard(
                  subscription: subscription,
                  onActivate: () => _activate(context, subscription),
                ),
                if (subscription.activation case final activation?) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'eSIM 二维码',
                    subtitle: '使用兼容设备扫描这份 Profile 的 LPA 激活凭据',
                    child: ActivationQrView(activation: activation),
                  ),
                ],
                if (subscription.lifecycle.stage == ProfileStage.active) ...[
                  const SizedBox(height: 16),
                  _QuickActions(
                    onActivity: (type) =>
                        _showActivitySheet(context, subscription, type),
                  ),
                  const SizedBox(height: 16),
                  _KeepAliveCard(
                    subscription: subscription,
                    status: status,
                    evaluation: keepAliveEvaluation,
                    onSetCompleted: (rule, completed) =>
                        _setKeepAliveRuleCompleted(
                          context,
                          subscription,
                          rule,
                          completed,
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                _PlanCard(subscription: subscription),
                const SizedBox(height: 16),
                SectionCard(
                  title: '余额',
                  subtitle: '当前余额与调整流水',
                  trailing: TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => BalanceManagementPage(
                          subscriptionId: subscription.id,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('管理'),
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child: Icon(Icons.account_balance_wallet_outlined),
                    ),
                    title: Text(
                      subscription.details.currentBalance == null
                          ? '尚未记录'
                          : formatMoney(subscription.details.currentBalance!),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: const Text('余额与流水在同一个事务中保存'),
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: '号码绑定',
                  subtitle: '号码在哪些 App 中用于登录、验证或恢复',
                  trailing: TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => AppBindingManagementPage(
                          subscriptionId: subscription.id,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('管理'),
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child: Icon(Icons.app_registration_rounded),
                    ),
                    title: Text(
                      subscription.details.appBindings.isEmpty
                          ? '尚未记录绑定'
                          : '${subscription.details.appBindings.length} 个 App 绑定',
                    ),
                    subtitle: Text(
                      subscription.details.appBindings.isEmpty
                          ? '可从 WhatsApp 预设开始，或添加自定义 App'
                          : subscription.details.appBindings
                                .map((binding) => binding.appName)
                                .toSet()
                                .join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'AFF',
                  subtitle: '这个 Profile 的优惠码与推荐链接',
                  trailing: TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => AffiliateManagementPage(
                          subscriptionId: subscription.id,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('管理'),
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child: Icon(Icons.handshake_outlined),
                    ),
                    title: Text(
                      subscription.details.affiliateOffers.isEmpty
                          ? '尚未关联 AFF'
                          : '${subscription.details.affiliateOffers.length} 个推荐项目',
                    ),
                    subtitle: Text(
                      subscription.details.affiliateOffers.isEmpty
                          ? '可从 ieSIM 推荐目录添加，或创建自定义项目'
                          : subscription.details.affiliateOffers
                                .map((offer) => offer.brand)
                                .join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: '动作记录',
                  subtitle: records.isEmpty
                      ? '每次保号动作都会留在这里'
                      : '共 ${records.length} 条记录',
                  trailing: subscription.lifecycle.stage == ProfileStage.active
                      ? IconButton.filledTonal(
                          tooltip: '添加记录',
                          onPressed: () => _showActivitySheet(
                            context,
                            subscription,
                            ActivityType.topUp,
                          ),
                          icon: const Icon(Icons.add_rounded),
                        )
                      : null,
                  child: records.isEmpty
                      ? const _NoActivities()
                      : Column(
                          children: [
                            for (var index = 0; index < records.length; index++)
                              _ActivityTile(
                                record: records[index],
                                timeZoneId: subscription.timeZoneId,
                                isLast: index == records.length - 1,
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: '更多资料',
                  child: Column(
                    children: [
                      InfoRow(
                        label: '基准时区',
                        value: subscription.timeZoneId,
                        icon: Icons.public_rounded,
                      ),
                      const Divider(),
                      InfoRow(
                        label: 'ICCID',
                        value: subscription.iccid ?? '未填写',
                        icon: Icons.sim_card_outlined,
                      ),
                      if (subscription.details.isDormant) ...[
                        const Divider(),
                        const InfoRow(
                          label: '状态',
                          value: 'SimHub 休眠卡',
                          icon: Icons.bedtime_outlined,
                        ),
                      ],
                      if (subscription.details.profileClassCode != null) ...[
                        const Divider(),
                        InfoRow(
                          label: 'Profile 类别代码',
                          value: subscription.details.profileClassCode
                              .toString(),
                          icon: Icons.category_outlined,
                        ),
                      ],
                      if (subscription.details.declaredProfileSizeBytes !=
                              null ||
                          subscription.details.installedProfileSizeBytes !=
                              null) ...[
                        const Divider(),
                        InfoRow(
                          label: 'Profile 容量',
                          value: [
                            if (subscription.details.declaredProfileSizeBytes
                                case final size?)
                              '声明 ${formatByteSize(size)}',
                            if (subscription.details.installedProfileSizeBytes
                                case final size?)
                              '实际占用 ${formatByteSize(size)}',
                          ].join(' · '),
                          icon: Icons.data_object_rounded,
                        ),
                      ],
                      if (subscription.details.gid1 != null ||
                          subscription.details.gid2 != null) ...[
                        const Divider(),
                        InfoRow(
                          label: '运营商分组标识',
                          value: [
                            if (subscription.details.gid1 case final gid1?)
                              'GID1 $gid1',
                            if (subscription.details.gid2 case final gid2?)
                              'GID2 $gid2',
                          ].join(' · '),
                          icon: Icons.fingerprint_rounded,
                        ),
                      ],
                      if (subscription.details.countryName != null ||
                          subscription.details.countryCode != null) ...[
                        const Divider(),
                        InfoRow(
                          label: '国家 / 地区',
                          value: [
                            subscription.details.countryName,
                            subscription.details.countryCode,
                          ].whereType<String>().join(' · '),
                          icon: Icons.flag_outlined,
                        ),
                      ],
                      if (subscription.details.mcc != null ||
                          subscription.details.mnc != null) ...[
                        const Divider(),
                        InfoRow(
                          label: '移动网络代码',
                          value: [
                            if (subscription.details.mcc case final mcc?)
                              'MCC $mcc',
                            if (subscription.details.mnc case final mnc?)
                              'MNC $mnc',
                          ].join(' · '),
                          icon: Icons.cell_tower_outlined,
                        ),
                      ],
                      if (subscription.details.apn != null) ...[
                        const Divider(),
                        InfoRow(
                          label: 'APN',
                          value: subscription.details.apn!,
                          icon: Icons.router_outlined,
                        ),
                      ],
                      if (subscription.details.secondaryPhoneNumber !=
                          null) ...[
                        const Divider(),
                        InfoRow(
                          label: '备用号码',
                          value: subscription.details.secondaryPhoneNumber!,
                          icon: Icons.phone_outlined,
                        ),
                      ],
                      if (subscription.details.activationDate != null) ...[
                        const Divider(),
                        InfoRow(
                          label: '激活日期',
                          value: formatZonedDate(
                            subscription.details.activationDate!,
                            subscription.timeZoneId,
                          ),
                          icon: Icons.event_available_outlined,
                        ),
                      ],
                      if (subscription.activation case final activation?) ...[
                        const Divider(),
                        InfoRow(
                          label: 'SM-DP+',
                          value: activation.smdpAddress,
                          icon: Icons.dns_outlined,
                        ),
                        const Divider(),
                        InfoRow(
                          label: '激活码',
                          value: activation.redactedMatchingId,
                          icon: Icons.key_outlined,
                        ),
                      ],
                      const Divider(),
                      InfoRow(
                        label: '标签',
                        value: subscription.tags.isEmpty
                            ? '无'
                            : subscription.tags.join(' · '),
                        icon: Icons.sell_outlined,
                      ),
                      if (controller.showNekokoTags &&
                          assetProfile?.nekokoTagsRaw?.trim().isNotEmpty ==
                              true) ...[
                        const Divider(),
                        InfoRow(
                          label: 'Nekoko Tag',
                          value: assetProfile!.nekokoTagsRaw!,
                          icon: Icons.label_outline_rounded,
                        ),
                      ],
                      if (subscription.appearance.customPrompt != null) ...[
                        const Divider(),
                        InfoRow(
                          label: '提示',
                          value: subscription.appearance.customPrompt!,
                          icon: Icons.lightbulb_outline_rounded,
                        ),
                      ],
                      if (subscription.details.transactionNotes != null) ...[
                        const Divider(),
                        InfoRow(
                          label: '交易备注',
                          value: subscription.details.transactionNotes!,
                          icon: Icons.receipt_long_outlined,
                        ),
                      ],
                      if (subscription.details.carrierAppName != null) ...[
                        const Divider(),
                        InfoRow(
                          label: '运营商 App',
                          value: subscription.details.carrierAppName!,
                          icon: Icons.apps_rounded,
                        ),
                      ],
                      if (subscription.appearance.websiteURL != null) ...[
                        const Divider(),
                        InfoRow(
                          label: '网站',
                          value: subscription.appearance.websiteURL!,
                          icon: Icons.language_rounded,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setKeepAliveRuleCompleted(
    BuildContext context,
    Subscription subscription,
    KeepAliveRuleEvaluation rule,
    bool completed,
  ) async {
    String? note;
    if (completed) {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('确认「${rule.title}」已完成？'),
          content: TextField(
            controller: controller,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '完成备注（可选）',
              hintText: '例如付款订单号、动作发生地区',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认完成'),
            ),
          ],
        ),
      );
      note = controller.text;
      controller.dispose();
      if (confirmed != true || !context.mounted) return;
    }
    final error = await AppScope.of(context).setKeepAliveConstraintCompleted(
      subscriptionId: subscription.id,
      constraintId: rule.id,
      completed: completed,
      note: note,
    );
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _showActivitySheet(
    BuildContext context,
    Subscription subscription,
    ActivityType initialType,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => AppScope(
        controller: AppScope.of(context),
        child: _ActivitySheet(
          subscription: subscription,
          initialType: initialType,
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, Subscription subscription) async {
    final permanent = subscription.lifecycle.stage == ProfileStage.museum;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: Text(permanent ? '永久删除这个 Profile？' : '删除这个 Profile？'),
        content: Text(
          permanent
              ? '${displayPhone(subscription.number)} 及其全部动作记录将永久删除，此操作不可撤销。'
              : '${displayPhone(subscription.number)} 会进入过期博物馆；套餐、号码和动作记录都会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(permanent ? '永久删除' : '移入博物馆'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await AppScope.of(
      context,
    ).deleteSubscription(subscription.id);
    if (!context.mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _activate(
    BuildContext context,
    Subscription subscription,
  ) async {
    final restoring = subscription.lifecycle.stage == ProfileStage.museum;
    final error = await AppScope.of(context).activateProfile(subscription.id);
    if (!context.mounted) return;
    _message(context, error ?? (restoring ? '已恢复为已激活 Profile' : 'Profile 已激活'));
  }

  Future<void> _togglePinned(
    BuildContext context,
    Subscription subscription,
  ) async {
    final willPin = !subscription.details.isPinned;
    final error = await AppScope.of(
      context,
    ).setSubscriptionPinned(subscription.id, willPin);
    if (context.mounted) {
      _message(context, error ?? (willPin ? 'Profile 已置顶' : '已取消置顶'));
    }
  }

  Future<void> _archive(BuildContext context, Subscription subscription) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.museum_outlined),
        title: const Text('移入过期博物馆？'),
        content: const Text('Profile 资料和历史动作会保留，但不会继续生成新的提醒。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移入博物馆'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await AppScope.of(context).archiveProfile(subscription.id);
    if (context.mounted) _message(context, error ?? '已移入过期博物馆');
  }

  static List<PopupMenuEntry<String>> _menuItems(ProfileStage stage) => [
    if (stage == ProfileStage.pendingActivation)
      const PopupMenuItem(
        value: 'activate',
        child: Row(
          children: [
            Icon(Icons.bolt_rounded),
            SizedBox(width: 12),
            Text('激活 Profile'),
          ],
        ),
      ),
    if (stage == ProfileStage.museum)
      const PopupMenuItem(
        value: 'restore',
        child: Row(
          children: [
            Icon(Icons.restore_rounded),
            SizedBox(width: 12),
            Text('恢复为已激活'),
          ],
        ),
      ),
    if (stage != ProfileStage.museum)
      const PopupMenuItem(
        value: 'archive',
        child: Row(
          children: [
            Icon(Icons.museum_outlined),
            SizedBox(width: 12),
            Text('移入过期博物馆'),
          ],
        ),
      ),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: 'delete',
      child: Row(
        children: [
          const Icon(Icons.delete_outline_rounded),
          const SizedBox(width: 12),
          Text(stage == ProfileStage.museum ? '永久删除 Profile' : '删除 Profile'),
        ],
      ),
    ),
  ];

  static void _message(BuildContext context, String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
    );
  }

  static Color? _parseColor(String? value) {
    if (value == null) return null;
    final parsed = int.tryParse(value.replaceFirst('#', ''), radix: 16);
    return parsed == null ? null : Color(0xFF000000 | parsed);
  }
}

class _IdentityHero extends StatelessWidget {
  const _IdentityHero({
    required this.subscription,
    required this.status,
    required this.accent,
  });

  final Subscription subscription;
  final KeepAliveStatus status;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, Color.lerp(accent, Colors.black, .28)!],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -26,
            top: -42,
            child: Icon(
              Icons.sim_card_rounded,
              size: 160,
              color: Colors.white.withValues(alpha: .08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OperatorIdentityLine(
                      subscription: subscription,
                      iconSize: 32,
                      iconBackgroundColor: Colors.white,
                      textStyle: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(
                            color: Colors.white.withValues(alpha: .86),
                          ),
                    ),
                  ),
                  Icon(
                    Icons.contactless_rounded,
                    color: Colors.white.withValues(alpha: .74),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Text(
                displayProfileIdentity(subscription),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .4,
                ),
              ),
              if (profileDisplayName(subscription) != null &&
                  !subscription.number.isUnknown) ...[
                const SizedBox(height: 5),
                Text(
                  displayPhone(subscription.number),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: .82),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: subscription.lifecycle.stage == ProfileStage.active
                    ? StatusBadge(status: status, compact: true)
                    : _LifecycleLabel(lifecycle: subscription.lifecycle),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LifecycleCard extends StatelessWidget {
  const _LifecycleCard({required this.subscription, required this.onActivate});

  final Subscription subscription;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final lifecycle = subscription.lifecycle;
    final stage = lifecycle.stage;
    final rows = <Widget>[];
    if (stage == ProfileStage.active) {
      rows.add(
        InfoRow(
          label: '设备状态',
          value: _deviceStateLabel(lifecycle.deviceState),
          icon: Icons.power_settings_new_rounded,
        ),
      );
      if (lifecycle.serviceExpiresAt != null) {
        rows.addAll([
          const Divider(),
          InfoRow(
            label: 'Profile 服务到期',
            value: formatZonedDate(
              lifecycle.serviceExpiresAt!,
              subscription.timeZoneId,
            ),
            icon: Icons.event_busy_outlined,
          ),
        ]);
      }
    } else if (stage == ProfileStage.pendingActivation) {
      if (lifecycle.activationDeadline != null) {
        rows.add(
          InfoRow(
            label: '最晚激活日期',
            value: formatZonedDate(
              lifecycle.activationDeadline!,
              subscription.timeZoneId,
            ),
            icon: Icons.event_outlined,
          ),
        );
      }
      if (lifecycle.activationRequirements != null) {
        if (rows.isNotEmpty) rows.add(const Divider());
        rows.add(
          InfoRow(
            label: '激活要求',
            value: lifecycle.activationRequirements!,
            icon: Icons.rule_rounded,
          ),
        );
      }
      if (rows.isEmpty) {
        rows.add(const Text('尚未设置激活期限或要求，可通过编辑补充。'));
      }
      rows.addAll([
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onActivate,
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('标记为已激活'),
          ),
        ),
      ]);
    } else {
      rows.add(
        InfoRow(
          label: '进入原因',
          value: _archiveReasonLabel(lifecycle.archiveReason),
          icon: Icons.inventory_2_outlined,
        ),
      );
      if (lifecycle.archivedAt != null) {
        rows.addAll([
          const Divider(),
          InfoRow(
            label: '归档日期',
            value: formatZonedDate(
              lifecycle.archivedAt!,
              subscription.timeZoneId,
            ),
            icon: Icons.event_available_outlined,
          ),
        ]);
      }
      rows.addAll([
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onActivate,
            icon: const Icon(Icons.restore_rounded),
            label: const Text('恢复为已激活 Profile'),
          ),
        ),
      ]);
    }

    return SectionCard(
      title: switch (stage) {
        ProfileStage.active => '已激活 Profile',
        ProfileStage.pendingActivation => '未激活 Profile',
        ProfileStage.museum => '过期博物馆',
      },
      subtitle: stage == ProfileStage.active
          ? 'Enabled 与 Disabled 都属于这一类'
          : null,
      child: Column(children: rows),
    );
  }

  static String _deviceStateLabel(ProfileDeviceState state) => switch (state) {
    ProfileDeviceState.unknown => '未知 / 不适用',
    ProfileDeviceState.enabled => '已启用（Enabled）',
    ProfileDeviceState.disabled => '已停用（Disabled）',
  };

  static String _archiveReasonLabel(ProfileArchiveReason? reason) =>
      switch (reason) {
        ProfileArchiveReason.manual => '手动移入',
        ProfileArchiveReason.deleted => '从已激活列表删除',
        ProfileArchiveReason.expired => '服务到期后自动移入',
        ProfileArchiveReason.imported => '直接导入博物馆',
        null => '未记录',
      };
}

class _LifecycleLabel extends StatelessWidget {
  const _LifecycleLabel({required this.lifecycle});

  final ProfileLifecycle lifecycle;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        lifecycle.stage == ProfileStage.museum
            ? Icons.museum_outlined
            : Icons.pending_outlined,
        size: 16,
      ),
      const SizedBox(width: 6),
      Text(
        lifecycle.stage == ProfileStage.museum ? '过期博物馆' : '等待激活',
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onActivity});

  final ValueChanged<ActivityType> onActivity;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            icon: Icons.add_card_rounded,
            label: '充值',
            onTap: () => onActivity(ActivityType.topUp),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            icon: Icons.call_outlined,
            label: '通话',
            onTap: () => onActivity(ActivityType.call),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            icon: Icons.sms_outlined,
            label: '短信',
            onTap: () => onActivity(ActivityType.sms),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            icon: Icons.autorenew_rounded,
            label: '续费',
            onTap: () => onActivity(ActivityType.renewal),
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, color: scheme.primary, size: 23),
              const SizedBox(height: 7),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeepAliveCard extends StatelessWidget {
  const _KeepAliveCard({
    required this.subscription,
    required this.status,
    required this.evaluation,
    required this.onSetCompleted,
  });

  final Subscription subscription;
  final KeepAliveStatus status;
  final KeepAliveEvaluation evaluation;
  final void Function(KeepAliveRuleEvaluation rule, bool completed)
  onSetCompleted;

  @override
  Widget build(BuildContext context) {
    final keepAlive = subscription.keepAlive;
    final deadline =
        keepAlive.lastActivityAt != null &&
            keepAlive.cycleDays != null &&
            keepAlive.required
        ? ZonedCalendar(
            subscription.timeZoneId,
          ).addDays(keepAlive.lastActivityAt!, keepAlive.cycleDays!)
        : null;
    final info = describeStatus(status);
    final actionableCount = evaluation.actionableRules.length;
    return SectionCard(
      title: '保号状态',
      subtitle: actionableCount == 0
          ? info.description
          : '$actionableCount 条规则需要处理 · ${info.description}',
      trailing: StatusBadge(status: status, compact: true),
      child: Column(
        children: [
          InfoRow(
            label: '保号周期',
            value: keepAlive.required
                ? (keepAlive.cycleDays == null
                      ? '未知'
                      : '${keepAlive.cycleDays} 天')
                : '无需保号',
            icon: Icons.autorenew_rounded,
          ),
          const Divider(),
          InfoRow(
            label: '上次动作',
            value: keepAlive.lastActivityAt == null
                ? '未知'
                : '${formatZonedDate(keepAlive.lastActivityAt!, subscription.timeZoneId)}'
                      '${keepAlive.confidence == DataConfidence.inferred ? '（推测）' : ''}',
            icon: Icons.history_rounded,
          ),
          const Divider(),
          InfoRow(
            label: '保号截止',
            value: deadline == null
                ? '未知'
                : '${formatZonedDate(deadline, subscription.timeZoneId)} '
                      '(${subscription.timeZoneId})',
            icon: Icons.event_available_outlined,
          ),
          if (keepAlive.required) ...[
            const Divider(),
            InfoRow(
              label: '有效动作',
              value: keepAlive.policy.qualifyingActions
                  .map(_keepAliveActionLabel)
                  .join('、'),
              icon: Icons.rule_rounded,
            ),
            if (keepAlive.policy.summary case final summary?) ...[
              const Divider(),
              InfoRow(label: '规则说明', value: summary, icon: Icons.notes_rounded),
            ],
            for (final rule in evaluation.rules.where(
              (item) => item.id != 'cycle',
            )) ...[
              const Divider(),
              _KeepAliveRuleTile(
                rule: rule,
                timeZoneId: subscription.timeZoneId,
                manuallyCompleted: keepAlive.policy.constraints.any(
                  (constraint) =>
                      constraint.id == rule.id &&
                      constraint.completedAt != null,
                ),
                onSetCompleted: (completed) => onSetCompleted(rule, completed),
              ),
            ],
            if (keepAlive.policy.sourceLabel case final source?) ...[
              const Divider(),
              InfoRow(
                label: '规则来源',
                value: source,
                icon: Icons.verified_outlined,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _KeepAliveRuleTile extends StatelessWidget {
  const _KeepAliveRuleTile({
    required this.rule,
    required this.timeZoneId,
    required this.manuallyCompleted,
    required this.onSetCompleted,
  });

  final KeepAliveRuleEvaluation rule;
  final String timeZoneId;
  final bool manuallyCompleted;
  final ValueChanged<bool> onSetCompleted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, statusText) = switch (rule.state) {
      KeepAliveRuleState.satisfied => (
        Icons.task_alt_rounded,
        scheme.primary,
        rule.completedLate ? '已完成，但晚于期限' : '已完成',
      ),
      KeepAliveRuleState.safe => (
        Icons.shield_outlined,
        scheme.primary,
        '剩余 ${rule.daysRemaining ?? 0} 天',
      ),
      KeepAliveRuleState.dueSoon => (
        Icons.notification_important_outlined,
        scheme.tertiary,
        '剩余 ${rule.daysRemaining ?? 0} 天',
      ),
      KeepAliveRuleState.overdue => (
        Icons.error_outline_rounded,
        scheme.error,
        '已超期 ${-(rule.daysRemaining ?? 0)} 天',
      ),
      KeepAliveRuleState.pending => (
        Icons.schedule_rounded,
        scheme.secondary,
        '等待起算或有效动作',
      ),
      KeepAliveRuleState.needsConfirmation => (
        Icons.fact_check_outlined,
        scheme.tertiary,
        '需要手动确认',
      ),
      KeepAliveRuleState.unknown => (
        Icons.help_outline_rounded,
        scheme.error,
        '缺少判定资料',
      ),
      KeepAliveRuleState.notApplicable => (
        Icons.remove_circle_outline,
        scheme.outline,
        '不适用',
      ),
    };
    final metadata = <String>[
      statusText,
      if (rule.deadlineUtc != null)
        '截止 ${formatZonedDate(rule.deadlineUtc!, timeZoneId)}',
      if (rule.regions.isNotEmpty) '地区 ${rule.regions.join(' / ')}',
      if (rule.evidenceAt != null)
        '证据 ${formatZonedDate(rule.evidenceAt!, timeZoneId)}',
      if (rule.inferred) '起算日期为推测值',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rule.title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  metadata.join(' · '),
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  rule.details,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (manuallyCompleted || rule.requiresManualConfirmation) ...[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () => onSetCompleted(!manuallyCompleted),
                    icon: Icon(
                      manuallyCompleted
                          ? Icons.undo_rounded
                          : Icons.check_rounded,
                      size: 18,
                    ),
                    label: Text(manuallyCompleted ? '撤销手动确认' : '确认已完成'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.subscription});

  final Subscription subscription;

  @override
  Widget build(BuildContext context) {
    final plan = subscription.plan;
    return SectionCard(
      title: '套餐信息',
      subtitle: plan.isLongTerm ? '长期套餐' : '周期套餐',
      child: Column(
        children: [
          InfoRow(
            label: '套餐名称',
            value: plan.name ?? '未填写',
            icon: Icons.layers_outlined,
          ),
          const Divider(),
          InfoRow(
            label: '周期资费',
            value: plan.cyclePrice == null
                ? '未知'
                : formatMoney(plan.cyclePrice!),
            icon: Icons.payments_outlined,
          ),
          const Divider(),
          InfoRow(
            label: '计费周期',
            value: plan.cycleDays == null ? '未知' : '${plan.cycleDays} 天',
            icon: Icons.calendar_view_month_outlined,
          ),
          const Divider(),
          InfoRow(
            label: '套餐开始',
            value: plan.startDate == null
                ? '未填写'
                : '${formatZonedDate(plan.startDate!, subscription.timeZoneId)} '
                      '(${subscription.timeZoneId})',
            icon: Icons.event_available_outlined,
          ),
          const Divider(),
          InfoRow(
            label: '套餐到期',
            value: plan.expiryDate == null
                ? (plan.isLongTerm ? '长期有效' : '未知')
                : '${formatZonedDate(plan.expiryDate!, subscription.timeZoneId)} '
                      '(${subscription.timeZoneId})',
            icon: Icons.event_outlined,
          ),
        ],
      ),
    );
  }
}

class _NoActivities extends StatelessWidget {
  const _NoActivities();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '完成充值、通话、短信或续费后，点上方快捷按钮记录。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.record,
    required this.timeZoneId,
    required this.isLast,
  });

  final ActivityRecord record;
  final String timeZoneId;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _activityIcon(record.type),
                size: 18,
                color: scheme.primary,
              ),
            ),
            if (!isLast)
              Container(width: 2, height: 36, color: scheme.outlineVariant),
          ],
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 4, bottom: isLast ? 0 : 22),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activityName(record.type),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        formatZonedDateTime(record.occurredAt, timeZoneId),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (record.amount != null)
                  Text(
                    formatMoney(record.amount!),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivitySheet extends StatefulWidget {
  const _ActivitySheet({required this.subscription, required this.initialType});

  final Subscription subscription;
  final ActivityType initialType;

  @override
  State<_ActivitySheet> createState() => _ActivitySheetState();
}

class _ActivitySheetState extends State<_ActivitySheet> {
  late ActivityType _type;
  late final TextEditingController _amount;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _amount = TextEditingController();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('记录保号动作', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 5),
          Text(
            displayPhone(widget.subscription.number),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in ActivityType.values.where(
                  (value) => value != ActivityType.balanceChange,
                ))
                  ChoiceChip(
                    selected: _type == type,
                    avatar: Icon(_activityIcon(type), size: 17),
                    label: Text(activityName(type)),
                    onSelected: (_) => setState(() => _type = type),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '金额（可选）',
              hintText: '0.00',
              prefixIcon: const Icon(Icons.payments_outlined),
              suffixText:
                  widget.subscription.plan.cyclePrice?.currencyCode ?? 'CNY',
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.update_rounded, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text('保存后，上次动作日期将更新为现在。')),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? '正在记录…' : '完成记录'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final minorUnits = _parseMinorUnits(_amount.text);
    if (_amount.text.trim().isNotEmpty && minorUnits == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('金额格式不正确，最多两位小数')));
      return;
    }
    setState(() => _saving = true);
    final currency = widget.subscription.plan.cyclePrice?.currencyCode ?? 'CNY';
    final error = await AppScope.of(context).recordActivity(
      subscription: widget.subscription,
      type: _type,
      occurredAt: DateTime.now().toUtc(),
      amount: minorUnits == null
          ? null
          : Money(minorUnits: minorUnits, currencyCode: currency),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
    }
  }

  static int? _parseMinorUnits(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final decimals = (match.group(2) ?? '').padRight(2, '0');
    return whole * 100 + int.parse(decimals.isEmpty ? '0' : decimals);
  }
}

IconData _activityIcon(ActivityType type) => switch (type) {
  ActivityType.topUp => Icons.add_card_rounded,
  ActivityType.call => Icons.call_outlined,
  ActivityType.sms => Icons.sms_outlined,
  ActivityType.renewal => Icons.autorenew_rounded,
  ActivityType.mobileData => Icons.data_usage_rounded,
  ActivityType.planPurchase => Icons.shopping_bag_outlined,
  ActivityType.balanceChange => Icons.account_balance_wallet_outlined,
  ActivityType.other => Icons.more_horiz_rounded,
};

String _keepAliveActionLabel(KeepAliveAction action) => switch (action) {
  KeepAliveAction.mobileData => '使用流量',
  KeepAliveAction.call => '通话',
  KeepAliveAction.sms => '短信',
  KeepAliveAction.topUp => '充值',
  KeepAliveAction.planPurchase => '购买套餐',
  KeepAliveAction.renewal => '续费',
  KeepAliveAction.balanceChange => '余额变动',
  KeepAliveAction.other => '其他动作',
};
