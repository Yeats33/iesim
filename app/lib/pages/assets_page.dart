import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../data/euicc_card_presets.dart';
import '../services/compatibility_assistant.dart';
import '../services/euicc_card_preset_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';
import 'device_preset_picker_page.dart';

class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key});

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (!_tabs.indexIsChanging && mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final inventory = controller.assets;
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备空间'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '设备'),
            Tab(text: 'SIM / eSIM'),
            Tab(text: '迁移'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _DevicesTab(inventory: inventory),
          _CardsTab(inventory: inventory),
          _EventsTab(inventory: inventory),
        ],
      ),
      floatingActionButton: _tabs.index == 2
          ? null
          : FloatingActionButton.extended(
              heroTag: 'asset-add',
              onPressed: () => _tabs.index == 0
                  ? _openDeviceForm(context)
                  : _openCardForm(context),
              icon: const Icon(Icons.add_rounded),
              label: Text(_tabs.index == 0 ? '添加设备' : '添加卡片'),
            ),
    );
  }

  static Future<void> _openDeviceForm(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const _DeviceFormPage()),
  );

  static Future<void> _openCardForm(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const _CardFormPage()),
  );
}

class _DevicesTab extends StatelessWidget {
  const _DevicesTab({required this.inventory});

  final AssetInventory inventory;

  @override
  Widget build(BuildContext context) {
    if (inventory.devices.isEmpty) {
      return EmptyState(
        icon: Icons.devices_other_rounded,
        title: '还没有设备',
        message: '添加手机、随身 Wi-Fi、平板或写卡器，再记录每个卡槽当前装着哪张卡。',
        actionLabel: '添加设备',
        onAction: () => _AssetsPageState._openDeviceForm(context),
      );
    }
    return RefreshIndicator(
      onRefresh: AppScope.of(context).reload,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.paddingOf(context).bottom + 100,
        ),
        itemCount: inventory.devices.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) return _AssetSummary(inventory: inventory);
          final device = inventory.devices[index - 1];
          final slots = inventory.slotsForDevice(device.id).toList();
          final occupied = slots.where((slot) => slot.cardId != null).length;
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 9,
              ),
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(_deviceIcon(device.kind)),
              ),
              title: Text(device.name),
              subtitle: Text(
                '${_deviceKindLabel(device.kind)} · $occupied/${slots.length} 个卡槽在用'
                '${device.brand == null ? '' : ' · ${device.brand}'}',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _DeviceDetailPage(deviceId: device.id),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AssetSummary extends StatelessWidget {
  const _AssetSummary({required this.inventory});

  final AssetInventory inventory;

  @override
  Widget build(BuildContext context) {
    final stored = inventory.cards
        .where((card) => inventory.slotHolding(card.id) == null)
        .length;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.teal, AppColors.tealDark],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.hub_outlined, color: Colors.white),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '设备关系一目了然',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '设备、卡槽和 eSIM Profile 独立管理',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: .72),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _AssetMetric(
                    value: inventory.devices.length,
                    label: '设备',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AssetMetric(
                    value: inventory.cards.length,
                    label: 'SIM / eSIM',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AssetMetric(value: stored, label: '库存中'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetMetric extends StatelessWidget {
  const _AssetMetric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
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
              color: Colors.white.withValues(alpha: .70),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardsTab extends StatelessWidget {
  const _CardsTab({required this.inventory});

  final AssetInventory inventory;

  @override
  Widget build(BuildContext context) {
    if (inventory.cards.isEmpty) {
      return EmptyState(
        icon: Icons.sim_card_outlined,
        title: '还没有卡片资产',
        message: '实体 SIM、可拆卸 eUICC 和设备内置 eUICC 都可以在这里管理。',
        actionLabel: '添加卡片',
        onAction: () => _AssetsPageState._openCardForm(context),
      );
    }
    return RefreshIndicator(
      onRefresh: AppScope.of(context).reload,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.paddingOf(context).bottom + 100,
        ),
        itemCount: inventory.cards.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final card = inventory.cards[index];
          final slot = inventory.slotHolding(card.id);
          final eids = inventory.eidsForCard(card.id).toList();
          final profileCount = eids.fold<int>(
            0,
            (count, eid) => count + inventory.profilesForEid(eid.id).length,
          );
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 9,
              ),
              leading: CircleAvatar(child: Icon(_cardIcon(card.kind))),
              title: Text(card.name),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_cardKindLabel(card.kind)} · '
                      '${_locationLabel(inventory, slot)}',
                    ),
                    const SizedBox(height: 4),
                    if (eids.isEmpty)
                      Text(
                        card is PhysicalSimCard ? '普通实体 SIM · 无 EID' : '暂无 EID',
                      )
                    else
                      for (final eid in eids)
                        Text(
                          '${eid.label ?? 'EID'} · ${eid.value}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    if (profileCount > 0) Text('$profileCount 个 Profile'),
                  ],
                ),
              ),
              trailing: card is EmbeddedEuiccCard
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 18),
                        SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded),
                      ],
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _CardDetailPage(cardId: card.id),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EventsTab extends StatelessWidget {
  const _EventsTab({required this.inventory});

  final AssetInventory inventory;

  @override
  Widget build(BuildContext context) {
    if (inventory.events.isEmpty) {
      return const EmptyState(
        icon: Icons.route_outlined,
        title: '还没有迁移记录',
        message: '移动卡片、移入库存、迁移或擦除 Profile 后，会在这里留下可追溯记录。',
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.paddingOf(context).bottom + 100,
      ),
      itemCount: inventory.events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final event = inventory.events[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(child: Icon(_eventIcon(event.type))),
            title: Text(_eventTitle(inventory, event)),
            subtitle: Text(
              '${_dateTime(event.occurredAt)}${event.note == null ? '' : '\n${event.note}'}',
            ),
            isThreeLine: event.note != null,
          ),
        );
      },
    );
  }
}

