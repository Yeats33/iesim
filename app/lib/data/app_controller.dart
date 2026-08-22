import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:iesim_core/iesim_core.dart';
import 'package:uuid/uuid.dart';

import 'euicc_card_presets.dart';
import '../services/reminder_notifications.dart';
import '../services/credential_vault.dart';
import '../services/euicc_card_preset_service.dart';
import '../services/home_action_center.dart';
import '../services/webdav_service.dart';
import '../services/webhook_notifications.dart';
import '../util/formatters.dart';

/// 应用层状态：只编排仓库与页面，不复制 core 中的日期和保号规则。
class AppController extends ChangeNotifier {
  AppController._({
    required SubscriptionRepository subscriptions,
    required ActivityRecordRepository activities,
    required AssetRepository assets,
    required this._importStore,
    required this._activityService,
    required this._reminderNotifications,
    required this._persistRemindersEnabled,
    required this._remindersEnabled,
    required this._persistMuseumAutoArchiveDays,
    required this._museumAutoArchiveDays,
    required this._persistShowNekokoTags,
    required this._showNekokoTags,
    required this._deletionService,
    required this._subscriptionReminderService,
    required this._credentialVault,
    required this._euiccCardPresetService,
    required this._webDav,
    required this._webhookNotifications,
    required this._closeStore,
  }) : _subscriptionRepository = subscriptions,
       _activityRepository = activities,
       _assetRepository = assets;

  factory AppController.open(
    String databasePath, {
    ReminderNotificationGateway reminderNotifications =
        const NoopReminderNotifications(),
    bool remindersEnabled = true,
    Future<void> Function(bool value)? persistRemindersEnabled,
    int? museumAutoArchiveDays = 90,
    Future<void> Function(int? value)? persistMuseumAutoArchiveDays,
    bool showNekokoTags = false,
    Future<void> Function(bool value)? persistShowNekokoTags,
    WebDavGateway? webDavGateway,
    ActivationCredentialVault? credentialVault,
    EuiccCardPresetService? euiccCardPresetService,
    WebhookNotificationGateway webhookNotifications =
        const NoopWebhookNotificationGateway(),
    bool enableWebDav = false,
  }) {
    final database = openIesimStore(databasePath);
    final vault =
        credentialVault ??
        (databasePath == ':memory:'
            ? MemoryActivationCredentialVault()
            : const SecureActivationCredentialVault());
    return AppController._(
      subscriptions: SubscriptionRepository(database),
      activities: ActivityRecordRepository(database),
      assets: AssetRepository(database),
      importStore: SimHubImportStore(database),
      activityService: ActivityService(database),
      reminderNotifications: reminderNotifications,
      remindersEnabled: remindersEnabled,
      persistRemindersEnabled: persistRemindersEnabled ?? (_) async {},
      museumAutoArchiveDays: museumAutoArchiveDays,
      persistMuseumAutoArchiveDays:
          persistMuseumAutoArchiveDays ?? (_) async {},
      showNekokoTags: showNekokoTags,
      persistShowNekokoTags: persistShowNekokoTags ?? (_) async {},
      deletionService: SubscriptionDeletionService(database),
      subscriptionReminderService: SubscriptionReminderService(database),
      credentialVault: vault,
      euiccCardPresetService: euiccCardPresetService,
      webDav:
          webDavGateway ??
          (enableWebDav
              ? AppWebDavService(SyncStore(database), vault)
              : const NoopWebDavGateway()),
      webhookNotifications: webhookNotifications,
      closeStore: database.close,
    );
  }

  @visibleForTesting
  factory AppController.inMemory({
    ReminderNotificationGateway reminderNotifications =
        const NoopReminderNotifications(),
    bool remindersEnabled = true,
    Future<void> Function(bool value)? persistRemindersEnabled,
    int? museumAutoArchiveDays = 90,
    Future<void> Function(int? value)? persistMuseumAutoArchiveDays,
    bool showNekokoTags = false,
    Future<void> Function(bool value)? persistShowNekokoTags,
    WebDavGateway? webDavGateway,
    ActivationCredentialVault? credentialVault,
    EuiccCardPresetService? euiccCardPresetService,
    WebhookNotificationGateway? webhookNotifications,
  }) => AppController.open(
    ':memory:',
    reminderNotifications: reminderNotifications,
    remindersEnabled: remindersEnabled,
    persistRemindersEnabled: persistRemindersEnabled,
    museumAutoArchiveDays: museumAutoArchiveDays,
    persistMuseumAutoArchiveDays: persistMuseumAutoArchiveDays,
    showNekokoTags: showNekokoTags,
    persistShowNekokoTags: persistShowNekokoTags,
    webDavGateway: webDavGateway,
    credentialVault: credentialVault,
    euiccCardPresetService: euiccCardPresetService,
    webhookNotifications:
        webhookNotifications ?? MemoryWebhookNotificationGateway(),
  );

  final SubscriptionRepository _subscriptionRepository;
  final ActivityRecordRepository _activityRepository;
  final AssetRepository _assetRepository;
  final SimHubImportStore _importStore;
  final ActivityService _activityService;
  final ReminderNotificationGateway _reminderNotifications;
  final Future<void> Function(bool value) _persistRemindersEnabled;
  final Future<void> Function(int? value) _persistMuseumAutoArchiveDays;
  final Future<void> Function(bool value) _persistShowNekokoTags;
  final SubscriptionDeletionService _deletionService;
  final SubscriptionReminderService _subscriptionReminderService;
  final ActivationCredentialVault _credentialVault;
  final EuiccCardPresetService? _euiccCardPresetService;
  final WebDavGateway _webDav;
  final WebhookNotificationGateway _webhookNotifications;
  final VoidCallback _closeStore;
  final Uuid _uuid = const Uuid();
  final KeepAliveEvaluator _evaluator = const KeepAliveEvaluator(
    clock: SystemClock(),
  );
  final KeepAliveRuleEngine _keepAliveRuleEngine = const KeepAliveRuleEngine(
    clock: SystemClock(),
  );
  final HomeActionCenter _homeActionCenter = const HomeActionCenter(
    clock: SystemClock(),
  );

  List<Subscription> _subscriptions = const [];
  List<ActivityRecord> _activities = const [];
  AssetInventory _assets = AssetInventory();
  UnmodifiableListView<Subscription> _subscriptionsView = UnmodifiableListView(
    const <Subscription>[],
  );
  UnmodifiableListView<ActivityRecord> _activitiesView = UnmodifiableListView(
    const <ActivityRecord>[],
  );
  Map<String, Subscription> _subscriptionsById = const {};
  Map<String, List<ActivityRecord>> _activitiesBySubscriptionId = const {};
  Map<String, EsimProfile> _assetProfilesBySubscriptionId = const {};
  Map<String, EsimProfile> _unlinkedAssetProfilesByIccid = const {};
  List<HomeActionItem> _homeActions = const [];
  int _scheduledReminderCount = 0;
  int _timeSensitiveDerivedBucket = -1;
  bool _ready = false;
  bool _busy = false;
  String? _errorMessage;
  String _defaultTimeZoneId = 'UTC';
  bool _remindersEnabled;
  int? _museumAutoArchiveDays;
  bool _showNekokoTags;
  bool _notificationPermissionGranted = false;
  String? _notificationError;
  WebhookConfiguration? _webhookConfiguration;
  DateTime? _webhookLastSentAtUtc;
  String? _webhookLastError;
  int _webhookInFlightCount = 0;
  bool _disposed = false;
  WebDavConfiguration? _webDavConfiguration;
  SyncRunReport? _lastSyncReport;
  List<SyncConflictLog> _syncConflicts = const [];
  SyncState _syncState = const SyncState();
  EuiccCardPresetLoadResult _euiccCardPresetResult = EuiccCardPresetLoadResult(
    catalog: builtInEuiccCardPresetCatalog,
    source: EuiccCardPresetSource.builtIn,
    loadedAt: builtInEuiccCardPresetCatalog.updatedAt,
  );

