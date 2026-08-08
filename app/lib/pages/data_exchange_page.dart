import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide KeepAlive;
import 'package:flutter/services.dart';
import 'package:iesim_core/iesim_core.dart';
import 'package:uuid/uuid.dart';

import '../app/app_scope.dart';
import '../app/brand.dart';
import '../platform/document_saver.dart';
import '../services/profile_catalog_service.dart';
import '../widgets/section_card.dart';
import 'lpa_scanner_page.dart';
import 'subscription_detail_page.dart';

class DataExchangePage extends StatefulWidget {
  const DataExchangePage({super.key, this.lpaOnly = false});

  final bool lpaOnly;

  @override
  State<DataExchangePage> createState() => _DataExchangePageState();
}

class _DataExchangePageState extends State<DataExchangePage> {
  bool _working = false;
  final _profileCatalog = ProfileCatalogService();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.lpaOnly ? '二维码 / LPA 识别' : '导入与导出')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.paddingOf(context).bottom + 36,
        ),
        children: [
          if (widget.lpaOnly)
            SectionCard(
              title: '二维码 / LPA 导入',
              subtitle: '识别 SM-DP+，并用外部 Profile 数据源匹配',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SafetyPoint(
                    icon: Icons.qr_code_scanner_rounded,
                    text: '支持相机扫描和粘贴 LPA:1\$… 激活码',
                  ),
                  const SizedBox(height: 10),
                  const _SafetyPoint(
                    icon: Icons.shield_outlined,
                    text: '匹配前先预览；不自动下载或安装 eSIM Profile',
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _working ? null : _scanLpa,
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: const Text('扫码导入'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _working ? null : _pasteLpa,
                          icon: const Icon(Icons.content_paste_rounded),
                          label: const Text('粘贴 LPA'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primaryContainer, scheme.secondaryContainer],
                ),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: .76),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.swap_horiz_rounded,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '从外部带入，也能完整带走',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '先选择导入或导出，再选择来源、目标应用与文件格式。${AppBrand.name} 会保留完整资产关系。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _ExchangePortalCard(
              icon: Icons.file_download_outlined,
              title: '导入数据',
              subtitle: '从二维码、其他应用或备份文件带入',
              detail: '导入前预览并检查，不会直接覆盖现有资料',
              onTap: _working ? null : _showImportOptions,
            ),
            const SizedBox(height: 14),
            _ExchangePortalCard(
              icon: Icons.file_upload_outlined,
              title: '导出数据',
              subtitle: '创建完整备份，或生成其他应用兼容文件',
              detail:
                  '${controller.assets.profiles.length} 个 Profile · '
                  '${controller.subscriptions.length} 条号码资料',
              onTap: _working ? null : _showExportOptions,
            ),
          ],
          if (_working) ...[
            const SizedBox(height: 22),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  Future<void> _showImportOptions() async {
    final source = await showModalBottomSheet<_ImportSource>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const _ExchangeChoiceSheet<_ImportSource>(
        title: '选择导入来源',
        subtitle: '选择激活码、备份格式或原来的管理软件',
        note: '所有文件都会先检查和预览，确认后才会整批写入。',
        choices: [
          _ExchangeChoice(
            value: _ImportSource.lpa,
            icon: Icons.qr_code_scanner_rounded,
            title: '二维码 / LPA',
            subtitle: '使用相机扫描，或粘贴 LPA 激活码',
          ),
          _ExchangeChoice(
            value: _ImportSource.compatibleJson,
            icon: Icons.data_object_rounded,
            title: 'ieSIM / SimHub / SimJ JSON',
            subtitle: '自动识别兼容备份并在写入前预览',
          ),
          _ExchangeChoice(
            value: _ImportSource.nekoko,
            icon: Icons.storage_rounded,
            title: 'Nekoko 数据库',
            subtitle: '导入 EID、Profile、nickname 标签和缓存号码',
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    switch (source) {
      case _ImportSource.lpa:
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => const DataExchangePage(lpaOnly: true),
          ),
        );
      case _ImportSource.compatibleJson:
        await _import();
      case _ImportSource.nekoko:
        await _importNekoko();
    }
  }

  Future<void> _showExportOptions() async {
    final controller = AppScope.of(context);
    final assets = controller.assets;
    final hasFullBackup =
        controller.subscriptions.isNotEmpty ||
        controller.activities.isNotEmpty ||
        assets.devices.isNotEmpty ||
        assets.slots.isNotEmpty ||
        assets.cards.isNotEmpty ||
        assets.eids.isNotEmpty ||
        assets.profiles.isNotEmpty ||
        assets.events.isNotEmpty;
    final target = await showModalBottomSheet<_ExportTarget>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _ExchangeChoiceSheet<_ExportTarget>(
        title: '选择导出目标',
        subtitle: '完整备份适合迁移 ieSIM；兼容格式适合其他应用',
        note: '不导出 WebDAV 密码；完整备份可能包含 LPA 激活凭据，请妥善保管。',
        choices: [
          _ExchangeChoice(
            value: _ExportTarget.fullBackup,
            icon: Icons.inventory_2_outlined,
            title: 'ieSIM / SimHub v5 完整备份',
            subtitle: '包含设备、卡槽、卡片、EID、Profile 与动作记录',
            enabled: hasFullBackup,
          ),
          _ExchangeChoice(
            value: _ExportTarget.simj,
            icon: Icons.code_rounded,
            title: 'SimJ 兼容 JSON',
            subtitle: '只导出其他应用可读取的号码与套餐资料',
            enabled: controller.subscriptions.isNotEmpty,
          ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    await _export(fullBackup: target == _ExportTarget.fullBackup);
  }

  Future<void> _scanLpa() async {
    final source = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const LpaScannerPage()),
    );
    if (source != null && mounted) await _inspectLpa(source);
  }

  Future<void> _pasteLpa() async {
    final text = TextEditingController();
    final source = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('粘贴 LPA 激活码'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: TextField(
            controller: text,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              hintText: 'LPA:1\$SM-DP+地址\$Matching-ID',
              helperText: '激活码属于敏感凭据，导入后仅遮盖显示。',
              prefixIcon: Icon(Icons.sim_card_download_outlined),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null) text.text = data!.text!;
            },
            icon: const Icon(Icons.content_paste_rounded),
            label: const Text('从剪贴板粘贴'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, text.text),
            child: const Text('解析'),
          ),
        ],
      ),
    );
    text.dispose();
    if (source != null && mounted) await _inspectLpa(source);
  }

  Future<void> _inspectLpa(String source) async {
    final LpaActivation activation;
    try {
      activation = LpaActivation.parse(source);
    } on FormatException catch (error) {
      _showMessage(error.message);
      return;
    } on ArgumentError {
      _showMessage('SM-DP+ 地址或激活码格式无效。');
      return;
    }

    final duplicate = AppScope.of(context).subscriptions.where(
      (item) => item.activation?.hasSameDownloadKey(activation) ?? false,
    );
    if (duplicate.isNotEmpty) {
      _showMessage('这份 LPA 激活码已经导入。');
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              SubscriptionDetailPage(subscriptionId: duplicate.first.id),
        ),
      );
      return;
    }

    setState(() => _working = true);
    ProfileCatalogMatch? match;
    String? lookupError;
    try {
      match = await _profileCatalog.lookup(activation);
    } catch (_) {
      lookupError = '外部数据源暂时不可用，仍可继续导入并稍后补全。';
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (!mounted) return;

    final choice = await showModalBottomSheet<_LpaImportChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _LpaImportPreview(
        activation: activation,
        match: match,
        lookupError: lookupError,
      ),
    );
    if (choice == null || !mounted) return;

    final controller = AppScope.of(context);
    final now = DateTime.now().toUtc();
    final candidate = choice.candidate;
    final importedActivation = LpaActivation(
      smdpAddress: activation.smdpAddress,
      matchingId: activation.matchingId,
      extra: activation.extra,
      confirmationCode: choice.confirmationCode,
    );
    final subscription = Subscription(
      id: const Uuid().v4(),
      number: const PhoneNumber.unknown(),
      operator: candidate?.serviceProviderName,
      lifecycle: const ProfileLifecycle(stage: ProfileStage.pendingActivation),
      activation: importedActivation,
      plan: Plan(
        name: candidate?.profileNames.length == 1
            ? candidate!.profileNames.single
            : null,
      ),
      keepAlive: KeepAlive(
        required: true,
        confidence: DataConfidence.confirmed,
      ),
      tags: [
        'eSIM',
        'LPA导入',
        if (candidate != null && candidate.plmn.isNotEmpty)
          'PLMN:${candidate.plmn}',
      ],
      appearance: const Appearance(cardColorHex: '#2374AB'),
      timeZoneId: controller.defaultTimeZoneId,
      createdAt: now,
      updatedAt: now,
    );
    final error = await controller.saveSubscription(subscription);
    if (!mounted) return;
    if (error != null) {
      _showMessage(error);
      return;
    }
    _showMessage(
      candidate == null
          ? 'LPA 已导入，可在 Profile 详情中继续添加套餐或其他资料。'
          : 'LPA 已导入，并匹配到 ${candidate.serviceProviderName}。',
    );
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SubscriptionDetailPage(subscriptionId: subscription.id),
      ),
    );
  }

  Future<void> _import() async {
    setState(() => _working = true);
    try {
      const jsonType = XTypeGroup(
        label: 'JSON',
        extensions: ['json'],
        mimeTypes: ['application/json', 'text/json'],
      );
      final file = await openFile(acceptedTypeGroups: const [jsonType]);
      if (file == null || !mounted) return;
      final size = await file.length();
      if (size > 10 * 1024 * 1024) {
        _showMessage('文件超过 10 MB，请确认选择的是 Profile 备份文件。');
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final source = utf8.decode(bytes);
      final report = AppScope.of(context).inspectSimHub(source);
      final destination = await showModalBottomSheet<_ImportDestination>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _ImportPreview(report: report, fileName: file.name),
      );
      if (destination == null || !mounted) return;
      final importReport = destination == _ImportDestination.museum
          ? _simHubReportForMuseum(report)
          : report;
      final error = await AppScope.of(context).applySimHubImport(importReport);
      if (!mounted) return;
      _showMessage(
        error ??
            '已导入 ${report.importedCount} 个 Profile、${report.assets.devices.length} 台设备、'
                '${report.assets.cards.length} 张卡片和 ${report.activityRecords.length} 条动作记录。',
      );
    } on FormatException {
      _showMessage('文件不是有效的 UTF-8 文本。');
    } catch (error) {
      _showMessage('导入失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _importNekoko() async {
    setState(() => _working = true);
    try {
      const databaseType = XTypeGroup(
        label: 'Nekoko SQLite',
        extensions: ['db', 'sqlite', 'sqlite3'],
        mimeTypes: [
          'application/vnd.sqlite3',
          'application/x-sqlite3',
          'application/octet-stream',
        ],
      );
      final file = await openFile(acceptedTypeGroups: const [databaseType]);
      if (file == null || !mounted) return;
      final size = await file.length();
      if (size > 100 * 1024 * 1024) {
        _showMessage('数据库超过 100 MB，请确认选择的是 Nekoko 导出的数据库备份。');
        return;
      }
      if (!mounted) return;
      final result = AppScope.of(context).inspectNekokoDatabase(file.path);
      if (result case Err(failure: final failure)) {
        _showMessage(_failureText(failure));
        return;
      }
      final report = (result as Ok<NekokoImportReport>).value;
      final destination = await showModalBottomSheet<_ImportDestination>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) =>
            _NekokoImportPreview(report: report, fileName: file.name),
      );
      if (destination == null || !mounted) return;
      final importReport = destination == _ImportDestination.museum
          ? _nekokoReportForMuseum(report)
          : report;
      final error = await AppScope.of(context).applyNekokoImport(importReport);
      if (!mounted) return;
      if (error != null) {
        _showMessage(error);
        return;
      }
      _showMessage(
        '已转换为 ${report.subscriptions.length} 个 ieSIM Profile，'
        '并建立 ${report.assets.eids.length} 个新 EID；已返回首页，可直接编辑。',
      );
      Navigator.pop(context);
    } catch (error) {
      _showMessage('Nekoko 导入失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _failureText(Failure failure) => switch (failure) {
    StoreError(message: final message) ||
    AuthError(message: final message) ||
    NetworkError(message: final message) ||
    SchemaError(message: final message) => message,
    PreconditionFailed() => '数据文件已变化，请重新选择。',
  };

  SimHubImportReport _simHubReportForMuseum(SimHubImportReport report) {
    final now = DateTime.now().toUtc();
    return SimHubImportReport(
      subscriptions: [
        for (final item in report.subscriptions) _importedMuseumItem(item, now),
      ],
      activityRecords: report.activityRecords,
      issues: report.issues,
      sourceRecordCount: report.sourceRecordCount,
      assets: report.assets,
      ignoredServiceCount: report.ignoredServiceCount,
      ignoredBindingCount: report.ignoredBindingCount,
    );
  }

  NekokoImportReport _nekokoReportForMuseum(NekokoImportReport report) {
    final now = DateTime.now().toUtc();
    return NekokoImportReport(
      sourceProfileCount: report.sourceProfileCount,
      subscriptions: [
        for (final item in report.subscriptions) _importedMuseumItem(item, now),
      ],
      assets: report.assets,
      issues: report.issues,
    );
  }

  Subscription _importedMuseumItem(Subscription item, DateTime now) =>
      item.lifecycle.stage == ProfileStage.museum
      ? item
      : item.copyWith(
          lifecycle: item.lifecycle.archive(
            now,
            reason: ProfileArchiveReason.imported,
          ),
          updatedAt: now,
        );

  Future<void> _export({required bool fullBackup}) async {
    setState(() => _working = true);
    try {
      final now = DateTime.now();
      final date =
          '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final bytes = Uint8List.fromList(
        utf8.encode(
          fullBackup
              ? AppScope.of(context).exportSimHubV5()
              : AppScope.of(context).exportSimHub(),
        ),
      );
      final saved = await DocumentSaver.saveJson(
        fileName: fullBackup
            ? 'ieSIM-simhub-v5-$date.json'
            : 'ieSIM-simj-$date.json',
        bytes: bytes,
      );
      if (!mounted || !saved) return;
      _showMessage('备份已保存。');
    } catch (error) {
      _showMessage('导出失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

enum _ImportSource { lpa, compatibleJson, nekoko }

enum _ExportTarget { fullBackup, simj }

class _ExchangePortalCard extends StatelessWidget {
  const _ExchangePortalCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: scheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExchangeChoice<T> {
  const _ExchangeChoice({
    required this.value,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.enabled = true,
  });

  final T value;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
}

class _ExchangeChoiceSheet<T> extends StatelessWidget {
  const _ExchangeChoiceSheet({
    required this.title,
    required this.subtitle,
    required this.choices,
    this.note,
  });

  final String title;
  final String subtitle;
  final List<_ExchangeChoice<T>> choices;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.paddingOf(context).bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            for (final choice in choices)
              Card(
                margin: const EdgeInsets.only(bottom: 9),
                child: ListTile(
                  enabled: choice.enabled,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  leading: CircleAvatar(child: Icon(choice.icon)),
                  title: Text(choice.title),
                  subtitle: Text(choice.enabled ? choice.subtitle : '暂无可导出数据'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: choice.enabled
                      ? () => Navigator.pop(context, choice.value)
                      : null,
                ),
              ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 17,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        note!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SafetyPoint extends StatelessWidget {
  const _SafetyPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _LpaImportChoice {
  const _LpaImportChoice(this.candidate, this.confirmationCode);

  final ProfileCatalogEntry? candidate;
  final String? confirmationCode;
}

class _LpaImportPreview extends StatefulWidget {
  const _LpaImportPreview({
    required this.activation,
    required this.match,
    required this.lookupError,
  });

  final LpaActivation activation;
  final ProfileCatalogMatch? match;
  final String? lookupError;

  @override
  State<_LpaImportPreview> createState() => _LpaImportPreviewState();
}

class _LpaImportPreviewState extends State<_LpaImportPreview> {
  late final List<ProfileCatalogEntry> _options;
  late final TextEditingController _confirmation;
  ProfileCatalogEntry? _selected;

  @override
  void initState() {
    super.initState();
    _confirmation = TextEditingController(
      text: widget.activation.confirmationCode ?? '',
    );
    final byProvider = <String, ProfileCatalogEntry>{};
    for (final candidate in widget.match?.candidates ?? const []) {
      byProvider.putIfAbsent(candidate.serviceProviderName, () => candidate);
    }
    _options = byProvider.values.take(50).toList(growable: false);
    if (_options.length == 1) _selected = _options.single;
  }

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .72,
      minChildSize: .48,
      maxChildSize: .94,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LPA 导入预览',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 5),
                Text(
                  '请核对 SM-DP+ 和匹配结果，确认后才会写入本机。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                SectionCard(
                  title: '激活信息',
                  child: Column(
                    children: [
                      _LpaInfoRow(
                        label: 'SM-DP+',
                        value: widget.activation.smdpAddress,
                        icon: Icons.dns_outlined,
                      ),
                      const Divider(),
                      _LpaInfoRow(
                        label: 'Matching ID',
                        value: widget.activation.redactedMatchingId,
                        icon: Icons.key_outlined,
                      ),
                      if (widget.activation.confirmationCodeRequired) ...[
                        const Divider(),
                        TextField(
                          controller: _confirmation,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: '确认码（可选）',
                            helperText: '二维码要求独立确认码；没有时也可先保存凭据。',
                            prefixIcon: Icon(Icons.password_rounded),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: '外部数据匹配',
                  subtitle: ProfileCatalogService.sourceName,
                  child: widget.lookupError != null
                      ? _LookupNotice(
                          icon: Icons.cloud_off_outlined,
                          message: widget.lookupError!,
                        )
                      : _options.isEmpty
                      ? const _LookupNotice(
                          icon: Icons.manage_search_rounded,
                          message: '没有找到精确匹配。可先导入，再手动填写运营商和套餐。',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _options.length == 1
                                  ? '已找到唯一服务商：'
                                  : '同一 SM-DP+ 对应多个服务商，请选择正确的一项：',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ProfileCatalogService.sourceDescription,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 10),
                            for (final option in _options)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () =>
                                      setState(() => _selected = option),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    padding: const EdgeInsets.all(13),
                                    decoration: BoxDecoration(
                                      color: _selected == option
                                          ? scheme.primaryContainer
                                          : scheme.surfaceContainerLow,
                                      border: Border.all(
                                        color: _selected == option
                                            ? scheme.primary
                                            : scheme.outlineVariant,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          _selected == option
                                              ? Icons.check_circle_rounded
                                              : Icons
                                                    .radio_button_unchecked_rounded,
                                          color: _selected == option
                                              ? scheme.primary
                                              : scheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 11),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                option.serviceProviderName,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                              if (option.plmn.isNotEmpty)
                                                Text(
                                                  'PLMN ${option.plmn}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              if (option
                                                  .profileNames
                                                  .isNotEmpty)
                                                Text(
                                                  option.profileNames.join(
                                                    ' · ',
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              if (_profileSizeSummary(
                                                    widget.match?.candidates.where(
                                                          (candidate) =>
                                                              candidate
                                                                  .serviceProviderName ==
                                                              option
                                                                  .serviceProviderName,
                                                        ) ??
                                                        [option],
                                                    widget.match?.referenceEum,
                                                  )
                                                  case final size?)
                                                Text(
                                                  size,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: scheme.primary,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if ((widget.match?.providerNames.length ?? 0) > 50)
                              Text(
                                '候选过多，仅显示前 50 项；也可以不选择并在导入后手动填写。',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                _LookupNotice(
                  icon: Icons.privacy_tip_outlined,
                  message:
                      '匹配只下载公共目录，不会把 SM-DP+ 或激活码发送给数据源。激活码会随 SimHub JSON 备份导出，请妥善保管备份文件。',
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              MediaQuery.paddingOf(context).bottom + 14,
            ),
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
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _finish,
                    icon: const Icon(Icons.download_done_rounded),
                    label: Text(_selected == null ? '直接导入' : '按所选结果导入'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _finish() {
    final confirmation = _confirmation.text.trim();
    try {
      LpaActivation(
        smdpAddress: widget.activation.smdpAddress,
        matchingId: widget.activation.matchingId,
        extra: widget.activation.extra,
        confirmationCode: confirmation,
      );
    } on ArgumentError {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('确认码格式无效，不能包含空格或分隔符。')));
      return;
    }
    Navigator.pop(
      context,
      _LpaImportChoice(_selected, confirmation.isEmpty ? null : confirmation),
    );
  }
}

String? _profileSizeSummary(
  Iterable<ProfileCatalogEntry> entries,
  String? referenceEum,
) {
  final referenceSizes = entries
      .map((entry) => entry.sizeForEum(referenceEum))
      .whereType<int>()
      .toList(growable: false);
  if (referenceSizes.isEmpty) return null;
  final minimumReference = referenceSizes.reduce((a, b) => a < b ? a : b);
  final maximumReference = referenceSizes.reduce((a, b) => a > b ? a : b);
  final allSizes = entries
      .expand(
        (entry) => [
          if (entry.minimumSizeBytes != null) entry.minimumSizeBytes!,
          if (entry.maximumSizeBytes != null) entry.maximumSizeBytes!,
        ],
      )
      .toList(growable: false);
  final minimum = allSizes.reduce((a, b) => a < b ? a : b);
  final maximum = allSizes.reduce((a, b) => a > b ? a : b);
  final source = referenceEum == null ? '参考值' : '参考 EUM $referenceEum';
  final reference = minimumReference == maximumReference
      ? _formatProfileBytes(minimumReference)
      : '${_formatProfileBytes(minimumReference)}–'
            '${_formatProfileBytes(maximumReference)}';
  if (minimum == maximum) {
    return 'Profile 容量估算 · $source · $reference';
  }
  return 'Profile 容量估算 · $source $reference'
      ' · 各 EUM ${_formatProfileBytes(minimum)}–${_formatProfileBytes(maximum)}';
}

String _formatProfileBytes(int bytes) {
  final kib = bytes / 1024;
  return '$bytes B（${kib.toStringAsFixed(kib >= 100 ? 0 : 1)} KiB）';
}

class _LpaInfoRow extends StatelessWidget {
  const _LpaInfoRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

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

class _LookupNotice extends StatelessWidget {
  const _LookupNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ImportDestination { source, museum }

class _ImportPreview extends StatelessWidget {
  const _ImportPreview({required this.report, required this.fileName});

  final SimHubImportReport report;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .68,
      minChildSize: .42,
      maxChildSize: .92,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('导入预览', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _PreviewStat(
                        value: report.importedCount,
                        label: '可导入',
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _PreviewStat(
                        value: report.skippedCount,
                        label: '已跳过',
                        color: scheme.error,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _PreviewStat(
                        value: report.issues.length,
                        label: '提示',
                        color: const Color(0xFFC27A12),
                      ),
                    ),
                  ],
                ),
                if (report.assets.devices.isNotEmpty ||
                    report.assets.cards.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '同时识别 ${report.assets.devices.length} 台设备、'
                    '${report.assets.slots.length} 个卡槽、${report.assets.cards.length} 张卡片、'
                    '${report.assets.eids.length} 个 EID 和 ${report.assets.profiles.length} 个 Profile。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (report.ignoredServiceCount > 0 ||
                    report.ignoredBindingCount > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '备份还包含 ${report.ignoredServiceCount} 条外部服务器配置和 '
                    '${report.ignoredBindingCount} 条服务绑定；它们不属于 SIM/eSIM 资产，'
                    '可能包含账户与服务器信息，本次不导入。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: report.issues.isEmpty
                ? ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24),
                    children: const [
                      Icon(
                        Icons.verified_rounded,
                        size: 48,
                        color: Color(0xFF21805D),
                      ),
                      SizedBox(height: 12),
                      Text('全部记录已通过格式检查', textAlign: TextAlign.center),
                    ],
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: report.issues.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final issue = report.issues[index];
                      return Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${issue.recordIndex == null ? '文件' : '第 ${issue.recordIndex} 条'}'
                                ' · ${issue.field}\n${issue.message}',
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.paddingOf(context).bottom + 14,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: report.importedCount == 0
                            ? null
                            : () => Navigator.pop(
                                context,
                                _ImportDestination.museum,
                              ),
                        icon: const Icon(Icons.museum_outlined),
                        label: const Text('导入博物馆'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: report.importedCount == 0
                            ? null
                            : () => Navigator.pop(
                                context,
                                _ImportDestination.source,
                              ),
                        child: const Text('正常导入'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NekokoImportPreview extends StatelessWidget {
  const _NekokoImportPreview({required this.report, required this.fileName});

  final NekokoImportReport report;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .68,
      minChildSize: .42,
      maxChildSize: .9,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nekoko 导入预览',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '识别 ${report.sourceProfileCount} 条源记录；可写入 '
                  '${report.assets.profiles.length} 个 Profile、'
                  '${report.assets.cards.length} 张新 eUICC 卡、'
                  '${report.assets.eids.length} 个新 EID，'
                  '并新增或补全 ${report.subscriptions.length} 条订阅。',
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '导入时会转换为 ieSIM 原生 Profile：名称、运营商、标签、设备状态、'
                    'EID/ICCID、类别、GID 与容量资料会按本地模型保存。完成后返回首页，'
                    '可使用标准编辑器继续修改。',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: report.issues.isEmpty
                ? ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24),
                    children: const [
                      Icon(
                        Icons.verified_rounded,
                        size: 48,
                        color: Color(0xFF21805D),
                      ),
                      SizedBox(height: 12),
                      Text('全部可互操作资料已通过检查', textAlign: TextAlign.center),
                    ],
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: report.issues.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final issue = report.issues[index];
                      return ListTile(
                        tileColor: scheme.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: const Icon(Icons.info_outline_rounded),
                        title: Text(
                          issue.record == null ? '文件提示' : '第 ${issue.record} 条',
                        ),
                        subtitle: Text(issue.message),
                      );
                    },
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.paddingOf(context).bottom + 14,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            report.assets.profiles.isEmpty &&
                                report.subscriptions.isEmpty
                            ? null
                            : () => Navigator.pop(
                                context,
                                _ImportDestination.museum,
                              ),
                        icon: const Icon(Icons.museum_outlined),
                        label: const Text('导入博物馆'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed:
                            report.assets.profiles.isEmpty &&
                                report.subscriptions.isEmpty
                            ? null
                            : () => Navigator.pop(
                                context,
                                _ImportDestination.source,
                              ),
                        child: const Text('导入到首页'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewStat extends StatelessWidget {
  const _PreviewStat({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: color),
          ),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
