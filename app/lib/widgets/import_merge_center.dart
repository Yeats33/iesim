import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

import '../services/import_merge_service.dart';

class ImportMergeSelection {
  const ImportMergeSelection({
    required this.actions,
    required this.targetEidId,
    required this.importToMuseum,
  });

  final Map<String, ImportMergeAction> actions;
  final String? targetEidId;
  final bool importToMuseum;
}

class ImportMergeCenter extends StatefulWidget {
  const ImportMergeCenter({
    super.key,
    required this.plan,
    required this.fileName,
    required this.sourceLabel,
    required this.inventory,
    required this.issueCount,
  });

  final ImportMergePlan plan;
  final String fileName;
  final String sourceLabel;
  final AssetInventory inventory;
  final int issueCount;

  @override
  State<ImportMergeCenter> createState() => ImportMergeCenterState();
}

class ImportMergeCenterState extends State<ImportMergeCenter> {
  late final Map<String, ImportMergeAction> _actions =
      widget.plan.defaultActions;
  String? _targetEidId;
  bool _importToMuseum = false;

  int get _selectedCount => _actions.values
      .where((action) => action != ImportMergeAction.skip)
      .length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final targetEids = widget.inventory.eids
        .where((eid) {
          final card = widget.inventory.cardById(eid.cardId);
          return card != null && card is! PhysicalSimCard;
        })
        .toList(growable: false);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .9,
      minChildSize: .6,
      maxChildSize: .96,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '导入合并中心',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  '${widget.sourceLabel} · ${widget.fileName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ImportStatChip(
                      label: '新增 ${widget.plan.newCount}',
                      icon: Icons.add_circle_outline_rounded,
                    ),
                    _ImportStatChip(
                      label: '匹配 ${widget.plan.matchedCount}',
                      icon: Icons.merge_type_rounded,
                    ),
                    _ImportStatChip(
                      label: '完全重复 ${widget.plan.duplicateCount}',
                      icon: Icons.content_copy_rounded,
                    ),
                    if (widget.plan.weakMatchCount > 0)
                      _ImportStatChip(
                        label: '弱匹配 ${widget.plan.weakMatchCount}',
                        icon: Icons.warning_amber_rounded,
                      ),
                    if (widget.issueCount > 0)
                      _ImportStatChip(
                        label: '源文件提示 ${widget.issueCount}',
                        icon: Icons.info_outline_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _targetEidId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '未关联 Profile 的目标 EID（可选）',
                    helperText: '只补全没有卡片/EID 关系的导入项',
                    prefixIcon: Icon(Icons.memory_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('保持未关联')),
                    for (final eid in targetEids)
                      DropdownMenuItem(
                        value: eid.id,
                        child: Text(_eidTargetLabel(eid)),
                      ),
                  ],
                  onChanged: targetEids.isEmpty
                      ? null
                      : (value) => setState(() => _targetEidId = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('导入到过期博物馆'),
                  subtitle: const Text('对本次写入的 Profile 统一归档'),
                  value: _importToMuseum,
                  onChanged: (value) => setState(() => _importToMuseum = value),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: widget.plan.candidates.isEmpty
                ? const Center(child: Text('没有可导入的 Profile'))
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                    itemCount: widget.plan.candidates.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _candidateTile(widget.plan.candidates[index]),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _selectedCount == 0
                          ? null
                          : () => Navigator.pop(
                              context,
                              ImportMergeSelection(
                                actions: Map.unmodifiable(_actions),
                                targetEidId: _targetEidId,
                                importToMuseum: _importToMuseum,
                              ),
                            ),
                      icon: const Icon(Icons.merge_rounded),
                      label: Text('应用 $_selectedCount 项'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _candidateTile(ImportMergeCandidate candidate) {
    final action = _actions[candidate.incoming.id] ?? candidate.defaultAction;
    final scheme = Theme.of(context).colorScheme;
    final title =
        candidate.incoming.details.profileName ??
        candidate.incoming.operator ??
        (candidate.incoming.number.isUnknown
            ? 'Profile ${candidate.incoming.id}'
            : candidate.incoming.number.value);
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Icon(
            action == ImportMergeAction.skip
                ? Icons.remove_rounded
                : _actionIcon(action),
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_matchLabel(candidate.matchKind)} · '
          '${candidate.diffs.isEmpty ? '无字段变化' : '${candidate.diffs.length} 项差异'}',
        ),
        trailing: Text(
          _actionLabel(action),
          style: TextStyle(
            color: action == ImportMergeAction.skip
                ? scheme.onSurfaceVariant
                : scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          if (candidate.isWeakMatch)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('只因手机号和运营商相同而匹配；默认作为新 Profile，请人工确认。'),
            ),
          DropdownButtonFormField<ImportMergeAction>(
            initialValue: action,
            decoration: const InputDecoration(labelText: '本条导入方式'),
            items: [
              for (final option in candidate.availableActions)
                DropdownMenuItem(
                  value: option,
                  child: Text(_actionDescription(option)),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _actions[candidate.incoming.id] = value);
              }
            },
          ),
          const SizedBox(height: 10),
          if (candidate.diffs.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('本地与导入的关键字段完全相同。'),
            )
          else
            for (final diff in candidate.diffs)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      diff.label,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 3),
                    Text('本地：${diff.currentValue}'),
                    Text('导入：${diff.incomingValue}'),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  String _eidTargetLabel(Euicc eid) {
    final card = widget.inventory.cardById(eid.cardId);
    final short = eid.value.length <= 10
        ? eid.value
        : '…${eid.value.substring(eid.value.length - 10)}';
    return '${card?.name ?? '卡片'} · ${eid.label ?? short}';
  }
}

class _ImportStatChip extends StatelessWidget {
  const _ImportStatChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, size: 17),
    label: Text(label),
    visualDensity: VisualDensity.compact,
  );
}

String _matchLabel(ImportMatchKind kind) => switch (kind) {
  ImportMatchKind.none => '新 Profile',
  ImportMatchKind.id => 'ID 匹配',
  ImportMatchKind.iccid => 'ICCID 匹配',
  ImportMatchKind.activation => 'LPA 凭据匹配',
  ImportMatchKind.phoneAndOperator => '手机号+运营商弱匹配',
};

String _actionLabel(ImportMergeAction action) => switch (action) {
  ImportMergeAction.create => '新增',
  ImportMergeAction.merge => '合并',
  ImportMergeAction.replace => '覆盖',
  ImportMergeAction.skip => '跳过',
};

String _actionDescription(ImportMergeAction action) => switch (action) {
  ImportMergeAction.create => '新增：作为独立 Profile 写入',
  ImportMergeAction.merge => '合并：保留本地值，只补全空字段',
  ImportMergeAction.replace => '覆盖：以导入元数据为主',
  ImportMergeAction.skip => '跳过：本次不写入',
};

IconData _actionIcon(ImportMergeAction action) => switch (action) {
  ImportMergeAction.create => Icons.add_rounded,
  ImportMergeAction.merge => Icons.merge_rounded,
  ImportMergeAction.replace => Icons.swap_horiz_rounded,
  ImportMergeAction.skip => Icons.remove_rounded,
};