  bool get ready => _ready;
  bool get busy => _busy;
  String? get errorMessage => _errorMessage;
  String get defaultTimeZoneId => _defaultTimeZoneId;
  bool get remindersEnabled => _remindersEnabled;
  int? get museumAutoArchiveDays => _museumAutoArchiveDays;
  bool get showNekokoTags => _showNekokoTags;
  bool get notificationPermissionGranted => _notificationPermissionGranted;
  String? get notificationError => _notificationError;
  WebhookConfiguration? get webhookConfiguration => _webhookConfiguration;
  DateTime? get webhookLastSentAtUtc => _webhookLastSentAtUtc;
  String? get webhookLastError => _webhookLastError;
  bool get webhookSending => _webhookInFlightCount > 0;
  Stream<String> get notificationSelections =>
      _reminderNotifications.selectedSubscriptionIds;
  WebDavConfiguration? get webDavConfiguration => _webDavConfiguration;
  SyncRunReport? get lastSyncReport => _lastSyncReport;
  UnmodifiableListView<SyncConflictLog> get syncConflicts =>
      UnmodifiableListView(_syncConflicts);
  SyncState get syncState => _syncState;
  EuiccCardPresetLoadResult get euiccCardPresetResult => _euiccCardPresetResult;
  int get scheduledReminderCount {
    _refreshTimeSensitiveDerivedStateIfNeeded();
    return _scheduledReminderCount;
  }

  UnmodifiableListView<Subscription> get subscriptions => _subscriptionsView;
  UnmodifiableListView<ActivityRecord> get activities => _activitiesView;
  AssetInventory get assets => _assets;
  List<HomeActionItem> get homeActions {
    _refreshTimeSensitiveDerivedStateIfNeeded();
    return _homeActions;
  }

  Future<void> initialize({required String defaultTimeZoneId}) async {
    _defaultTimeZoneId = defaultTimeZoneId;
    initializeIesimTimeZones();
    var remindersReady = false;
    try {
      await _reminderNotifications.initialize();
      remindersReady = true;
    } catch (error) {
      _notificationError = '通知服务初始化失败：$error';
    }
    try {
      _webDavConfiguration = await _webDav.loadConfiguration();
    } catch (error) {
      _errorMessage = 'WebDAV 凭据读取失败：$error';
    }
    try {
      _webhookConfiguration = await _webhookNotifications.loadConfiguration();
    } catch (error) {
      _webhookLastError = 'Webhook 配置读取失败：$error';
    }
    final euiccService = _euiccCardPresetService;
    if (euiccService != null) {
      try {
        _euiccCardPresetResult = await euiccService.loadCachedOrBuiltIn();
      } catch (error) {
        _errorMessage = 'eUICC 型号缓存读取失败：$error';
      }
      unawaited(refreshEuiccCardPresets());
    }
    _loadSyncConflicts();
    _loadSyncState();
    await reload();
    if (remindersReady) {
      await refreshNotificationPermission(reschedule: true);
    }
    _ready = true;
    notifyListeners();
  }

  KeepAliveStatus statusOf(Subscription subscription) =>
      _evaluator.evaluate(subscription.keepAlive, subscription.timeZoneId);

  KeepAliveEvaluation keepAliveEvaluationOf(Subscription subscription) =>
      _keepAliveRuleEngine.evaluate(
        subscription,
        activities: activitiesFor(subscription.id),
      );

  List<ActivityRecord> activitiesFor(String subscriptionId) =>
      _activitiesBySubscriptionId[subscriptionId] ?? const [];

  Subscription? subscriptionById(String id) => _subscriptionsById[id];

  EsimProfile? assetProfileForSubscription(Subscription subscription) {
    final linked = _assetProfilesBySubscriptionId[subscription.id];
    if (linked != null) return linked;
    final iccid = subscription.iccid;
    if (iccid == null) return null;
    return _unlinkedAssetProfilesByIccid[iccid];
  }

  Future<void> reload() async {
    _errorMessage = null;
    final archiveResult = _archiveExpiredProfiles(DateTime.now().toUtc());
    var automaticallyArchived = 0;
    if (archiveResult case Err(failure: final failure)) {
      _errorMessage = _failureMessage(failure);
    } else if (archiveResult case Ok(value: final count)) {
      automaticallyArchived = count;
    }
    final subscriptionsResult = _subscriptionRepository.listAll();
    final activitiesResult = _activityRepository.listAll();
    final assetsResult = _assetRepository.load();
    switch ((subscriptionsResult, activitiesResult, assetsResult)) {
      case (
        Ok(value: final subscriptions),
        Ok(value: final activities),
        Ok(value: final assets),
      ):
        try {
          _subscriptions = await _hydrateCredentials(subscriptions);
        } catch (error) {
          _subscriptions = subscriptions;
          _errorMessage = '本机凭据保险库读取失败：$error';
        }
        _activities = activities.reversed.toList(growable: false);
        _assets = assets;
        _rebuildDerivedState();
      case (Err(failure: final failure), _, _):
        _errorMessage = _failureMessage(failure);
      case (_, Err(failure: final failure), _):
        _errorMessage = _failureMessage(failure);
      case (_, _, Err(failure: final failure)):
        _errorMessage = _failureMessage(failure);
    }
    if (automaticallyArchived > 0) {
      await _refreshNotifications();
      _queueWebhook(
        WebhookEventCategory.profile,
        WebhookNotification(
          title: 'Profile 已自动归档',
          message: '已将 $automaticallyArchived 个到期 Profile 移入过期博物馆',
          event: 'profile.auto_archived',
          occurredAtUtc: DateTime.now().toUtc(),
          payload: {'count': automaticallyArchived},
        ),
      );
    }
    notifyListeners();
  }

  void _rebuildDerivedState() {
    _subscriptionsView = UnmodifiableListView(_subscriptions);
    _activitiesView = UnmodifiableListView(_activities);
    _subscriptionsById = Map.unmodifiable({
      for (final subscription in _subscriptions) subscription.id: subscription,
    });
    final activityGroups = <String, List<ActivityRecord>>{};
    for (final activity in _activities) {
      activityGroups
          .putIfAbsent(activity.subscriptionId, () => <ActivityRecord>[])
          .add(activity);
    }
    _activitiesBySubscriptionId = Map.unmodifiable({
      for (final entry in activityGroups.entries)
        entry.key: List<ActivityRecord>.unmodifiable(entry.value),
    });
    final linkedProfiles = <String, EsimProfile>{};
    final unlinkedProfiles = <String, EsimProfile>{};
    for (final profile in _assets.profiles) {
      final subscriptionId = profile.subscriptionId;
      if (subscriptionId != null) {
        linkedProfiles.putIfAbsent(subscriptionId, () => profile);
      } else if (profile.iccid case final iccid?) {
        unlinkedProfiles.putIfAbsent(iccid, () => profile);
      }
    }
    _assetProfilesBySubscriptionId = Map.unmodifiable(linkedProfiles);
    _unlinkedAssetProfilesByIccid = Map.unmodifiable(unlinkedProfiles);
    _rebuildTimeSensitiveDerivedState(_currentTimeBucket());
  }

