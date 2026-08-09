import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/app_binding_preset_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('内置目录包含 WhatsApp 的双平台标识和接码方式', () {
    final preset = AppBindingPresetService.builtInCatalog.apps.singleWhere(
      (item) => item.id == 'whatsapp',
    );

    expect(preset.appStoreId, '310633997');
    expect(preset.googlePlayPackage, 'com.whatsapp');
    expect(preset.verificationChannels.map((item) => item.name), [
      'sms',
      'voiceCall',
    ]);
    expect(preset.verificationNote, contains('不读取验证码'));
  });

  test('下载成功后缓存，304 时通过 ETag 复用目录', () async {
    final first = _FakeTransport([
      AppBindingPresetResponse(
        statusCode: 200,
        body: AppBindingPresetService.builtInCatalog.encode(),
        etag: '"apps-1"',
      ),
    ]);
    final downloaded = await AppBindingPresetService(
      sourceUri: Uri.parse('https://example.com/apps.json'),
      transport: first,
    ).load();
    expect(downloaded.source, AppBindingPresetSource.network);

    final second = _FakeTransport([
      const AppBindingPresetResponse(statusCode: 304),
    ]);
    final cached = await AppBindingPresetService(
      sourceUri: Uri.parse('https://example.com/apps.json'),
      transport: second,
    ).load();
    expect(second.receivedEtag, '"apps-1"');
    expect(cached.source, AppBindingPresetSource.cache);
    expect(cached.catalog.apps.single.id, 'whatsapp');
  });

  test('远端不可用且无缓存时回退到内置目录', () async {
    final result = await AppBindingPresetService(
      sourceUri: Uri.parse('https://example.com/apps.json'),
      transport: _FailingTransport(),
    ).load();

    expect(result.source, AppBindingPresetSource.builtIn);
    expect(result.catalog.apps.single.id, 'whatsapp');
    expect(result.warning, isNotNull);
  });
}

class _FakeTransport implements AppBindingPresetTransport {
  _FakeTransport(this.responses);

  final List<AppBindingPresetResponse> responses;
  String? receivedEtag;

  @override
  Future<AppBindingPresetResponse> get(Uri uri, {String? etag}) async {
    receivedEtag = etag;
    return responses.removeAt(0);
  }
}

class _FailingTransport implements AppBindingPresetTransport {
  @override
  Future<AppBindingPresetResponse> get(Uri uri, {String? etag}) {
    throw const FormatException('offline');
  }
}
