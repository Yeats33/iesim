import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

import '../app/app_scope.dart';
import '../app/brand.dart';
import '../app/theme.dart';
import '../data/app_controller.dart';
import '../widgets/app_logo.dart';
import '../widgets/empty_state.dart';
import '../widgets/profile_card.dart';
import '../widgets/subscription_card.dart';
import 'data_exchange_page.dart';
import 'subscription_detail_page.dart';
import 'subscription_form_page.dart';

enum _Filter { all, attention, safe, unknown }

class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  ProfileStage _stage = ProfileStage.active;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final subscriptions = controller.subscriptions;
    final profiles = controller.assets.profiles;
    final claimedProfileIds = <String>{};
    final entries = <_ProfileEntry>[];
    for (final subscription in subscriptions) {
      EsimProfile? profile;
      for (final candidate in profiles) {
        if (candidate.subscriptionId == subscription.id) {
          profile = candidate;
          break;
        }
      }
      final subscriptionIccid = subscription.iccid;
      if (profile == null && subscriptionIccid != null) {
        for (final candidate in profiles) {
          if (candidate.subscriptionId == null &&
              candidate.iccid == subscriptionIccid) {
            profile = candidate;
            break;
          }
        }
      }
      if (profile != null) claimedProfileIds.add(profile.id);
      entries.add(_ProfileEntry(subscription: subscription, profile: profile));
    }
    for (final profile in profiles) {
      if (!claimedProfileIds.contains(profile.id)) {
        entries.add(_ProfileEntry(profile: profile));
      }
    }
    final activeCount = entries
        .where((entry) => entry.stage == ProfileStage.active)
        .length;
    final pendingCount = entries
        .where((entry) => entry.stage == ProfileStage.pendingActivation)
        .length;
    final museumCount = entries
        .where((entry) => entry.stage == ProfileStage.museum)
        .length;
    final matches =
        entries
            .where((entry) {
              if (entry.stage != _stage) return false;
              final query = _search.text.trim().toLowerCase();
              final searchable = [
                entry.subscription?.number.value ?? '',
                entry.subscription?.operator ?? '',
                entry.subscription?.details.profileName ?? '',
                entry.subscription?.plan.name ?? '',
                entry.subscription?.tags.join(' ') ?? '',
                entry.subscription?.iccid ?? '',
                entry.profile?.operatorName ?? '',
                entry.profile?.nickname ?? '',
                entry.profile?.iccid ?? '',
              ].join(' ').toLowerCase();
              if (query.isNotEmpty && !searchable.contains(query)) return false;
              final status =
                  entry.subscription == null ||
                      entry.stage != ProfileStage.active
                  ? null
                  : controller.statusOf(entry.subscription!);
              return switch (_filter) {
                _Filter.all => true,
                _Filter.attention => status is DueSoon || status is Overdue,
                _Filter.safe =>
                  status == null || status is Safe || status is NotRequired,
                _Filter.unknown => status is Unknown,
              };
            })
            .toList(growable: false)
          ..sort((a, b) {
            if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
            final risk = _entryRiskRank(
              a,
              controller.statusOf,
            ).compareTo(_entryRiskRank(b, controller.statusOf));
            if (risk != 0) return risk;
            return b.updatedAt.compareTo(a.updatedAt);
          });

    final activeSubscriptions = subscriptions.where(
      (item) => item.lifecycle.stage == ProfileStage.active,
    );
    final urgent = activeSubscriptions.where((item) {
      final status = controller.statusOf(item);
      return status is DueSoon || status is Overdue;
    }).length;
    final safe =
        activeSubscriptions.where((item) {
          final status = controller.statusOf(item);
          return status is Safe || status is NotRequired;
        }).length +
        entries.where((item) => item.subscription == null).length;
    final unknown = activeSubscriptions
        .where((item) => controller.statusOf(item) is Unknown)
        .length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: controller.reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _BrandHeader(onAdd: () => _openForm(context)),
                          const SizedBox(height: 18),
                          _OverviewHero(
                            total: entries.length,
                            urgent: urgent,
                            safe: safe,
                            unknown: unknown,
                            onAdd: () => _openForm(context),
                            onImport: () => _openImport(context),
                          ),
                          const SizedBox(height: 22),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _FilterChip(
                                  label: '已激活 $activeCount',
                                  selected: _stage == ProfileStage.active,
                                  onTap: () => setState(() {
                                    _stage = ProfileStage.active;
                                    _filter = _Filter.all;
                                  }),
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: '未激活 $pendingCount',
                                  selected:
                                      _stage == ProfileStage.pendingActivation,
                                  onTap: () => setState(() {
                                    _stage = ProfileStage.pendingActivation;
                                    _filter = _Filter.all;
                                  }),
                                ),
                                const SizedBox(width: 8),
                                _FilterChip(
                                  label: '过期博物馆 $museumCount',
                                  selected: _stage == ProfileStage.museum,
                                  onTap: () => setState(() {
                                    _stage = ProfileStage.museum;
                                    _filter = _Filter.all;
                                  }),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: '搜索号码、运营商、Profile 名称或 ICCID',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: '清除搜索',
                                      onPressed: () {
                                        _search.clear();
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_stage == ProfileStage.active)
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _FilterChip(
                                    label: '全部 ${entries.length}',
                                    selected: _filter == _Filter.all,
                                    onTap: () =>
                                        setState(() => _filter = _Filter.all),
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterChip(
                                    label: '需关注 $urgent',
                                    selected: _filter == _Filter.attention,
                                    onTap: () => setState(
                                      () => _filter = _Filter.attention,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterChip(
                                    label: '状态良好 $safe',
                                    selected: _filter == _Filter.safe,
                                    onTap: () =>
                                        setState(() => _filter = _Filter.safe),
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterChip(
                                    label: '待完善 $unknown',
                                    selected: _filter == _Filter.unknown,
                                    onTap: () => setState(
                                      () => _filter = _Filter.unknown,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Text(
                                _stageTitle(_stage),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const Spacer(),
                              Text(
                                '${matches.length} 条',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 13),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!controller.ready)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (controller.errorMessage != null && entries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.storage_rounded,
                    title: '暂时无法读取本地数据',
                    message: controller.errorMessage!,
                    actionLabel: '重试',
                    onAction: controller.reload,
                  ),
                )
              else if (entries.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.sim_card_outlined,
                    title: '从第一个 Profile 开始',
                    message: '可以手动添加，也可以扫描二维码或导入已有备份。',
                  ),
                )
              else if (matches.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: _search.text.trim().isEmpty
                        ? _stageIcon(_stage)
                        : Icons.search_off_rounded,
                    title: _search.text.trim().isEmpty
                        ? '${_stageTitle(_stage)}还是空的'
                        : '没有匹配结果',
                    message: _search.text.trim().isEmpty
                        ? '可以在添加或导入 Profile 时直接选择这个分类。'
                        : '试试其他关键词，或切换筛选条件。',
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    MediaQuery.paddingOf(context).bottom + 106,
                  ),
                  sliver: SliverList.separated(
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final entry = matches[index];
                      final subscription = entry.subscription;
                      final profile = entry.profile;
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: subscription != null
                              ? SubscriptionCard(
                                  subscription: subscription,
                                  status: controller.statusOf(subscription),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => SubscriptionDetailPage(
                                        subscriptionId: subscription.id,
                                      ),
                                    ),
                                  ),
                                )
                              : ProfileCard(
                                  profile: profile!,
                                  eid: _eidFor(
                                    controller.assets,
                                    profile.eidId,
                                  ),
                                  onTap: () => showModalBottomSheet<void>(
                                    context: context,
                                    showDragHandle: true,
                                    isScrollControlled: true,
                                    builder: (sheetContext) =>
                                        ProfileDetailsSheet(
                                          profile: profile,
                                          eid: _eidFor(
                                            controller.assets,
                                            profile.eidId,
                                          ),
                                          onTogglePin: () =>
                                              _toggleAssetProfilePin(
                                                sheetContext,
                                                controller,
                                                profile,
                                              ),
                                        ),
                                  ),
                                ),
                        ),
                      );
                    },
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const SubscriptionFormPage()),
  );

  Future<void> _openImport(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const DataExchangePage()),
  );

  Future<void> _toggleAssetProfilePin(
    BuildContext sheetContext,
    AppController controller,
    EsimProfile profile,
  ) async {
    final willPin = !profile.isPinned;
    final error = await controller.setAssetProfilePinned(profile.id, willPin);
    if (!sheetContext.mounted) return;
    final messenger = ScaffoldMessenger.of(sheetContext);
    if (error == null) Navigator.pop(sheetContext);
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? (willPin ? 'Profile 已置顶' : '已取消置顶'))),
    );
  }

  static int _riskRank(KeepAliveStatus status) => switch (status) {
    Overdue() => 0,
    DueSoon() => 1,
    Unknown() => 2,
    Safe() => 3,
    NotRequired() => 4,
  };

  static int _entryRiskRank(
    _ProfileEntry entry,
    KeepAliveStatus Function(Subscription subscription) statusOf,
  ) =>
      entry.subscription == null ? 3 : _riskRank(statusOf(entry.subscription!));

  static Euicc? _eidFor(AssetInventory inventory, String eidId) {
    for (final eid in inventory.eids) {
      if (eid.id == eidId) return eid;
    }
    return null;
  }

  static String _stageTitle(ProfileStage stage) => switch (stage) {
    ProfileStage.active => '已激活 Profile',
    ProfileStage.pendingActivation => '未激活 Profile',
    ProfileStage.museum => '过期博物馆',
  };

  static IconData _stageIcon(ProfileStage stage) => switch (stage) {
    ProfileStage.active => Icons.check_circle_outline_rounded,
    ProfileStage.pendingActivation => Icons.pending_outlined,
    ProfileStage.museum => Icons.museum_outlined,
  };
}

