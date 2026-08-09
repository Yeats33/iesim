import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  const source = '''
{
  "schemaVersion": 1,
  "catalogVersion": "2026.08.09.1",
  "updatedAt": "2026-08-09T00:00:00.000Z",
  "apps": [{
    "id": "whatsapp",
    "displayName": "WhatsApp Messenger",
    "developerName": "WhatsApp LLC",
    "description": "手机号消息与通话应用",
    "websiteUrl": "https://www.whatsapp.com/",
    "iconUrl": "https://example.com/whatsapp.png",
    "aliases": ["WA"],
    "defaultPurposes": ["messaging", "verification"],
    "verificationChannels": ["sms", "voiceCall"],
    "verificationNote": "仅记录验证状态",
    "appStore": {
      "appId": "310633997",
      "bundleId": "net.whatsapp.WhatsApp",
      "url": "https://apps.apple.com/app/id310633997"
    },
    "googlePlay": {
      "packageName": "com.whatsapp",
      "url": "https://play.google.com/store/apps/details?id=com.whatsapp"
    }
  }]
}
''';

  test('解析、按别名和包名搜索并稳定往返', () {
    final catalog = AppBindingPresetCatalog.decode(source);
    final byAlias = catalog.search('WA').single;
    final byPackage = catalog.search('com.whatsapp').single;

    expect(byAlias.id, 'whatsapp');
    expect(byPackage.appStoreId, '310633997');
    expect(
      byPackage.verificationChannels,
      containsAll([
        PhoneVerificationChannel.sms,
        PhoneVerificationChannel.voiceCall,
      ]),
    );
    expect(
      AppBindingPresetCatalog.decode(catalog.encode()).encode(),
      catalog.encode(),
    );
  });

  test('拒绝非 HTTPS 图标和未知用途', () {
    expect(
      () => AppBindingPresetCatalog.decode(
        source.replaceFirst(
          'https://example.com/whatsapp.png',
          'http://example.com/whatsapp.png',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => AppBindingPresetCatalog.decode(
        source.replaceFirst('"messaging"', '"unsupported"'),
      ),
      throwsFormatException,
    );
  });

  test('允许只在一个应用商店上架的 App 预设', () {
    final iosOnly = source.replaceFirst(
      RegExp(r',\s*"googlePlay": \{[^}]+\}', multiLine: true),
      '',
    );
    final preset = AppBindingPresetCatalog.decode(iosOnly).apps.single;

    expect(preset.appStoreId, '310633997');
    expect(preset.googlePlayPackage, isNull);
  });
}
