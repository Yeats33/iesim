import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/data/app_controller.dart';
import 'package:iesim/services/credential_vault.dart';
import 'package:iesim/services/reminder_notifications.dart';
import 'package:iesim/services/webdav_service.dart';
import 'package:iesim_core/iesim_core.dart';

void main() {
  test('Nekoko Tag 默认隐藏且展示选择会持久化', () async {
    final persisted = <bool>[];
    final controller = AppController.inMemory(
      persistShowNekokoTags: (value) async => persisted.add(value),
    );
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');

    expect(controller.showNekokoTags, isFalse);
    expect(await controller.setShowNekokoTags(true), isNull);
    expect(controller.showNekokoTags, isTrue);
    expect(persisted, [true]);
  });

  test('Profile 保存和 reload 都通过凭据保险库还原 LPA 信息', () async {
    final vault = MemoryActivationCredentialVault();
    final controller = AppController.inMemory(credentialVault: vault);
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final now = DateTime.now().toUtc();
    final activation = LpaActivation(
      smdpAddress: 'rsp.private.example',
      matchingId: 'MATCHING-ID-SECRET',
      confirmationCode: '123456',
    );
    final subscription = Subscription(
      id: 'vault-profile',
      number: const PhoneNumber.unknown(),
      activation: activation,
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'UTC',
      createdAt: now,
      updatedAt: now,
    );

    expect(await controller.saveSubscription(subscription), isNull);
    expect(controller.subscriptions.single.activation, activation);
    expect((await vault.read(subscription.id))?.activation, activation);

    await controller.reload();
    expect(controller.subscriptions.single.activation, activation);

    expect(await controller.clearDeveloperData(), isNull);
    expect(await vault.readAll(), isEmpty);
  });

  test('SimHub 报告确认后写入并可再次导出', () async {
    final controller = AppController.inMemory();
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'Asia/Shanghai');
    final report = controller.inspectSimHub(
      jsonEncode([
        {
          'id': 'sub-a',
          'phoneNumber': '10086',
          'carrier': '测试运营商',
          'createdAt': '2026-08-08',
          'renewDays': 30,
          'activityRecords': [
            {
              'id': 'act-a',
              'type': 'call',
              'occurredAt': '2026-08-08T08:00:00Z',
            },
          ],
        },
      ]),
    );

    expect(report.importedCount, 1);
    expect(await controller.applySimHubImport(report), isNull);
    expect(controller.subscriptions, hasLength(1));
    expect(controller.activities, hasLength(1));

    final exported = jsonDecode(controller.exportSimHub()) as List;
    expect(exported.single['phoneNumber'], '10086');
    expect(exported.single['activityRecords'], hasLength(1));
  });

  test('订阅变更后替换系统提醒，关闭开关后清空', () async {
    final notifications = _FakeNotifications();
    final persisted = <bool>[];
    final controller = AppController.inMemory(
      reminderNotifications: notifications,
      persistRemindersEnabled: (value) async => persisted.add(value),
    );
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'Asia/Shanghai');

    expect(
      await controller.saveSubscription(
        Subscription(
          id: 'sub-reminder',
          number: PhoneNumber('10010'),
          plan: Plan(expiryDate: DateTime.utc(2030, 1, 20)),
          keepAlive: KeepAlive.notRequired(),
          timeZoneId: 'Asia/Shanghai',
          createdAt: DateTime.utc(2026, 8, 8),
          updatedAt: DateTime.utc(2026, 8, 8),
        ),
      ),
      isNull,
    );
    expect(notifications.lastSubscriptions, hasLength(1));

    await controller.setRemindersEnabled(false);
    expect(notifications.cancelCount, greaterThan(0));
    expect(persisted, [false]);
  });

  test('SimHub v5 设备资产导入后可由控制器完整导出', () async {
    final controller = AppController.inMemory();
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final report = controller.inspectSimHub(
      jsonEncode({
        'formatVersion': 5,
        'esimCards': [
          {
            'id': 'sub-device',
            'phoneNumber': '10086',
            'iccid': '8986001',
            'deviceID': 'phone-a',
            'createdAt': '2026-08-08T00:00:00Z',
          },
        ],
        'dormantCards': [],
        'devices': [
          {
            'id': 'phone-a',
            'name': '测试手机',
            'deviceTypeRaw': 'phone',
            'simCapabilityRaw': 'physicalOnly',
            'createdAt': '2026-08-08T00:00:00Z',
          },
        ],
      }),
    );
    expect(await controller.applySimHubImport(report), isNull);
    expect(controller.assets.devices, hasLength(1));
    expect(controller.assets.cards, hasLength(1));
    final exported = jsonDecode(controller.exportSimHubV5());
    expect(exported['devices'], hasLength(1));
    expect(exported['esimCards'].single['deviceID'], 'phone-a');
  });

  test('新建业务 Profile 可归属到卡片 EID 并可更换 EID', () async {
    final controller = AppController.inMemory();
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final now = DateTime.utc(2026, 8, 8);
    final card = RemovableEuiccCard(
      id: 'card-profile-placement',
      name: '测试 eUICC',
      createdAt: now,
      updatedAt: now,
    );
    final eid1 = Euicc(
      id: 'eid-profile-placement-1',
      cardId: card.id,
      value: '89000000000000000000000000000001',
      createdAt: now,
      updatedAt: now,
    );
    final eid2 = Euicc(
      id: 'eid-profile-placement-2',
      cardId: card.id,
      value: '89000000000000000000000000000002',
      createdAt: now,
      updatedAt: now,
    );
    expect(await controller.saveCard(card), isNull);
    expect(await controller.saveEid(eid1), isNull);
    expect(await controller.saveEid(eid2), isNull);
    final subscription = Subscription(
      id: 'subscription-profile-placement',
      number: const PhoneNumber.unknown(),
      operator: '测试运营商',
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'UTC',
      createdAt: now,
      updatedAt: now,
    );

    expect(
      await controller.saveSubscriptionAtEid(
        subscription: subscription,
        eidId: eid1.id,
      ),
      isNull,
    );
    expect(controller.subscriptions, hasLength(1));
    expect(controller.assets.profiles, hasLength(1));
    final profileId = controller.assets.profiles.single.id;
    expect(controller.assets.profiles.single.eidId, eid1.id);
    expect(controller.assets.profiles.single.subscriptionId, subscription.id);

    expect(
      await controller.saveSubscriptionAtEid(
        subscription: subscription.copyWith(
          updatedAt: now.add(const Duration(minutes: 1)),
        ),
        eidId: eid2.id,
      ),
      isNull,
    );
    expect(controller.assets.profiles.single.id, profileId);
    expect(controller.assets.profiles.single.eidId, eid2.id);
    expect(controller.assets.events.single, isA<ProfileMoved>());
  });

  test('置顶状态同步保存到业务 Profile 与资产 Profile', () async {
    final controller = AppController.inMemory();
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final now = DateTime.utc(2026, 8, 8);
    final card = RemovableEuiccCard(
      id: 'card-pin',
      name: '置顶测试卡',
      createdAt: now,
      updatedAt: now,
    );
    final eid = Euicc(
      id: 'eid-pin',
      cardId: card.id,
      value: '89000000000000000000000000000003',
      createdAt: now,
      updatedAt: now,
    );
    expect(await controller.saveCard(card), isNull);
    expect(await controller.saveEid(eid), isNull);
    expect(
      await controller.saveSubscriptionAtEid(
        subscription: Subscription(
          id: 'subscription-pin',
          number: const PhoneNumber.unknown(),
          operator: '置顶运营商',
          plan: Plan(),
          keepAlive: KeepAlive.notRequired(),
          timeZoneId: 'UTC',
          createdAt: now,
          updatedAt: now,
        ),
        eidId: eid.id,
      ),
      isNull,
    );

    expect(
      await controller.setSubscriptionPinned('subscription-pin', true),
      isNull,
    );
    expect(
      controller.subscriptionById('subscription-pin')!.details.isPinned,
      isTrue,
    );
    final profile = controller.assets.profiles.single;
    expect(profile.isPinned, isTrue);

    expect(await controller.setAssetProfilePinned(profile.id, false), isNull);
    expect(
      controller.subscriptionById('subscription-pin')!.details.isPinned,
      isFalse,
    );
    expect(controller.assets.profiles.single.isPinned, isFalse);

    expect(
      await controller.saveProfile(
        EsimProfile(
          id: 'asset-only-pin',
          eidId: eid.id,
          iccid: '8944000000000000099',
          operatorName: '仅资产 Profile',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      isNull,
    );
    expect(
      await controller.setAssetProfilePinned('asset-only-pin', true),
      isNull,
    );
    expect(
      controller.assets.profiles
          .singleWhere((item) => item.id == 'asset-only-pin')
          .isPinned,
      isTrue,
    );
  });

  test('开发者测试数据幂等覆盖主要关系且可一键清空', () async {
    final notifications = _FakeNotifications();
    final controller = AppController.inMemory(
      reminderNotifications: notifications,
    );
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');

    expect(await controller.addDeveloperTestData(), isNull);
    expect(controller.subscriptions, hasLength(3));
    expect(controller.activities, hasLength(3));
    expect(controller.assets.devices, hasLength(1));
    expect(controller.assets.slots, hasLength(2));
    expect(controller.assets.cards, hasLength(2));
    expect(controller.assets.eids, hasLength(2));
    expect(controller.assets.profiles, hasLength(3));
    expect(
      controller.subscriptions.map((item) => item.lifecycle.stage).toSet(),
      {
        ProfileStage.active,
        ProfileStage.pendingActivation,
        ProfileStage.museum,
      },
    );

    expect(await controller.addDeveloperTestData(), isNull);
    expect(controller.subscriptions, hasLength(3));
    expect(controller.assets.profiles, hasLength(3));

    expect(await controller.clearDeveloperData(), isNull);
    expect(controller.subscriptions, isEmpty);
    expect(controller.activities, isEmpty);
    expect(controller.assets.devices, isEmpty);
    expect(controller.assets.cards, isEmpty);
    expect(notifications.cancelCount, greaterThan(0));
  });

  test('开发者可选择清空范围且默认保留 WebDAV 本地配置', () async {
    final webDav = _FakeWebDavGateway(
      const WebDavConfiguration(
        directoryUrl: 'https://dav.example.test/iesim/',
        username: 'tester',
        password: 'secret',
        encryptionPassword: 'correct horse battery staple',
      ),
    );
    final controller = AppController.inMemory(webDavGateway: webDav);
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    expect(await controller.addDeveloperTestData(), isNull);

    expect(
      await controller.clearDeveloperData(
        clearProfiles: true,
        clearAssets: false,
      ),
      isNull,
    );
    expect(controller.subscriptions, isEmpty);
    expect(controller.assets.devices, isNotEmpty);
    expect(controller.webDavConfiguration, isNotNull);
    expect(webDav.clearCount, 0);

    expect(
      await controller.clearDeveloperData(
        clearProfiles: false,
        clearAssets: true,
        clearWebDavConfiguration: true,
      ),
      isNull,
    );
    expect(controller.assets.devices, isEmpty);
    expect(controller.webDavConfiguration, isNull);
    expect(webDav.clearCount, 1);
  });

  test('删除已激活 Profile 先进入博物馆，再删除才永久移除', () async {
    final controller = AppController.inMemory(museumAutoArchiveDays: null);
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final now = DateTime.now().toUtc();
    final subscription = Subscription(
      id: 'profile-delete-flow',
      number: PhoneNumber('10086'),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'UTC',
      createdAt: now,
      updatedAt: now,
    );
    expect(await controller.saveSubscription(subscription), isNull);

    expect(await controller.deleteSubscription(subscription.id), isNull);
    expect(controller.subscriptions, hasLength(1));
    expect(
      controller.subscriptions.single.lifecycle.stage,
      ProfileStage.museum,
    );
    expect(
      controller.subscriptions.single.lifecycle.archiveReason,
      ProfileArchiveReason.deleted,
    );

    expect(await controller.deleteSubscription(subscription.id), isNull);
    expect(controller.subscriptions, isEmpty);
  });

  test('未激活 Profile 可执行激活操作', () async {
    final controller = AppController.inMemory(museumAutoArchiveDays: null);
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final now = DateTime.now().toUtc();
    final subscription = Subscription(
      id: 'profile-pending',
      number: const PhoneNumber.unknown(),
      lifecycle: ProfileLifecycle(
        stage: ProfileStage.pendingActivation,
        activationDeadline: now.add(const Duration(days: 30)),
        activationRequirements: '需要联网',
      ),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'UTC',
      createdAt: now,
      updatedAt: now,
    );
    expect(await controller.saveSubscription(subscription), isNull);
    expect(await controller.activateProfile(subscription.id), isNull);
    final activated = controller.subscriptions.single;
    expect(activated.lifecycle.stage, ProfileStage.active);
    expect(activated.lifecycle.activatedAt, isNotNull);
    expect(activated.details.activationDate, isNotNull);
    expect(activated.lifecycle.activationRequirements, '需要联网');
  });

  test('用户选择到期宽限期后自动移入博物馆', () async {
    final persisted = <int?>[];
    final controller = AppController.inMemory(
      museumAutoArchiveDays: null,
      persistMuseumAutoArchiveDays: (value) async => persisted.add(value),
    );
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final now = DateTime.now().toUtc();
    final subscription = Subscription(
      id: 'profile-expired',
      number: PhoneNumber('10010'),
      lifecycle: ProfileLifecycle(
        serviceExpiresAt: now.subtract(const Duration(days: 31)),
      ),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'UTC',
      createdAt: now.subtract(const Duration(days: 100)),
      updatedAt: now.subtract(const Duration(days: 31)),
    );
    expect(await controller.saveSubscription(subscription), isNull);
    expect(
      controller.subscriptions.single.lifecycle.stage,
      ProfileStage.active,
    );

    expect(await controller.setMuseumAutoArchiveDays(30), isNull);
    expect(persisted, [30]);
    expect(
      controller.subscriptions.single.lifecycle.stage,
      ProfileStage.museum,
    );
    expect(
      controller.subscriptions.single.lifecycle.archiveReason,
      ProfileArchiveReason.expired,
    );
  });

  test('余额调整同时更新当前余额与余额流水', () async {
    final controller = AppController.inMemory(museumAutoArchiveDays: null);
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final now = DateTime.now().toUtc();
    final subscription = Subscription(
      id: 'profile-balance',
      number: const PhoneNumber.unknown(),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      details: const SubscriptionDetails(
        currentBalance: Money(minorUnits: 1000, currencyCode: 'GBP'),
      ),
      timeZoneId: 'UTC',
      createdAt: now,
      updatedAt: now,
    );
    expect(await controller.saveSubscription(subscription), isNull);

    expect(
      await controller.updateBalance(
        subscription: controller.subscriptions.single,
        balance: const Money(minorUnits: 725, currencyCode: 'GBP'),
        note: '购买套餐',
      ),
      isNull,
    );

    expect(
      controller.subscriptions.single.details.currentBalance,
      const Money(minorUnits: 725, currencyCode: 'GBP'),
    );
    final activity = controller.activities.single;
    expect(activity.type, ActivityType.balanceChange);
    expect(activity.amount, const Money(minorUnits: -275, currencyCode: 'GBP'));
    expect(
      activity.balanceAfter,
      const Money(minorUnits: 725, currencyCode: 'GBP'),
    );
    expect(activity.note, '购买套餐');
  });

  test('首页派生列表和按 Profile 活动查询复用 reload 后的缓存', () async {
    final controller = AppController.inMemory(museumAutoArchiveDays: null);
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final now = DateTime.now().toUtc();
    final subscription = Subscription(
      id: 'cached-profile',
      number: const PhoneNumber.unknown(),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'UTC',
      createdAt: now,
      updatedAt: now,
    );
    expect(await controller.saveSubscription(subscription), isNull);
    expect(
      await controller.recordActivity(
        subscription: controller.subscriptions.single,
        type: ActivityType.mobileData,
        occurredAt: now.subtract(const Duration(days: 1)),
      ),
      isNull,
    );
    expect(
      await controller.recordActivity(
        subscription: controller.subscriptions.single,
        type: ActivityType.call,
        occurredAt: now,
      ),
      isNull,
    );

    expect(identical(controller.subscriptions, controller.subscriptions), true);
    expect(identical(controller.activities, controller.activities), true);
    expect(identical(controller.homeActions, controller.homeActions), true);
    final activities = controller.activitiesFor(subscription.id);
    expect(
      identical(activities, controller.activitiesFor(subscription.id)),
      true,
    );
    expect(activities.map((item) => item.type), [
      ActivityType.call,
      ActivityType.mobileData,
    ]);
  });
}

class _FakeNotifications implements ReminderNotificationGateway {
  List<Subscription> lastSubscriptions = const [];
  int cancelCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> replaceAll(List<Subscription> subscriptions) async {
    lastSubscriptions = List.of(subscriptions);
  }

  @override
  Future<void> cancelAll() async => cancelCount++;

  @override
  Stream<String> get selectedSubscriptionIds => const Stream.empty();

  @override
  Future<String?> initialSubscriptionId() async => null;

  @override
  void dispose() {}
}

class _FakeWebDavGateway implements WebDavGateway {
  _FakeWebDavGateway(this.configuration);

  WebDavConfiguration? configuration;
  int clearCount = 0;

  @override
  Future<WebDavConfiguration?> loadConfiguration() async => configuration;

  @override
  Future<void> saveConfiguration(WebDavConfiguration configuration) async {
    this.configuration = configuration;
  }

  @override
  Future<void> clearConfiguration() async {
    clearCount++;
    configuration = null;
  }

  @override
  Future<Result<void>> testConnection(
    WebDavConfiguration configuration,
  ) async => const Ok(null);

  @override
  Future<Result<SyncRunReport>> sync(WebDavConfiguration configuration) async =>
      const Err(NetworkError('测试未实现同步'));

  @override
  Result<List<SyncConflictLog>> listConflicts() => const Ok([]);

  @override
  Result<SyncState> readState() => const Ok(SyncState());
}
