import 'dart:convert';
import 'dart:typed_data';

import 'package:iesim_core/iesim_core.dart';

import '../app/brand.dart';
import '../data/app_controller.dart';
import '../data/euicc_card_presets.dart';

/// 生成可安全附在问题报告中的脱敏运行摘要。
///
/// 报告只包含版本、功能状态和聚合数量，不包含号码、ICCID、EID、激活码、
/// WebDAV 地址、运营商名称、标签或记录 ID。
abstract final class DiagnosticReportService {
  static const formatVersion = 1;

  static Uint8List build(AppController controller, {DateTime? generatedAtUtc}) {
    final generatedAt = generatedAtUtc ?? DateTime.now().toUtc();
    if (!generatedAt.isUtc) {
      throw ArgumentError.value(generatedAt, 'generatedAtUtc', '必须是 UTC 时刻');
    }
    final subscriptions = controller.subscriptions;
    final assets = controller.assets;
    final stageCounts = {
      for (final stage in ProfileStage.values)
        stage.name: subscriptions
            .where((item) => item.lifecycle.stage == stage)
            .length,
    };
    final preset = controller.euiccCardPresetResult;
    final report = <String, Object?>{
      'formatVersion': formatVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'app': {
        'name': AppBrand.name,
        'version': AppBrand.version,
        'databaseSchemaVersion': iesimDatabaseSchemaVersion,
      },
      'health': {
        'ready': controller.ready,
        'busy': controller.busy,
        'hasLocalDataError': controller.errorMessage != null,
        'hasNotificationError': controller.notificationError != null,
        'hasWebhookError': controller.webhookLastError != null,
      },
      'records': {
        'profiles': subscriptions.length,
        'profileStages': stageCounts,
        'activities': controller.activities.length,
        'scheduledReminders': controller.scheduledReminderCount,
      },
      'assets': {
        'devices': assets.devices.length,
        'slots': assets.slots.length,
        'cards': assets.cards.length,
        'eids': assets.eids.length,
        'esimProfiles': assets.profiles.length,
        'unlinkedEsimProfiles': assets.profiles
            .where((item) => item.subscriptionId == null)
            .length,
        'events': assets.events.length,
      },
      'sync': {
        'webDavConfigured': controller.webDavConfiguration != null,
        'hasCompletedSync': controller.lastSyncReport != null,
        'conflictCount': controller.syncConflicts.length,
      },
      'notifications': {
        'enabled': controller.remindersEnabled,
        'permissionGranted': controller.notificationPermissionGranted,
        'webhookConfigured': controller.webhookConfiguration != null,
        'webhookEnabled': controller.webhookConfiguration?.enabled ?? false,
        'webhookProfileDetailsEnabled':
            controller.webhookConfiguration?.includeProfileDetails ?? false,
      },
      'euiccPresets': {
        'catalogVersion': preset.catalog.catalogVersion,
        'schemaVersion': EuiccCardPresetCatalog.schemaVersion,
        'source': preset.source.name,
        'loadedAt': preset.loadedAt.toUtc().toIso8601String(),
        'entryCount': preset.catalog.cards.length,
        'hasWarning': preset.warning != null,
      },
      'privacy': {
        'containsIdentifiers': false,
        'containsCredentials': false,
        'containsRemoteAddresses': false,
      },
    };
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(report)),
    );
  }
}
