import 'dart:io';

import 'package:iesim_core/iesim_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('只读解析 Nekoko 数据库并建立 EID、Profile 与号码关系', () {
    final directory = Directory.systemTemp.createTempSync('iesim-nekoko-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/backup.db';
    final database = sqlite3.open(path);
    database.execute('''
CREATE TABLE profile_metadata (
  iccid TEXT PRIMARY KEY,
  nickname TEXT,
  name TEXT,
  providerName TEXT,
  mcc TEXT,
  mnc TEXT,
  enabled INTEGER,
  profileClass INTEGER,
  profileSize INTEGER,
  gid1 TEXT,
  gid2 TEXT,
  tags TEXT,
  lastSeen INTEGER,
  eid TEXT
);
CREATE TABLE profile_msisdn (iccid TEXT PRIMARY KEY, msisdn TEXT);
CREATE TABLE profile_storage (
  eid TEXT,
  iccid TEXT,
  spaceConsumed INTEGER,
  version INTEGER
);
INSERT INTO profile_metadata VALUES
  ('8986001', '旅行卡 t:欧洲 d:260901:到期', 'Travel', 'Carrier A', '262', '01', 1, 2, 48000, '01', '02', 't:备用', 1786060800000, '8900001'),
  ('8986002', '无 EID', 'Local', 'Carrier B', '460', '00', 0, 2, NULL, NULL, NULL, '', 1786060800000, NULL);
INSERT INTO profile_msisdn VALUES ('8986001', '+4912345');
INSERT INTO profile_storage VALUES ('8900001', '8986001', 63200, 1);
''');
    database.close();

    var nextId = 0;
    final result = NekokoDatabaseCodec(
      idFactory: () => 'sub-${nextId++}',
      nowUtc: () => DateTime.utc(2026, 8, 8),
    ).inspectFile(path, defaultTimeZoneId: 'Europe/Berlin');

    expect(result, isA<Ok<NekokoImportReport>>());
    final report = (result as Ok<NekokoImportReport>).value;
    expect(report.sourceProfileCount, 2);
    expect(report.subscriptions, hasLength(2));
    final numbered = report.subscriptions.firstWhere(
      (item) => item.iccid == '8986001',
    );
    final numberless = report.subscriptions.firstWhere(
      (item) => item.iccid == '8986002',
    );
    expect(numbered.number.value, '+4912345');
    expect(numbered.tags, containsAll(['欧洲', '备用']));
    expect(numbered.tags, isNot(contains('Nekoko导入')));
    expect(numbered.details.profileName, '旅行卡');
    expect(numbered.details.profileClassCode, 2);
    expect(numbered.details.declaredProfileSizeBytes, 48000);
    expect(numbered.details.installedProfileSizeBytes, 63200);
    expect(numbered.details.gid1, '01');
    expect(numbered.details.gid2, '02');
    expect(numbered.lifecycle.deviceState, ProfileDeviceState.enabled);
    expect(numbered.details.mcc, '262');
    expect(numbered.details.mnc, '01');
    expect(numberless.number.isUnknown, isTrue);
    expect(numberless.details.profileName, '无 EID');
    expect(numberless.lifecycle.deviceState, ProfileDeviceState.disabled);
    expect(report.assets.cards, hasLength(1));
    expect(report.assets.eids.single.value, '8900001');
    expect(report.assets.profiles.single.iccid, '8986001');
    expect(report.assets.profiles.single.subscriptionId, numbered.id);
    expect(report.issues.single.message, contains('缺少 EID'));
  });

  test('已有 ICCID 和 EID 时更新关系而不重复创建硬件', () {
    final directory = Directory.systemTemp.createTempSync('iesim-nekoko-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/backup.db';
    final database = sqlite3.open(path);
    database.execute('''
CREATE TABLE profile_metadata (
  iccid TEXT PRIMARY KEY,
  nickname TEXT,
  providerName TEXT,
  lastSeen INTEGER,
  eid TEXT
);
INSERT INTO profile_metadata VALUES
  ('8986001', '新昵称 t:新标签', '新运营商', 1786060800000, '8900001');
''');
    database.close();
    final old = DateTime.utc(2026, 1, 1);
    final subscription = Subscription(
      id: 'sub-existing',
      iccid: '8986001',
      number: PhoneNumber('+4912345'),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      tags: const ['旧标签'],
      timeZoneId: 'Europe/Berlin',
      createdAt: old,
      updatedAt: old,
    );
    final card = RemovableEuiccCard(
      id: 'card-existing',
      name: 'eUICC',
      createdAt: old,
      updatedAt: old,
    );
    final eid = Euicc(
      id: 'eid-existing',
      cardId: card.id,
      value: '8900001',
      createdAt: old,
      updatedAt: old,
    );
    final profile = EsimProfile(
      id: 'profile-existing',
      eidId: eid.id,
      iccid: '8986001',
      subscriptionId: subscription.id,
      createdAt: old,
      updatedAt: old,
    );

    final report =
        (NekokoDatabaseCodec().inspectFile(
                  path,
                  defaultTimeZoneId: 'Europe/Berlin',
                  existingSubscriptions: [subscription],
                  existingAssets: AssetInventory(
                    cards: [card],
                    eids: [eid],
                    profiles: [profile],
                  ),
                )
                as Ok<NekokoImportReport>)
            .value;
    expect(report.assets.cards, isEmpty);
    expect(report.assets.eids, isEmpty);
    expect(report.assets.profiles.single.id, 'profile-existing');
    expect(report.assets.profiles.single.nickname, contains('新昵称'));
    expect(report.subscriptions.single.tags, containsAll(['旧标签', '新标签']));
    expect(report.subscriptions.single.details.profileName, '新昵称');
  });
}
