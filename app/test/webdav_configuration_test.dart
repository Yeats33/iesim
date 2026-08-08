import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/webdav_service.dart';

void main() {
  test('WebDAV 目录统一补斜杠并固定单快照文件名', () {
    const configuration = WebDavConfiguration(
      directoryUrl: 'https://dav.example.com/user/iesim',
      username: 'user',
      password: 'secret',
    );
    expect(
      configuration.directoryUri.toString(),
      'https://dav.example.com/user/iesim/',
    );
    expect(
      configuration.snapshotUri.toString(),
      'https://dav.example.com/user/iesim/iesim-v1.json',
    );
  });

  test('拒绝缺少主机或含查询参数的目录地址', () {
    expect(
      () => const WebDavConfiguration(
        directoryUrl: 'not-a-url',
        username: 'u',
        password: 'p',
      ).directoryUri,
      throwsFormatException,
    );
    expect(
      () => const WebDavConfiguration(
        directoryUrl: 'https://dav.example.com/path?token=x',
        username: 'u',
        password: 'p',
      ).directoryUri,
      throwsFormatException,
    );
    expect(
      () => const WebDavConfiguration(
        directoryUrl: 'http://dav.example.com/path',
        username: 'u',
        password: 'p',
      ).directoryUri,
      throwsFormatException,
    );
  });
}