class _DeviceDetailPage extends StatelessWidget {
  const _DeviceDetailPage({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final inventory = controller.assets;
    final device = inventory.deviceById(deviceId);
    if (device == null) {
      return const Scaffold(body: Center(child: Text('设备已不存在')));
    }
    final slots = inventory.slotsForDevice(device.id).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    return Scaffold(
      appBar: AppBar(
        title: Text(device.name),
        actions: [
          IconButton(
            tooltip: '编辑设备',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => _DeviceFormPage(existing: device),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'embedded') {
                await _createEmbeddedEuicc(context, device, slots);
              } else if (value == 'delete') {
                await _deleteDevice(context, device);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'embedded', child: Text('添加内置 eSIM 组合')),
              PopupMenuItem(value: 'delete', child: Text('删除设备')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.paddingOf(context).bottom + 90,
        ),
        children: [
          SectionCard(
            title: _deviceKindLabel(device.kind),
            subtitle: device.brand,
            child: Column(
              children: [
                InfoRow(
                  label: 'SIM 能力',
                  value: _capabilityLabel(device.simCapability),
                ),
                if (device.region != null)
                  InfoRow(label: '地区', value: device.region!),
                if (device.usage != null)
                  InfoRow(label: '用途', value: device.usage!),
                InfoRow(
                  label: '5G SA 漫游',
                  value: device.supportsSaRoaming ? '支持' : '不支持 / 未确认',
                ),
                InfoRow(label: '排序位置', value: '${device.orderIndex}'),
                if (device.note != null)
                  InfoRow(label: '备注', value: device.note!),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: '卡槽',
            subtitle: '物理卡可更换；内置 eSIM 是卡槽与不可拆 eUICC 的组合',
            trailing: IconButton(
              tooltip: '添加物理卡槽',
              onPressed: () => _addSlot(context, device, slots.length),
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
            child: slots.isEmpty
                ? const Text('暂无卡槽，请先添加。')
                : Column(
                    children: [
                      for (var index = 0; index < slots.length; index++) ...[
                        _SlotTile(
                          slot: slots[index],
                          inventory: inventory,
                          onCreateEmbedded: () =>
                              _createEmbeddedEuicc(context, device, slots),
                        ),
                        if (index != slots.length - 1) const Divider(),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static Future<void> _addSlot(
    BuildContext context,
    DeviceAsset device,
    int position,
  ) async {
    final result = await showDialog<(String, SimSlotKind, int)>(
      context: context,
      builder: (_) => _SlotDialog(position: position),
    );
    if (result == null || !context.mounted) return;
    final now = DateTime.now().toUtc();
    final error = await AppScope.of(context).saveSlot(
      SimSlot(
        id: const Uuid().v4(),
        deviceId: device.id,
        label: result.$1,
        kind: result.$2,
        position: result.$3,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (context.mounted) _message(context, error ?? '卡槽已添加');
  }

  static Future<void> _createEmbeddedEuicc(
    BuildContext context,
    DeviceAsset device,
    List<SimSlot> slots,
  ) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _EmbeddedEuiccDialog(),
    );
    if (result == null || !context.mounted) return;
    final controller = AppScope.of(context);
    final now = DateTime.now().toUtc();
    var target = slots.where(
      (slot) => slot.kind == SimSlotKind.embeddedEuicc && slot.cardId == null,
    );
    SimSlot slot;
    if (target.isEmpty) {
      slot = SimSlot(
        id: const Uuid().v4(),
        deviceId: device.id,
        label: '内置 eSIM',
        kind: SimSlotKind.embeddedEuicc,
        position: slots.length,
        createdAt: now,
        updatedAt: now,
      );
    } else {
      slot = target.first;
    }
    final card = EmbeddedEuiccCard(
      id: const Uuid().v4(),
      name: result.$1,
      embeddedDeviceId: device.id,
      createdAt: now,
      updatedAt: now,
    );
    final error = await controller.createEmbeddedEuicc(
      card: card,
      eid: Euicc(
        id: const Uuid().v4(),
        cardId: card.id,
        value: result.$2,
        createdAt: now,
        updatedAt: now,
      ),
      slot: slot,
    );
    if (context.mounted) _message(context, error ?? '内置 eSIM 组合已添加');
  }

  static Future<void> _deleteDevice(
    BuildContext context,
    DeviceAsset device,
  ) async {
    final confirmed = await _confirm(
      context,
      title: '删除 ${device.name}？',
      message: '只有卡槽为空且没有内置 eUICC 时才能删除。',
    );
    if (!confirmed || !context.mounted) return;
    final error = await AppScope.of(context).deleteDevice(device.id);
    if (!context.mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      _message(context, error);
    }
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.slot,
    required this.inventory,
    required this.onCreateEmbedded,
  });

  final SimSlot slot;
  final AssetInventory inventory;
  final VoidCallback onCreateEmbedded;

  @override
  Widget build(BuildContext context) {
    final card = slot.cardId == null ? null : inventory.cardById(slot.cardId!);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        slot.kind == SimSlotKind.physical
            ? Icons.sim_card_outlined
            : Icons.memory_rounded,
      ),
      title: Text(slot.label),
      subtitle: Text(
        card is EmbeddedEuiccCard
            ? '${card.name} · 不可拆卸'
            : card?.name ??
                  (slot.kind == SimSlotKind.embeddedEuicc
                      ? '尚未绑定内置 eUICC'
                      : '空卡槽'),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '编辑卡槽',
            onPressed: () => _edit(context),
            icon: const Icon(Icons.edit_outlined),
          ),
          Icon(
            card is EmbeddedEuiccCard
                ? Icons.lock_outline_rounded
                : slot.kind == SimSlotKind.embeddedEuicc
                ? Icons.add_circle_outline_rounded
                : Icons.swap_horiz_rounded,
          ),
        ],
      ),
      onTap: card is EmbeddedEuiccCard
          ? () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => _CardDetailPage(cardId: card.id),
              ),
            )
          : slot.kind == SimSlotKind.embeddedEuicc
          ? onCreateEmbedded
          : () => _chooseCard(context, card),
      onLongPress: card == null ? () => _delete(context) : null,
    );
  }

  Future<void> _chooseCard(BuildContext context, SimCard? current) async {
    final available = inventory.cards.where((card) {
      if (card.id == current?.id) return false;
      if (inventory.slotHolding(card.id) != null) return false;
      return AssetRules.canPlace(card, slot);
    }).toList();
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          children: [
            Text('选择卡片', style: Theme.of(context).textTheme.titleLarge),
            if (current != null)
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text('将 ${current.name} 移至库存'),
                onTap: () => Navigator.pop(sheetContext, ''),
              ),
            for (final card in available)
              ListTile(
                leading: Icon(_cardIcon(card.kind)),
                title: Text(card.name),
                subtitle: Text(_cardKindLabel(card.kind)),
                onTap: () => Navigator.pop(sheetContext, card.id),
              ),
            if (available.isEmpty && current == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('库存中没有可装入这台设备的卡片。'),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    final error = await AppScope.of(context).replaceCardInSlot(
      slotId: slot.id,
      cardId: selected.isEmpty ? null : selected,
    );
    if (context.mounted) _message(context, error ?? '位置已更新');
  }

  Future<void> _edit(BuildContext context) async {
    final result = await showDialog<(String, SimSlotKind, int)>(
      context: context,
      builder: (_) => _SlotDialog(existing: slot, position: slot.position),
    );
    if (result == null || !context.mounted) return;
    final error = await AppScope.of(context).saveSlot(
      SimSlot(
        id: slot.id,
        deviceId: slot.deviceId,
        label: result.$1,
        kind: result.$2,
        position: result.$3,
        cardId: slot.cardId,
        createdAt: slot.createdAt,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    if (context.mounted) _message(context, error ?? '卡槽已更新');
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      title: '删除 ${slot.label}？',
      message: '空卡槽可以安全删除。',
    );
    if (!confirmed || !context.mounted) return;
    final error = await AppScope.of(context).deleteSlot(slot.id);
    if (context.mounted) _message(context, error ?? '卡槽已删除');
  }
}

class _CardDetailPage extends StatelessWidget {
  const _CardDetailPage({required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final inventory = controller.assets;
    final card = inventory.cardById(cardId);
    if (card == null) {
      return const Scaffold(body: Center(child: Text('卡片已不存在')));
    }
    final slot = inventory.slotHolding(card.id);
    final eids = inventory.eidsForCard(card.id).toList();
    final preset = euiccCardPresetById(
      card.presetId,
      presets: AppScope.of(context).euiccCardPresetResult.catalog.cards,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(card.name),
        actions: [
          IconButton(
            tooltip: '编辑卡片',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => _CardFormPage(existing: card),
              ),
            ),
          ),
          if (card is! EmbeddedEuiccCard)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'move') {
                  await _moveCard(context, inventory, card, slot);
                } else if (value == 'delete') {
                  await _deleteCard(context, card, slot);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'move', child: Text('移动卡片')),
                PopupMenuItem(value: 'delete', child: Text('删除卡片')),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.paddingOf(context).bottom + 40,
        ),
        children: [
          SectionCard(
            title: _cardKindLabel(card.kind),
            subtitle: _locationLabel(inventory, slot),
            child: Column(
              children: [
                if (card is EmbeddedEuiccCard)
                  const InfoRow(label: '安装方式', value: '与设备永久绑定，不可移出或换卡'),
                InfoRow(label: 'EID 数量', value: '${eids.length}'),
                if (card.note != null) InfoRow(label: '备注', value: card.note!),
              ],
            ),
          ),
          if (preset != null) ...[
            const SizedBox(height: 14),
            _EuiccPresetOfferCard(preset: preset),
          ],
          const SizedBox(height: 14),
          SectionCard(
            title: 'EID',
            subtitle: '一张 eUICC 卡片可包含多个 EID；每个 EID 下可管理多个 Profile',
            trailing: card is PhysicalSimCard
                ? null
                : IconButton(
                    tooltip: '添加 EID',
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: () => _addEid(context, card),
                  ),
            child: eids.isEmpty
                ? Text(card is PhysicalSimCard ? '实体 SIM 不需要 EID。' : '暂无 EID。')
                : Column(
                    children: [
                      for (var index = 0; index < eids.length; index++) ...[
                        _EidPanel(eid: eids[index], inventory: inventory),
                        if (index != eids.length - 1) const Divider(height: 28),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static Future<void> _moveCard(
    BuildContext context,
    AssetInventory inventory,
    SimCard card,
    SimSlot? current,
  ) async {
    final slots = inventory.slots.where((slot) {
      if (slot.cardId != null && slot.cardId != card.id) return false;
      return AssetRules.canPlace(card, slot);
    }).toList();
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (card is! EmbeddedEuiccCard)
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('移至库存'),
                selected: current == null,
                onTap: () => Navigator.pop(sheetContext, ''),
              ),
            for (final slot in slots)
              ListTile(
                leading: const Icon(Icons.devices_rounded),
                title: Text(_locationLabel(inventory, slot)),
                selected: slot.id == current?.id,
                onTap: () => Navigator.pop(sheetContext, slot.id),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    final error = await AppScope.of(
      context,
    ).moveCard(cardId: card.id, toSlotId: selected.isEmpty ? null : selected);
    if (context.mounted) _message(context, error ?? '位置已更新');
  }

  static Future<void> _deleteCard(
    BuildContext context,
    SimCard card,
    SimSlot? slot,
  ) async {
    final confirmed = await _confirm(
      context,
      title: '删除 ${card.name}？',
      message: slot == null ? '关联的 EID 与 Profile 也会删除。' : '请先把卡片移至库存。',
    );
    if (!confirmed || !context.mounted) return;
    final error = await AppScope.of(context).deleteCard(card.id);
    if (!context.mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      _message(context, error);
    }
  }

  static Future<void> _addEid(BuildContext context, SimCard card) async {
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => const _EidDialog(),
    );
    if (result == null || !context.mounted) return;
    final now = DateTime.now().toUtc();
    final error = await AppScope.of(context).saveEid(
      Euicc(
        id: const Uuid().v4(),
        cardId: card.id,
        value: result.$1,
        label: result.$2,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (context.mounted) _message(context, error ?? 'EID 已添加');
  }
}

class _EidPanel extends StatelessWidget {
  const _EidPanel({required this.eid, required this.inventory});

  final Euicc eid;
  final AssetInventory inventory;

  @override
  Widget build(BuildContext context) {
    final profiles = inventory.profilesForEid(eid.id).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                eid.label ?? 'EID ${_redact(eid.value)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: '编辑 EID',
              onPressed: () => _editEid(context),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: '添加 Profile',
              onPressed: () => _editProfile(context),
              icon: const Icon(Icons.add_rounded),
            ),
            if (profiles.isEmpty)
              IconButton(
                tooltip: '删除 EID',
                onPressed: () => _deleteEid(context),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
        Text(
          eid.value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (profiles.isEmpty)
          const Text('暂无 Profile')
        else
          for (final profile in profiles)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sim_card_download_outlined),
              title: Text(
                profile.nickname ?? profile.operatorName ?? '未命名 Profile',
              ),
              subtitle: Text(_profileSubtitle(context, profile)),
              trailing: PopupMenuButton<String>(
                onSelected: (value) => _profileAction(context, profile, value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'move', child: Text('迁移到其他 EID')),
                  PopupMenuItem(value: 'wipe', child: Text('标记擦除并删除')),
                ],
              ),
            ),
      ],
    );
  }

  String _profileSubtitle(BuildContext context, EsimProfile profile) {
    final subscriptions = AppScope.of(context).subscriptions;
    final linked = subscriptions.where(
      (item) => item.id == profile.subscriptionId,
    );
    final parts = <String>[];
    if (profile.iccid != null) parts.add('ICCID ${profile.iccid}');
    if (linked.isNotEmpty) {
      parts.add(linked.single.operator ?? linked.single.number.value);
    }
    return parts.isEmpty ? '未关联订阅' : parts.join(' · ');
  }

  Future<void> _editProfile(
    BuildContext context, [
    EsimProfile? existing,
  ]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _ProfileFormPage(eidId: eid.id, existing: existing),
      ),
    );
  }

  Future<void> _editEid(BuildContext context) async {
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => _EidDialog(existing: eid),
    );
    if (result == null || !context.mounted) return;
    final error = await AppScope.of(context).saveEid(
      Euicc(
        id: eid.id,
        cardId: eid.cardId,
        value: result.$1,
        label: result.$2,
        createdAt: eid.createdAt,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    if (context.mounted) _message(context, error ?? 'EID 已更新');
  }

  Future<void> _deleteEid(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      title: '删除这个 EID？',
      message: '仅没有 Profile 的 EID 可以删除。',
    );
    if (!confirmed || !context.mounted) return;
    final error = await AppScope.of(context).deleteEid(eid.id);
    if (context.mounted) _message(context, error ?? 'EID 已删除');
  }

  Future<void> _profileAction(
    BuildContext context,
    EsimProfile profile,
    String action,
  ) async {
    if (action == 'edit') {
      await _editProfile(context, profile);
      return;
    }
    if (action == 'move') {
      final controller = AppScope.of(context);
      final linked = profile.subscriptionId == null
          ? null
          : controller.subscriptionById(profile.subscriptionId!);
      final assistant = EuiccCompatibilityAssistant(
        inventory: inventory,
        subscriptions: controller.subscriptions,
        presets: controller.euiccCardPresetResult.catalog.cards,
      );
      final candidates = [
        for (final item in inventory.eids)
          if (item.id != profile.eidId)
            (
              eid: item,
              assessment: assistant.assess(
                eidId: item.id,
                subscription: linked,
                currentAssetProfileId: profile.id,
              ),
            ),
      ];
      final target = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final candidate in candidates)
                ListTile(
                  leading: Icon(switch (candidate.assessment.severity) {
                    CompatibilitySeverity.compatible => Icons.verified_outlined,
                    CompatibilitySeverity.caution =>
                      Icons.warning_amber_rounded,
                    CompatibilitySeverity.blocked => Icons.block_rounded,
                  }),
                  title: Text(
                    candidate.eid.label ?? _redact(candidate.eid.value),
                  ),
                  subtitle: Text(
                    '${candidate.assessment.shortLabel} · '
                    '${candidate.assessment.primaryMessage}\n'
                    '${_redact(candidate.eid.value)}',
                  ),
                  isThreeLine: true,
                  onTap: candidate.assessment.canProceed
                      ? () => Navigator.pop(sheetContext, candidate.eid.id)
                      : null,
                ),
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('没有其他 EID 可供迁移。'),
                ),
            ],
          ),
        ),
      );
      if (target == null || !context.mounted) return;
      final assessment = assistant.assess(
        eidId: target,
        subscription: linked,
        currentAssetProfileId: profile.id,
      );
      if (assessment.severity == CompatibilitySeverity.caution) {
        final confirmed = await _confirmCompatibilityMove(context, assessment);
        if (!confirmed || !context.mounted) return;
      }
      final error = await controller.moveProfile(
        profileId: profile.id,
        toEidId: target,
      );
      if (context.mounted) _message(context, error ?? 'Profile 已迁移');
      return;
    }
    final confirmed = await _confirm(
      context,
      title: '标记这个 Profile 已擦除？',
      message: '只删除资产记录，不会操作真实 eUICC，也不会删除关联订阅。',
    );
    if (!confirmed || !context.mounted) return;
    final error = await AppScope.of(context).wipeProfile(profile.id);
    if (context.mounted) _message(context, error ?? 'Profile 已从资产记录移除');
  }

  static Future<bool> _confirmCompatibilityMove(
    BuildContext context,
    CompatibilityAssessment assessment,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('迁移前确认'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final finding in assessment.findings.where(
                (item) => item.severity == CompatibilitySeverity.caution,
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: Text(finding.title),
                  subtitle: Text(finding.detail),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('仍然迁移'),
            ),
          ],
        ),
      ) ??
      false;
}

class _DeviceFormPage extends StatefulWidget {
  const _DeviceFormPage({this.existing});

