import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/app/brand.dart';
import 'package:iesim/data/app_controller.dart';
import 'package:iesim/main.dart';

void main() {
  test('作者联系方式与四种捐赠地址保持完整', () {
    expect(AppAuthor.githubName, 'Yeats33');
    expect(AppAuthor.telegramName, '@yeatssang');
    expect(AppAuthor.telegramPhone, '+372 57633333');
    expect(AppAuthor.evmAddress, '0x00000073a2c5581b9ea3d79261a567571Dd14E31');
    expect(
      AppAuthor.solanaAddress,
      'Efs8EFAeizs4naJZPdQVvNjhEAgRTYcfEQsXZaLpR43J',
    );
    expect(
      AppAuthor.bitcoinAddress,
      'bc1pu0hvdm7sk09av8e6uus08rzwy3xx5gna494aatqwlkp44a3sm3vqjgseue',
    );
    expect(AppAuthor.tronAddress, 'THvESTrXgkWXSBZhoF66wrULcX3LTCnrDJ');
  });

  testWidgets('设置页展示作者联系方式并可复制捐赠地址', (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final controller = AppController.inMemory();
    await controller.initialize(defaultTimeZoneId: 'UTC');

    await tester.pumpWidget(IesimApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('联系作者'), findsOneWidget);
    expect(find.text('GitHub · Yeats33'), findsOneWidget);
    expect(find.text('Telegram · @yeatssang'), findsOneWidget);
    expect(find.text('+372 57633333'), findsOneWidget);
    expect(find.text('支持开发'), findsOneWidget);
    expect(find.text('EVM'), findsOneWidget);
    expect(find.text('Solana'), findsOneWidget);
    expect(find.text('Bitcoin'), findsOneWidget);
    expect(find.text('TRON'), findsOneWidget);

    final copyEvm = find.byTooltip('复制 EVM 地址');
    await tester.ensureVisible(copyEvm);
    await tester.pumpAndSettle();
    await tester.tap(copyEvm);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已复制 EVM 地址'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