  void _refreshTimeSensitiveDerivedStateIfNeeded() {
    final bucket = _currentTimeBucket();
    if (bucket == _timeSensitiveDerivedBucket) return;
    _rebuildTimeSensitiveDerivedState(bucket);
  }

  void _rebuildTimeSensitiveDerivedState(int bucket) {
    _homeActions = _homeActionCenter.build(
      subscriptions: _subscriptions,
      activities: _activities,
    );
    final planner = ReminderPlanner(clock: const SystemClock());
    _scheduledReminderCount = _subscriptions.fold(
      0,
      (count, subscription) => count + planner.planFor(subscription).length,
    );
    _timeSensitiveDerivedBucket = bucket;
  }

  static int _currentTimeBucket() =>
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 300000;

  Future<String?> saveSubscription(Subscription subscription) async {
    final previous = subscriptionById(subscription.id);
    final error = await _mutateSubscription(
      subscription,
      () => _subscriptionReminderService.upsert(
        subscription: subscription,
        clock: FixedClock(subscription.updatedAt),
      ),
      refreshReminders: true,
    );
    if (error == null) _queueSubscriptionWebhook(previous, subscription);
    return error;
  }

  /// 原子保存业务 Profile，并将它放入选定卡片的 EID。
  Future<String?> saveSubscriptionAtEid({
    required Subscription subscription,
    required String eidId,
  }) async {
    final previous = subscriptionById(subscription.id);
    final existing = assetProfileForSubscription(subscription);
    final placementError = _profilePlacementError(
      eidId,
      iccid: subscription.iccid,
      excludedProfileId: existing?.id,
    );
    if (placementError != null) return placementError;
    final assetProfile = EsimProfile(
      id: existing?.id ?? _uuid.v4(),
      eidId: eidId,
      iccid: subscription.iccid,
      operatorName: subscription.operator,
      nickname: existing?.nickname ?? subscription.details.profileName,
      subscriptionId: subscription.id,
      isPinned: subscription.details.isPinned,
      createdAt: existing?.createdAt ?? subscription.updatedAt,
      updatedAt: subscription.updatedAt,
    );
    final error = await _mutateSubscription(
      subscription,
      () => _subscriptionReminderService.upsert(
        subscription: subscription,
        clock: FixedClock(subscription.updatedAt),
        assetProfile: assetProfile,
        movementEventId: _uuid.v4(),
      ),
      refreshReminders: true,
    );
    if (error == null) _queueSubscriptionWebhook(previous, subscription);
    return error;
  }

  /// 删除已激活/待激活 Profile 时先移入博物馆；博物馆内才执行永久删除。
  Future<String?> deleteSubscription(String id) async {
    final subscription = subscriptionById(id);
    if (subscription == null) return 'Profile 不存在';
    if (subscription.lifecycle.stage != ProfileStage.museum) {
      return archiveProfile(id, reason: ProfileArchiveReason.deleted);
    }
    return deleteSubscriptionPermanently(id);
  }

  Future<String?> deleteSubscriptionPermanently(String id) async {
    final subscription = subscriptionById(id);
    final now = DateTime.now().toUtc();
    final error = await _mutate(
      () => _deletionService.delete(subscriptionId: id, nowUtc: now),
      refreshReminders: true,
    );
    if (error != null) return error;
    try {
      await _credentialVault.write(
        ActivationCredentialRecord(
          subscriptionId: id,
          updatedAtUtc: now,
          activation: null,
        ),
      );
      if (subscription != null) {
        _queueWebhook(
          WebhookEventCategory.profile,
          _subscriptionWebhook(
            subscription,
            title: 'Profile 已永久删除',
            event: 'profile.deleted',
            occurredAtUtc: now,
          ),
        );
      }
      return null;
    } catch (error) {
      return 'Profile 已删除，但凭据墓碑保存失败：$error';
    }
  }

  Future<String?> activateProfile(String id) async {
    final subscription = subscriptionById(id);
    if (subscription == null) return 'Profile 不存在';
    final now = DateTime.now().toUtc();
    return saveSubscription(
      subscription.copyWith(
        lifecycle: subscription.lifecycle.activate(now),
        details: subscription.details.copyWith(
          activationDate: subscription.details.activationDate ?? now,
        ),
        updatedAt: now,
      ),
    );
  }

  Future<String?> archiveProfile(
    String id, {
    ProfileArchiveReason reason = ProfileArchiveReason.manual,
  }) async {
    final subscription = subscriptionById(id);
    if (subscription == null) return 'Profile 不存在';
    final now = DateTime.now().toUtc();
    return saveSubscription(
      subscription.copyWith(
        lifecycle: subscription.lifecycle.archive(now, reason: reason),
        updatedAt: now,
      ),
    );
  }

  Future<String?> setMuseumAutoArchiveDays(int? days) async {
    if (days != null && days < 0) return '自动归档天数不能为负数';
    try {
      await _persistMuseumAutoArchiveDays(days);
    } catch (error) {
      return '自动归档设置保存失败：$error';
    }
    _museumAutoArchiveDays = days;
    await reload();
    await _refreshNotifications();
    return _errorMessage;
  }

  Future<String?> setShowNekokoTags(bool value) async {
    try {
      await _persistShowNekokoTags(value);
    } catch (error) {
      return 'Nekoko Tag 展示设置保存失败：$error';
    }
    _showNekokoTags = value;
    notifyListeners();
    return null;
  }

  Future<String?> saveDevice(DeviceAsset device) =>
      _mutate(() => _assetRepository.upsertDevice(device));

  Future<String?> deleteDevice(String id) => _mutate(
    () =>
        _assetRepository.deleteDevice(id, deletedAtUtc: DateTime.now().toUtc()),
  );

  Future<String?> saveSlot(SimSlot slot) =>
      _mutate(() => _assetRepository.upsertSlot(slot));

  Future<String?> deleteSlot(String id) => _mutate(
    () => _assetRepository.deleteSlot(id, deletedAtUtc: DateTime.now().toUtc()),
  );

  Future<String?> saveCard(SimCard card) =>
      _mutate(() => _assetRepository.upsertCard(card));

  Future<String?> deleteCard(String id) => _mutate(
    () => _assetRepository.deleteCard(id, deletedAtUtc: DateTime.now().toUtc()),
  );

  Future<String?> saveEid(Euicc eid) =>
      _mutate(() => _assetRepository.upsertEid(eid));

  Future<String?> deleteEid(String id) => _mutate(
    () => _assetRepository.deleteEid(id, deletedAtUtc: DateTime.now().toUtc()),
  );

  Future<String?> saveProfile(EsimProfile profile) =>
      _mutate(() => _assetRepository.upsertProfile(profile));

  Future<String?> setSubscriptionPinned(String id, bool isPinned) {
    final subscription = subscriptionById(id);
    if (subscription == null) return Future.value('Profile 不存在');
    if (subscription.details.isPinned == isPinned) return Future.value(null);
    final now = DateTime.now().toUtc();
    final linkedProfile = assetProfileForSubscription(subscription);
    return _mutate(
      () => _subscriptionReminderService.upsert(
        subscription: subscription.copyWith(
          details: subscription.details.copyWith(isPinned: isPinned),
          updatedAt: now,
        ),
        clock: FixedClock(now),
        assetProfile: linkedProfile?.copyWith(
          subscriptionId: subscription.id,
          isPinned: isPinned,
          updatedAt: now,
        ),
      ),
    );
  }

