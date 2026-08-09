import 'package:flutter/material.dart' hide KeepAlive;
import 'package:iesim_core/iesim_core.dart';
import 'package:uuid/uuid.dart';

import '../app/app_scope.dart';
import '../data/euicc_card_presets.dart';
import '../services/compatibility_assistant.dart';
import '../services/carrier_network_catalog_service.dart';
import '../services/carrier_preset_service.dart';
import '../services/country_calling_codes.dart';
import '../widgets/section_card.dart';
import 'data_exchange_page.dart';

class SubscriptionFormPage extends StatefulWidget {
  const SubscriptionFormPage({
    super.key,
    this.subscription,
    this.networkCatalog,
  });

  final Subscription? subscription;
  final CarrierNetworkCatalogService? networkCatalog;

  @override
  State<SubscriptionFormPage> createState() => _SubscriptionFormPageState();
}

class _SubscriptionFormPageState extends State<SubscriptionFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _profileName;
  late final TextEditingController _number;
  late final TextEditingController _operator;
  late final TextEditingController _mcc;
  late final TextEditingController _mnc;
  late final TextEditingController _apn;
  late final TextEditingController _planName;
  late final TextEditingController _price;
  late final TextEditingController _currency;
  late final TextEditingController _planCycle;
  late final TextEditingController _keepAliveCycle;
  late final TextEditingController _keepAliveSummary;
  late final TextEditingController _iccid;
  late final TextEditingController _tags;
  late final TextEditingController _timeZone;
  late final TextEditingController _prompt;
  late final TextEditingController _website;
  late final TextEditingController _activationRequirements;
  final _operatorFocus = FocusNode();

  DateTime? _startDate;
  DateTime? _expiryDate;
  DateTime? _lastActivityDate;
  DateTime? _activationDeadline;
  DateTime? _serviceExpiresAt;
  late ProfileStage _profileStage;
  late ProfileDeviceState _profileDeviceState;
  bool _isLongTerm = false;
  bool _keepAliveRequired = true;
  late Set<KeepAliveAction> _qualifyingActions;
  late List<KeepAliveConstraint> _keepAliveConstraints;
  String? _keepAlivePresetId;
  String? _keepAliveSourceLabel;
  String? _keepAliveSourceUrl;
  DateTime? _keepAliveSourceCheckedAt;
  String? _countryCode;
  String? _countryName;
  String? _flag;
  String? _selectedCardId;
  String? _selectedEidId;
  bool _allowUnassignedPlacement = true;
  bool _placementInitialized = false;
  String _colorHex = '#0B5D57';
  bool _saving = false;
  late final CarrierNetworkCatalogService _networkCatalog;
  Future<CarrierNetworkCatalogLoadResult>? _networkCatalogLoad;
  List<CarrierApn> _availableApns = const [];

  bool get _editing => widget.subscription != null;

  static const _colors = [
    '#0B5D57',
    '#2374AB',
    '#6554C0',
    '#B24C63',
    '#E36B3D',
    '#C38B13',
    '#3D6B47',
    '#4B5563',
  ];

  @override
  void initState() {
    super.initState();
    _networkCatalog = widget.networkCatalog ?? CarrierNetworkCatalogService();
    final subscription = widget.subscription;
    _profileName = TextEditingController(
      text: subscription?.details.profileName,
    );
    _number = TextEditingController(text: subscription?.number.value);
    _operator = TextEditingController(text: subscription?.operator);
    _mcc = TextEditingController(text: subscription?.details.mcc);
    _mnc = TextEditingController(text: subscription?.details.mnc);
    _apn = TextEditingController(text: subscription?.details.apn);
    _planName = TextEditingController(text: subscription?.plan.name);
    _price = TextEditingController(
      text: subscription?.plan.cyclePrice == null
          ? ''
          : _minorUnitsToText(subscription!.plan.cyclePrice!.minorUnits),
    );
    _currency = TextEditingController(
      text: subscription?.plan.cyclePrice?.currencyCode ?? 'CNY',
    );
    _planCycle = TextEditingController(
      text: subscription?.plan.cycleDays?.toString() ?? '',
    );
    _keepAliveCycle = TextEditingController(
      text: subscription?.keepAlive.cycleDays?.toString() ?? '180',
    );
    _keepAliveSummary = TextEditingController(
      text: subscription?.keepAlive.policy.summary,
    );
    _iccid = TextEditingController(text: subscription?.iccid);
    _tags = TextEditingController(text: subscription?.tags.join('，'));
    _timeZone = TextEditingController(
      text: subscription?.timeZoneId ?? 'Asia/Shanghai',
    );
    _prompt = TextEditingController(
      text: subscription?.appearance.customPrompt,
    );
    _website = TextEditingController(text: subscription?.appearance.websiteURL);
    _activationRequirements = TextEditingController(
      text: subscription?.lifecycle.activationRequirements,
    );
    _startDate = _calendarDate(subscription?.plan.startDate, subscription);
    _expiryDate = _calendarDate(subscription?.plan.expiryDate, subscription);
    _lastActivityDate = _calendarDate(
      subscription?.keepAlive.lastActivityAt,
      subscription,
    );
    _activationDeadline = _calendarDate(
      subscription?.lifecycle.activationDeadline,
      subscription,
    );
    _serviceExpiresAt = _calendarDate(
      subscription?.lifecycle.serviceExpiresAt,
      subscription,
    );
    _profileStage = subscription?.lifecycle.stage ?? ProfileStage.active;
    _profileDeviceState =
        subscription?.lifecycle.deviceState ?? ProfileDeviceState.unknown;
    _isLongTerm = subscription?.plan.isLongTerm ?? false;
    _keepAliveRequired = subscription?.keepAlive.required ?? true;
    _qualifyingActions = {
      ...(subscription?.keepAlive.policy.qualifyingActions ??
          KeepAlivePolicy.legacyQualifyingActions),
    };
    _keepAliveConstraints = [...?subscription?.keepAlive.policy.constraints];
    _keepAlivePresetId = subscription?.keepAlive.policy.presetId;
    _keepAliveSourceLabel = subscription?.keepAlive.policy.sourceLabel;
    _keepAliveSourceUrl = subscription?.keepAlive.policy.sourceUrl;
    _keepAliveSourceCheckedAt = subscription?.keepAlive.policy.sourceCheckedAt;
    _countryCode = subscription?.details.countryCode;
    _countryName = subscription?.details.countryName;
    _flag = subscription?.appearance.flag;
    _colorHex = subscription?.appearance.cardColorHex ?? '#0B5D57';
  }

  DateTime? _calendarDate(DateTime? utc, Subscription? subscription) {
    if (utc == null || subscription == null) return null;
    final value = ZonedCalendar(subscription.timeZoneId).momentAt(utc);
    return DateTime(value.year, value.month, value.day);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (!_editing && _timeZone.text == 'Asia/Shanghai') {
      _timeZone.text = controller.defaultTimeZoneId;
    }
    if (!_placementInitialized) {
      _placementInitialized = true;
      final subscription = widget.subscription;
      final profile = subscription == null
          ? null
          : controller.assetProfileForSubscription(subscription);
      if (profile != null) {
        _allowUnassignedPlacement = false;
        for (final eid in controller.assets.eids) {
          if (eid.id != profile.eidId) continue;
          _selectedEidId = eid.id;
          _selectedCardId = eid.cardId;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _profileName,
      _number,
      _operator,
      _mcc,
      _mnc,
      _apn,
      _planName,
      _price,
      _currency,
      _planCycle,
      _keepAliveCycle,
      _keepAliveSummary,
      _iccid,
      _tags,
      _timeZone,
      _prompt,
      _website,
      _activationRequirements,
    ]) {
      controller.dispose();
    }
    _operatorFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? '编辑 Profile' : '添加 Profile'),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            MediaQuery.paddingOf(context).bottom + 110,
          ),
          children: [
            if (!_editing) ...[
              _LpaRecognitionEntry(
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DataExchangePage(lpaOnly: true),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            _FormIntro(editing: _editing),
            const SizedBox(height: 16),
            _ProfilePlacementSection(
              inventory: controller.assets,
              subscriptions: controller.subscriptions,
              presets: controller.euiccCardPresetResult.catalog.cards,
              subscription: widget.subscription,
              selectedCardId: _selectedCardId,
              selectedEidId: _selectedEidId,
              allowUnassigned: _allowUnassignedPlacement,
              onCardChanged: (cardId) {
                setState(() {
                  _selectedCardId = cardId;
                  final selectedStillBelongsToCard = controller.assets.eids.any(
                    (eid) => eid.id == _selectedEidId && eid.cardId == cardId,
                  );
                  if (!selectedStillBelongsToCard) _selectedEidId = null;
                });
              },
              onEidChanged: (eidId) => setState(() => _selectedEidId = eidId),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Profile 状态',
              subtitle: '启用或停用都属于已激活；这里只区分运营商侧生命周期',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<ProfileStage>(
                    segments: const [
                      ButtonSegment(
                        value: ProfileStage.active,
                        label: Text('已激活'),
                        icon: Icon(Icons.check_circle_outline_rounded),
                      ),
                      ButtonSegment(
                        value: ProfileStage.pendingActivation,
                        label: Text('未激活'),
                        icon: Icon(Icons.pending_outlined),
                      ),
                      ButtonSegment(
                        value: ProfileStage.museum,
                        label: Text('博物馆'),
                        icon: Icon(Icons.museum_outlined),
                      ),
                    ],
                    selected: {_profileStage},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) =>
                        setState(() => _profileStage = value.first),
                  ),
                  const SizedBox(height: 16),
                  if (_profileStage == ProfileStage.active) ...[
                    DropdownButtonFormField<ProfileDeviceState>(
                      initialValue: _profileDeviceState,
                      decoration: const InputDecoration(
                        labelText: '设备状态',
                        prefixIcon: Icon(Icons.power_settings_new_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ProfileDeviceState.unknown,
                          child: Text('未知 / 不适用'),
                        ),
                        DropdownMenuItem(
                          value: ProfileDeviceState.enabled,
                          child: Text('已启用（Enabled）'),
                        ),
                        DropdownMenuItem(
                          value: ProfileDeviceState.disabled,
                          child: Text('已停用（Disabled）'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) _profileDeviceState = value;
                      },
                    ),
                    const SizedBox(height: 12),
                    _DateField(
                      label: 'Profile 服务到期日（可选）',
                      value: _serviceExpiresAt,
                      onPick: () => _pickDate(
                        current: _serviceExpiresAt,
                        onChanged: (value) =>
                            setState(() => _serviceExpiresAt = value),
                      ),
                      onClear: _serviceExpiresAt == null
                          ? null
                          : () => setState(() => _serviceExpiresAt = null),
                    ),
                  ] else if (_profileStage ==
                      ProfileStage.pendingActivation) ...[
                    _DateField(
                      label: '最晚激活日期（可选）',
                      value: _activationDeadline,
                      onPick: () => _pickDate(
                        current: _activationDeadline,
                        onChanged: (value) =>
                            setState(() => _activationDeadline = value),
                      ),
                      onClear: _activationDeadline == null
                          ? null
                          : () => setState(() => _activationDeadline = null),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _activationRequirements,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: '激活要求（可选）',
                        hintText: '例如：购买后 180 天内激活；首次下载需位于指定国家',
                        prefixIcon: Icon(Icons.rule_rounded),
                      ),
                    ),
                  ] else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        '直接保存到过期博物馆。资料和历史动作仍会保留，但不再生成保号、套餐或服务到期提醒。',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '基础信息',
              subtitle: '用于识别这个 Profile',
              child: Column(
                children: [
                  _CountryCarrierSelector(
                    countryLabel: _countryName,
                    flag: _flag,
                    callingCode: CountryCallingCodes.forIso(
                      _countryCode,
                    )?.value,
                    carrierLabel: _operator.text.trim().isEmpty
                        ? null
                        : _operator.text.trim(),
                    onCountry: _showCountryPicker,
                    onCarrier: _countryCode == null ? null : _showNetworkPicker,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          '数据库：MCC-MNC.net · APN：Android Open Source Project',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _enableCustomCarrier,
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: const Text('自定义'),
                      ),
                    ],
                  ),
                  Text(
                    '目录只用于建议；运营商、MCC/MNC 和 APN 都可以手动填写。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showCarrierPresets,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: Text(
                        _keepAlivePresetId == null ? '使用运营商预设' : '更换运营商预设',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _profileName,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Profile 名称（可选）',
                      hintText: '例如：英国主号、欧洲旅行卡',
                      helperText: '显示在首页；不等同于运营商品牌或手机号码',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _number,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: '手机号码（可选）',
                      hintText:
                          '${CountryCallingCodes.forIso(_countryCode)?.value ?? '+86'} 138 0000 0000',
                      helperText: '选国家后自动填入国际区号；只保留区号仍视为无号码',
                      prefixIcon: const Icon(Icons.phone_iphone_rounded),
                    ),
                    validator: _validatePhone,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('profile-operator-field'),
                          controller: _operator,
                          focusNode: _operatorFocus,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '运营商',
                            hintText: '中国移动',
                            helperText: '可填写数据库中没有的运营商',
                            prefixIcon: Icon(Icons.cell_tower_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _mcc,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'MCC'),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            return text.isEmpty ||
                                    RegExp(r'^\d{3}$').hasMatch(text)
                                ? null
                                : '应为 3 位';
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _mnc,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'MNC'),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            return text.isEmpty ||
                                    RegExp(r'^\d{2,3}$').hasMatch(text)
                                ? null
                                : '应为 2–3 位';
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _apn,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'APN（可选）',
                      hintText: '例如 internet',
                      prefixIcon: const Icon(Icons.router_outlined),
                      suffixIcon: _availableApns.length > 1
                          ? IconButton(
                              tooltip: '选择 AOSP APN',
                              onPressed: _showApnPicker,
                              icon: const Icon(Icons.expand_more_rounded),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _iccid,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'ICCID',
                      hintText: '用于关联 eSIM Profile（可选）',
                      prefixIcon: Icon(Icons.sim_card_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _tags,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '标签',
                      hintText: '工作，旅行，备用',
                      prefixIcon: Icon(Icons.sell_outlined),
                      helperText: '使用逗号或空格分隔多个标签',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (widget.subscription?.activation case final activation?) ...[
              SectionCard(
                title: 'eSIM 激活信息',
                subtitle: '由二维码 / LPA 导入，激活码已遮盖',
                child: Column(
                  children: [
                    _ReadonlyField(
                      icon: Icons.dns_outlined,
                      label: 'SM-DP+',
                      value: activation.smdpAddress,
                    ),
                    const Divider(),
                    _ReadonlyField(
                      icon: Icons.key_outlined,
                      label: 'Matching ID',
                      value: activation.redactedMatchingId,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            SectionCard(
              title: '套餐',
              subtitle: '套餐到期与保号截止是两套独立日期',
              child: Column(
                children: [
                  TextFormField(
                    controller: _planName,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '套餐名称',
                      hintText: '长期流量卡 / 30 天预付费',
                      prefixIcon: Icon(Icons.layers_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _price,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: '周期价格',
                            hintText: '19.90',
                            prefixIcon: Icon(Icons.payments_outlined),
                          ),
                          validator: _validateMoney,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _currency,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: '币种',
                            hintText: 'CNY',
                          ),
                          validator: (value) {
                            if (_price.text.trim().isEmpty) return null;
                            if (value == null || value.trim().length != 3) {
                              return '三位代码';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _planCycle,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '计费周期（天）',
                            hintText: '30',
                          ),
                          validator: (value) =>
                              _validatePositiveInt(value, required: false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DateField(
                          label: '套餐到期日',
                          value: _expiryDate,
                          onPick: () => _pickDate(
                            current: _expiryDate,
                            onChanged: (value) =>
                                setState(() => _expiryDate = value),
                          ),
                          onClear: _expiryDate == null
                              ? null
                              : () => setState(() => _expiryDate = null),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DateField(
                    label: '套餐开始日',
                    value: _startDate,
                    onPick: () => _pickDate(
                      current: _startDate,
                      onChanged: (value) => setState(() => _startDate = value),
                    ),
                    onClear: _startDate == null
                        ? null
                        : () => setState(() => _startDate = null),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    value: _isLongTerm,
                    onChanged: (value) => setState(() => _isLongTerm = value),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('长期套餐'),
                    subtitle: const Text('长期套餐仍可单独设置保号要求'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '保号策略',
              subtitle: '依据上次真实动作计算号码回收风险',
              trailing: Switch.adaptive(
                value: _keepAliveRequired,
                onChanged: (value) =>
                    setState(() => _keepAliveRequired = value),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: !_keepAliveRequired
                    ? Container(
                        key: const ValueKey('not-required'),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.all_inclusive_rounded,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(child: Text('此号码不需要周期性动作保号')),
                          ],
                        ),
                      )
                    : Column(
                        key: const ValueKey('required'),
                        children: [
                          TextFormField(
                            controller: _keepAliveCycle,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '保号周期（天）*',
                              hintText: '180',
                              prefixIcon: Icon(Icons.autorenew_rounded),
                            ),
                            validator: (value) => _validatePositiveInt(
                              value,
                              required: _keepAliveRequired,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '哪些动作算作保号',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final action in KeepAliveAction.values)
                                  FilterChip(
                                    selected: _qualifyingActions.contains(
                                      action,
                                    ),
                                    avatar: Icon(
                                      _keepAliveActionIcon(action),
                                      size: 17,
                                    ),
                                    label: Text(_keepAliveActionName(action)),
                                    onSelected: (selected) =>
                                        _toggleKeepAliveAction(
                                          action,
                                          selected,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _keepAliveSummary,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: '规则说明（可自定义）',
                              hintText: '写清楚哪些动作有效、何时会被回收号码',
                              prefixIcon: Icon(Icons.rule_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '附加条件',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => _editConstraint(),
                                icon: const Icon(Icons.add_rounded, size: 19),
                                label: const Text('添加'),
                              ),
                            ],
                          ),
                          if (_keepAliveConstraints.isEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '可添加首次使用、套餐到期后续订或付费保号等条件。',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            )
                          else
                            Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < _keepAliveConstraints.length;
                                  index++
                                ) ...[
                                  _ConstraintTile(
                                    constraint: _keepAliveConstraints[index],
                                    onEdit: () => _editConstraint(index),
                                    onDelete: () => setState(
                                      () =>
                                          _keepAliveConstraints.removeAt(index),
                                    ),
                                  ),
                                  if (index < _keepAliveConstraints.length - 1)
                                    const SizedBox(height: 8),
                                ],
                              ],
                            ),
                          if (_keepAliveSourceLabel != null) ...[
                            const SizedBox(height: 12),
                            _RuleSourceCard(
                              label: _keepAliveSourceLabel!,
                              url: _keepAliveSourceUrl,
                              checkedAt: _keepAliveSourceCheckedAt,
                            ),
                          ],
                          const SizedBox(height: 12),
                          _DateField(
                            label: '上次动作日期',
                            value: _lastActivityDate,
                            hint: _editing ? '未记录（状态将显示未知）' : '留空将按创建日期推测',
                            onPick: () => _pickDate(
                              current: _lastActivityDate,
                              onChanged: (value) =>
                                  setState(() => _lastActivityDate = value),
                            ),
                            onClear: _lastActivityDate == null
                                ? null
                                : () =>
                                      setState(() => _lastActivityDate = null),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 17,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '只有上面选中的动作会自动更新这一天；其他记录仍会保留在历史中。',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '显示与时区',
              subtitle: '截止日始终按 Profile 基准时区计算',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _timeZone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'IANA 基准时区 *',
                      hintText: 'Asia/Shanghai',
                      prefixIcon: Icon(Icons.public_rounded),
                    ),
                    validator: _validateTimeZone,
                  ),
                  const SizedBox(height: 16),
                  Text('卡片颜色', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 11,
                    runSpacing: 11,
                    children: [
                      for (final color in _colors)
                        _ColorChoice(
                          colorHex: color,
                          selected: _colorHex == color,
                          onTap: () => setState(() => _colorHex = color),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _prompt,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '自定义提示',
                      hintText: '例如：充值需关闭 Wi-Fi',
                      prefixIcon: Icon(Icons.lightbulb_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _website,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: '运营商网站',
                      hintText: 'https://example.com/account',
                      prefixIcon: Icon(Icons.language_rounded),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final uri = Uri.tryParse(value.trim());
                      if (uri == null ||
                          !uri.hasScheme ||
                          (uri.scheme != 'https' && uri.scheme != 'http')) {
                        return '请输入完整的 http(s) 地址';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? '正在保存…' : '保存 Profile'),
            ),
          ],
        ),
      ),
    );
  }

  Future<CarrierNetworkCatalogLoadResult> _loadNetworkCatalog() =>
      _networkCatalogLoad ??= _networkCatalog.load();

  Future<void> _showCountryPicker() async {
    final country = await showModalBottomSheet<CarrierCountry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .82,
        child: FutureBuilder<CarrierNetworkCatalogLoadResult>(
          future: _loadNetworkCatalog(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _CatalogError(message: '运营商目录加载失败：${snapshot.error}');
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return _CarrierCountryPicker(
              result: snapshot.data!,
              selectedCode: _countryCode,
            );
          },
        ),
      ),
    );
    if (country == null || !mounted) return;
    setState(() {
      final previousCallingCode = CountryCallingCodes.forIso(
        _countryCode,
      )?.value;
      if (_countryCode != country.code) {
        _operator.clear();
        _mcc.clear();
        _mnc.clear();
        _apn.clear();
        _availableApns = const [];
      }
      _countryCode = country.code;
      _countryName = country.name;
      _flag = country.flag;
      _applyCallingCode(
        previousCallingCode: previousCallingCode,
        nextCallingCode: country.callingCode,
      );
    });
  }

  Future<void> _showNetworkPicker() async {
    final countryCode = _countryCode;
    if (countryCode == null) return;
    final selection =
        await showModalBottomSheet<({bool custom, CarrierNetwork? network})>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => FractionallySizedBox(
            heightFactor: .82,
            child: FutureBuilder<CarrierNetworkCatalogLoadResult>(
              future: _loadNetworkCatalog(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _CatalogError(message: '运营商目录加载失败：${snapshot.error}');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _CarrierNetworkPicker(
                  result: snapshot.data!,
                  countryCode: countryCode,
                  selectedPlmn: '${_mcc.text}${_mnc.text}',
                );
              },
            ),
          ),
        );
    if (selection == null || !mounted) return;
    if (selection.custom) {
      _enableCustomCarrier();
      return;
    }
    final network = selection.network!;
    setState(() {
      final previousCallingCode = CountryCallingCodes.forIso(
        _countryCode,
      )?.value;
      _countryCode = network.countryCode;
      _countryName = network.countryName;
      _flag = network.flag;
      _operator.text = network.displayName;
      _mcc.text = network.mcc;
      _mnc.text = network.mnc;
      _availableApns = network.apns;
      _apn.text = network.preferredApn?.apn ?? '';
      _applyCallingCode(
        previousCallingCode: previousCallingCode,
        nextCallingCode: CountryCallingCodes.forIso(network.countryCode)?.value,
      );
    });
  }

  void _enableCustomCarrier() {
    setState(() => _availableApns = const []);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _operatorFocus.requestFocus();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已切换为自定义，可直接修改运营商、MCC/MNC 和 APN'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _applyCallingCode({
    required String? previousCallingCode,
    required String? nextCallingCode,
  }) {
    if (nextCallingCode == null) return;
    final current = _number.text.trim().replaceAll(RegExp(r'\s+'), '');
    if (current.isNotEmpty && current != previousCallingCode) return;
    final text = '$nextCallingCode ';
    _number.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _showApnPicker() async {
    final selected = await showModalBottomSheet<CarrierApn>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .72,
        child: _ApnPicker(apns: _availableApns, selectedApn: _apn.text.trim()),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _apn.text = selected.apn);
  }

  Future<void> _showCarrierPresets() async {
    final load = CarrierPresetService().load();
    final preset = await showModalBottomSheet<CarrierPreset>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .76,
        child: FutureBuilder<CarrierPresetLoadResult>(
          future: load,
          builder: (context, snapshot) {
            if (!snapshot.hasData && !snapshot.hasError) {
              return const Center(child: CircularProgressIndicator());
            }
            final result = snapshot.data;
            final catalog =
                result?.catalog ?? CarrierPresetService.builtInCatalog;
            return _CarrierPresetPicker(
              catalog: catalog,
              warning:
                  result?.warning ??
                  (snapshot.hasError ? '在线目录不可用，已显示内置预设。' : null),
              onSelected: (value) => Navigator.pop(sheetContext, value),
            );
          },
        ),
      ),
    );
    if (preset == null || !mounted) return;
    setState(() {
      final previousCallingCode = CountryCallingCodes.forIso(
        _countryCode,
      )?.value;
      _operator.text = preset.operatorName;
      _website.text = preset.websiteUrl;
      _timeZone.text = preset.timeZoneId;
      _flag = preset.flag;
      _countryCode = preset.countryCode;
      _countryName = preset.countryName;
      _applyCallingCode(
        previousCallingCode: previousCallingCode,
        nextCallingCode: CountryCallingCodes.forIso(preset.countryCode)?.value,
      );
      _keepAliveRequired = true;
      _keepAliveCycle.text = preset.keepAliveDays.toString();
      _keepAliveSummary.text = preset.keepAlivePolicy.summary ?? '';
      _qualifyingActions = {...preset.keepAlivePolicy.qualifyingActions};
      _keepAliveConstraints = [...preset.keepAlivePolicy.constraints];
      _keepAlivePresetId = preset.id;
      _keepAliveSourceLabel = preset.keepAlivePolicy.sourceLabel;
      _keepAliveSourceUrl = preset.keepAlivePolicy.sourceUrl;
      _keepAliveSourceCheckedAt = preset.keepAlivePolicy.sourceCheckedAt;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已套用 ${preset.displayName}，所有字段仍可继续修改'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleKeepAliveAction(KeepAliveAction action, bool selected) {
    if (!selected && _qualifyingActions.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('至少保留一种有效动作'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      if (selected) {
        _qualifyingActions.add(action);
      } else {
        _qualifyingActions.remove(action);
      }
    });
  }

  Future<void> _editConstraint([int? index]) async {
    final existing = index == null ? null : _keepAliveConstraints[index];
    final title = TextEditingController(text: existing?.title);
    final details = TextEditingController(text: existing?.details);
    final days = TextEditingController(text: existing?.withinDays?.toString());
    final regions = TextEditingController(text: existing?.regions.join('，'));
    final completionNote = TextEditingController(
      text: existing?.completionNote,
    );
    var kind = existing?.kind ?? KeepAliveConstraintKind.custom;
    var evaluationMode =
        existing?.evaluationMode ?? _defaultConstraintMode(kind);
    var qualifyingActions = {...?existing?.qualifyingActions};
    var anchorAt = existing?.anchorAt;
    var completed = existing?.completedAt != null;
    String? errorText;
    final result = await showDialog<KeepAliveConstraint>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '添加附加条件' : '编辑附加条件'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<KeepAliveConstraintKind>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: '条件类型'),
                    items: [
                      for (final item in KeepAliveConstraintKind.values)
                        DropdownMenuItem(
                          value: item,
                          child: Text(_constraintKindName(item)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          kind = value;
                          if (existing == null) {
                            evaluationMode = _defaultConstraintMode(value);
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<KeepAliveConstraintEvaluationMode>(
                    initialValue: evaluationMode,
                    decoration: const InputDecoration(labelText: '完成判定'),
                    items: [
                      for (final item
                          in KeepAliveConstraintEvaluationMode.values)
                        DropdownMenuItem(
                          value: item,
                          child: Text(_constraintModeName(item)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => evaluationMode = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: '标题 *',
                      hintText: '例如：激活后首次使用',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: days,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '期限（天，可选）',
                      hintText: '10',
                    ),
                  ),
                  if (kind == KeepAliveConstraintKind.custom ||
                      kind == KeepAliveConstraintKind.paidRetention) ...[
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.flag_outlined),
                      title: const Text('起算日期'),
                      subtitle: Text(
                        anchorAt == null
                            ? '未设置；有期限时将显示资料不足'
                            : '${anchorAt!.year}-${anchorAt!.month.toString().padLeft(2, '0')}-${anchorAt!.day.toString().padLeft(2, '0')}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (anchorAt != null)
                            IconButton(
                              tooltip: '清除',
                              onPressed: () =>
                                  setDialogState(() => anchorAt = null),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          IconButton(
                            tooltip: '选择日期',
                            onPressed: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: dialogContext,
                                initialDate: anchorAt?.toLocal() ?? now,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(now.year + 30),
                              );
                              if (picked == null) return;
                              final calendar = ZonedCalendar(
                                _timeZone.text.trim().isEmpty
                                    ? 'UTC'
                                    : _timeZone.text.trim(),
                              );
                              setDialogState(
                                () => anchorAt = calendar.utcFromParts(
                                  year: picked.year,
                                  month: picked.month,
                                  day: picked.day,
                                  hour: 12,
                                ),
                              );
                            },
                            icon: const Icon(Icons.calendar_month_outlined),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (evaluationMode ==
                      KeepAliveConstraintEvaluationMode.activity) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '独立有效动作（不选则继承主规则）',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final action in KeepAliveAction.values)
                            FilterChip(
                              label: Text(_keepAliveActionName(action)),
                              selected: qualifyingActions.contains(action),
                              onSelected: (selected) => setDialogState(() {
                                if (selected) {
                                  qualifyingActions.add(action);
                                } else {
                                  qualifyingActions.remove(action);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: regions,
                    decoration: const InputDecoration(
                      labelText: '适用地区（可选）',
                      hintText: '英国，欧盟',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: details,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: '具体要求 *',
                      errorText: errorText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('已满足此条件'),
                    subtitle: const Text('手动确认会覆盖自动判定；可随时撤销'),
                    value: completed,
                    onChanged: (value) =>
                        setDialogState(() => completed = value),
                  ),
                  if (completed)
                    TextField(
                      controller: completionNote,
                      maxLength: 500,
                      decoration: const InputDecoration(labelText: '完成备注（可选）'),
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
                final parsedDays = days.text.trim().isEmpty
                    ? null
                    : int.tryParse(days.text.trim());
                if (title.text.trim().isEmpty ||
                    details.text.trim().isEmpty ||
                    (days.text.trim().isNotEmpty &&
                        (parsedDays == null || parsedDays <= 0))) {
                  setDialogState(() => errorText = '请填写标题和要求；期限需为正整数');
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  KeepAliveConstraint(
                    id: existing?.id ?? const Uuid().v4(),
                    kind: kind,
                    title: title.text.trim(),
                    details: details.text.trim(),
                    withinDays: parsedDays,
                    regions: _parseTags(regions.text),
                    evaluationMode: evaluationMode,
                    qualifyingActions: qualifyingActions,
                    anchorAt: anchorAt,
                    completedAt: completed
                        ? existing?.completedAt ?? DateTime.now().toUtc()
                        : null,
                    completionNote: completed
                        ? _emptyToNull(completionNote.text)
                        : null,
                  ),
                );
              },
              child: const Text('保存条件'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    details.dispose();
    days.dispose();
    regions.dispose();
    completionNote.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _keepAliveConstraints.add(result);
      } else {
        _keepAliveConstraints[index] = result;
      }
    });
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (_isCallingCodeOnly(value)) return null;
    try {
      PhoneNumber(value);
      return null;
    } on ArgumentError {
      return '请输入有效号码（允许 +、#、*）';
    }
  }

  bool _isCallingCodeOnly(String value) {
    final callingCode = CountryCallingCodes.forIso(_countryCode)?.value;
    if (callingCode == null) return false;
    return value.trim().replaceAll(RegExp(r'\s+'), '') == callingCode;
  }

  String? _validateMoney(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _parseMinorUnits(value) == null ? '请输入有效金额，最多两位小数' : null;
  }

  String? _validatePositiveInt(String? value, {required bool required}) {
    if (value == null || value.trim().isEmpty) {
      return required ? '请填写天数' : null;
    }
    final parsed = int.tryParse(value.trim());
    return parsed == null || parsed <= 0 ? '请输入正整数' : null;
  }

  String? _validateTimeZone(String? value) {
    if (value == null || value.trim().isEmpty) return '请填写基准时区';
    try {
      ZonedCalendar(value.trim());
      return null;
    } on ArgumentError {
      return '无法识别该 IANA 时区';
    }
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime> onChanged,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 30),
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked != null) onChanged(picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCardId != null && _selectedEidId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请为选定的卡片选择一个 EID'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final existing = widget.subscription;
      final now = DateTime.now().toUtc();
      final createdAt = existing?.createdAt ?? now;
      final timeZoneId = _timeZone.text.trim();
      final calendar = ZonedCalendar(timeZoneId);
      final keepAliveDays = _keepAliveRequired
          ? int.parse(_keepAliveCycle.text.trim())
          : null;
      final lastActivityUtc = _lastActivityDate == null
          ? null
          : calendar.utcFromParts(
              year: _lastActivityDate!.year,
              month: _lastActivityDate!.month,
              day: _lastActivityDate!.day,
              hour: 12,
            );
      final keepAlivePolicy = KeepAlivePolicy(
        qualifyingActions: _qualifyingActions,
        summary: _emptyToNull(_keepAliveSummary.text),
        constraints: _keepAliveConstraints,
        presetId: _keepAlivePresetId,
        sourceLabel: _keepAliveSourceLabel,
        sourceUrl: _keepAliveSourceUrl,
        sourceCheckedAt: _keepAliveSourceCheckedAt,
      );

      final KeepAlive keepAlive;
      if (!_keepAliveRequired) {
        keepAlive = KeepAlive.notRequired();
      } else if (lastActivityUtc != null) {
        keepAlive = KeepAlive(
          required: true,
          cycleDays: keepAliveDays,
          lastActivityAt: lastActivityUtc,
          confidence: DataConfidence.confirmed,
          policy: keepAlivePolicy,
        );
      } else if (!_editing) {
        keepAlive = KeepAlive.inferredFrom(
          createdAt,
          keepAliveDays!,
          policy: keepAlivePolicy,
        );
      } else {
        keepAlive = KeepAlive(
          required: true,
          cycleDays: keepAliveDays,
          confidence: existing!.keepAlive.confidence,
          policy: keepAlivePolicy,
        );
      }

      final priceMinor = _parseMinorUnits(_price.text);
      final expiryUtc = _expiryDate == null
          ? null
          : calendar.utcFromParts(
              year: _expiryDate!.year,
              month: _expiryDate!.month,
              day: _expiryDate!.day,
              hour: 12,
            );
      final startUtc = _startDate == null
          ? null
          : calendar.utcFromParts(
              year: _startDate!.year,
              month: _startDate!.month,
              day: _startDate!.day,
              hour: 12,
            );
      final activationDeadlineUtc = _activationDeadline == null
          ? null
          : calendar.utcFromParts(
              year: _activationDeadline!.year,
              month: _activationDeadline!.month,
              day: _activationDeadline!.day,
              hour: 12,
            );
      final serviceExpiresAtUtc = _serviceExpiresAt == null
          ? null
          : calendar.utcFromParts(
              year: _serviceExpiresAt!.year,
              month: _serviceExpiresAt!.month,
              day: _serviceExpiresAt!.day,
              hour: 12,
            );
      final previousLifecycle = existing?.lifecycle ?? const ProfileLifecycle();
      final lifecycle = switch (_profileStage) {
        ProfileStage.active => ProfileLifecycle(
          stage: ProfileStage.active,
          deviceState: _profileDeviceState,
          activationDeadline: activationDeadlineUtc,
          activationRequirements: _emptyToNull(_activationRequirements.text),
          serviceExpiresAt: serviceExpiresAtUtc,
          activatedAt: previousLifecycle.stage == ProfileStage.active
              ? previousLifecycle.activatedAt
              : now,
        ),
        ProfileStage.pendingActivation => ProfileLifecycle(
          stage: ProfileStage.pendingActivation,
          deviceState: _profileDeviceState,
          activationDeadline: activationDeadlineUtc,
          activationRequirements: _emptyToNull(_activationRequirements.text),
          serviceExpiresAt: serviceExpiresAtUtc,
          activatedAt: previousLifecycle.activatedAt,
        ),
        ProfileStage.museum => ProfileLifecycle(
          stage: ProfileStage.museum,
          deviceState: _profileDeviceState,
          activationDeadline: activationDeadlineUtc,
          activationRequirements: _emptyToNull(_activationRequirements.text),
          serviceExpiresAt: serviceExpiresAtUtc,
          activatedAt: previousLifecycle.activatedAt,
          archivedAt: previousLifecycle.stage == ProfileStage.museum
              ? previousLifecycle.archivedAt ?? now
              : now,
          archiveReason: previousLifecycle.stage == ProfileStage.museum
              ? previousLifecycle.archiveReason ?? ProfileArchiveReason.imported
              : existing == null
              ? ProfileArchiveReason.imported
              : ProfileArchiveReason.manual,
        ),
      };
      final subscription = Subscription(
        id: existing?.id ?? const Uuid().v4(),
        iccid: _emptyToNull(_iccid.text),
        number: _number.text.trim().isEmpty || _isCallingCodeOnly(_number.text)
            ? const PhoneNumber.unknown()
            : PhoneNumber(_number.text),
        operator: _emptyToNull(_operator.text),
        lifecycle: lifecycle,
        activation: existing?.activation,
        plan: Plan(
          name: _emptyToNull(_planName.text),
          cyclePrice: priceMinor == null
              ? null
              : Money(
                  minorUnits: priceMinor,
                  currencyCode: _currency.text.trim().toUpperCase(),
                ),
          cycleDays: int.tryParse(_planCycle.text.trim()),
          startDate: startUtc,
          expiryDate: expiryUtc,
          isLongTerm: _isLongTerm,
        ),
        keepAlive: keepAlive,
        tags: _parseTags(_tags.text),
        appearance: Appearance(
          flag: _flag,
          cardColorHex: _colorHex,
          cardBackgroundAssetName: existing?.appearance.cardBackgroundAssetName,
          websiteURL: _emptyToNull(_website.text),
          customPrompt: _emptyToNull(_prompt.text),
        ),
        details: (existing?.details ?? const SubscriptionDetails()).copyWith(
          profileName: _emptyToNull(_profileName.text),
          countryCode: _countryCode,
          countryName: _countryName,
          mcc: _emptyToNull(_mcc.text),
          mnc: _emptyToNull(_mnc.text),
          apn: _emptyToNull(_apn.text),
          activationDate:
              _profileStage == ProfileStage.active &&
                  previousLifecycle.stage != ProfileStage.active
              ? now
              : existing?.details.activationDate,
        ),
        timeZoneId: timeZoneId,
        createdAt: createdAt,
        updatedAt: now,
      );
      final controller = AppScope.of(context);
      if (_selectedEidId != null) {
        final assessment = EuiccCompatibilityAssistant(
          inventory: controller.assets,
          subscriptions: controller.subscriptions,
          presets: controller.euiccCardPresetResult.catalog.cards,
        ).assess(eidId: _selectedEidId!, subscription: subscription);
        if (assessment.severity != CompatibilitySeverity.compatible) {
          final proceed = await _reviewCompatibility(assessment);
          if (!mounted || !proceed) return;
        }
      }
      final error = _selectedEidId == null
          ? await controller.saveSubscription(subscription)
          : await controller.saveSubscriptionAtEid(
              subscription: subscription,
              eidId: _selectedEidId!,
            );
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _reviewCompatibility(CompatibilityAssessment assessment) async {
    final blocked = !assessment.canProceed;
    final findings = assessment.findings
        .where(
          (finding) => finding.severity != CompatibilitySeverity.compatible,
        )
        .toList(growable: false);
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(blocked ? '无法放置到该 EID' : '保存前确认兼容性'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final finding in findings)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        finding.severity == CompatibilitySeverity.blocked
                            ? Icons.block_rounded
                            : Icons.warning_amber_rounded,
                        color: finding.severity == CompatibilitySeverity.blocked
                            ? Theme.of(dialogContext).colorScheme.error
                            : Theme.of(dialogContext).colorScheme.tertiary,
                      ),
                      title: Text(finding.title),
                      subtitle: Text(finding.detail),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(blocked ? '知道了' : '返回检查'),
              ),
              if (!blocked)
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('仍然保存'),
                ),
            ],
          ),
        ) ??
        false;
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _parseTags(String value) {
    final seen = <String>{};
    return value
        .split(RegExp(r'[,，\s]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && seen.add(item))
        .toList(growable: false);
  }

  static int? _parseMinorUnits(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
    if (match == null) return null;
    final sign = match.group(1) == '-' ? -1 : 1;
    final whole = int.parse(match.group(2)!);
    final decimals = (match.group(3) ?? '').padRight(2, '0');
    return sign * (whole * 100 + int.parse(decimals.isEmpty ? '0' : decimals));
  }

  static String _minorUnitsToText(int value) {
    final negative = value < 0 ? '-' : '';
    final absolute = value.abs();
    return '$negative${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
  }
}

class _CountryCarrierSelector extends StatelessWidget {
  const _CountryCarrierSelector({
    required this.countryLabel,
    required this.flag,
    required this.callingCode,
    required this.carrierLabel,
    required this.onCountry,
    required this.onCarrier,
  });

  final String? countryLabel;
  final String? flag;
  final String? callingCode;
  final String? carrierLabel;
  final VoidCallback onCountry;
  final VoidCallback? onCarrier;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _CatalogSelectionButton(
          step: '1',
          label: '国家/地区',
          value: countryLabel == null
              ? '先选择'
              : '${flag ?? ''} $countryLabel${callingCode == null ? '' : ' · $callingCode'}'
                    .trim(),
          onTap: onCountry,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _CatalogSelectionButton(
          step: '2',
          label: '运营商',
          value: carrierLabel ?? '选择或自定义',
          onTap: onCarrier,
        ),
      ),
    ],
  );
}

class _CatalogSelectionButton extends StatelessWidget {
  const _CatalogSelectionButton({
    required this.step,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String step;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: onTap == null
          ? scheme.surfaceContainerHighest.withValues(alpha: .55)
          : scheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.primary,
                child: Text(
                  step,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 9),
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
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 19,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarrierCountryPicker extends StatefulWidget {
  const _CarrierCountryPicker({required this.result, this.selectedCode});

  final CarrierNetworkCatalogLoadResult result;
  final String? selectedCode;

  @override
  State<_CarrierCountryPicker> createState() => _CarrierCountryPickerState();
}

class _CarrierCountryPickerState extends State<_CarrierCountryPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final countries = widget.result.catalog.countries
        .where((item) => item.matches(query))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CatalogHeader(
          title: '先选择国家/地区',
          subtitle: '${widget.result.catalog.networks.length} 条运营商记录',
          warning: widget.result.warning,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '搜索国家名称、ISO 代码或国际区号',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: countries.length,
            itemBuilder: (context, index) {
              final item = countries[index];
              return ListTile(
                leading: Text(item.flag, style: const TextStyle(fontSize: 24)),
                title: Text(item.name),
                subtitle: Text(
                  '${item.code}${item.callingCode == null ? '' : ' · ${item.callingCode}'}'
                  ' · ${item.networkCount} 个数据库运营商',
                ),
                trailing: item.code == widget.selectedCode
                    ? const Icon(Icons.check_rounded)
                    : const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CarrierNetworkPicker extends StatefulWidget {
  const _CarrierNetworkPicker({
    required this.result,
    required this.countryCode,
    required this.selectedPlmn,
  });

  final CarrierNetworkCatalogLoadResult result;
  final String countryCode;
  final String selectedPlmn;

  @override
  State<_CarrierNetworkPicker> createState() => _CarrierNetworkPickerState();
}

class _CarrierNetworkPickerState extends State<_CarrierNetworkPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.result.catalog.networksForCountry(widget.countryCode);
    final networks = all
        .where((item) => item.matches(_search.text))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CatalogHeader(
          title: '再选择运营商',
          subtitle: all.isEmpty
              ? widget.countryCode
              : '${all.first.flag} ${all.first.countryName} · ${all.length} 条',
          warning: widget.result.warning,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '搜索运营商、MCC、MNC 或 APN',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pop(context, (custom: true, network: null)),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('数据库中没有？自定义运营商'),
            ),
          ),
        ),
        Expanded(
          child: networks.isEmpty
              ? const Center(child: Text('没有匹配的运营商'))
              : ListView.builder(
                  itemCount: networks.length,
                  itemBuilder: (context, index) {
                    final item = networks[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.cell_tower_rounded),
                      ),
                      title: Text(item.displayName),
                      subtitle: Text(
                        'MCC ${item.mcc} · MNC ${item.mnc}'
                        '${item.apns.isEmpty ? '' : ' · ${item.apns.length} 个 APN'}',
                      ),
                      trailing: item.plmn == widget.selectedPlmn
                          ? const Icon(Icons.check_rounded)
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(context, (
                        custom: false,
                        network: item,
                      )),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CatalogHeader extends StatelessWidget {
  const _CatalogHeader({
    required this.title,
    required this.subtitle,
    this.warning,
  });

  final String title;
  final String subtitle;
  final String? warning;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 3),
        Text(subtitle),
        const SizedBox(height: 5),
        Text(
          '${CarrierNetworkCatalogService.mccMncAttribution} · '
          '${CarrierNetworkCatalogService.aospAttribution}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (warning != null) ...[
          const SizedBox(height: 8),
          Text(
            warning!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    ),
  );
}

class _ApnPicker extends StatelessWidget {
  const _ApnPicker({required this.apns, required this.selectedApn});

  final List<CarrierApn> apns;
  final String selectedApn;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      children: [
        Text('选择 AOSP APN', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          CarrierNetworkCatalogService.aospAttribution,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final item in apns)
          ListTile(
            leading: Icon(
              item.apn == selectedApn
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
            ),
            title: Text(item.name),
            subtitle: Text(
              '${item.apn}${item.types.isEmpty ? '' : '\n${item.types.join(' · ')}'}',
            ),
            isThreeLine: item.types.isNotEmpty,
            onTap: () => Navigator.pop(context, item),
          ),
      ],
    ),
  );
}

class _ProfilePlacementSection extends StatelessWidget {
  const _ProfilePlacementSection({
    required this.inventory,
    required this.subscriptions,
    required this.presets,
    required this.subscription,
    required this.selectedCardId,
    required this.selectedEidId,
    required this.allowUnassigned,
    required this.onCardChanged,
    required this.onEidChanged,
  });

  final AssetInventory inventory;
  final Iterable<Subscription> subscriptions;
  final Iterable<EuiccCardPreset> presets;
  final Subscription? subscription;
  final String? selectedCardId;
  final String? selectedEidId;
  final bool allowUnassigned;
  final ValueChanged<String?> onCardChanged;
  final ValueChanged<String?> onEidChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cards = inventory.cards
        .where((card) {
          if (card.kind != SimCardKind.physicalSim) return true;
          return inventory.eids.any((eid) => eid.cardId == card.id);
        })
        .toList(growable: false);
    final eids = selectedCardId == null
        ? const <Euicc>[]
        : inventory.eidsForCard(selectedCardId!).toList(growable: false);
    final selectedEid = eids.where((eid) => eid.id == selectedEidId);
    final assessment = selectedEidId == null
        ? null
        : EuiccCompatibilityAssistant(
            inventory: inventory,
            subscriptions: subscriptions,
            presets: presets,
          ).assess(eidId: selectedEidId!, subscription: subscription);

    return SectionCard(
      title: '卡片与 EID',
      subtitle: '可选：先选卡片，再选该卡片下的 EID',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String?>(
            key: ValueKey('profile-card-$selectedCardId'),
            initialValue: selectedCardId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '卡片',
              prefixIcon: Icon(Icons.sim_card_outlined),
            ),
            items: [
              if (allowUnassigned)
                const DropdownMenuItem(value: null, child: Text('暂不关联卡片')),
              for (final card in cards)
                DropdownMenuItem(
                  value: card.id,
                  child: Text(
                    _cardLabel(card),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: cards.isEmpty ? null : onCardChanged,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: ValueKey('profile-eid-$selectedCardId-$selectedEidId'),
            initialValue: selectedEidId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'EID',
              prefixIcon: const Icon(Icons.memory_rounded),
              helperText: selectedCardId == null
                  ? '请先选择卡片'
                  : eids.isEmpty
                  ? '该卡片还没有 EID，请先到设备页添加'
                  : '一张卡片可以包含多个 EID',
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('请选择 EID')),
              for (final eid in eids)
                DropdownMenuItem(
                  value: eid.id,
                  child: Text(
                    _eidLabel(eid),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: eids.isEmpty ? null : onEidChanged,
          ),
          if (selectedEid.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SelectableText(
                'EID  ${selectedEid.single.value}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
          if (assessment != null) ...[
            const SizedBox(height: 10),
            _CompatibilityPanel(assessment: assessment),
          ],
          if (cards.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '还没有可承载 Profile 的 eUICC 卡片。可以先保存为未关联，或先到“设备”中添加卡片和 EID。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  String _cardLabel(SimCard card) {
    final kind = switch (card.kind) {
      SimCardKind.physicalSim => '实体 SIM',
      SimCardKind.removableEuicc => '可拆卸 eUICC',
      SimCardKind.embeddedEuicc => '内置 eSIM',
    };
    final slot = inventory.slotHolding(card.id);
    String? location;
    if (slot != null) {
      final device = inventory.devices.where(
        (device) => device.id == slot.deviceId,
      );
      location = device.isEmpty
          ? slot.label
          : '${device.single.name} / ${slot.label}';
    }
    return '${card.name} · $kind${location == null ? '' : ' · $location'}';
  }

  static String _eidLabel(Euicc eid) {
    final shortValue = eid.value.length <= 10
        ? eid.value
        : '…${eid.value.substring(eid.value.length - 10)}';
    final label = eid.label?.trim();
    return label == null || label.isEmpty ? shortValue : '$label · $shortValue';
  }
}

class _CompatibilityPanel extends StatelessWidget {
  const _CompatibilityPanel({required this.assessment});

  final CompatibilityAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, foreground, background) = switch (assessment.severity) {
      CompatibilitySeverity.compatible => (
        Icons.verified_outlined,
        scheme.primary,
        scheme.primaryContainer.withValues(alpha: 0.5),
      ),
      CompatibilitySeverity.caution => (
        Icons.warning_amber_rounded,
        scheme.onTertiaryContainer,
        scheme.tertiaryContainer.withValues(alpha: 0.65),
      ),
      CompatibilitySeverity.blocked => (
        Icons.block_rounded,
        scheme.error,
        scheme.errorContainer.withValues(alpha: 0.55),
      ),
    };
    final important = assessment.findings
        .where((finding) => finding.severity == assessment.severity)
        .take(2)
        .toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '兼容性：${assessment.shortLabel}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                for (final finding in important)
                  Text(
                    finding.detail,
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
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

class _FormIntro extends StatelessWidget {
  const _FormIntro({required this.editing});

  final bool editing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer,
            scheme.secondaryContainer.withValues(alpha: .72),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: .82),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              editing ? Icons.edit_rounded : Icons.add_card_rounded,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editing ? '完善 Profile 资料' : '记录一个 SIM / eSIM Profile',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '手机号码可以留空，运营商、ICCID 与套餐也可以稍后补充。',
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
}

class _CarrierPresetPicker extends StatefulWidget {
  const _CarrierPresetPicker({
    required this.catalog,
    required this.onSelected,
    this.warning,
  });

  final CarrierPresetCatalog catalog;
  final String? warning;
  final ValueChanged<CarrierPreset> onSelected;

  @override
  State<_CarrierPresetPicker> createState() => _CarrierPresetPickerState();
}

class _CarrierPresetPickerState extends State<_CarrierPresetPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final carriers = widget.catalog.search(_search.text);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('运营商预设', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            '套用官网核对过的保号规则，之后仍可逐项修改。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '搜索运营商、国家或别名',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          if (widget.warning != null) ...[
            const SizedBox(height: 10),
            Text(
              '在线目录尚未更新，当前使用内置预设。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: carriers.isEmpty
                ? const Center(child: Text('没有匹配的运营商'))
                : ListView.separated(
                    itemCount: carriers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final carrier = carriers[index];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => widget.onSelected(carrier),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  carrier.flag,
                                  style: const TextStyle(fontSize: 28),
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        carrier.displayName,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${carrier.keepAliveDays} 天 · ${carrier.keepAlivePolicy.qualifyingActions.map(_keepAliveActionName).join('、')}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                      if (carrier.keepAlivePolicy.summary
                                          case final summary?) ...[
                                        const SizedBox(height: 7),
                                        Text(
                                          summary,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConstraintTile extends StatelessWidget {
  const _ConstraintTile({
    required this.constraint,
    required this.onEdit,
    required this.onDelete,
  });

  final KeepAliveConstraint constraint;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scope = <String>[
      _constraintModeName(constraint.evaluationMode),
      if (constraint.withinDays != null) '${constraint.withinDays} 天内',
      if (constraint.regions.isNotEmpty) constraint.regions.join(' / '),
      if (constraint.qualifyingActions.isNotEmpty)
        constraint.qualifyingActions.map(_keepAliveActionName).join('、'),
      if (constraint.completedAt != null) '已确认完成',
    ].join(' · ');
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _constraintKindIcon(constraint.kind),
                color: scheme.primary,
                size: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      constraint.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (scope.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        scope,
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: scheme.primary),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      constraint.details,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '删除条件',
                onPressed: onDelete,
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleSourceCard extends StatelessWidget {
  const _RuleSourceCard({required this.label, this.url, this.checkedAt});

  final String label;
  final String? url;
  final DateTime? checkedAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final checked = checkedAt == null
        ? null
        : '${checkedAt!.year}-${checkedAt!.month.toString().padLeft(2, '0')}-${checkedAt!.day.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: .48),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_outlined, color: scheme.tertiary, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('规则来源：$label'),
                if (checked != null)
                  Text(
                    '核对日期 $checked',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (url != null)
                  Text(
                    url!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
}

String _keepAliveActionName(KeepAliveAction action) => switch (action) {
  KeepAliveAction.mobileData => '使用流量',
  KeepAliveAction.call => '通话',
  KeepAliveAction.sms => '短信',
  KeepAliveAction.topUp => '充值',
  KeepAliveAction.planPurchase => '购买套餐',
  KeepAliveAction.renewal => '续费',
  KeepAliveAction.balanceChange => '余额变动',
  KeepAliveAction.other => '其他动作',
};

IconData _keepAliveActionIcon(KeepAliveAction action) => switch (action) {
  KeepAliveAction.mobileData => Icons.data_usage_rounded,
  KeepAliveAction.call => Icons.call_outlined,
  KeepAliveAction.sms => Icons.sms_outlined,
  KeepAliveAction.topUp => Icons.add_card_rounded,
  KeepAliveAction.planPurchase => Icons.shopping_bag_outlined,
  KeepAliveAction.renewal => Icons.autorenew_rounded,
  KeepAliveAction.balanceChange => Icons.account_balance_wallet_outlined,
  KeepAliveAction.other => Icons.more_horiz_rounded,
};

String _constraintKindName(KeepAliveConstraintKind kind) => switch (kind) {
  KeepAliveConstraintKind.firstUse => '首次使用',
  KeepAliveConstraintKind.afterPlanExpiry => '套餐到期后',
  KeepAliveConstraintKind.paidRetention => '付费保号',
  KeepAliveConstraintKind.custom => '自定义',
};

KeepAliveConstraintEvaluationMode _defaultConstraintMode(
  KeepAliveConstraintKind kind,
) => switch (kind) {
  KeepAliveConstraintKind.firstUse || KeepAliveConstraintKind.afterPlanExpiry =>
    KeepAliveConstraintEvaluationMode.activity,
  KeepAliveConstraintKind.paidRetention ||
  KeepAliveConstraintKind.custom => KeepAliveConstraintEvaluationMode.manual,
};

String _constraintModeName(KeepAliveConstraintEvaluationMode mode) =>
    switch (mode) {
      KeepAliveConstraintEvaluationMode.activity => '按活动记录自动判定',
      KeepAliveConstraintEvaluationMode.manual => '手动确认',
    };

IconData _constraintKindIcon(KeepAliveConstraintKind kind) => switch (kind) {
  KeepAliveConstraintKind.firstUse => Icons.first_page_rounded,
  KeepAliveConstraintKind.afterPlanExpiry => Icons.event_busy_outlined,
  KeepAliveConstraintKind.paidRetention => Icons.payments_outlined,
  KeepAliveConstraintKind.custom => Icons.tune_rounded,
};

class _LpaRecognitionEntry extends StatelessWidget {
  const _LpaRecognitionEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  color: scheme.primary,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '二维码 / LPA 识别',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '相机扫码、从相册或截图识别，也可以粘贴激活码',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(alpha: .76),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onPrimaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadonlyField extends StatelessWidget {
  const _ReadonlyField({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 11),
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    this.hint = '选择日期',
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final String hint;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = value == null
        ? hint
        : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-'
              '${value!.day.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(18),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear == null
              ? const Icon(Icons.calendar_today_outlined, size: 19)
              : IconButton(
                  tooltip: '清除日期',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: value == null ? scheme.onSurfaceVariant : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.colorHex,
    required this.selected,
    required this.onTap,
  });

  final String colorHex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(
      0xFF000000 | int.parse(colorHex.substring(1), radix: 16),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '卡片颜色 $colorHex',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: .25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: selected
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 21)
              : null,
        ),
      ),
    );
  }
}
