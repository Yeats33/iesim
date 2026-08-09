import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../app/app_scope.dart';
import '../services/app_binding_preset_service.dart';
import '../services/apple_app_store_lookup_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_card.dart';

class AppBindingManagementPage extends StatefulWidget {
  const AppBindingManagementPage({
    super.key,
    required this.subscriptionId,
    this.presetService,
    this.appStoreLookupService,
  });

  final String subscriptionId;
  final AppBindingPresetService? presetService;
  final AppleAppStoreLookupService? appStoreLookupService;

  @override
  State<AppBindingManagementPage> createState() =>
      _AppBindingManagementPageState();
}

class _AppBindingManagementPageState extends State<AppBindingManagementPage> {
  late final AppBindingPresetService _presetService =
      widget.presetService ?? AppBindingPresetService();
  late final AppleAppStoreLookupService _lookupService =
      widget.appStoreLookupService ?? AppleAppStoreLookupService();
  bool _loadingPreset = false;

  @override
  Widget build(BuildContext context) {
    final subscription = AppScope.of(
      context,
    ).subscriptionById(widget.subscriptionId);
    if (subscription == null) {
      return const Scaffold(
        body: EmptyState(
          icon: Icons.link_off_rounded,
          title: 'Profile 不存在',
          message: '无法读取它的号码绑定。',
        ),
      );
    }
    final bindings = subscription.details.appBindings;
    final numberCount = bindings.map((item) => item.phoneNumber).toSet().length;
    return Scaffold(
      appBar: AppBar(title: const Text('号码绑定')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadingPreset ? null : () => _addBinding(subscription),
        icon: _loadingPreset
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_link_rounded),
        label: Text(_loadingPreset ? '读取预设' : '添加绑定'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.paddingOf(context).bottom + 104,
        ),
        children: [
          const _PrivacyNotice(),
          const SizedBox(height: 16),
          SectionCard(
            title: '绑定总览',
            subtitle: bindings.isEmpty
                ? '记录号码在哪些 App 中使用'
                : '$numberCount 个号码 · ${bindings.length} 个 App 绑定',
            child: bindings.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('还没有记录。可以从 WhatsApp 预设开始，或添加自定义 App。'),
                  )
                : Column(
                    children: [
                      for (var index = 0; index < bindings.length; index++) ...[
                        _BindingTile(
                          binding: bindings[index],
                          onEdit: () =>
                              _editBinding(subscription, bindings[index]),
                          onDelete: () =>
                              _deleteBinding(subscription, bindings[index]),
                        ),
                        if (index != bindings.length - 1) const Divider(),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _addBinding(Subscription subscription) async {
    setState(() => _loadingPreset = true);
    final AppBindingPresetLoadResult result;
    try {
      result = await _presetService.load();
    } finally {
      if (mounted) setState(() => _loadingPreset = false);
    }
    if (!mounted) return;
    if (result.warning case final warning?) _message(warning);
    final choice = await showModalBottomSheet<_PresetChoice>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _PresetPicker(catalog: result.catalog),
    );
    if (!mounted || choice == null) return;
    final created = await showModalBottomSheet<PhoneAppBinding>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _BindingEditor(
        subscription: subscription,
        preset: choice.preset,
        lookupService: _lookupService,
      ),
    );
    if (created != null && mounted) await _saveBinding(created);
  }

  Future<void> _editBinding(
    Subscription subscription,
    PhoneAppBinding binding,
  ) async {
    final edited = await showModalBottomSheet<PhoneAppBinding>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _BindingEditor(
        subscription: subscription,
        existing: binding,
        lookupService: _lookupService,
      ),
    );
    if (edited != null && mounted) await _saveBinding(edited);
  }

  Future<void> _saveBinding(PhoneAppBinding binding) async {
    final controller = AppScope.of(context);
    final latest = controller.subscriptionById(widget.subscriptionId);
    if (latest == null) return;
    final bindings = [...latest.details.appBindings];
    final index = bindings.indexWhere((item) => item.id == binding.id);
    if (index < 0) {
      bindings.add(binding);
    } else {
      bindings[index] = binding;
    }
    final error = await controller.saveSubscription(
      latest.copyWith(
        details: latest.details.copyWith(appBindings: bindings),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    if (mounted) _message(error ?? '号码绑定已保存');
  }

  Future<void> _deleteBinding(
    Subscription subscription,
    PhoneAppBinding binding,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.link_off_rounded),
        title: Text('删除 ${binding.appName} 绑定？'),
        content: Text('只会删除 ieSIM 中 ${binding.phoneNumber} 的记录，不会更改外部 App 账户。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除记录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final controller = AppScope.of(context);
    final latest = controller.subscriptionById(subscription.id);
    if (latest == null) return;
    final error = await controller.saveSubscription(
      latest.copyWith(
        details: latest.details.copyWith(
          appBindings: latest.details.appBindings
              .where((item) => item.id != binding.id)
              .toList(growable: false),
        ),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    if (mounted) _message(error ?? '已删除绑定记录');
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.privacy_tip_outlined, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'ieSIM 只保存你填写的绑定关系和验证状态，不读取短信、验证码或 App 内容。查询商店资料时也不会发送手机号。',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetPicker extends StatefulWidget {
  const _PresetPicker({required this.catalog});

  final AppBindingPresetCatalog catalog;

  @override
  State<_PresetPicker> createState() => _PresetPickerState();
}

class _PresetPickerState extends State<_PresetPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = widget.catalog.search(_query);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('选择 App', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            '目录版本 ${widget.catalog.catalogVersion}，也可以完全自定义。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              labelText: '搜索名称或包名',
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.add_box_outlined),
                  ),
                  title: const Text('自定义 App'),
                  subtitle: const Text('手动填写名称、商店 ID 与绑定用途'),
                  onTap: () {
                    Navigator.pop(context, const _PresetChoice.custom());
                  },
                ),
                for (final preset in results)
                  ListTile(
                    leading: _AppIcon(url: preset.iconUrl, size: 42),
                    title: Text(preset.displayName),
                    subtitle: Text(
                      '${preset.developerName}\n${preset.description}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    onTap: () =>
                        Navigator.pop(context, _PresetChoice.preset(preset)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChoice {
  const _PresetChoice.custom() : preset = null;
  const _PresetChoice.preset(this.preset);

  final AppBindingPreset? preset;
}

class _BindingEditor extends StatefulWidget {
  const _BindingEditor({
    required this.subscription,
    required this.lookupService,
    this.existing,
    this.preset,
  });

  final Subscription subscription;
  final AppleAppStoreLookupService lookupService;
  final PhoneAppBinding? existing;
  final AppBindingPreset? preset;

  @override
  State<_BindingEditor> createState() => _BindingEditorState();
}

class _BindingEditorState extends State<_BindingEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone;
  late final TextEditingController _appName;
  late final TextEditingController _developer;
  late final TextEditingController _account;
  late final TextEditingController _note;
  late final TextEditingController _appStoreId;
  late final TextEditingController _googlePackage;
  late String? _iconUrl;
  late String? _appStoreUrl;
  late String? _appStoreBundleId;
  late String? _googlePlayUrl;
  late String? _websiteUrl;
  late DateTime? _metadataUpdatedAt;
  late PhoneAppBindingStatus _status;
  late Set<PhoneAppBindingPurpose> _purposes;
  late Set<PhoneVerificationChannel> _channels;
  late bool _verified;
  bool _lookingUp = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final preset = widget.preset;
    final primary = !widget.subscription.number.isUnknown
        ? widget.subscription.number.value
        : '';
    _phone = TextEditingController(text: existing?.phoneNumber ?? primary);
    _appName = TextEditingController(
      text: existing?.appName ?? preset?.displayName ?? '',
    );
    _developer = TextEditingController(
      text: existing?.developerName ?? preset?.developerName ?? '',
    );
    _account = TextEditingController(text: existing?.accountLabel ?? '');
    _note = TextEditingController(
      text: existing?.note ?? preset?.verificationNote ?? '',
    );
    _appStoreId = TextEditingController(
      text: existing?.appStoreId ?? preset?.appStoreId ?? '',
    );
    _googlePackage = TextEditingController(
      text: existing?.googlePlayPackage ?? preset?.googlePlayPackage ?? '',
    );
    _iconUrl = existing?.iconUrl ?? preset?.iconUrl;
    _appStoreUrl = existing?.appStoreUrl ?? preset?.appStoreUrl;
    _appStoreBundleId = existing?.appStoreBundleId ?? preset?.appStoreBundleId;
    _googlePlayUrl = existing?.googlePlayUrl ?? preset?.googlePlayUrl;
    _websiteUrl = existing?.websiteUrl ?? preset?.websiteUrl;
    _metadataUpdatedAt = existing?.storeMetadataUpdatedAt;
    _status = existing?.status ?? PhoneAppBindingStatus.active;
    _purposes = {
      ...(existing?.purposes ??
          preset?.defaultPurposes ??
          const <PhoneAppBindingPurpose>[]),
    };
    _channels = {
      ...(existing?.verificationChannels ??
          preset?.verificationChannels ??
          const <PhoneVerificationChannel>[]),
    };
    _verified = existing?.verifiedAt != null;
  }

  @override
  void dispose() {
    _phone.dispose();
    _appName.dispose();
    _developer.dispose();
    _account.dispose();
    _note.dispose();
    _appStoreId.dispose();
    _googlePackage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final numbers = <String>{
      if (!widget.subscription.number.isUnknown)
        widget.subscription.number.value,
      if (widget.subscription.details.secondaryPhoneNumber?.trim()
          case final number? when number.isNotEmpty)
        number,
    };
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _AppIcon(url: _iconUrl, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.existing == null ? '添加号码绑定' : '编辑号码绑定',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const Text('绑定资料保存在这个 Profile 中'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: '绑定号码',
                  hintText: '+372…',
                  suffixIcon: numbers.isEmpty
                      ? null
                      : PopupMenuButton<String>(
                          tooltip: '选择 Profile 号码',
                          icon: const Icon(Icons.contact_phone_outlined),
                          onSelected: (value) => _phone.text = value,
                          itemBuilder: (_) => [
                            for (final number in numbers)
                              PopupMenuItem(value: number, child: Text(number)),
                          ],
                        ),
                ),
                maxLength: 80,
                validator: _required,
              ),
              TextFormField(
                controller: _appName,
                decoration: const InputDecoration(labelText: 'App 名称'),
                maxLength: 160,
                validator: _required,
              ),
              TextFormField(
                controller: _developer,
                decoration: const InputDecoration(labelText: '开发者（可选）'),
                maxLength: 160,
              ),
              TextFormField(
                controller: _account,
                decoration: const InputDecoration(
                  labelText: '账号 / 使用场景（可选）',
                  hintText: '例如：主账号、客服号、恢复号码',
                ),
                maxLength: 160,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<PhoneAppBindingStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: '绑定状态'),
                items: [
                  for (final status in PhoneAppBindingStatus.values)
                    DropdownMenuItem(
                      value: status,
                      child: Text(_statusLabel(status)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              const SizedBox(height: 18),
              Text('用途', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final purpose in PhoneAppBindingPurpose.values)
                    FilterChip(
                      label: Text(_purposeLabel(purpose)),
                      selected: _purposes.contains(purpose),
                      onSelected: (selected) => setState(() {
                        selected
                            ? _purposes.add(purpose)
                            : _purposes.remove(purpose);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text('号码验证方式', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final channel in PhoneVerificationChannel.values)
                    FilterChip(
                      label: Text(_channelLabel(channel)),
                      selected: _channels.contains(channel),
                      onSelected: (selected) => setState(() {
                        selected
                            ? _channels.add(channel)
                            : _channels.remove(channel);
                      }),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('已完成号码验证'),
                subtitle: const Text('只记录状态，不读取验证码'),
                value: _verified,
                onChanged: (value) => setState(() => _verified = value),
              ),
              const Divider(height: 32),
              Text('商店资料', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              TextFormField(
                controller: _appStoreId,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'App Store ID（可选）',
                  suffixIcon: IconButton(
                    tooltip: '从 Apple 刷新公开资料',
                    onPressed: _lookingUp ? null : _lookupApple,
                    icon: _lookingUp
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download_outlined),
                  ),
                ),
                maxLength: 40,
              ),
              TextFormField(
                controller: _googlePackage,
                decoration: const InputDecoration(
                  labelText: 'Google Play 包名（可选）',
                  hintText: 'com.example.app',
                ),
                maxLength: 200,
              ),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(labelText: '验证 / 绑定备注（可选）'),
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
              ),
              if (_appStoreUrl != null || _googlePlayUrl != null) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    if (_appStoreUrl case final url?)
                      TextButton.icon(
                        onPressed: () => _openUrl(url),
                        icon: const Icon(Icons.apple_rounded),
                        label: const Text('App Store'),
                      ),
                    if (_googlePlayUrl case final url?)
                      TextButton.icon(
                        onPressed: () => _openUrl(url),
                        icon: const Icon(Icons.shop_outlined),
                        label: const Text('Google Play'),
                      ),
                  ],
                ),
                const Text(
                  '图标用于识别 App，并与对应商店入口一起展示。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存绑定'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _lookupApple() async {
    FocusScope.of(context).unfocus();
    setState(() => _lookingUp = true);
    try {
      final country = widget.subscription.details.countryCode ?? 'US';
      final metadata = await widget.lookupService.lookupById(
        _appStoreId.text,
        country: country.length == 2 ? country : 'US',
      );
      if (!mounted) return;
      setState(() {
        _appName.text = metadata.name;
        _developer.text = metadata.developerName;
        _appStoreId.text = metadata.appId;
        _appStoreBundleId = metadata.bundleId;
        _appStoreUrl = metadata.storeUrl;
        _iconUrl = metadata.iconUrl;
        _metadataUpdatedAt = metadata.fetchedAt;
      });
      _message('已从 App Store 刷新 ${metadata.name}（${metadata.version}）');
    } catch (error) {
      if (mounted) _message('App Store 资料读取失败：$error');
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;
    final now = DateTime.now().toUtc();
    final appStoreId = _nullable(_appStoreId.text);
    final googlePackage = _nullable(_googlePackage.text);
    try {
      final binding = PhoneAppBinding(
        id: widget.existing?.id ?? const Uuid().v4(),
        phoneNumber: _phone.text.trim(),
        appName: _appName.text.trim(),
        presetId: widget.existing?.presetId ?? widget.preset?.id,
        developerName: _nullable(_developer.text),
        accountLabel: _nullable(_account.text),
        status: _status,
        purposes: _purposes.toList(growable: false),
        verificationChannels: _channels.toList(growable: false),
        verifiedAt: _verified ? widget.existing?.verifiedAt ?? now : null,
        note: _nullable(_note.text),
        appStoreId: appStoreId,
        appStoreBundleId: _appStoreBundleId,
        appStoreUrl:
            _appStoreUrl ??
            (appStoreId == null
                ? null
                : 'https://apps.apple.com/app/id$appStoreId'),
        googlePlayPackage: googlePackage,
        googlePlayUrl: googlePackage == null
            ? _googlePlayUrl
            : 'https://play.google.com/store/apps/details?id=$googlePackage',
        iconUrl: _iconUrl,
        websiteUrl: _websiteUrl,
        storeMetadataUpdatedAt: _metadataUpdatedAt,
        createdAt: widget.existing?.createdAt ?? now,
        updatedAt: now,
      );
      Navigator.pop(context, binding);
    } on FormatException catch (error) {
      _message(error.message);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
}

class _BindingTile extends StatelessWidget {
  const _BindingTile({
    required this.binding,
    required this.onEdit,
    required this.onDelete,
  });

  final PhoneAppBinding binding;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      ?binding.accountLabel,
      if (binding.purposes.isNotEmpty)
        binding.purposes.map(_purposeLabel).join(' · '),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AppIcon(url: binding.iconUrl, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        binding.appName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    _StatusChip(status: binding.status),
                  ],
                ),
                Text(
                  binding.phoneNumber,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle.isNotEmpty) Text(subtitle),
                if (binding.developerName case final developer?)
                  Text(developer, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  children: [
                    if (binding.appStoreUrl case final url?)
                      IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        tooltip: '打开 App Store',
                        onPressed: () => _openUrl(url),
                        icon: const Icon(Icons.apple_rounded, size: 18),
                      ),
                    if (binding.googlePlayUrl case final url?)
                      IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        tooltip: '打开 Google Play',
                        onPressed: () => _openUrl(url),
                        icon: const Icon(Icons.shop_outlined, size: 18),
                      ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '编辑',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '删除',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
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
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final PhoneAppBindingStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = status == PhoneAppBindingStatus.active;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabel(status),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(size * .24),
      ),
      child: const Icon(Icons.apps_rounded),
    );
    if (url == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .24),
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

String _statusLabel(PhoneAppBindingStatus value) => switch (value) {
  PhoneAppBindingStatus.pending => '待验证',
  PhoneAppBindingStatus.active => '使用中',
  PhoneAppBindingStatus.disabled => '已停用',
};

String _purposeLabel(PhoneAppBindingPurpose value) => switch (value) {
  PhoneAppBindingPurpose.messaging => '通讯',
  PhoneAppBindingPurpose.signIn => '登录',
  PhoneAppBindingPurpose.verification => '验证',
  PhoneAppBindingPurpose.recovery => '找回',
  PhoneAppBindingPurpose.payment => '支付',
  PhoneAppBindingPurpose.other => '其他',
};

String _channelLabel(PhoneVerificationChannel value) => switch (value) {
  PhoneVerificationChannel.sms => '短信',
  PhoneVerificationChannel.voiceCall => '语音来电',
  PhoneVerificationChannel.inApp => 'App 内',
};

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? '请填写这个字段' : null;

String? _nullable(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Future<void> _openUrl(String value) async {
  final uri = Uri.tryParse(value);
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