  Future<String?> setKeepAliveConstraintCompleted({
    required String subscriptionId,
    required String constraintId,
    required bool completed,
    String? note,
  }) {
    final subscription = subscriptionById(subscriptionId);
    if (subscription == null) return Future.value('Profile 不存在');
    final constraints = [...subscription.keepAlive.policy.constraints];
    final index = constraints.indexWhere((item) => item.id == constraintId);
    if (index < 0) return Future.value('保号条件不存在');
    final now = DateTime.now().toUtc();
    constraints[index] = constraints[index].copyWith(
      completedAt: completed ? now : null,
      completionNote: completed && note != null && note.trim().isNotEmpty
          ? note.trim()
          : null,
    );
    return saveSubscription(
      subscription.copyWith(
        keepAlive: subscription.keepAlive.copyWith(
          policy: subscription.keepAlive.policy.copyWith(
            constraints: constraints,
          ),
        ),
        updatedAt: now,
      ),
    );
  }

  Future<String?> setAssetProfilePinned(String id, bool isPinned) {
    EsimProfile? profile;
    for (final candidate in _assets.profiles) {
      if (candidate.id == id) {
        profile = candidate;
        break;
      }
    }
    if (profile == null) return Future.value('Profile 不存在');
    final subscriptionId = profile.subscriptionId;
    if (subscriptionId != null && subscriptionById(subscriptionId) != null) {
      return setSubscriptionPinned(subscriptionId, isPinned);
    }
    if (profile.isPinned == isPinned) return Future.value(null);
    return saveProfile(
      profile.copyWith(isPinned: isPinned, updatedAt: DateTime.now().toUtc()),
    );
  }

  Future<String?> createEmbeddedEuicc({
    required EmbeddedEuiccCard card,
    required Euicc eid,
    required SimSlot slot,
  }) => _mutate(
    () => _assetRepository.createEmbeddedEuicc(
      card: card,
      eid: eid,
      slot: slot,
      eventId: _uuid.v4(),
      occurredAt: DateTime.now().toUtc(),
    ),
  );

  Future<String?> replaceCardInSlot({
    required String slotId,
    required String? cardId,
  }) => _mutate(
    () => _assetRepository.replaceCardInSlot(
      slotId: slotId,
      cardId: cardId,
      storedEventId: _uuid.v4(),
      movedEventId: _uuid.v4(),
      occurredAt: DateTime.now().toUtc(),
    ),
  );

  Future<String?> moveCard({
    required String cardId,
    required String? toSlotId,
    String? note,
  }) => _mutate(
    () => _assetRepository.moveCard(
      cardId: cardId,
      toSlotId: toSlotId,
      eventId: _uuid.v4(),
      occurredAt: DateTime.now().toUtc(),
      note: note,
    ),
  );

  Future<String?> moveProfile({
    required String profileId,
    required String toEidId,
    String? note,
  }) {
    final profile = _assets.profiles.where((item) => item.id == profileId);
    if (profile.isEmpty) return Future.value('Profile 不存在');
    final placementError = _profilePlacementError(
      toEidId,
      iccid: profile.single.iccid,
      excludedProfileId: profileId,
    );
    if (placementError != null) return Future.value(placementError);
    return _mutate(
      () => _assetRepository.moveProfile(
        profileId: profileId,
        toEidId: toEidId,
        eventId: _uuid.v4(),
        occurredAt: DateTime.now().toUtc(),
        note: note,
      ),
    );
  }

  Future<String?> wipeProfile(String profileId, {String? note}) => _mutate(
    () => _assetRepository.wipeProfile(
      profileId: profileId,
      eventId: _uuid.v4(),
      occurredAt: DateTime.now().toUtc(),
      note: note,
    ),
  );

  SimHubImportReport inspectSimHub(String source) => SimHubCodec(
    idFactory: _uuid.v4,
  ).decode(source, defaultTimeZoneId: _defaultTimeZoneId);

  Result<NekokoImportReport> inspectNekokoDatabase(String path) =>
      NekokoDatabaseCodec(idFactory: _uuid.v4).inspectFile(
        path,
        defaultTimeZoneId: _defaultTimeZoneId,
        existingSubscriptions: _subscriptions,
        existingAssets: _assets,
      );

  String exportSimHub() =>
      SimHubCodec().encode(_subscriptions, activityRecords: _activities);

  String exportSimHubV5() => SimHubCodec().encodeV5(
    _subscriptions,
    assets: _assets,
    activityRecords: _activities,
  );

  Future<String?> applySimHubImport(SimHubImportReport report) async {
    if (_busy) return '当前操作尚未完成，请稍候';
    _setBusy(true);
    final result = _importStore.apply(report);
    if (result case Err(failure: final failure)) {
      return _finishFailure(failure);
    }
    try {
      await _saveImportedCredentials(report.subscriptions);
    } catch (error) {
      _setBusy(false);
      return '数据已导入，但激活凭据写入保险库失败：$error';
    }
    await reload();
    await _refreshNotifications();
    _setBusy(false);
    return null;
  }

  Future<String?> applyNekokoImport(NekokoImportReport report) async {
    if (_busy) return '当前操作尚未完成，请稍候';
    _setBusy(true);
    final result = _importStore.applyNekoko(report);
    if (result case Err(failure: final failure)) {
      return _finishFailure(failure);
    }
    await reload();
    await _refreshNotifications();
    _setBusy(false);
    return null;
  }

  /// 开发者模式：幂等写入一组覆盖主要领域关系的示例资料。
  Future<String?> addDeveloperTestData() async {
    if (_busy) return '当前操作尚未完成，请稍候';
    _setBusy(true);
    final report = _developerSampleReport(
      DateTime.now().toUtc(),
      _defaultTimeZoneId,
    );
    final result = _importStore.apply(report);
    if (result case Err(failure: final failure)) {
      return _finishFailure(failure);
    }
    try {
      await _saveImportedCredentials(report.subscriptions);
    } catch (error) {
      _setBusy(false);
      return '测试数据已写入，但激活凭据写入保险库失败：$error';
    }
    await reload();
    await _refreshNotifications();
    _setBusy(false);
    return null;
  }

  /// 开发者模式：按选择清空本机数据；任何情况都不删除远端文件。
  Future<String?> clearDeveloperData({
    bool clearProfiles = true,
    bool clearAssets = true,
    bool clearWebDavConfiguration = false,
  }) async {
    if (_busy) return '当前操作尚未完成，请稍候';
    if (!clearProfiles && !clearAssets && !clearWebDavConfiguration) {
      return '请至少选择一项要清空的数据';
    }
    _setBusy(true);
    final resetSyncState =
        clearProfiles || clearAssets || clearWebDavConfiguration;
    final result = _importStore.clearSelected(
      clearProfiles: clearProfiles,
      clearAssets: clearAssets,
      resetSyncState: resetSyncState,
    );
    if (result case Err(failure: final failure)) {
      return _finishFailure(failure);
    }
    try {
      if (clearProfiles) await _reminderNotifications.cancelAll();
      if (clearProfiles) await _credentialVault.clear();
      if (clearWebDavConfiguration) await _webDav.clearConfiguration();
    } catch (error) {
      await reload();
      _setBusy(false);
      return '本机清理未完全完成：$error';
    }
    if (clearWebDavConfiguration) _webDavConfiguration = null;
    if (resetSyncState) {
      _lastSyncReport = null;
      _syncConflicts = const [];
      _syncState = const SyncState();
    }
    if (clearProfiles) _notificationError = null;
    await reload();
    _setBusy(false);
    return null;
  }

