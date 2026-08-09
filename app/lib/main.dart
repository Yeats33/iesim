import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app_scope.dart';
import 'app/brand.dart';
import 'app/theme.dart';
import 'data/app_controller.dart';
import 'data/app_preferences.dart';
import 'pages/home_shell.dart';
import 'pages/subscription_detail_page.dart';
import 'platform/device_timezone.dart';
import 'services/euicc_card_preset_service.dart';
import 'services/reminder_notifications.dart';
import 'widgets/app_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final directory = await getApplicationSupportDirectory();
    final preferences = await AppPreferences.load();
    final controller = AppController.open(
      p.join(directory.path, 'iesim.db'),
      reminderNotifications: LocalReminderNotifications(),
      remindersEnabled: preferences.remindersEnabled,
      persistRemindersEnabled: preferences.setRemindersEnabled,
      museumAutoArchiveDays: preferences.museumAutoArchiveDays,
      persistMuseumAutoArchiveDays: preferences.setMuseumAutoArchiveDays,
      showNekokoTags: preferences.showNekokoTags,
      persistShowNekokoTags: preferences.setShowNekokoTags,
      euiccCardPresetService: EuiccCardPresetService(),
      enableWebDav: true,
    );
    await controller.initialize(
      defaultTimeZoneId: await DeviceTimeZone.identifier,
    );
    runApp(IesimApp(controller: controller, preferences: preferences));
  } catch (error) {
    runApp(_BootFailureApp(message: error.toString()));
  }
}

class IesimApp extends StatefulWidget {
  const IesimApp({super.key, required this.controller, this.preferences});

  final AppController controller;
  final AppPreferences? preferences;

  @override
  State<IesimApp> createState() => _IesimAppState();
}

class _IesimAppState extends State<IesimApp> {
  late ThemeMode _themeMode = widget.preferences?.themeMode ?? ThemeMode.system;
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _notificationSelection;

  @override
  void initState() {
    super.initState();
    _notificationSelection = widget.controller.notificationSelections.listen(
      _openSubscription,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final id = await widget.controller.initialNotificationSubscriptionId();
      if (id != null) _openSubscription(id);
    });
  }

  @override
  void dispose() {
    _notificationSelection?.cancel();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: AppBrand.name,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _themeMode,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: HomeShell(
          themeMode: _themeMode,
          onThemeModeChanged: (mode) {
            setState(() => _themeMode = mode);
            widget.preferences?.setThemeMode(mode);
          },
        ),
      ),
    );
  }

  void _openSubscription(String id) {
    if (!mounted || widget.controller.subscriptionById(id) == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => SubscriptionDetailPage(subscriptionId: id),
        ),
      );
    });
  }
}

class _BootFailureApp extends StatelessWidget {
  const _BootFailureApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppLogo(size: 64),
                    const SizedBox(height: 24),
                    Text(
                      '${AppBrand.name} 暂时无法启动',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '请重新打开应用；如果问题持续，请保留下面的错误信息。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        message,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
