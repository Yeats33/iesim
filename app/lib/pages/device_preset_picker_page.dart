import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';

import '../services/device_preset_service.dart';

class DevicePresetPickerPage extends StatefulWidget {
  const DevicePresetPickerPage({super.key, this.service});

  final DevicePresetService? service;

  @override
  State<DevicePresetPickerPage> createState() => _DevicePresetPickerPageState();
}

class _DevicePresetPickerPageState extends State<DevicePresetPickerPage> {
  late final DevicePresetService _service;
  final _search = TextEditingController();
  DevicePresetLoadResult? _result;
  Object? _error;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? DevicePresetService();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择设备型号'),
        actions: [
          IconButton(
            tooltip: '刷新型号库',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: switch ((_loading, _result, _error)) {
        (true, _, _) => const Center(child: CircularProgressIndicator()),
        (false, null, final error?) => _LoadError(
          message: _readableError(error),
          onRetry: _load,
        ),
        (false, final result?, _) => _catalogBody(result),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _catalogBody(DevicePresetLoadResult result) {
    final devices = result.catalog.search(_query);
    final cached = result.source == DevicePresetSource.cache;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _search,
            autofocus: true,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: '搜索品牌、型号、地区版或代号',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空',
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                cached
                    ? Icons.offline_bolt_outlined
                    : Icons.cloud_done_outlined,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${cached ? '离线缓存' : '已在线更新'} · '
                  '${result.catalog.catalogVersion} · '
                  '${result.catalog.devices.length} 个型号',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        if (result.warning case final warning?)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Text(
              warning,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
        Expanded(
          child: devices.isEmpty
              ? const Center(child: Text('没有匹配的型号'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  itemCount: devices.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final preset = devices[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Icon(_deviceIcon(preset.kind), size: 20),
                      ),
                      title: Text('${preset.brand} ${preset.displayName}'),
                      subtitle: Text(
                        [
                          ?preset.region,
                          _capabilityLabel(preset.simCapability),
                          if (preset.slots.isNotEmpty)
                            '${preset.slots.length} 个卡槽',
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(context, preset),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text(
              '预设用于快速填写，请以设备的实际地区版本和卡槽为准。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.load();
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 46,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 14),
            const Text('暂时无法读取型号库'),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回手动填写'),
            ),
          ],
        ),
      ),
    );
  }
}

String _readableError(Object error) => error
    .toString()
    .replaceFirst('FormatException: ', '')
    .replaceFirst('HttpException: ', '');

String _capabilityLabel(SimCapability value) => switch (value) {
  SimCapability.physicalOnly => '单实体 SIM',
  SimCapability.esimOnly => '仅 eSIM',
  SimCapability.physicalPlusEsim => '实体 SIM + eSIM',
  SimCapability.dualPhysical => '双实体 SIM',
  SimCapability.multiEsim => '多 eSIM Profile',
  SimCapability.unknown => '卡槽信息待确认',
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