  Future<String?> recordActivity({
    required Subscription subscription,
    required ActivityType type,
    required DateTime occurredAt,
    Money? amount,
  }) async {
    if (type == ActivityType.balanceChange) {
      return '余额变动必须从余额管理中记录';
    }
    if (_busy) return '当前操作尚未完成，请稍候';
    _setBusy(true);
    final record = ActivityRecord(
      id: _uuid.v4(),
      subscriptionId: subscription.id,
      type: type,
      occurredAt: occurredAt.toUtc(),
      updatedAt: DateTime.now().toUtc(),
      amount: amount,
    );
    final result = _activityService.record(
      subscription: subscription,
      activity: record,
      updatedAtUtc: DateTime.now().toUtc(),
    );
    if (result case Err(failure: final failure)) {
      return _finishFailure(failure);
    }
    await reload();
    await _refreshNotifications();
    _setBusy(false);
    _queueWebhook(
      WebhookEventCategory.activity,
      _activityWebhook(subscription, record),
    );
    return null;
  }

  /// 原子更新 Profile 当前余额并留下可同步的余额流水。
  Future<String?> updateBalance({
    required Subscription subscription,
    required Money balance,
    String? note,
  }) async {
    if (_busy) return '当前操作尚未完成，请稍候';
    final previous = subscription.details.currentBalance;
    if (previous == balance) return '余额没有变化';
    final delta = previous == null
        ? balance
        : previous.currencyCode == balance.currencyCode
        ? balance - previous
        : null;
    _setBusy(true);
    final now = DateTime.now().toUtc();
    final record = ActivityRecord(
      id: _uuid.v4(),
      subscriptionId: subscription.id,
      type: ActivityType.balanceChange,
      occurredAt: now,
      updatedAt: now,
      amount: delta,
      balanceAfter: balance,
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
    );
    final result = _activityService.updateBalance(
      subscription: subscription,
      activity: record,
      balance: balance,
      updatedAtUtc: now,
    );
    if (result case Err(failure: final failure)) {
      return _finishFailure(failure);
    }
    await reload();
    await _refreshNotifications();
    _setBusy(false);
    _queueWebhook(
      WebhookEventCategory.activity,
      _activityWebhook(subscription, record),
    );
    return null;
  }

  Result<int> _archiveExpiredProfiles(DateTime nowUtc) {
    final graceDays = _museumAutoArchiveDays;
    if (graceDays == null) return const Ok(0);
    final loaded = _subscriptionRepository.listAll();
    if (loaded case Err(failure: final failure)) return Err(failure);
    final subscriptions = (loaded as Ok<List<Subscription>>).value;
    var archived = 0;
    for (final subscription in subscriptions) {
      final expiresAt = subscription.lifecycle.serviceExpiresAt;
      if (subscription.lifecycle.stage != ProfileStage.active ||
          expiresAt == null ||
          expiresAt.add(Duration(days: graceDays)).isAfter(nowUtc)) {
        continue;
      }
      final result = _subscriptionReminderService.upsert(
        subscription: subscription.copyWith(
          lifecycle: subscription.lifecycle.archive(
            nowUtc,
            reason: ProfileArchiveReason.expired,
          ),
          updatedAt: nowUtc,
        ),
        clock: FixedClock(nowUtc),
      );
      if (result case Err(failure: final failure)) return Err(failure);
      archived++;
    }
    return Ok(archived);
  }

  Future<String?> _mutate(
    Result<void> Function() operation, {
    bool refreshReminders = false,
  }) async {
    if (_busy) return '当前操作尚未完成，请稍候';
    _setBusy(true);
    final result = operation();
    if (result case Err(failure: final failure)) {
      return _finishFailure(failure);
    }
    await reload();
    if (refreshReminders) await _refreshNotifications();
    _setBusy(false);
    return null;
  }

  Future<String?> _mutateSubscription(
    Subscription subscription,
    Result<void> Function() operation, {
    bool refreshReminders = false,
  }) async {
    if (_busy) return '当前操作尚未完成，请稍候';
    _setBusy(true);
    ActivationCredentialRecord? previous;
    try {
      previous = await _credentialVault.read(subscription.id);
      await _credentialVault.write(
        ActivationCredentialRecord(
          subscriptionId: subscription.id,
          updatedAtUtc: subscription.updatedAt,
          activation: subscription.activation,
        ),
      );
    } catch (error) {
      _setBusy(false);
      return '激活凭据保险库写入失败：$error';
    }
    final result = operation();
    if (result case Err(failure: final failure)) {
      try {
        if (previous == null) {
          await _credentialVault.purge(subscription.id);
        } else {
          await _credentialVault.write(previous);
        }
      } catch (_) {}
      return _finishFailure(failure);
    }
    await reload();
    if (refreshReminders) await _refreshNotifications();
    _setBusy(false);
    return null;
  }

  Future<List<Subscription>> _hydrateCredentials(
    List<Subscription> subscriptions,
  ) async {
    final records = {
      for (final record in await _credentialVault.readAll())
        record.subscriptionId: record,
    };
    return [
      for (final subscription in subscriptions)
        subscription.copyWith(activation: records[subscription.id]?.activation),
    ];
  }

  Future<void> _saveImportedCredentials(
    Iterable<Subscription> subscriptions,
  ) async {
    for (final subscription in subscriptions) {
      if (subscription.activation == null) continue;
      await _credentialVault.write(
        ActivationCredentialRecord(
          subscriptionId: subscription.id,
          updatedAtUtc: subscription.updatedAt,
          activation: subscription.activation,
        ),
      );
    }
  }

  String? _profilePlacementError(
    String eidId, {
    String? iccid,
    String? excludedProfileId,
  }) {
    final eids = _assets.eids.where((item) => item.id == eidId);
    if (eids.isEmpty) return '选定的 EID 已不存在，请重新选择';
    final eid = eids.single;
    final card = _assets.cardById(eid.cardId);
    if (card == null) return '目标 EID 没有可用的所属卡片';
    if (card is PhysicalSimCard) return '普通实体 SIM 不能承载 eSIM Profile';
    final slot = _assets.slotHolding(card.id);
    if (card is EmbeddedEuiccCard && slot == null) {
      return '内置 eUICC 必须位于所属设备卡槽';
    }
    if (slot != null) {
      final error = AssetRules.placementError(card, slot);
      if (error != null) return error;
    }
    if (iccid != null && iccid.trim().isNotEmpty) {
      final cardEids = _assets
          .eidsForCard(card.id)
          .map((item) => item.id)
          .toSet();
      final duplicate = _assets.profiles.any(
        (profile) =>
            profile.id != excludedProfileId &&
            cardEids.contains(profile.eidId) &&
            profile.iccid == iccid,
      );
      if (duplicate) return '该卡片上已有相同 ICCID 的 Profile';
    }
    return null;
  }

