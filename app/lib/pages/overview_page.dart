import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

import '../app/app_scope.dart';
import '../data/app_controller.dart';
import '../services/home_action_center.dart';
import '../widgets/empty_state.dart';
import '../widgets/profile_card.dart';
import '../widgets/subscription_card.dart';
import '../widgets/home_action_center_panel.dart';
import '../widgets/overview_header.dart';
import 'data_exchange_page.dart';
import 'reminders_page.dart';
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
    final homeActions = controller.homeActions;
    final attentionProfileIds = {
      for (final action in homeActions)
        if (action.urgency != HomeActionUrgency.data) action.subscriptionId,
    };
    final missingDataProfileIds = {
      for (final action in homeActions)
        if (action.urgency == HomeActionUrgency.data) action.subscriptionId,
    };
    final actionRankByProfile = <String, int>{};
    for (final action in homeActions) {
      final rank = action.urgency.index;
      final previous = actionRankByProfile[action.subscriptionId];
      if (previous == null || rank < previous) {
        actionRankByProfile[action.subscriptionId] = rank;
      }
    }
    final profiles = controller.assets.profiles;
    final claimedProfileIds = <String>{};
    final entries = <_ProfileEntry>[];
    var activeCount = 0;
    var pendingCount = 0;
    var museumCount = 0;
    void addEntry(_ProfileEntry entry) {
      entries.add(entry);
      switch (entry.stage) {
        case ProfileStage.active:
          activeCount++;
        case ProfileStage.pendingActivation:
          pendingCount++;
        case ProfileStage.museum:
          museumCount++;
      }
    }

    for (final subscription in subscriptions) {
      final profile = controller.assetProfileForSubscription(subscription);
      if (profile != null) claimedProfileIds.add(profile.id);
      addEntry(_ProfileEntry(subscription: subscription, profile: profile));
    }
    for (final profile in profiles) {
      if (!claimedProfileIds.contains(profile.id)) {
        addEntry(_ProfileEntry(profile: profile));
      }
    }
    final riskRankByProfile = {
      for (final subscription in subscriptions)
        subscription.id:
            actionRankByProfile[subscription.id] ??
            4 + _riskRank(controller.statusOf(subscription)),
    };
    final query = _search.text.trim().toLowerCase();
    final matches =
        entries
            .where((entry) {
              if (entry.stage != _stage) return false;
              if (query.isNotEmpty) {
                final searchable = [
                  entry.subscription?.number.value ?? '',
                  entry.subscription?.operator ?? '',
                  entry.subscription?.details.profileName ?? '',
                  entry.subscription?.plan.name ?? '',
                  entry.subscription?.tags.join(' ') ?? '',
                  entry.subscription?.iccid ?? '',
                  entry.profile?.operatorName ?? '',
                  entry.profile?.nickname ?? '',
                  if (controller.showNekokoTags)
                    entry.profile?.nekokoTagsRaw ?? '',
                  entry.profile?.iccid ?? '',
                ].join(' ').toLowerCase();
                if (!searchable.contains(query)) return false;
              }
              return switch (_filter) {
                _Filter.all => true,
                _Filter.attention =>
                  entry.subscription != null &&
                      attentionProfileIds.contains(entry.subscription!.id),
                _Filter.safe =>
                  entry.subscription == null ||
                      (!attentionProfileIds.contains(entry.subscription!.id) &&
                          !missingDataProfileIds.contains(
                            entry.subscription!.id,
                          )),
                _Filter.unknown =>
                  entry.subscription != null &&
                      missingDataProfileIds.contains(entry.subscription!.id),
              };
            })
            .toList(growable: false)
          ..sort((a, b) {
            if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
            final risk = (riskRankByProfile[a.subscription?.id] ?? 6).compareTo(
              riskRankByProfile[b.subscription?.id] ?? 6,
            );
            if (risk != 0) return risk;
            return b.updatedAt.compareTo(a.updatedAt);
          });

    final activeSubscriptions = subscriptions.where(
      (item) => item.lifecycle.stage == ProfileStage.active,
    );
    final urgent = homeActions
        .where((item) => item.urgency != HomeActionUrgency.data)
        .length;
    final safe =
        activeSubscriptions.where((item) {
          return !attentionProfileIds.contains(item.id) &&
              !missingDataProfileIds.contains(item.id);
        }).length +
        entries.where((item) => item.subscription == null).length;
    final unknown = missingDataProfileIds.length;

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
                          OverviewHeader(
                            total: entries.length,
                            urgent: urgent,
                            safe: safe,
                            unknown: unknown,
                            onAdd: () => _openForm(context),
                            onImport: () => _openImport(context),
                          ),
                          const SizedBox(height: 14),
                          HomeActionCenterPanel(
                            actions: homeActions,
                            subscriptionFor: controller.subscriptionById,
                            onOpen: (action) => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => SubscriptionDetailPage(
                                  subscriptionId: action.subscriptionId,
                                ),
                              ),
                            ),
                            onViewAll: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const RemindersPage(),
                              ),
                            ),
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
                                  nekokoTagsRaw: controller.showNekokoTags
                                      ? profile?.nekokoTagsRaw
                                      : null,
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
                                  eid: controller.assets.eidById(profile.eidId),
                                  showNekokoTags: controller.showNekokoTags,
                                  onTap: () => showModalBottomSheet<void>(
                                    context: context,
                                    showDragHandle: true,
                                    isScrollControlled: true,
                                    builder: (sheetContext) =>
                                        ProfileDetailsSheet(
                                          profile: profile,
                                          showNekokoTags:
                                              controller.showNekokoTags,
                                          eid: controller.assets.eidById(
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
