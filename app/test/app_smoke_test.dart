import 'package:flutter/material.dart' hide KeepAlive;
import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/app/app_scope.dart';
import 'package:iesim/pages/subscription_form_page.dart';
import 'package:iesim/services/carrier_network_catalog_service.dart';
import 'package:iesim/main.dart';
import 'package:iesim/data/app_controller.dart';
import 'package:iesim_core/iesim_core.dart';

void main() {
  testWidgets('ieSIM 首页适配窄屏且可切换深色模式', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'Asia/Shanghai');
    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('ieSIM'), findsOneWidget);
    expect(find.text('本地优先'), findsOneWidget);
    expect(find.text('添加 Profile'), findsOneWidget);
    expect(find.text('外部数据'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(find.text('ieSIM 数据属于你'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空状态可进入新增订阅表单', (tester) async {
    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'Asia/Shanghai');

    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('ieSIM'), findsOneWidget);
    expect(find.text('从第一张 SIM 开始'), findsOneWidget);
    expect(find.text('外部数据'), findsOneWidget);

    final addButton = find.widgetWithText(FilledButton, '添加 Profile');
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(find.text('二维码 / LPA 识别'), findsOneWidget);
    expect(find.text('添加 Profile'), findsOneWidget);
    expect(find.text('卡片与 EID'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(find.text('基础信息'), findsOneWidget);
    expect(find.text('国家/地区'), findsOneWidget);
    expect(find.text('先选择'), findsOneWidget);
    expect(find.text('选择或自定义'), findsOneWidget);
    expect(find.textContaining('MCC-MNC.net'), findsOneWidget);
    expect(find.textContaining('Android Open Source Project'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(find.text('保号策略'), findsOneWidget);
  });

  testWidgets('新建 Profile 时手机号码可以留空', (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'Asia/Shanghai');
    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加 Profile'));
    await tester.pumpAndSettle();
    expect(find.text('手机号码（可选）'), findsOneWidget);
    final operatorField = find.ancestor(
      of: find.text('运营商'),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(operatorField, 'Data Only');
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('Data Only'), findsOneWidget);
    expect(find.text('未分配号码'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选国家可按国际区号搜索并自动填入，运营商可自定义', (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController.inMemory();
    addTearDown(controller.dispose);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          home: SubscriptionFormPage(
            networkCatalog: _FixedCarrierNetworkCatalogService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final countryButton = find.text('国家/地区');
    await tester.tap(countryButton);
    await tester.pumpAndSettle();
    expect(find.text('搜索国家名称、ISO 代码或国际区号'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '+44');
    await tester.pumpAndSettle();
    await tester.tap(find.text('United Kingdom'));
    await tester.pumpAndSettle();

    final phoneFieldFinder = find.ancestor(
      of: find.text('手机号码（可选）'),
      matching: find.byType(TextFormField),
    );
    final phoneField = tester.widget<TextFormField>(phoneFieldFinder);
    expect(phoneField.controller?.text, '+44 ');

    await tester.tap(find.text('选择或自定义'));
    await tester.pumpAndSettle();
    expect(find.text('数据库中没有？自定义运营商'), findsOneWidget);
    await tester.tap(find.text('数据库中没有？自定义运营商'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已切换为自定义'), findsOneWidget);
    final operatorFieldFinder = find.ancestor(
      of: find.text('运营商'),
      matching: find.byType(TextFormField),
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: operatorFieldFinder,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(controller.subscriptions, hasLength(1));
    expect(controller.subscriptions.single.number.isUnknown, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新建 Profile 先选卡片再选该卡片的 EID', (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'UTC');
    final now = DateTime.utc(2026, 8, 8);
    final personalCard = RemovableEuiccCard(
      id: 'personal-card',
      name: '个人 eUICC',
      createdAt: now,
      updatedAt: now,
    );
    final workCard = RemovableEuiccCard(
      id: 'work-card',
      name: '工作 eUICC',
      createdAt: now,
      updatedAt: now,
    );
    expect(await controller.saveCard(personalCard), isNull);
    expect(await controller.saveCard(workCard), isNull);
    expect(
      await controller.saveEid(
        Euicc(
          id: 'personal-eid',
          cardId: personalCard.id,
          value: '89000000000000000000000000000001',
          label: '个人 EID',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      isNull,
    );
    expect(
      await controller.saveEid(
        Euicc(
          id: 'work-eid',
          cardId: workCard.id,
          value: '89000000000000000000000000000002',
          label: '工作 EID',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      isNull,
    );
    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加 Profile'));
    await tester.pumpAndSettle();
    expect(find.text('卡片与 EID'), findsOneWidget);
    expect(find.text('请先选择卡片'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-card-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('工作 eUICC').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-eid-work-card-null')));
    await tester.pumpAndSettle();
    expect(find.textContaining('工作 EID'), findsOneWidget);
    expect(find.textContaining('个人 EID'), findsNothing);
    await tester.tap(find.textContaining('工作 EID').last);
    await tester.pumpAndSettle();
    final operatorField = find.ancestor(
      of: find.text('运营商'),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(operatorField, '工作测试运营商');
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(controller.subscriptions, hasLength(1));
    expect(controller.assets.profiles, hasLength(1));
    expect(controller.assets.profiles.single.eidId, 'work-eid');
    expect(
      controller.assets.profiles.single.subscriptionId,
      controller.subscriptions.single.id,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('未关联号码的 Nekoko Profile 会直接显示在首页', (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'Europe/London');
    final now = DateTime.utc(2026, 8, 8);
    expect(
      await controller.saveCard(
        RemovableEuiccCard(
          id: 'nekoko-card:eid-1',
          name: 'CTExcel eUICC',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      isNull,
    );
    expect(
      await controller.saveEid(
        Euicc(
          id: 'nekoko-eid:eid-1',
          cardId: 'nekoko-card:eid-1',
          value: '89049032000000000000000000000001',
          label: 'CTExcel',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      isNull,
    );
    expect(
      await controller.saveProfile(
        EsimProfile(
          id: 'nekoko-profile:8944304253496424814f',
          eidId: 'nekoko-eid:eid-1',
          iccid: '8944304253496424814f',
          operatorName: 'CTExcel',
          nickname: 'CTExcel eSIM t:+44_7726_751499',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      isNull,
    );

    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('已激活 Profile'), findsOneWidget);
    expect(find.text('CTExcel eSIM'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('+44_7726_751499'), findsOneWidget);
    expect(find.text('从第一个 Profile 开始'), findsNothing);

    await tester.ensureVisible(find.text('CTExcel eSIM'));
    await tester.tap(find.text('CTExcel eSIM'));
    await tester.pumpAndSettle();
    expect(find.text('8944304253496424814f'), findsOneWidget);
    expect(find.text('Nekoko 标签'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('原生 Profile 名称在首页展示并可用标准编辑器修改', (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'Europe/Berlin');
    final now = DateTime.utc(2026, 8, 8);
    expect(
      await controller.saveSubscription(
        Subscription(
          id: 'imported-native-profile',
          iccid: '8986001234567890001',
          number: const PhoneNumber.unknown(),
          operator: 'Carrier A',
          plan: Plan(),
          keepAlive: KeepAlive.notRequired(),
          details: const SubscriptionDetails(
            profileName: '欧洲旅行 Profile',
            profileClassCode: 2,
            installedProfileSizeBytes: 63200,
            gid1: '01',
          ),
          timeZoneId: 'Europe/Berlin',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      isNull,
    );

    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('欧洲旅行 Profile'), findsOneWidget);
    expect(find.text('未分配号码'), findsNothing);

    await tester.tap(find.text('欧洲旅行 Profile'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(find.text('Profile 类别代码'), findsOneWidget);
    expect(find.textContaining('实际占用 62 KiB'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();

    final profileNameField = find.ancestor(
      of: find.text('Profile 名称（可选）'),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(profileNameField);
    await tester.enterText(profileNameField, '英国主号');
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(controller.subscriptions.single.details.profileName, '英国主号');
    expect(find.text('英国主号'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手动填写页顶部可进入二维码与 LPA 识别', (tester) async {
    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'Asia/Shanghai');
    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加 Profile'));
    await tester.pumpAndSettle();
    expect(find.text('二维码 / LPA 识别'), findsOneWidget);

    await tester.tap(find.text('二维码 / LPA 识别'));
    await tester.pumpAndSettle();
    expect(find.text('扫码导入'), findsOneWidget);
    expect(find.text('粘贴 LPA'), findsOneWidget);
    expect(find.text('导入 JSON'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页按三类 Profile 分组，未激活项可执行激活', (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController.inMemory(museumAutoArchiveDays: null);
    await controller.initialize(defaultTimeZoneId: 'UTC');
    expect(await controller.addDeveloperTestData(), isNull);
    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('已激活 1'), findsOneWidget);
    expect(find.text('未激活 1'), findsOneWidget);
    expect(find.text('过期博物馆 1'), findsOneWidget);

    await tester.tap(find.text('未激活 1'));
    await tester.pumpAndSettle();
    expect(find.text('旅行数据 eSIM（测试）'), findsOneWidget);
    await tester.tap(find.text('旅行数据 eSIM（测试）'));
    await tester.pumpAndSettle();
    expect(find.text('未激活 Profile'), findsOneWidget);
    expect(find.text('标记为已激活'), findsOneWidget);
    expect(find.textContaining('购买后 180 天内激活'), findsOneWidget);

    await tester.tap(find.text('标记为已激活'));
    await tester.pumpAndSettle();
    expect(find.text('已激活 Profile'), findsOneWidget);
    expect(
      controller.subscriptionById('developer-sample-travel')!.lifecycle.stage,
      ProfileStage.active,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('数据交换顶层只显示导入和导出两个主入口', (tester) async {
    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'Asia/Shanghai');
    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('外部数据'));
    await tester.pumpAndSettle();
    expect(find.text('导入数据'), findsOneWidget);
    expect(find.text('导出数据'), findsOneWidget);
    expect(find.textContaining('Nekoko'), findsNothing);
    expect(find.textContaining('SimHub'), findsNothing);
    expect(find.text('二维码 / LPA 导入'), findsNothing);

    await tester.tap(find.text('导入数据'));
    await tester.pumpAndSettle();
    expect(find.text('选择导入来源'), findsOneWidget);
    expect(find.text('二维码 / LPA'), findsOneWidget);
    expect(find.text('ieSIM / SimHub / SimJ JSON'), findsOneWidget);
    expect(find.text('Nekoko 数据库'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页可进入 WebDAV 与本地通知完整配置页', (tester) async {
    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'Asia/Shanghai');
    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('数据与互操作'), findsOneWidget);

    final webDav = find.text('WebDAV 同步');
    await tester.drag(find.byType(ListView).last, const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(webDav);
    await tester.pumpAndSettle();
    expect(find.text('连接你的 WebDAV'), findsOneWidget);
    expect(find.text('同步安全'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final notifications = find.text('本地通知');
    await tester.ensureVisible(notifications);
    await tester.tap(notifications);
    await tester.pumpAndSettle();
    expect(find.text('提醒节奏'), findsOneWidget);
    expect(find.text('可靠性与隐私'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页可选择 Profile 到期后的自动归档时间', (tester) async {
    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'UTC');
    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('过期博物馆'));
    await tester.pumpAndSettle();
    expect(find.text('Profile 生命周期'), findsOneWidget);
    expect(find.text('到期 90 天后（推荐）'), findsOneWidget);
    expect(find.text('永不自动归档'), findsOneWidget);
    await tester.tap(find.text('到期 30 天后'));
    await tester.pumpAndSettle();
    expect(controller.museumAutoArchiveDays, 30);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页展示带推广披露的内置 AFF 推荐', (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'UTC');
    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    final recommendations = find.text('优惠与推荐');
    await tester.ensureVisible(recommendations);
    await tester.tap(recommendations);
    await tester.pumpAndSettle();

    expect(find.text('推广 / 推荐披露'), findsOneWidget);
    expect(find.text('9eSIM'), findsOneWidget);
    expect(find.text('优惠码  yeats2'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('CTExcel UK'), findsOneWidget);
    expect(find.text('优惠码  RNAFZW'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开发者模式需密码并提供清空与测试数据', (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'UTC');
    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开发者模式'));
    await tester.pumpAndSettle();

    expect(find.text('进入开发者模式'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();
    expect(find.text('密码不正确'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'yeats33');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();
    expect(find.text('仅用于测试设备'), findsOneWidget);
    expect(find.text('添加测试数据'), findsOneWidget);
    expect(find.text('清空数据'), findsOneWidget);
    await tester.ensureVisible(find.text('清空数据'));
    await tester.tap(find.text('清空数据'));
    await tester.pumpAndSettle();

    expect(find.text('选择要清空的数据'), findsOneWidget);
    expect(find.text('Profile 与业务记录'), findsOneWidget);
    expect(find.text('设备资产'), findsOneWidget);
    expect(find.text('WebDAV 本地配置（默认保留）'), findsOneWidget);
    final dialogCheckboxes = tester
        .widgetList<Checkbox>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Checkbox),
          ),
        )
        .map((checkbox) => checkbox.value)
        .toList();
    expect(dialogCheckboxes, [true, true, false]);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('资产页可进入设备建档表单', (tester) async {
    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'Asia/Shanghai');
    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();
    expect(find.text('设备空间'), findsOneWidget);
    expect(find.text('还没有设备'), findsOneWidget);
    final add = find.widgetWithText(FilledButton, '添加设备');
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('设备名称 *'), findsOneWidget);
    expect(find.text('SIM 能力'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('内置 eSIM 以不可拆卸的卡槽加卡片组合显示', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'Asia/Shanghai');
    final now = DateTime.utc(2026, 8, 8);
    expect(
      await controller.saveDevice(
        DeviceAsset(
          id: 'phone-1',
          name: '测试手机',
          simCapability: SimCapability.esimOnly,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      isNull,
    );
    final card = EmbeddedEuiccCard(
      id: 'embedded-card-1',
      name: '内置 eUICC',
      embeddedDeviceId: 'phone-1',
      createdAt: now,
      updatedAt: now,
    );
    expect(
      await controller.createEmbeddedEuicc(
        card: card,
        eid: Euicc(
          id: 'eid-1',
          cardId: card.id,
          value: '89049032000000000000000000000001',
          createdAt: now,
          updatedAt: now,
        ),
        slot: SimSlot(
          id: 'embedded-slot-1',
          deviceId: 'phone-1',
          label: '内置 eSIM',
          kind: SimSlotKind.embeddedEuicc,
          position: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      isNull,
    );

    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试手机'));
    await tester.pumpAndSettle();

    expect(find.text('内置 eUICC · 不可拆卸'), findsOneWidget);
    expect(find.text('物理卡可更换；内置 eSIM 是卡槽与不可拆 eUICC 的组合'), findsOneWidget);
    await tester.tap(find.text('内置 eSIM'));
    await tester.pumpAndSettle();

    expect(find.text('安装方式'), findsOneWidget);
    expect(find.text('与设备永久绑定，不可移出或换卡'), findsOneWidget);
    expect(find.byTooltip('编辑卡片'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _FixedCarrierNetworkCatalogService extends CarrierNetworkCatalogService {
  @override
  Future<CarrierNetworkCatalogLoadResult> load() async =>
      CarrierNetworkCatalogLoadResult(
        source: CarrierNetworkCatalogSource.builtIn,
        catalog: CarrierNetworkCatalog([
          const CarrierNetwork(
            countryCode: 'GB',
            countryName: 'United Kingdom',
            flag: '🇬🇧',
            mcc: '234',
            mnc: '15',
            operatorName: 'Vodafone Limited',
            brand: 'Vodafone',
            bands: '',
            apns: [],
          ),
        ]),
      );
}
