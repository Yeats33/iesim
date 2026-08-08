import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iesim_core/iesim_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../app/app_scope.dart';
import '../data/builtin_affiliate_offers.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';

class AffiliateManagementPage extends StatelessWidget {
  const AffiliateManagementPage({super.key, this.subscriptionId});

  /// 留空时只浏览应用内置推荐；传入后同时管理该 Profile 的 AFF。
  final String? subscriptionId;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final subscription = subscriptionId == null
        ? null
        : controller.subscriptionById(subscriptionId!);
    if (subscriptionId != null && subscription == null) {
      return const Scaffold(
        body: EmptyState(
          icon: Icons.link_off_rounded,
          title: 'Profile 不存在',
          message: '无法读取它关联的 AFF 项目。',
        ),
      );
    }
    final linked = subscription?.details.affiliateOffers ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(subscription == null ? '优惠与推荐' : 'AFF 管理')),
      floatingActionButton: subscription == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editCustom(context, subscription),
              icon: const Icon(Icons.add_link_rounded),
              label: const Text('自定义 AFF'),
            ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.paddingOf(context).bottom +
              (subscription == null ? 32 : 104),
        ),
        children: [
          const _AffiliateDisclosure(),
          if (subscription != null) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: '这个 Profile 的 AFF',
              subtitle: linked.isEmpty
                  ? '尚未关联推广或推荐项目'
                  : '已关联 ${linked.length} 项',
              child: linked.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('可以从下方内置目录添加，也可以创建自己的 AFF。'),
                    )
                  : Column(
                      children: [
                        for (var index = 0; index < linked.length; index++) ...[
                          _AffiliateOfferTile(
                            offer: linked[index],
                            onEdit: () => _editCustom(
                              context,
                              subscription,
                              existing: linked[index],
                            ),
                            onDelete: () =>
                                _remove(context, subscription, linked[index]),
                          ),
                          if (index != linked.length - 1) const Divider(),
                        ],
                      ],
                    ),
            ),
          ],
          const SizedBox(height: 16),
          SectionCard(
            title: 'ieSIM 推荐',
            subtitle: '实体 eUICC、eSIM 服务与运营商',
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < builtinAffiliateOffers.length;
                  index++
                ) ...[
                  _AffiliateOfferTile(
                    offer: builtinAffiliateOffers[index],
                    linked: linked.any(
                      (offer) => offer.id == builtinAffiliateOffers[index].id,
                    ),
                    onAdd: subscription == null
                        ? null
                        : () => _addBuiltIn(
                            context,
                            subscription,
                            builtinAffiliateOffers[index],
                          ),
                  ),
                  if (index != builtinAffiliateOffers.length - 1)
                    const Divider(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addBuiltIn(
    BuildContext context,
    Subscription subscription,
    AffiliateOffer offer,
  ) async {
    final latest = AppScope.of(context).subscriptionById(subscription.id);
    if (latest == null) return;
    if (latest.details.affiliateOffers.any((item) => item.id == offer.id)) {
      _message(context, '已经关联过 ${offer.brand}');
      return;
    }
    final error = await AppScope.of(context).saveSubscription(
      latest.copyWith(
        details: latest.details.copyWith(
          affiliateOffers: [...latest.details.affiliateOffers, offer],
        ),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    if (!context.mounted) return;
    _message(context, error ?? '已关联 ${offer.brand}');
  }

  Future<void> _remove(
    BuildContext context,
    Subscription subscription,
    AffiliateOffer offer,
  ) async {
    final latest = AppScope.of(context).subscriptionById(subscription.id);
    if (latest == null) return;
    final error = await AppScope.of(context).saveSubscription(
      latest.copyWith(
        details: latest.details.copyWith(
          affiliateOffers: latest.details.affiliateOffers
              .where((item) => item.id != offer.id)
              .toList(growable: false),
        ),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    if (!context.mounted) return;
    _message(context, error ?? '已移除 ${offer.brand}');
  }

  Future<void> _editCustom(
    BuildContext context,
    Subscription subscription, {
    AffiliateOffer? existing,
  }) async {
    final result = await _showAffiliateEditor(context, existing: existing);
    if (result == null || !context.mounted) return;
    final latest = AppScope.of(context).subscriptionById(subscription.id);
    if (latest == null) return;
    final offers = [...latest.details.affiliateOffers];
    final index = offers.indexWhere((offer) => offer.id == result.id);
    if (index < 0) {
      offers.add(result);
    } else {
      offers[index] = result;
    }
    final error = await AppScope.of(context).saveSubscription(
      latest.copyWith(
        details: latest.details.copyWith(affiliateOffers: offers),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    if (!context.mounted) return;
    _message(context, error ?? 'AFF 已保存');
  }
}

class _AffiliateDisclosure extends StatelessWidget {
  const _AffiliateDisclosure();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.handshake_outlined, color: scheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '推广 / 推荐披露',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '下列内置入口含优惠码或推荐参数。通过链接购买时，ieSIM 开发者可能获得推广收益；请以商家页面的实时价格和条款为准。',
                  style: TextStyle(color: scheme.onTertiaryContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AffiliateOfferTile extends StatelessWidget {
  const _AffiliateOfferTile({
    required this.offer,
    this.linked = false,
    this.onAdd,
    this.onEdit,
    this.onDelete,
  });

  final AffiliateOffer offer;
  final bool linked;
  final VoidCallback? onAdd;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final code = offer.promoCode;
    final host = Uri.tryParse(offer.url)?.host ?? offer.url;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(child: Icon(_categoryIcon(offer.category))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            offer.brand,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (offer.isBuiltIn) ...[
                          const SizedBox(width: 8),
                          const Badge(label: Text('推荐')),
                        ],
                      ],
                    ),
                    Text(
                      '${_categoryLabel(offer.category)} · $host',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (offer.note case final note? when note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(note),
                    ],
                  ],
                ),
              ),
              if (onEdit != null || onDelete != null)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') onEdit?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => [
                    if (onEdit != null)
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    if (onDelete != null)
                      const PopupMenuItem(value: 'delete', child: Text('移除')),
                  ],
                ),
            ],
          ),
          if (code != null && code.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _copy(context, code),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('优惠码  $code'),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy_rounded, size: 17),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _open(context, offer.url),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('打开推荐链接'),
              ),
              if (onAdd != null)
                FilledButton.tonalIcon(
                  onPressed: linked ? null : onAdd,
                  icon: Icon(linked ? Icons.check_rounded : Icons.add_rounded),
                  label: Text(linked ? '已关联' : '关联到 Profile'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<void> _copy(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    _message(context, '已复制优惠码 $code');
  }

  static Future<void> _open(BuildContext context, String source) async {
    final uri = Uri.tryParse(source);
    final opened =
        uri != null &&
        uri.scheme == 'https' &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted || opened) return;
    _message(context, '无法打开链接，请检查系统浏览器');
  }
}

Future<AffiliateOffer?> _showAffiliateEditor(
  BuildContext context, {
  AffiliateOffer? existing,
}) async {
  final brand = TextEditingController(text: existing?.brand);
  final code = TextEditingController(text: existing?.promoCode);
  final url = TextEditingController(text: existing?.url);
  final note = TextEditingController(text: existing?.note);
  var category = existing?.category ?? AffiliateOfferCategory.other;
  String? error;
  final result = await showDialog<AffiliateOffer>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(existing == null ? '添加自定义 AFF' : '编辑 AFF'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: brand,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '品牌 / 名称'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AffiliateOfferCategory>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: '类型'),
                  items: [
                    for (final value in AffiliateOfferCategory.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(_categoryLabel(value)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => category = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: code,
                  decoration: const InputDecoration(labelText: '优惠 / 推荐码（可选）'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'HTTPS 推荐链接',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: '说明（可选）'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final uri = Uri.tryParse(url.text.trim());
              if (brand.text.trim().isEmpty ||
                  uri == null ||
                  uri.scheme != 'https' ||
                  uri.host.isEmpty) {
                setState(() => error = '请填写品牌和有效的 HTTPS 链接');
                return;
              }
              Navigator.pop(
                dialogContext,
                AffiliateOffer(
                  id: existing?.id ?? const Uuid().v4(),
                  brand: brand.text.trim(),
                  category: category,
                  url: uri.toString(),
                  promoCode: _optional(code.text),
                  note: _optional(note.text),
                  isBuiltIn: existing?.isBuiltIn ?? false,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  brand.dispose();
  code.dispose();
  url.dispose();
  note.dispose();
  return result;
}

String? _optional(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

IconData _categoryIcon(AffiliateOfferCategory value) => switch (value) {
  AffiliateOfferCategory.physicalEsimCard => Icons.sim_card_outlined,
  AffiliateOfferCategory.esimService => Icons.travel_explore_rounded,
  AffiliateOfferCategory.mobileOperator => Icons.cell_tower_outlined,
  AffiliateOfferCategory.other => Icons.link_rounded,
};

String _categoryLabel(AffiliateOfferCategory value) => switch (value) {
  AffiliateOfferCategory.physicalEsimCard => '实体 eUICC / eSIM 卡',
  AffiliateOfferCategory.esimService => 'eSIM 服务',
  AffiliateOfferCategory.mobileOperator => '实体 SIM / 运营商',
  AffiliateOfferCategory.other => '其他推荐',
};

void _message(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