  final DeviceAsset? existing;

  @override
  State<_DeviceFormPage> createState() => _DeviceFormPageState();
}

class _DeviceFormPageState extends State<_DeviceFormPage> {
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _note;
  late final TextEditingController _region;
  late final TextEditingController _usage;
  late final TextEditingController _orderIndex;
  late DeviceKind _kind;
  late SimCapability _capability;
  late bool _supportsSaRoaming;
  List<DevicePresetSlot>? _presetSlots;
  String? _selectedPresetName;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    _name = TextEditingController(text: item?.name);
    _brand = TextEditingController(text: item?.brand);
    _note = TextEditingController(text: item?.note);
    _region = TextEditingController(text: item?.region);
    _usage = TextEditingController(text: item?.usage);
    _orderIndex = TextEditingController(text: item?.orderIndex.toString());
    _kind = item?.kind ?? DeviceKind.phone;
    _capability = item?.simCapability ?? SimCapability.physicalPlusEsim;
    _supportsSaRoaming = item?.supportsSaRoaming ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _note.dispose();
    _region.dispose();
    _usage.dispose();
    _orderIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? '添加设备' : '编辑设备')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (widget.existing == null) ...[
            OutlinedButton.icon(
              onPressed: _choosePreset,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('从手机型号库选择'),
            ),
            if (_selectedPresetName case final name?) ...[
              const SizedBox(height: 8),
              Text(
                '已应用：$name',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _name,
            autofocus: widget.existing == null,
            decoration: const InputDecoration(labelText: '设备名称 *'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _brand,
            decoration: const InputDecoration(labelText: '品牌（可选）'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<DeviceKind>(
            key: ValueKey(_kind),
            initialValue: _kind,
            decoration: const InputDecoration(labelText: '设备类型'),
            items: [
              for (final kind in DeviceKind.values)
                DropdownMenuItem(
                  value: kind,
                  child: Text(_deviceKindLabel(kind)),
                ),
            ],
            onChanged: (value) => setState(() => _kind = value ?? _kind),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<SimCapability>(
            key: ValueKey(_capability),
            initialValue: _capability,
            decoration: const InputDecoration(labelText: 'SIM 能力'),
            items: [
              for (final item in SimCapability.values)
                DropdownMenuItem(
                  value: item,
                  child: Text(_capabilityLabel(item)),
                ),
            ],
            onChanged: (value) => setState(() {
              _capability = value ?? _capability;
              _presetSlots = null;
              _selectedPresetName = null;
            }),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _region,
            decoration: const InputDecoration(
              labelText: '地区版本（可选）',
              hintText: '例如 CN、US、全球版',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _usage,
            decoration: const InputDecoration(
              labelText: '用途（可选）',
              hintText: '例如主力机、备用机、出差路由器',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _orderIndex,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '排序位置（可选）',
              helperText: '从 0 开始；留空时新设备自动排在最后',
            ),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('支持 5G SA 漫游'),
            subtitle: const Text('按该型号和地区版本的实际能力填写'),
            value: _supportsSaRoaming,
            onChanged: (value) => setState(() => _supportsSaRoaming = value),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '备注（可选）'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('保存设备'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _message(context, '请填写设备名称');
      return;
    }
    final enteredOrder = _orderIndex.text.trim();
    final parsedOrder = enteredOrder.isEmpty
        ? null
        : int.tryParse(enteredOrder);
    if ((parsedOrder != null && parsedOrder < 0) ||
        (enteredOrder.isNotEmpty && parsedOrder == null)) {
      _message(context, '排序位置必须是非负整数');
      return;
    }
    setState(() => _saving = true);
    final controller = AppScope.of(context);
    final existing = widget.existing;
    final now = DateTime.now().toUtc();
    final device = DeviceAsset(
      id: existing?.id ?? const Uuid().v4(),
      name: name,
      kind: _kind,
      brand: _optional(_brand.text),
      note: _optional(_note.text),
      region: _optional(_region.text),
      usage: _optional(_usage.text),
      simCapability: _capability,
      supportsSaRoaming: _supportsSaRoaming,
      orderIndex:
          parsedOrder ??
          existing?.orderIndex ??
          controller.assets.devices.length,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    var error = await controller.saveDevice(device);
    if (error == null && existing == null) {
      final specs =
          _presetSlots?.map((slot) => (slot.label, slot.kind)).toList() ??
          _defaultSlots(_capability);
      for (var index = 0; index < specs.length; index++) {
        final spec = specs[index];
        error = await controller.saveSlot(
          SimSlot(
            id: const Uuid().v4(),
            deviceId: device.id,
            label: spec.$1,
            kind: spec.$2,
            position: index,
            createdAt: now,
            updatedAt: now,
          ),
        );
        if (error != null) break;
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) {
      Navigator.pop(context);
    } else {
      _message(context, error);
    }
  }

  Future<void> _choosePreset() async {
    final preset = await Navigator.push<DevicePreset>(
      context,
      MaterialPageRoute(builder: (_) => const DevicePresetPickerPage()),
    );
    if (preset == null || !mounted) return;
    setState(() {
      _name.text = preset.displayName;
      _brand.text = preset.brand;
      _region.text = preset.region ?? '';
      if (_note.text.trim().isEmpty && preset.note != null) {
        _note.text = preset.note!;
      }
      _kind = preset.kind;
      _capability = preset.simCapability;
      _supportsSaRoaming = preset.supportsSaRoaming;
      _presetSlots = preset.slots.isEmpty ? null : preset.slots;
      _selectedPresetName = '${preset.brand} ${preset.displayName}';
    });
  }
}

class _CardFormPage extends StatefulWidget {
  const _CardFormPage({this.existing});

  final SimCard? existing;

  @override
  State<_CardFormPage> createState() => _CardFormPageState();
}

class _CardFormPageState extends State<_CardFormPage> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  late SimCardKind _kind;
  EuiccCardPreset? _selectedPreset;
  bool _presetInitialized = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name);
    _note = TextEditingController(text: widget.existing?.note);
    _kind = widget.existing?.kind ?? SimCardKind.physicalSim;
    _selectedPreset = euiccCardPresetById(widget.existing?.presetId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_presetInitialized) return;
    _presetInitialized = true;
    _selectedPreset = euiccCardPresetById(
      widget.existing?.presetId,
      presets: AppScope.of(context).euiccCardPresetResult.catalog.cards,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final hasEids =
        existing != null &&
        AppScope.of(context).assets.eidsForCard(existing.id).isNotEmpty;
    final kindLocked =
        existing is EmbeddedEuiccCard ||
        (hasEids && existing is! PhysicalSimCard);
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? '添加卡片' : '编辑卡片')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: _name,
            autofocus: widget.existing == null,
            decoration: const InputDecoration(labelText: '卡片名称 *'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<SimCardKind>(
            key: ValueKey(_kind),
            initialValue: _kind,
            decoration: InputDecoration(
              labelText: '卡片类型',
              helperText: existing is EmbeddedEuiccCard
                  ? '内置类型由设备绑定关系决定'
                  : hasEids && existing is PhysicalSimCard
                  ? '检测到已有 EID，请将类型修正为可拆卸 eUICC'
                  : hasEids
                  ? '卡片已有 EID，需先删除 EID 才能更改类型'
                  : null,
            ),
            items: [
              if (existing is EmbeddedEuiccCard)
                const DropdownMenuItem(
                  value: SimCardKind.embeddedEuicc,
                  child: Text('内置 eUICC'),
                )
              else ...const [
                DropdownMenuItem(
                  value: SimCardKind.physicalSim,
                  child: Text('实体 SIM'),
                ),
                DropdownMenuItem(
                  value: SimCardKind.removableEuicc,
                  child: Text('可拆卸 eUICC'),
                ),
              ],
            ],
            onChanged: kindLocked
                ? null
                : (value) => setState(() {
                    _kind = value ?? _kind;
                    if (_kind != SimCardKind.removableEuicc) {
                      _selectedPreset = null;
                    }
                  }),
          ),
          if (_kind == SimCardKind.removableEuicc) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _choosePreset,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(
                _selectedPreset == null ? '选择可拆卸 eUICC 预设' : '更换 eUICC 预设',
              ),
            ),
            if (_selectedPreset case final preset?) ...[
              const SizedBox(height: 12),
              _SelectedEuiccPreset(
                preset: preset,
                onRemove: () => setState(() => _selectedPreset = null),
              ),
            ],
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '备注（可选）'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存卡片'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _message(context, '请填写卡片名称');
      return;
    }
    setState(() => _saving = true);
    final existing = widget.existing;
    final now = DateTime.now().toUtc();
    final common = (
      id: existing?.id ?? const Uuid().v4(),
      createdAt: existing?.createdAt ?? now,
    );
    final SimCard card = switch (_kind) {
      SimCardKind.physicalSim => PhysicalSimCard(
        id: common.id,
        name: name,
        physicalIccid: existing?.physicalIccid,
        note: _optional(_note.text),
        createdAt: common.createdAt,
        updatedAt: now,
      ),
      SimCardKind.removableEuicc => RemovableEuiccCard(
        id: common.id,
        name: name,
        physicalIccid: existing?.physicalIccid,
        note: _optional(_note.text),
        presetId: _selectedPreset?.id,
        createdAt: common.createdAt,
        updatedAt: now,
      ),
      SimCardKind.embeddedEuicc => EmbeddedEuiccCard(
        id: common.id,
        name: name,
        note: _optional(_note.text),
        presetId: existing?.presetId,
        embeddedDeviceId: (existing as EmbeddedEuiccCard).embeddedDeviceId,
        createdAt: common.createdAt,
        updatedAt: now,
      ),
    };
    final error = await AppScope.of(context).saveCard(card);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) {
      Navigator.pop(context);
    } else {
      _message(context, error);
    }
  }

  Future<void> _choosePreset() async {
    final controller = AppScope.of(context);
    final refreshWarning = await controller.refreshEuiccCardPresets();
    if (!mounted) return;
    final result = controller.euiccCardPresetResult;
    final selected = await showModalBottomSheet<EuiccCardPreset>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '选择可拆卸 eUICC',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${switch (result.source) {
                      EuiccCardPresetSource.network => '已在线更新',
                      EuiccCardPresetSource.cache => '本地缓存',
                      EuiccCardPresetSource.builtIn => 'ieSIM 内置目录',
                    }} · ${result.catalog.catalogVersion} · '
                    '${result.catalog.cards.length} 个型号\n'
                    '以下购买入口为推广链接，9eSIM 与 eSTK.me 均享 9 折。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (refreshWarning != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Text(
                  refreshWarning,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            for (final preset in result.catalog.cards)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.sd_card_outlined),
                  ),
                  title: Text(preset.displayName),
                  subtitle: Text(
                    '${preset.storageLabel} · ${preset.profileCapacityLabel}\n'
                    '${preset.managementLabel}\n推广链接 · 9 折',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(sheetContext, preset),
                ),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedPreset = selected;
      _name.text = selected.displayName;
      if (_note.text.trim().isEmpty) _note.text = selected.description;
    });
  }
}

