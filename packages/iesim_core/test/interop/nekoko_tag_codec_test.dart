import 'package:iesim_core/iesim_core.dart';
import 'package:test/test.dart';

void main() {
  test('文本与日期标签转义后可完整往返', () {
    final tags = <NekokoTag>[
      NekokoTextTag('旅行 卡:主卡'),
      NekokoDateTag(date: DateTime.utc(2026, 8, 8), note: '充值 日:上午'),
    ];

    final encoded = NekokoTagCodec.encode(tags);
    expect(encoded, contains('\x11'));
    expect(encoded, contains('\x03'));
    expect(encoded, contains('\x0A'));
    final decoded = NekokoTagCodec.decode(encoded);

    expect(decoded.tags, tags);
    expect(decoded.issues, isEmpty);
  });

  test('同时兼容 YYMMDD 与 YYYYMMDD 日期', () {
    final decoded = NekokoTagCodec.decode('d:260808\x0Ad:20270809:到期');
    expect(decoded.tags, [
      NekokoDateTag(date: DateTime.utc(2026, 8, 8)),
      NekokoDateTag(date: DateTime.utc(2027, 8, 9), note: '到期'),
    ]);
  });

  test('从普通 nickname 中提取标签', () {
    final decoded = NekokoTagCodec.decode('China Mobile t:旅行\x11卡 d:260808:续费');
    expect(decoded.tags, [
      NekokoTextTag('旅行 卡'),
      NekokoDateTag(date: DateTime.utc(2026, 8, 8), note: '续费'),
    ]);
  });

  test('replaceTags 保留普通昵称并替换旧标签', () {
    final replaced = NekokoTagCodec.replaceTags('Main Profile t:旧标签', [
      NekokoTextTag('新 标签'),
    ]);
    expect(replaced, 'Main Profile\x0At:新\x11标签');
  });

  test('畸形日期进入 issues，其余标签继续解析', () {
    final result = NekokoTagCodec.decode('d:260230\x0At:正常');
    expect(result.tags, [NekokoTextTag('正常')]);
    expect(result.issues, hasLength(1));
  });

  test('日期标签拒绝携带时刻的 DateTime', () {
    expect(
      () => NekokoDateTag(date: DateTime.utc(2026, 8, 8, 1)),
      throwsArgumentError,
    );
  });
}
