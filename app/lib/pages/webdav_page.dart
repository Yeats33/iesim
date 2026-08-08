import 'package:flutter/material.dart';
import 'package:iesim_core/iesim_core.dart';
import 'package:intl/intl.dart';

import '../app/app_scope.dart';
import '../services/webdav_service.dart';
import '../widgets/section_card.dart';

class WebDavPage extends StatefulWidget {
  const WebDavPage({super.key});

  @override
  State<WebDavPage> createState() => _WebDavPageState();
}

class _WebDavPageState extends State<WebDavPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _initialized = false;
  bool _obscurePassword = true;
  bool _working = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final configuration = AppScope.of(context).webDavConfiguration;
    if (configuration != null) {
      _urlController.text = configuration.directoryUrl;
      _usernameController.text = configuration.username;
      _passwordController.text = configuration.password;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final configured = controller.webDavConfiguration != null;
    final scheme = Theme.of(context).colorScheme;
    final syncedAt = controller.syncState.lastSyncedAtUtc;
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 同步')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.paddingOf(context).bottom + 28,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  _SyncHero(
                    configured: configured,
                    syncedAt: syncedAt,
                    conflictCount: controller.syncConflicts.length,
                    onSync: _working || !configured ? null : _sync,
                  ),
                  const SizedBox(height: 18),
                  SectionCard(
                    title: configured ? '连接配置' : '连接你的 WebDAV',
                    subtitle: 'ieSIM 只读写该目录中的 iesim-v1.json',
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _urlController,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.url],
                            decoration: const InputDecoration(
                              labelText: 'WebDAV 目录地址',
                              hintText: 'https://dav.example.com/iesim/',
                              prefixIcon: Icon(Icons.link_rounded),
                            ),
                            validator: _validateUrl,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _usernameController,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            decoration: const InputDecoration(
                              labelText: '用户名',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: _required,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: '密码或应用专用密码',
                              prefixIcon: const Icon(Icons.key_rounded),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: _required,
                            onFieldSubmitted: (_) =>
                                _working ? null : _testAndSave(),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _working ? null : _testOnly,
                                  icon: const Icon(
                                    Icons.wifi_tethering_rounded,
                                  ),
                                  label: const Text('测试连接'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _working ? null : _testAndSave,
                                  icon: _working
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.cloud_done_outlined),
                                  label: Text(configured ? '验证并保存' : '连接并同步'),
                                ),
                              ),
                            ],
                          ),
                          if (configured) ...[
                            const SizedBox(height: 10),
                            TextButton.icon(
                              onPressed: _working ? null : _disconnect,
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.error,
                              ),
                              icon: const Icon(Icons.link_off_rounded),
                              label: const Text('移除此设备上的 WebDAV 配置'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: '同步安全',
                    child: const Column(
                      children: [
                        InfoRow(
                          label: '防覆盖',
                          value: 'ETag 乐观锁，冲突自动重试 3 次',
                          icon: Icons.shield_outlined,
                        ),
                        InfoRow(
                          label: '合并方式',
                          value: '按记录比较修改时间',
                          icon: Icons.merge_type_rounded,
                        ),
                        InfoRow(
                          label: '删除保护',
                          value: '墓碑保留 90 天',
                          icon: Icons.delete_sweep_outlined,
                        ),
                        InfoRow(
                          label: '凭据',
                          value: '密码由 Android 安全存储加密',
                          icon: Icons.password_rounded,
                        ),
                      ],
                    ),
                  ),
                  if (controller.syncConflicts.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _ConflictCard(conflicts: controller.syncConflicts),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  WebDavConfiguration? _configuration() {
    if (!_formKey.currentState!.validate()) return null;
    return WebDavConfiguration(
      directoryUrl: _urlController.text,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
  }

  Future<void> _testOnly() async {
    final configuration = _configuration();
    if (configuration == null) return;
    setState(() => _working = true);
    final error = await AppScope.of(context).testWebDav(configuration);
    if (!mounted) return;
    setState(() => _working = false);
    _show(error ?? '连接成功，目录可用', error: error != null);
  }

  Future<void> _testAndSave() async {
    final configuration = _configuration();
    if (configuration == null) return;
    setState(() => _working = true);
    final controller = AppScope.of(context);
    var error = await controller.testWebDav(configuration);
    error ??= await controller.saveWebDavConfiguration(configuration);
    error ??= await controller.syncWebDav();
    if (!mounted) return;
    setState(() => _working = false);
    _show(error ?? '连接成功，数据已安全同步', error: error != null);
  }

  Future<void> _sync() async {
    setState(() => _working = true);
    final error = await AppScope.of(context).syncWebDav();
    if (!mounted) return;
    setState(() => _working = false);
    _show(error ?? '同步完成', error: error != null);
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除 WebDAV 配置？'),
        content: const Text('只会移除本机保存的地址和凭据，不会删除远端快照或本地订阅。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await AppScope.of(context).disconnectWebDav();
    if (!mounted) return;
    if (error == null) {
      _urlController.clear();
      _usernameController.clear();
      _passwordController.clear();
    }
    _show(error ?? '配置已从本机移除', error: error != null);
  }

  void _show(String message, {required bool error}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '此项不能为空' : null;

  static String? _validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) return '请输入 WebDAV 目录地址';
    try {
      final configuration = WebDavConfiguration(
        directoryUrl: value,
        username: '',
        password: '',
      );
      configuration.directoryUri;
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }
}

class _SyncHero extends StatelessWidget {
  const _SyncHero({
    required this.configured,
    required this.syncedAt,
    required this.conflictCount,
    required this.onSync,
  });

  final bool configured;
  final DateTime? syncedAt;
  final int conflictCount;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = syncedAt == null
        ? (configured ? '尚未完成首次同步' : '连接后，数据仍由你自己的网盘保管')
        : '上次同步 ${DateFormat('MM月dd日 HH:mm').format(syncedAt!.toLocal())}';
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: configured
              ? [scheme.primary, const Color(0xFF174B59)]
              : [scheme.surfaceContainerHighest, scheme.surfaceContainer],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Icon(
            configured ? Icons.cloud_done_rounded : Icons.cloud_off_outlined,
            size: 38,
            color: configured ? Colors.white : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  configured ? 'WebDAV 已连接' : 'WebDAV 未配置',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: configured ? Colors.white : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  conflictCount > 0
                      ? '$subtitle · $conflictCount 条合并记录'
                      : subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: configured
                        ? Colors.white.withValues(alpha: .76)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (configured)
            IconButton.filledTonal(
              tooltip: '立即同步',
              onPressed: onSync,
              icon: const Icon(Icons.sync_rounded),
            ),
        ],
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.conflicts});

  final List<SyncConflictLog> conflicts;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '合并记录',
      subtitle: '同一条数据在两台设备上都修改过时，ieSIM 会诚实记录裁决结果',
      child: Column(
        children: [
          for (final (index, entry) in conflicts.take(10).indexed) ...[
            if (index > 0) const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.call_merge_rounded),
              title: Text(
                '${_entityLabel(entry.conflict.entityType)} ${entry.conflict.entityId}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${DateFormat('MM月dd日 HH:mm').format(entry.recordedAtUtc.toLocal())} · ${_winner(entry.conflict.winner)}',
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _winner(SyncWinner winner) => switch (winner) {
    SyncWinner.local => '保留本机较新版本',
    SyncWinner.remote => '保留远端较新版本',
    SyncWinner.deletion => '保留删除结果',
  };

  static String _entityLabel(SyncEntityType type) => switch (type) {
    SyncEntityType.subscription => '订阅',
    SyncEntityType.activityRecord => '动作记录',
    SyncEntityType.device => '设备',
    SyncEntityType.slot => '卡槽',
    SyncEntityType.card => '卡片',
    SyncEntityType.eid => 'EID',
    SyncEntityType.profile => 'Profile',
    SyncEntityType.assetEvent => '资产事件',
  };
}