  Future<bool> setRemindersEnabled(bool value) async {
    _notificationError = null;
    try {
      if (value) {
        _notificationPermissionGranted = await _reminderNotifications
            .requestPermission();
        if (!_notificationPermissionGranted) {
          _remindersEnabled = false;
          await _persistRemindersEnabled(false);
          notifyListeners();
          return false;
        }
        _remindersEnabled = true;
        await _persistRemindersEnabled(true);
        await _refreshNotifications();
      } else {
        _remindersEnabled = false;
        await _persistRemindersEnabled(false);
        await _reminderNotifications.cancelAll();
      }
      notifyListeners();
      return true;
    } catch (error) {
      _notificationError = '通知设置失败：$error';
      _remindersEnabled = false;
      await _persistRemindersEnabled(false);
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshNotificationPermission({bool reschedule = false}) async {
    try {
      _notificationPermissionGranted = await _reminderNotifications
          .areNotificationsEnabled();
      if (reschedule) await _refreshNotifications();
    } catch (error) {
      _notificationError = '无法读取通知权限：$error';
      _notificationPermissionGranted = false;
    }
    notifyListeners();
  }

  Future<void> openNotificationSettings() =>
      _reminderNotifications.openSettings();

  Future<String?> initialNotificationSubscriptionId() =>
      _reminderNotifications.initialSubscriptionId();

  Future<void> _refreshNotifications() async {
    _notificationError = null;
    try {
      if (!_remindersEnabled || !_notificationPermissionGranted) {
        await _reminderNotifications.cancelAll();
        return;
      }
      await _reminderNotifications.replaceAll(_subscriptions);
    } catch (error) {
      _notificationError = '提醒排程失败：$error';
    }
  }

  Future<String?> testWebhook(WebhookConfiguration configuration) async {
    if (_webhookInFlightCount > 0) return 'Webhook 请求尚未完成，请稍候';
    try {
      configuration.validate();
    } on FormatException catch (error) {
      return error.message;
    }
    _webhookInFlightCount++;
    _webhookLastError = null;
    notifyListeners();
    try {
      await _webhookNotifications.send(
        configuration,
        WebhookNotification(
          title: 'Webhook 测试成功',
          message: 'ieSIM 已成功连接到你配置的 Webhook 服务',
          event: 'webhook.test',
          occurredAtUtc: DateTime.now().toUtc(),
          payload: const {'source': 'settings'},
        ),
      );
      _webhookLastSentAtUtc = DateTime.now().toUtc();
      return null;
    } catch (error) {
      final message = _webhookErrorMessage(error);
      _webhookLastError = message;
      return message;
    } finally {
      _webhookInFlightCount--;
      if (!_disposed) notifyListeners();
    }
  }

  Future<String?> saveWebhookConfiguration(
    WebhookConfiguration configuration,
  ) async {
    try {
      configuration.validate();
      await _webhookNotifications.saveConfiguration(configuration);
      _webhookConfiguration = configuration;
      _webhookLastError = null;
      notifyListeners();
      return null;
    } on FormatException catch (error) {
      return error.message;
    } catch (error) {
      return 'Webhook 配置保存失败：$error';
    }
  }

  Future<String?> disconnectWebhook() async {
    try {
      await _webhookNotifications.clearConfiguration();
      _webhookConfiguration = null;
      _webhookLastError = null;
      _webhookLastSentAtUtc = null;
      notifyListeners();
      return null;
    } catch (error) {
      return 'Webhook 配置移除失败：$error';
    }
  }

  void _queueSubscriptionWebhook(
    Subscription? previous,
    Subscription subscription,
  ) {
    final stage = subscription.lifecycle.stage;
    final (title, event) = switch ((previous?.lifecycle.stage, stage)) {
      (null, _) => ('Profile 已添加', 'profile.created'),
      (ProfileStage.pendingActivation, ProfileStage.active) => (
        'Profile 已激活',
        'profile.activated',
      ),
      (_, ProfileStage.museum) when previous?.lifecycle.stage != stage => (
        'Profile 已归档',
        'profile.archived',
      ),
      (ProfileStage.museum, ProfileStage.active) => (
        'Profile 已恢复',
        'profile.restored',
      ),
      _ => ('Profile 已更新', 'profile.updated'),
    };
    _queueWebhook(
      WebhookEventCategory.profile,
      _subscriptionWebhook(
        subscription,
        title: title,
        event: event,
        occurredAtUtc: subscription.updatedAt,
      ),
    );
  }

  WebhookNotification _subscriptionWebhook(
    Subscription subscription, {
    required String title,
    required String event,
    required DateTime occurredAtUtc,
  }) {
    final includeDetails =
        _webhookConfiguration?.includeProfileDetails ?? false;
    final details = <String, Object?>{};
    if (includeDetails) {
      details.addAll({
        'subscriptionId': subscription.id,
        'profileName': profileDisplayName(subscription),
        'phoneNumber': subscription.number.isUnknown
            ? null
            : subscription.number.value,
        'operator': subscription.operator,
      });
    }
    return WebhookNotification(
      title: title,
      message: includeDetails
          ? '${displayProfileIdentity(subscription)}：$title'
          : title,
      event: event,
      occurredAtUtc: occurredAtUtc.toUtc(),
      payload: {
        'stage': subscription.lifecycle.stage.name,
        'deviceState': subscription.lifecycle.deviceState.name,
        ...details,
      },
    );
  }

  WebhookNotification _activityWebhook(
    Subscription subscription,
    ActivityRecord record,
  ) {
    final includeDetails =
        _webhookConfiguration?.includeProfileDetails ?? false;
    final action = activityName(record.type);
    return WebhookNotification(
      title: '$action已记录',
      message: includeDetails
          ? '${displayProfileIdentity(subscription)}：$action已记录'
          : '一个 Profile 的$action已记录',
      event: record.type == ActivityType.balanceChange
          ? 'activity.balance_changed'
          : 'activity.recorded',
      occurredAtUtc: record.occurredAt,
      payload: {
        'activityType': record.type.name,
        if (record.amount case final amount?) ...{
          'amountMinorUnits': amount.minorUnits,
          'currencyCode': amount.currencyCode,
        },
        if (record.balanceAfter case final balance?) ...{
          'balanceMinorUnits': balance.minorUnits,
          'balanceCurrencyCode': balance.currencyCode,
        },
        if (includeDetails) ...{
          'subscriptionId': subscription.id,
          'profileName': profileDisplayName(subscription),
          'phoneNumber': subscription.number.isUnknown
              ? null
              : subscription.number.value,
          'operator': subscription.operator,
        },
      },
    );
  }

  void _queueWebhook(
    WebhookEventCategory category,
    WebhookNotification notification,
  ) {
    final configuration = _webhookConfiguration;
    if (configuration == null || !configuration.allows(category)) return;
    unawaited(_deliverWebhook(configuration, notification));
  }

  Future<void> _deliverWebhook(
    WebhookConfiguration configuration,
    WebhookNotification notification,
  ) async {
    _webhookInFlightCount++;
    if (!_disposed) notifyListeners();
    try {
      await _webhookNotifications.send(configuration, notification);
      _webhookLastSentAtUtc = DateTime.now().toUtc();
      _webhookLastError = null;
    } catch (error) {
      _webhookLastError = _webhookErrorMessage(error);
    } finally {
      _webhookInFlightCount--;
      if (!_disposed) notifyListeners();
    }
  }

  static String _webhookErrorMessage(Object error) => switch (error) {
    FormatException(message: final message) => message,
    WebhookHttpException() || WebhookNetworkException() => error.toString(),
    _ => 'Webhook 发送失败：$error',
  };

  Future<String?> testWebDav(WebDavConfiguration configuration) async {
    if (_busy) return '当前操作尚未完成，请稍候';
    _setBusy(true);
    try {
      final result = await _webDav.testConnection(configuration);
      return switch (result) {
        Ok() => null,
        Err(failure: final failure) => _failureMessage(failure),
      };
    } catch (error) {
      return '连接测试失败：$error';
    } finally {
      _setBusy(false);
    }
  }

  Future<String?> saveWebDavConfiguration(
    WebDavConfiguration configuration,
  ) async {
    try {
      await _webDav.saveConfiguration(configuration);
      _webDavConfiguration = configuration;
      notifyListeners();
      return null;
    } catch (error) {
      return '配置保存失败：$error';
    }
  }

  Future<String?> syncWebDav() async {
    final configuration = _webDavConfiguration;
    if (configuration == null) return '请先配置 WebDAV';
    if (_busy) return '当前操作尚未完成，请稍候';
    _setBusy(true);
    try {
      final result = await _webDav.sync(configuration);
      switch (result) {
        case Ok(value: final report):
          _lastSyncReport = report;
          await reload();
          _loadSyncConflicts();
          _loadSyncState();
          await _refreshNotifications();
          _queueWebhook(
            WebhookEventCategory.sync,
            WebhookNotification(
              title: 'WebDAV 同步完成',
              message: report.conflictCount == 0
                  ? '数据已安全同步到 WebDAV'
                  : '数据已同步，并记录 ${report.conflictCount} 个冲突',
              event: 'sync.succeeded',
              occurredAtUtc: report.syncedAtUtc,
              payload: {
                'subscriptionCount': report.subscriptionCount,
                'activityCount': report.activityCount,
                'conflictCount': report.conflictCount,
                'attempts': report.attempts,
              },
            ),
          );
          return null;
        case Err(failure: final failure):
          final message = _failureMessage(failure);
          _queueWebhook(
            WebhookEventCategory.sync,
            WebhookNotification(
              title: 'WebDAV 同步失败',
              message: message,
              event: 'sync.failed',
              occurredAtUtc: DateTime.now().toUtc(),
              payload: {'failureType': failure.runtimeType.toString()},
            ),
          );
          return message;
      }
    } catch (error) {
      _queueWebhook(
        WebhookEventCategory.sync,
        WebhookNotification(
          title: 'WebDAV 同步失败',
          message: '同步过程中发生未预期错误',
          event: 'sync.failed',
          occurredAtUtc: DateTime.now().toUtc(),
          payload: {'failureType': error.runtimeType.toString()},
        ),
      );
      return '同步失败：$error';
    } finally {
      _setBusy(false);
    }
  }

  Future<String?> disconnectWebDav() async {
    try {
      await _webDav.clearConfiguration();
      _webDavConfiguration = null;
      _lastSyncReport = null;
      notifyListeners();
      return null;
    } catch (error) {
      return '移除配置失败：$error';
    }
  }

  Future<String?> refreshEuiccCardPresets() async {
    final service = _euiccCardPresetService;
    if (service == null) return null;
    try {
      _euiccCardPresetResult = await service.load();
      notifyListeners();
      return _euiccCardPresetResult.warning;
    } catch (error) {
      return 'eUICC 型号库更新失败：$error';
    }
  }

  void _loadSyncConflicts() {
    final result = _webDav.listConflicts();
    if (result case Ok(value: final conflicts)) {
      _syncConflicts = conflicts;
    }
  }

  void _loadSyncState() {
    final result = _webDav.readState();
    if (result case Ok(value: final state)) _syncState = state;
  }

  String _finishFailure(Failure failure) {
    final message = _failureMessage(failure);
    _errorMessage = message;
    _setBusy(false);
    return message;
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  static String _failureMessage(Failure failure) => switch (failure) {
    StoreError(message: final message) => '本地数据保存失败：$message',
    AuthError(message: final message) => '认证失败：$message',
    NetworkError(message: final message) => '网络错误：$message',
    SchemaError(message: final message) => '数据版本错误：$message',
    PreconditionFailed() => '远端数据正在被修改，请稍后重试',
  };

  @override
  void dispose() {
    _disposed = true;
    _reminderNotifications.dispose();
    _closeStore();
    super.dispose();
  }
}

SimHubImportReport _developerSampleReport(DateTime now, String timeZoneId) {
  const ctExcelId = 'developer-sample-ctexcel';
  const travelId = 'developer-sample-travel';
  const mobileId = 'developer-sample-mobile';
  final createdAt = now.subtract(const Duration(days: 240));
  final ctExcelActivity = now.subtract(const Duration(days: 36));
  final mobileActivity = now.subtract(const Duration(days: 171));

  final subscriptions = <Subscription>[
    Subscription(
      id: ctExcelId,
      iccid: '8944000000000000001',
      number: PhoneNumber('+447700900001'),
      operator: 'CTExcel UK（测试）',
      lifecycle: ProfileLifecycle(
        deviceState: ProfileDeviceState.enabled,
        serviceExpiresAt: now.add(const Duration(days: 365)),
        activatedAt: createdAt,
      ),
      plan: Plan(
        name: 'UK 预付费测试套餐',
        cyclePrice: const Money(minorUnits: 1200, currencyCode: 'GBP'),
        cycleDays: 30,
        startDate: now.subtract(const Duration(days: 8)),
        expiryDate: now.add(const Duration(days: 22)),
      ),
      keepAlive: KeepAlive(
        required: true,
        cycleDays: 90,
        lastActivityAt: ctExcelActivity,
        policy: KeepAlivePolicy(
          qualifyingActions: const {
            KeepAliveAction.mobileData,
            KeepAliveAction.call,
            KeepAliveAction.sms,
            KeepAliveAction.topUp,
          },
          summary: '测试规则：90 天内产生一次有效使用。',
        ),
      ),
      tags: const ['测试数据', '英国', '主套餐'],
      appearance: const Appearance(flag: '🇬🇧', cardColorHex: '#2374AB'),
      details: SubscriptionDetails(
        profileName: '英国主号（测试）',
        countryCode: 'GB',
        countryName: 'United Kingdom',
        mcc: '234',
        mnc: '30',
        apn: 'everywhere',
        currentBalance: Money(minorUnits: 850, currencyCode: 'GBP'),
        affiliateOffers: [
          AffiliateOffer(
            id: 'builtin-ctexcel-uk',
            brand: 'CTExcel UK',
            category: AffiliateOfferCategory.mobileOperator,
            url:
                'https://www.ctexcel.com/uk/buyCard/buyCardPackage/1?recommendCode=RNAFZW',
            promoCode: 'RNAFZW',
            note: '英国实体 SIM / 手机号码推荐。',
            isBuiltIn: true,
          ),
        ],
        appBindings: [
          PhoneAppBinding(
            id: 'developer-sample-whatsapp-binding',
            phoneNumber: '+447700900001',
            appName: 'WhatsApp Messenger',
            presetId: 'whatsapp',
            developerName: 'WhatsApp LLC',
            accountLabel: '主账号（测试）',
            purposes: const [
              PhoneAppBindingPurpose.messaging,
              PhoneAppBindingPurpose.verification,
            ],
            verificationChannels: const [
              PhoneVerificationChannel.sms,
              PhoneVerificationChannel.voiceCall,
            ],
            verifiedAt: createdAt,
            appStoreId: '310633997',
            appStoreBundleId: 'net.whatsapp.WhatsApp',
            appStoreUrl:
                'https://apps.apple.com/app/whatsapp-messenger/id310633997',
            googlePlayPackage: 'com.whatsapp',
            googlePlayUrl:
                'https://play.google.com/store/apps/details?id=com.whatsapp',
            websiteUrl: 'https://www.whatsapp.com/',
            createdAt: createdAt,
            updatedAt: now,
          ),
        ],
        orderIndex: 0,
      ),
      timeZoneId: timeZoneId,
      createdAt: createdAt,
      updatedAt: now,
    ),
    Subscription(
      id: travelId,
      iccid: '8944000000000000002',
      number: const PhoneNumber.unknown(),
      operator: '旅行数据 eSIM（测试）',
      lifecycle: ProfileLifecycle(
        stage: ProfileStage.pendingActivation,
        activationDeadline: now.add(const Duration(days: 180)),
        activationRequirements: '测试要求：购买后 180 天内激活，首次下载需要联网。',
      ),
      activation: LpaActivation(
        smdpAddress: 'rsp.example.test',
        matchingId: 'IESIM-TEST-PROFILE',
      ),
      plan: Plan(
        name: '欧洲 10 GB / 30 天',
        cyclePrice: const Money(minorUnits: 1590, currencyCode: 'EUR'),
        cycleDays: 30,
        startDate: now.subtract(const Duration(days: 3)),
        expiryDate: now.add(const Duration(days: 27)),
      ),
      keepAlive: KeepAlive.notRequired(),
      tags: const ['测试数据', '无号码', '旅行'],
      appearance: const Appearance(flag: '🇪🇺', cardColorHex: '#6554C0'),
      details: const SubscriptionDetails(
        profileName: '欧洲旅行 Profile（测试）',
        countryCode: 'DE',
        countryName: 'Germany',
        mcc: '262',
        mnc: '01',
        apn: 'internet',
        orderIndex: 1,
      ),
      timeZoneId: timeZoneId,
      createdAt: now.subtract(const Duration(days: 3)),
      updatedAt: now,
    ),
    Subscription(
      id: mobileId,
      iccid: '8986000000000000003',
      number: PhoneNumber('+8613800000001'),
      operator: '中国移动（测试）',
      lifecycle: ProfileLifecycle(
        stage: ProfileStage.museum,
        deviceState: ProfileDeviceState.disabled,
        serviceExpiresAt: now.subtract(const Duration(days: 30)),
        activatedAt: createdAt,
        archivedAt: now.subtract(const Duration(days: 10)),
        archiveReason: ProfileArchiveReason.expired,
      ),
      plan: Plan(name: '长期保号测试卡', isLongTerm: true),
      keepAlive: KeepAlive(
        required: true,
        cycleDays: 180,
        lastActivityAt: mobileActivity,
        policy: KeepAlivePolicy(
          qualifyingActions: const {
            KeepAliveAction.mobileData,
            KeepAliveAction.call,
            KeepAliveAction.sms,
            KeepAliveAction.topUp,
          },
          summary: '测试规则：用于验证临期状态和提醒。',
        ),
      ),
      tags: const ['测试数据', '临期', '实体 eUICC'],
      appearance: const Appearance(flag: '🇨🇳', cardColorHex: '#E36B3D'),
      details: const SubscriptionDetails(
        profileName: '中国保号 Profile（测试）',
        countryCode: 'CN',
        countryName: 'China',
        mcc: '460',
        mnc: '00',
        apn: 'cmnet',
        orderIndex: 2,
      ),
      timeZoneId: timeZoneId,
      createdAt: createdAt,
      updatedAt: now,
    ),
  ];

  final activities = <ActivityRecord>[
    ActivityRecord(
      id: 'developer-sample-activity-ctexcel-balance',
      subscriptionId: ctExcelId,
      type: ActivityType.balanceChange,
      occurredAt: now.subtract(const Duration(days: 2)),
      updatedAt: now,
      amount: const Money(minorUnits: 850, currencyCode: 'GBP'),
      balanceAfter: const Money(minorUnits: 850, currencyCode: 'GBP'),
      note: '测试余额初始化',
    ),
    ActivityRecord(
      id: 'developer-sample-activity-ctexcel',
      subscriptionId: ctExcelId,
      type: ActivityType.mobileData,
      occurredAt: ctExcelActivity,
      updatedAt: now,
    ),
    ActivityRecord(
      id: 'developer-sample-activity-mobile',
      subscriptionId: mobileId,
      type: ActivityType.topUp,
      occurredAt: mobileActivity,
      updatedAt: now,
      amount: const Money(minorUnits: 1000, currencyCode: 'CNY'),
    ),
  ];

  final device = DeviceAsset(
    id: 'developer-sample-device',
    name: 'Pixel 测试机',
    kind: DeviceKind.phone,
    brand: 'Google',
    note: '由开发者模式生成，可安全删除。',
    region: 'Global',
    usage: '测试',
    simCapability: SimCapability.physicalPlusEsim,
    supportsSaRoaming: true,
    createdAt: createdAt,
    updatedAt: now,
  );
  final removable = RemovableEuiccCard(
    id: 'developer-sample-removable-card',
    name: '测试可拆卸 eUICC',
    note: '用于测试卡片迁移。',
    createdAt: createdAt,
    updatedAt: now,
  );
  final embedded = EmbeddedEuiccCard(
    id: 'developer-sample-embedded-card',
    name: 'Pixel 内置 eSIM',
    embeddedDeviceId: device.id,
    createdAt: createdAt,
    updatedAt: now,
  );
  final removableEid = Euicc(
    id: 'developer-sample-removable-eid',
    cardId: removable.id,
    value: '89049032000000000000000000000001',
    label: '可拆卸 EID（测试）',
    createdAt: createdAt,
    updatedAt: now,
  );
  final embeddedEid = Euicc(
    id: 'developer-sample-embedded-eid',
    cardId: embedded.id,
    value: '89044045000000000000000000000002',
    label: '内置 EID（测试）',
    createdAt: createdAt,
    updatedAt: now,
  );

  return SimHubImportReport(
    subscriptions: subscriptions,
    activityRecords: activities,
    issues: const [],
    sourceRecordCount: subscriptions.length,
    assets: AssetInventory(
      devices: [device],
      cards: [removable, embedded],
      slots: [
        SimSlot(
          id: 'developer-sample-slot-physical',
          deviceId: device.id,
          label: 'SIM 1',
          kind: SimSlotKind.physical,
          position: 0,
          cardId: removable.id,
          createdAt: createdAt,
          updatedAt: now,
        ),
        SimSlot(
          id: 'developer-sample-slot-embedded',
          deviceId: device.id,
          label: '内置 eSIM',
          kind: SimSlotKind.embeddedEuicc,
          position: 1,
          cardId: embedded.id,
          createdAt: createdAt,
          updatedAt: now,
        ),
      ],
      eids: [removableEid, embeddedEid],
      profiles: [
        EsimProfile(
          id: 'developer-sample-profile-mobile',
          eidId: removableEid.id,
          iccid: subscriptions[2].iccid,
          operatorName: subscriptions[2].operator,
          nickname: 't:测试实体卡',
          subscriptionId: mobileId,
          createdAt: createdAt,
          updatedAt: now,
        ),
        EsimProfile(
          id: 'developer-sample-profile-ctexcel',
          eidId: embeddedEid.id,
          iccid: subscriptions[0].iccid,
          operatorName: subscriptions[0].operator,
          nickname: 't:测试主卡',
          subscriptionId: ctExcelId,
          createdAt: createdAt,
          updatedAt: now,
        ),
        EsimProfile(
          id: 'developer-sample-profile-travel',
          eidId: embeddedEid.id,
          iccid: subscriptions[1].iccid,
          operatorName: subscriptions[1].operator,
          nickname: 't:测试旅行卡',
          subscriptionId: travelId,
          createdAt: now.subtract(const Duration(days: 3)),
          updatedAt: now,
        ),
      ],
    ),
  );
}