class _ProfileEntry {
  const _ProfileEntry({this.subscription, this.profile})
    : assert(subscription != null || profile != null);

  final Subscription? subscription;
  final EsimProfile? profile;

  ProfileStage get stage =>
      subscription?.lifecycle.stage ?? ProfileStage.active;

  DateTime get updatedAt => subscription?.updatedAt ?? profile!.updatedAt;

  bool get isPinned =>
      subscription?.details.isPinned ?? profile?.isPinned ?? false;
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const AppLogo(size: 46),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppBrand.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 1),
              Text(
                AppBrand.tagline,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 15, color: scheme.primary),
              const SizedBox(width: 5),
              Text(
                '本地优先',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: '添加 Profile',
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

class _OverviewHero extends StatelessWidget {
  const _OverviewHero({
    required this.total,
    required this.urgent,
    required this.safe,
    required this.unknown,
    required this.onAdd,
    required this.onImport,
  });

  final int total;
  final int urgent;
  final int safe;
  final int unknown;
  final VoidCallback onAdd;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final title = total == 0
        ? '从第一张 SIM 开始'
        : urgent > 0
        ? '$urgent 项需要处理'
        : unknown > 0
        ? '$unknown 个 Profile 待完善'
        : '所有 Profile 状态良好';
    final subtitle = total == 0
        ? '手动记录，或从二维码与外部备份快速导入。'
        : unknown > 0
        ? '可补充套餐或保号资料，也可以先保持现状。'
        : '保号截止和套餐到期都在掌握中。';

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.teal, AppColors.tealDark],
                ),
              ),
            ),
          ),
          Positioned(
            right: -44,
            top: -50,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.mintStrong.withValues(alpha: .14),
                  width: 24,
                ),
              ),
            ),
          ),
          Positioned(
            right: 32,
            top: 34,
            child: Icon(
              Icons.wifi_tethering_rounded,
              size: 42,
              color: AppColors.mintStrong.withValues(alpha: .23),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_greeting()} · 今日概览',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.mintStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    letterSpacing: -.6,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: .78),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _HeroMetric(value: total, label: '全部'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroMetric(value: urgent, label: '需关注'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HeroMetric(value: safe, label: '状态良好'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.paper,
                          foregroundColor: AppColors.tealDark,
                        ),
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('添加 Profile'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: .42),
                          ),
                        ),
                        onPressed: onImport,
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('外部数据'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 11) return '早上好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: .72),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
    );
  }
}
