import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  test('解析标准 LPA 二维码并生成规范格式', () {
    final activation = LpaActivation.parse(
      r'LPA:1$SMDP.Example.COM$MATCH-1234',
    );

    expect(activation.smdpAddress, 'smdp.example.com');
    expect(activation.matchingId, 'MATCH-1234');
    expect(activation.encoded, r'LPA:1$smdp.example.com$MATCH-1234');
    expect(activation.redactedMatchingId, '••••1234');
  });

  test(r'接受 URL carddata 与 bare 1$ 格式', () {
    final fromUrl = LpaActivation.parse(
      'https://example.com/install?carddata='
      '${Uri.encodeQueryComponent(r'LPA:1$rsp.example.com$ABCDEF')}',
    );
    final bare = LpaActivation.parse(r'1$rsp.example.com$ABCDEF');

    expect(fromUrl, bare);
  });

  test('保留 SM-DP+ OID 与确认码要求标志', () {
    final activation = LpaActivation.parse(
      r'LPA:1$smdp.gsma.com$MATCH$1.3.6.1.4.1.31746$1',
    );

    expect(activation.smdpOid, '1.3.6.1.4.1.31746');
    expect(activation.confirmationCodeRequired, isTrue);
    expect(
      activation.encoded,
      r'LPA:1$smdp.gsma.com$MATCH$1.3.6.1.4.1.31746$1',
    );
  });

  test('有 SM-DP+ OID 时允许空 Matching ID', () {
    final activation = LpaActivation.parse(
      r'LPA:1$smdp.gsma.com$$1.3.6.1.4.1.31746',
    );

    expect(activation.matchingId, isEmpty);
    expect(activation.redactedMatchingId, '未提供');
  });

  test('确认码不同仍识别为同一下载凭据', () {
    final withoutConfirmation = LpaActivation(
      smdpAddress: 'rsp.example.com',
      matchingId: 'MATCH',
    );
    final withConfirmation = LpaActivation(
      smdpAddress: 'rsp.example.com',
      matchingId: 'MATCH',
      confirmationCode: '123456',
    );

    expect(withoutConfirmation, isNot(withConfirmation));
    expect(withoutConfirmation.hasSameDownloadKey(withConfirmation), isTrue);
  });

  test('toString 不泄露完整 Matching ID', () {
    final activation = LpaActivation.parse(
      r'LPA:1$rsp.example.com$SECRET-CREDENTIAL',
    );

    expect(activation.toString(), isNot(contains('SECRET-CREDENTIAL')));
    expect(activation.toString(), contains('TIAL'));
  });

  test('拒绝路径、缺字段与空白 Matching ID', () {
    expect(
      () => LpaActivation.parse(r'LPA:1$example.com/path$CODE'),
      throwsArgumentError,
    );
    expect(
      () => LpaActivation.parse(r'LPA:1$example.com'),
      throwsFormatException,
    );
    expect(
      () => LpaActivation.parse(r'LPA:1$example.com$'),
      throwsArgumentError,
    );
  });
}
