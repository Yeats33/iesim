import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

import '../app/app_scope.dart';
import '../util/formatters.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';
import 'subscription_form_page.dart';

class BalanceManagementPage extends StatelessWidget {
  const BalanceManagementPage({super.key, required this.subscriptionId});

  final String subscriptionId;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final subscription = controller.subscriptionById(subscriptionId);
    if (subscription == null) {
      return const Scaffold(
        body: EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Profile 不存在',
          message: '无法读取余额资料。',
        ),
      );
    }
    final entries = controller
        .activitiesFor(subscriptionId)
        .where((record) => record.type == ActivityType.balanceChange)
        .toList(growable: false);
    final balance = subscription.details.currentBalance;
    final value = const SubscriptionValueCalculator().evaluate(
      subscription,
      nowUtc: DateTime.now().toUtc(),
    );
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('余额与价值')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, subscription),
        icon: const Icon(Icons.add_rounded),
        label: const Text('调整余额'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.paddingOf(context).bottom + 104,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subscription.operator ?? 'Profile',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _heroValue(value),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value.hasMixedCurrencies
                      ? '余额与套餐币种不同，已分开统计，不做自动换汇。'
                      : value.combinedValue == null
                      ? '补充余额或套餐资料后即可计算当前价值。'
                      : '当前可计价值 · 余额 + 套餐剩余价值',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: .76),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _HeroMetric(
                        label: '账面余额',
                        value: balance == null ? '未记录' : formatMoney(balance),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeroMetric(
                        label: '套餐残值',
                        value: value.plan.remainingValue == null
                            ? '待补充'
                            : formatMoney(value.plan.remainingValue!),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PlanValueCard(subscription: subscription, estimate: value.plan),
          const SizedBox(height: 16),
          SectionCard(
            title: '余额流水',
            subtitle: entries.isEmpty ? '暂无调整记录' : '共 ${entries.length} 条',
            child: entries.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('余额更新会与流水在同一个事务中保存。'),
                  )
                : Column(
                    children: [
                      for (var index = 0; index < entries.length; index++) ...[
                        _BalanceEntryTile(
                          record: entries[index],
                          timeZoneId: subscription.timeZoneId,
                        ),
                        if (index != entries.length - 1) const Divider(),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _heroValue(SubscriptionValueBreakdown value) {
    final combined = value.combinedValue;
    if (combined != null) return formatMoney(combined);
    if (value.hasMixedCurrencies) return '分币种统计';
    return '尚未估值';
  }

  static Future<void> _openEditor(
    BuildContext context,
    Subscription subscription,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => AppScope(
      controller: AppScope.of(context),
      child: _BalanceEditorSheet(subscription: subscription),
    ),
  );
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground.withValues(alpha: .72),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanValueCard extends StatelessWidget {
  const _PlanValueCard({required this.subscription, required this.estimate});

  final Subscription subscription;
  final PlanValueEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: '套餐剩余价值',
      subtitle: '按时间线性摊销的账面估算，不包含实时汇率或转售折价',
      trailing: TextButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => SubscriptionFormPage(subscription: subscription),
          ),
        ),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('编辑套餐'),
      ),
      child: estimate.isAvailable
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        formatMoney(estimate.remainingValue!),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    Text(
                      '剩余 ${estimate.remainingPercent}%',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 9,
                    value: estimate.remainingRatio,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _periodDescription(subscription, estimate),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  estimate.method == PlanValueMethod.billingCycle
                      ? '计算：周期价格 × 当前计费周期剩余时间比例'
                      : '计算：套餐价格 × 完整有效期剩余时间比例',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _unavailableMessage(estimate.status),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
    );
  }

  static String _periodDescription(
    Subscription subscription,
    PlanValueEstimate estimate,
  ) {
    final start = estimate.periodStartUtc;
    final end = estimate.periodEndUtc;
    if (start == null || end == null) return '当前估值周期未知';
    return '估值周期 ${formatZonedDate(start, subscription.timeZoneId)} — '
        '${formatZonedDate(end, subscription.timeZoneId)}';
  }

  static String _unavailableMessage(PlanValueStatus status) => switch (status) {
    PlanValueStatus.missingPrice => '尚未填写套餐价格。填写价格和周期后即可计算剩余价值。',
    PlanValueStatus.missingPeriod => '已有套餐价格，还需要计费周期；或同时填写套餐开始与到期日期。',
    PlanValueStatus.invalidPrice => '套餐价格不能为负数，请检查套餐资料。',
    PlanValueStatus.invalidPeriod => '套餐起止时间无效，请检查开始、到期与周期资料。',
    PlanValueStatus.available => '',
  };
}

class _BalanceEntryTile extends StatelessWidget {
  const _BalanceEntryTile({required this.record, required this.timeZoneId});

  final ActivityRecord record;
  final String timeZoneId;

  @override
  Widget build(BuildContext context) {
    final delta = record.amount;
    final after = record.balanceAfter;
    final deltaLabel = delta == null
        ? '更换币种'
        : '${delta.minorUnits >= 0 ? '+' : ''}${formatMoney(delta)}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Icon(
          delta != null && delta.minorUnits < 0
              ? Icons.remove_rounded
              : Icons.add_rounded,
        ),
      ),
      title: Text(deltaLabel),
      subtitle: Text(
        [
          formatZonedDateTime(record.occurredAt, timeZoneId),
          if (record.note case final note? when note.isNotEmpty) note,
        ].join('\n'),
      ),
      trailing: after == null
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('余额'),
                Text(
                  formatMoney(after),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
    );
  }
}

