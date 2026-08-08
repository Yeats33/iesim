import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_scope.dart';
import '../app/brand.dart';
import '../app/theme.dart';
import '../widgets/app_logo.dart';
import 'data_exchange_page.dart';
import 'affiliate_management_page.dart';
import 'developer_mode_page.dart';
import 'nekoko_tags_page.dart';
import 'notification_settings_page.dart';
import 'profile_lifecycle_settings_page.dart';
import 'webdav_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            20,
            16,
            MediaQuery.paddingOf(context).bottom + 106,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('设置', style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: 6),
                    Text(
                      '管理外观、数据交换、设备资产与同步。',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _DataOverview(
                      subscriptions: controller.subscriptions.length,
                      activities: controller.activities.length,
                      devices: controller.assets.devices.length,
                      cards: controller.assets.cards.length,
                    ),
                    const SizedBox(height: 22),
                    _SettingsSection(
                      title: '外观',
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment(
                                value: ThemeMode.system,
                                label: Text('跟随系统'),
                                icon: Icon(Icons.brightness_auto_rounded),
                              ),
                              ButtonSegment(
                                value: ThemeMode.light,
                                label: Text('浅色'),
                                icon: Icon(Icons.light_mode_outlined),
                              ),
                              ButtonSegment(
                                value: ThemeMode.dark,
                                label: Text('深色'),
                                icon: Icon(Icons.dark_mode_outlined),
                              ),
                            ],
                            selected: {themeMode},
                            showSelectedIcon: false,
                            onSelectionChanged: (values) =>
                                onThemeModeChanged(values.first),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SettingsSection(
                      title: '数据与互操作',
                      children: [
                        _SettingsTile(
                          icon: Icons.swap_horiz_rounded,
                          title: '导入与导出',
                          subtitle: '二维码、SimHub、SimJ 与 Nekoko 数据',
                          onTap: () => _open(context, const DataExchangePage()),
                        ),
                        const Divider(indent: 62),
                        _SettingsTile(
                          icon: Icons.label_outline_rounded,
                          title: 'Nekoko 标签工具',
                          subtitle: '按 ICCID 双向转换 Profile 标签',
                          onTap: () => _open(context, const NekokoTagsPage()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SettingsSection(
                      title: '同步与提醒',
                      children: [
                        _SettingsTile(
                          icon: Icons.cloud_sync_outlined,
                          title: 'WebDAV 同步',
                          subtitle: '数据保存在你自己的网盘',
                          badge: controller.webDavConfiguration == null
                              ? '未配置'
                              : '已连接',
                          onTap: () => _open(context, const WebDavPage()),
                        ),
                        const Divider(indent: 62),
                        _SettingsTile(
                          icon: Icons.notifications_outlined,
                          title: '本地通知',
                          subtitle: '在截止前预排程提醒，不依赖后台轮询',
                          badge:
                              controller.remindersEnabled &&
                                  controller.notificationPermissionGranted
                              ? '已开启'
                              : '需开启',
                          onTap: () =>
                              _open(context, const NotificationSettingsPage()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SettingsSection(
                      title: 'Profile 管理',
                      children: [
                        _SettingsTile(
                          icon: Icons.handshake_outlined,
                          title: '优惠与推荐',
                          subtitle: 'AFF 披露、优惠码与实体 eSIM 卡推荐',
                          onTap: () =>
                              _open(context, const AffiliateManagementPage()),
                        ),
                        const Divider(indent: 62),
                        _SettingsTile(
                          icon: Icons.inventory_2_outlined,
                          title: '过期博物馆',
                          subtitle: _museumSettingLabel(
                            controller.museumAutoArchiveDays,
                          ),
                          onTap: () => _open(
                            context,
                            const ProfileLifecycleSettingsPage(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SettingsSection(
                      title: '高级',
                      children: [
                        _SettingsTile(
                          icon: Icons.developer_mode_rounded,
                          title: '开发者模式',
                          subtitle: '需密码；清空或生成测试数据',
                          onTap: () => DeveloperModePage.open(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SettingsSection(
                      title: '关于',
                      children: [
                        _SettingsTile(
                          icon: Icons.privacy_tip_outlined,
                          title: '隐私设计',
                          subtitle: '无账号、无自建云，本地优先',
                          onTap: () => showAboutDialog(
                            context: context,
                            applicationName: AppBrand.name,
                            applicationVersion: AppBrand.version,
                            applicationIcon: const AppLogo(size: 48),
                            children: const [
                              Text(
                                '${AppBrand.name} 将订阅资料保存在设备本地；启用 WebDAV 后，数据只会同步到用户指定的服务。',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SettingsSection(
                      title: '联系作者',
                      children: [
                        _SettingsTile(
                          icon: Icons.code_rounded,
                          title: 'GitHub · ${AppAuthor.githubName}',
                          subtitle: 'github.com/${AppAuthor.githubName}',
                          onTap: () => _openExternal(
                            context,
                            AppAuthor.githubUrl,
                            destination: 'GitHub',
                          ),
                        ),
                        const Divider(indent: 62),
                        _SettingsTile(
                          icon: Icons.send_outlined,
                          title: 'Telegram · ${AppAuthor.telegramName}',
                          subtitle: AppAuthor.telegramPhone,
                          onTap: () => _openExternal(
                            context,
                            AppAuthor.telegramUrl,
                            destination: 'Telegram',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SettingsSection(
                      title: '支持开发',
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                          child: Text(
                            '如果 ieSIM 对你有帮助，可以向以下地址捐赠。请在转账前确认网络和地址完全一致。',
                          ),
                        ),
                        _DonationAddressTile(
                          network: 'EVM',
                          detail: 'Ethereum 及兼容 EVM 网络',
                          address: AppAuthor.evmAddress,
                          icon: Icons.token_outlined,
                        ),
                        const Divider(indent: 62),
                        _DonationAddressTile(
                          network: 'Solana',
                          address: AppAuthor.solanaAddress,
                          icon: Icons.blur_on_rounded,
                        ),
                        const Divider(indent: 62),
                        _DonationAddressTile(
                          network: 'Bitcoin',
                          address: AppAuthor.bitcoinAddress,
                          icon: Icons.currency_bitcoin_rounded,
                        ),
                        const Divider(indent: 62),
                        _DonationAddressTile(
                          network: 'TRON',
                          address: AppAuthor.tronAddress,
                          icon: Icons.change_history_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'ieSIM · Android v${AppBrand.version}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  }

  static Future<void> _openExternal(
    BuildContext context,
    String source, {
    required String destination,
  }) async {
    final uri = Uri.parse(source);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('无法打开 $destination，请检查系统浏览器')));
  }

  static String _museumSettingLabel(int? days) => switch (days) {
    null => '只手动归档，永不自动移动',
    0 => 'Profile 服务到期后立即归档',
    365 => 'Profile 服务到期 1 年后自动归档',
    _ => 'Profile 服务到期 $days 天后自动归档',
  };
}

class _DonationAddressTile extends StatelessWidget {
  const _DonationAddressTile({
    required this.network,
    required this.address,
    required this.icon,
    this.detail,
  });

  final String network;
  final String? detail;
  final String address;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: scheme.secondary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  network,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                SelectableText(
                  address,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '复制 $network 地址',
            onPressed: () => _copyAddress(context),
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _copyAddress(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制 $network 地址')));
  }
}

class _DataOverview extends StatelessWidget {
  const _DataOverview({
    required this.subscriptions,
    required this.activities,
    required this.devices,
    required this.cards,
  });

  final int subscriptions;
  final int activities;
  final int devices;
  final int cards;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.teal, AppColors.tealDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      child: Row(
        children: [
          const AppLogo(size: 52),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${AppBrand.name} 数据属于你',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  '$subscriptions 条订阅 · $devices 台设备 · $cards 张卡片\n'
                  '$activities 条续存动作记录',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: .76),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.lock_outline_rounded,
            color: Colors.white.withValues(alpha: .8),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Card(child: Column(children: children)),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: scheme.primary, size: 21),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: badge == null
          ? Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant)
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badge!,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
      onTap: onTap,
    );
  }
}