class _SelectedEuiccPreset extends StatelessWidget {
  const _SelectedEuiccPreset({required this.preset, required this.onRemove});

  final EuiccCardPreset preset;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  preset.displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: '移除预设',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          Text(preset.description),
          const SizedBox(height: 6),
          Text(
            preset.managementLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSecondaryContainer),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(preset.storageLabel)),
              Chip(label: Text(preset.profileCapacityLabel)),
              Chip(
                avatar: const Icon(Icons.sell_outlined, size: 17),
                label: const Text('推广链接 · 9 折'),
              ),
              if (preset.affiliateOffer.promoCode case final code?)
                Chip(label: Text('优惠 / 推荐码 $code')),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () =>
                    _openExternalLink(context, preset.affiliateOffer.url),
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('9 折购买'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openExternalLink(context, preset.officialUrl),
                icon: const Icon(Icons.info_outline_rounded),
                label: const Text('型号官网'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EuiccPresetOfferCard extends StatelessWidget {
  const _EuiccPresetOfferCard({required this.preset});

  final EuiccCardPreset preset;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: preset.displayName,
    subtitle: '可拆卸 eUICC 具体型号预设',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoRow(label: '存储容量', value: preset.storageLabel),
        InfoRow(label: '预计容量', value: preset.profileCapacityLabel),
        InfoRow(label: '管理方式', value: preset.managementLabel),
        Text(preset.description),
        const SizedBox(height: 12),
        Text(
          '推广披露：通过下方链接购买可享 9 折，作者可能获得推荐收益。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (preset.affiliateOffer.promoCode case final code?) ...[
          const SizedBox(height: 8),
          SelectableText('优惠 / 推荐码：$code'),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () =>
                  _openExternalLink(context, preset.affiliateOffer.url),
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text('9 折购买（推广链接）'),
            ),
            OutlinedButton.icon(
              onPressed: () => _openExternalLink(context, preset.officialUrl),
              icon: const Icon(Icons.info_outline_rounded),
              label: const Text('查看型号官网'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ProfileFormPage extends StatefulWidget {
  const _ProfileFormPage({required this.eidId, this.existing});

  final String eidId;
  final EsimProfile? existing;

  @override
  State<_ProfileFormPage> createState() => _ProfileFormPageState();
}

class _ProfileFormPageState extends State<_ProfileFormPage> {
  late final TextEditingController _iccid;
  late final TextEditingController _operator;
  late final TextEditingController _nickname;
  late final TextEditingController _nekokoTagsRaw;
  String? _subscriptionId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _iccid = TextEditingController(text: widget.existing?.iccid);
    _operator = TextEditingController(text: widget.existing?.operatorName);
    _nickname = TextEditingController(text: widget.existing?.nickname);
    _nekokoTagsRaw = TextEditingController(
      text: widget.existing?.nekokoTagsRaw,
    );
    _subscriptionId = widget.existing?.subscriptionId;
  }

  @override
  void dispose() {
    _iccid.dispose();
    _operator.dispose();
    _nickname.dispose();
    _nekokoTagsRaw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final linkedIds = controller.assets.profiles
        .where((item) => item.id != widget.existing?.id)
        .map((item) => item.subscriptionId)
        .whereType<String>()
        .toSet();
    final choices = controller.subscriptions
        .where(
          (item) => !linkedIds.contains(item.id) || item.id == _subscriptionId,
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '添加 Profile' : '编辑 Profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          DropdownButtonFormField<String?>(
            initialValue: _subscriptionId,
            decoration: const InputDecoration(labelText: '关联订阅（推荐）'),
            items: [
              const DropdownMenuItem(value: null, child: Text('暂不关联')),
              for (final item in choices)
                DropdownMenuItem(
                  value: item.id,
                  child: Text(item.operator ?? item.number.value),
                ),
            ],
            onChanged: (value) {
              setState(() => _subscriptionId = value);
              final match = choices.where((item) => item.id == value);
              if (match.isNotEmpty) {
                _iccid.text = match.single.iccid ?? _iccid.text;
                _operator.text = match.single.operator ?? _operator.text;
              }
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _iccid,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'ICCID'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _operator,
            decoration: const InputDecoration(labelText: '运营商'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nickname,
            decoration: const InputDecoration(
              labelText: 'Profile 名称',
              helperText: 'ieSIM 自己的显示名称，不与外部 Tag 混存。',
            ),
          ),
          if (controller.showNekokoTags) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _nekokoTagsRaw,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Nekoko Tag（外部元数据）',
                helperText: '可在“设置”中隐藏；隐藏不会删除已经保存的值。',
              ),
            ),
            if (_subscriptionId != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  final sub = choices.singleWhere(
                    (item) => item.id == _subscriptionId,
                  );
                  _nekokoTagsRaw.text = NekokoTagCodec.encode(
                    _tagsForSubscription(sub),
                  );
                },
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: const Text('从订阅生成 Nekoko Tag'),
              ),
            ],
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存 Profile'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final iccid = _optional(_iccid.text);
    if (iccid == null && _subscriptionId == null) {
      _message(context, '请填写 ICCID 或关联一个订阅');
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now().toUtc();
    final item = EsimProfile(
      id: widget.existing?.id ?? const Uuid().v4(),
      eidId: widget.eidId,
      iccid: iccid,
      operatorName: _optional(_operator.text),
      nickname: _optional(_nickname.text),
      nekokoTagsRaw: _optional(_nekokoTagsRaw.text),
      subscriptionId: _subscriptionId,
      isPinned: widget.existing?.isPinned ?? false,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );
    final error = await AppScope.of(context).saveProfile(item);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) {
      Navigator.pop(context);
    } else {
      _message(context, error);
    }
  }
}

class _EidDialog extends StatefulWidget {
  const _EidDialog({this.existing});

  final Euicc? existing;

  @override
  State<_EidDialog> createState() => _EidDialogState();
}

class _EidDialogState extends State<_EidDialog> {
  late final TextEditingController _value;
  late final TextEditingController _label;

  @override
  void initState() {
    super.initState();
    _value = TextEditingController(text: widget.existing?.value);
    _label = TextEditingController(text: widget.existing?.label);
  }

  @override
  void dispose() {
    _value.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? '添加 EID' : '编辑 EID'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _value,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'EID *',
            hintText: '通常为 32 位数字',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _label,
          decoration: const InputDecoration(
            labelText: '标签（可选）',
            hintText: '例如主 EID、测试 EID',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final value = _value.text.trim();
          if (value.isEmpty) return;
          Navigator.pop(context, (value, _optional(_label.text)));
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class _SlotDialog extends StatefulWidget {
  const _SlotDialog({this.existing, required this.position});

  final SimSlot? existing;
  final int position;

  @override
  State<_SlotDialog> createState() => _SlotDialogState();
}

class _SlotDialogState extends State<_SlotDialog> {
  late final TextEditingController _label;
  late final TextEditingController _position;
  late SimSlotKind _kind;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.existing?.label ?? 'SIM');
    _position = TextEditingController(
      text: (widget.existing?.position ?? widget.position).toString(),
    );
    _kind = widget.existing?.kind ?? SimSlotKind.physical;
  }

  @override
  void dispose() {
    _label.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? '添加卡槽' : '编辑卡槽'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _label,
          autofocus: true,
          decoration: const InputDecoration(labelText: '卡槽名称'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<SimSlotKind>(
          initialValue: _kind,
          decoration: InputDecoration(
            labelText: '卡槽类型',
            helperText: widget.existing?.cardId == null
                ? null
                : '装有卡片时不能更改卡槽类型',
          ),
          items: const [
            DropdownMenuItem(value: SimSlotKind.physical, child: Text('物理卡槽')),
            DropdownMenuItem(
              value: SimSlotKind.embeddedEuicc,
              child: Text('内置 eSIM 卡槽'),
            ),
          ],
          onChanged: widget.existing?.cardId == null
              ? (value) => setState(() => _kind = value ?? _kind)
              : null,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _position,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '排序位置',
            helperText: '从 0 开始，数字较小的卡槽排在前面',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final label = _label.text.trim();
          final position = int.tryParse(_position.text.trim());
          if (label.isNotEmpty && position != null && position >= 0) {
            Navigator.pop(context, (label, _kind, position));
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class _EmbeddedEuiccDialog extends StatefulWidget {
  const _EmbeddedEuiccDialog();

  @override
  State<_EmbeddedEuiccDialog> createState() => _EmbeddedEuiccDialogState();
}

class _EmbeddedEuiccDialogState extends State<_EmbeddedEuiccDialog> {
  final _name = TextEditingController(text: '内置 eUICC');
  final _eid = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _eid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('添加内置 eSIM 组合'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('将同时建立一个内置 eSIM 卡槽和一张与本设备永久绑定的 eUICC 卡。'),
        const SizedBox(height: 14),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'eUICC 卡片名称'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _eid,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'EID'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_name.text.trim().isNotEmpty && _eid.text.trim().isNotEmpty) {
            Navigator.pop(context, (_name.text.trim(), _eid.text.trim()));
          }
        },
        child: const Text('添加'),
      ),
    ],
  );
}

List<NekokoTag> _tagsForSubscription(Subscription item) => [
  for (final tag in item.tags) NekokoTextTag(tag),
  if (item.keepAlive.lastActivityAt case final date?)
    NekokoDateTag(date: _dateOnly(date), note: '保号动作'),
  if (item.plan.expiryDate case final date?)
    NekokoDateTag(date: _dateOnly(date), note: '套餐到期'),
];

DateTime _dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

List<(String, SimSlotKind)> _defaultSlots(SimCapability capability) =>
    switch (capability) {
      SimCapability.physicalOnly => const [('SIM 1', SimSlotKind.physical)],
      SimCapability.esimOnly => const [('内置 eSIM', SimSlotKind.embeddedEuicc)],
      SimCapability.physicalPlusEsim => const [
        ('SIM 1', SimSlotKind.physical),
        ('内置 eSIM', SimSlotKind.embeddedEuicc),
      ],
      SimCapability.dualPhysical => const [
        ('SIM 1', SimSlotKind.physical),
        ('SIM 2', SimSlotKind.physical),
      ],
      SimCapability.multiEsim => const [('eSIM', SimSlotKind.embeddedEuicc)],
      SimCapability.unknown => const [],
    };

String _deviceKindLabel(DeviceKind kind) => switch (kind) {
  DeviceKind.phone => '手机',
  DeviceKind.mobileRouter => '随身 Wi-Fi',
  DeviceKind.tablet => '平板',
  DeviceKind.watch => '手表',
  DeviceKind.laptop => '电脑',
  DeviceKind.esimWriter => 'eSIM 写卡器',
  DeviceKind.other => '其他设备',
};

IconData _deviceIcon(DeviceKind kind) => switch (kind) {
  DeviceKind.phone => Icons.smartphone_rounded,
  DeviceKind.mobileRouter => Icons.router_outlined,
  DeviceKind.tablet => Icons.tablet_android_rounded,
  DeviceKind.watch => Icons.watch_outlined,
  DeviceKind.laptop => Icons.laptop_rounded,
  DeviceKind.esimWriter => Icons.developer_board_outlined,
  DeviceKind.other => Icons.devices_other_rounded,
};

String _capabilityLabel(SimCapability value) => switch (value) {
  SimCapability.physicalOnly => '单实体 SIM',
  SimCapability.esimOnly => '仅 eSIM',
  SimCapability.physicalPlusEsim => '实体 SIM + eSIM',
  SimCapability.dualPhysical => '双实体 SIM',
  SimCapability.multiEsim => '多 eSIM Profile',
  SimCapability.unknown => '自定义 / 未知',
};

String _cardKindLabel(SimCardKind kind) => switch (kind) {
  SimCardKind.physicalSim => '实体 SIM',
  SimCardKind.removableEuicc => '可拆卸 eUICC',
  SimCardKind.embeddedEuicc => '内置 eUICC',
};

IconData _cardIcon(SimCardKind kind) => switch (kind) {
  SimCardKind.physicalSim => Icons.sim_card_outlined,
  SimCardKind.removableEuicc => Icons.sd_card_outlined,
  SimCardKind.embeddedEuicc => Icons.memory_rounded,
};

IconData _eventIcon(AssetEventType type) => switch (type) {
  AssetEventType.cardMoved => Icons.swap_horiz_rounded,
  AssetEventType.cardStored => Icons.inventory_2_outlined,
  AssetEventType.profileMoved => Icons.move_down_rounded,
  AssetEventType.profileWiped => Icons.delete_sweep_outlined,
};

String _locationLabel(AssetInventory inventory, SimSlot? slot) {
  if (slot == null) return '库存';
  final device = inventory.devices.where((item) => item.id == slot.deviceId);
  return '${device.isEmpty ? '未知设备' : device.single.name} / ${slot.label}';
}

String _eventTitle(AssetInventory inventory, AssetEvent event) {
  switch (event) {
    case CardMoved():
      final card = inventory.cardById(event.cardId);
      final slot = inventory.slots.where((item) => item.id == event.toSlotId);
      return '${card?.name ?? '卡片'} 移至 ${_locationLabel(inventory, slot.isEmpty ? null : slot.single)}';
    case CardStored():
      return '${inventory.cardById(event.cardId)?.name ?? '卡片'} 移至库存';
    case ProfileMoved():
      return 'Profile 已迁移到其他 EID';
    case ProfileWiped():
      return 'Profile 已标记擦除';
  }
}

String _dateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _redact(String value) => value.length <= 6
    ? value
    : '${value.substring(0, 4)}••••${value.substring(value.length - 4)}';

String? _optional(String value) {
  final result = value.trim();
  return result.isEmpty ? null : result;
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;

Future<void> _openExternalLink(BuildContext context, String source) async {
  try {
    final opened = await launchUrl(
      Uri.parse(source),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) _message(context, '无法打开链接，请检查系统浏览器');
  } catch (_) {
    if (context.mounted) _message(context, '无法打开链接，请检查系统浏览器');
  }
}

void _message(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}