enum _BalanceMode { set, increase, decrease }

class _BalanceEditorSheet extends StatefulWidget {
  const _BalanceEditorSheet({required this.subscription});

  final Subscription subscription;

  @override
  State<_BalanceEditorSheet> createState() => _BalanceEditorSheetState();
}

class _BalanceEditorSheetState extends State<_BalanceEditorSheet> {
  late _BalanceMode _mode;
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _note;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final current = widget.subscription.details.currentBalance;
    _mode = current == null ? _BalanceMode.set : _BalanceMode.increase;
    _amount = TextEditingController();
    _currency = TextEditingController(
      text:
          current?.currencyCode ??
          widget.subscription.plan.cyclePrice?.currencyCode ??
          'CNY',
    );
    _note = TextEditingController();
  }

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.subscription.details.currentBalance;
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
          Text('调整余额', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(current == null ? '当前未记录余额' : '当前 ${formatMoney(current)}'),
          const SizedBox(height: 20),
          SegmentedButton<_BalanceMode>(
            segments: const [
              ButtonSegment(value: _BalanceMode.set, label: Text('设为')),
              ButtonSegment(value: _BalanceMode.increase, label: Text('增加')),
              ButtonSegment(value: _BalanceMode.decrease, label: Text('减少')),
            ],
            selected: {_mode},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() {
              _mode = value.first;
              if (_mode != _BalanceMode.set && current != null) {
                _currency.text = current.currencyCode;
              }
            }),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '金额',
                    hintText: '0.00',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _currency,
                  enabled: _mode == _BalanceMode.set || current == null,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 3,
                  decoration: const InputDecoration(
                    labelText: '币种',
                    hintText: 'CNY',
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
              hintText: '例如：运营商 App 手动校准',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 14),
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
              label: Text(_saving ? '正在保存…' : '保存并记录流水'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final parsed = _parseMinorUnits(_amount.text);
    if (parsed == null ||
        (_mode != _BalanceMode.set && parsed <= 0) ||
        _currency.text.trim().length != 3) {
      _message('请填写有效金额与 3 位币种代码；增加/减少必须大于 0');
      return;
    }
    final current = widget.subscription.details.currentBalance;
    final currency = _currency.text.trim().toUpperCase();
    final nextMinor = switch (_mode) {
      _BalanceMode.set => parsed,
      _BalanceMode.increase => (current?.minorUnits ?? 0) + parsed,
      _BalanceMode.decrease => (current?.minorUnits ?? 0) - parsed,
    };
    setState(() => _saving = true);
    final error = await AppScope.of(context).updateBalance(
      subscription: widget.subscription,
      balance: Money(minorUnits: nextMinor, currencyCode: currency),
      note: _note.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) {
      Navigator.pop(context);
    } else {
      _message(error);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );

  static int? _parseMinorUnits(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
    if (match == null) return null;
    final sign = match.group(1) == '-' ? -1 : 1;
    final whole = int.parse(match.group(2)!);
    final decimals = (match.group(3) ?? '').padRight(2, '0');
    return sign * (whole * 100 + int.parse(decimals.isEmpty ? '0' : decimals));
  }
}
