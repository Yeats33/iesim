import 'package:flutter_test/flutter_test.dart';
import 'package:iesim/services/import_merge_service.dart';
import 'package:iesim_core/iesim_core.dart';

void main() {
  test('ICCID 强匹配默认合并，保留本地值并补全空字段', () {
    final local = _subscription(
      id: 'local-id',
      iccid: '8900-1',
      number: '10086',
      tags: const ['本地'],
    );
    final incoming = _subscription(
      id: 'incoming-id',
      iccid: '8900-1',
      number: '10010',
      operator: '导入运营商',
      tags: const ['导入'],
      activation: LpaActivation(
        smdpAddress: 'rsp.example.test',
        matchingId: 'MATCH-ID',
      ),
    );
    final planner = ImportMergePlanner(
      existingSubscriptions: [local],
      existingAssets: AssetInventory(),
    );
    final plan = planner.inspect([incoming]);

    expect(plan.candidates.single.matchKind, ImportMatchKind.iccid);
    expect(plan.candidates.single.defaultAction, ImportMergeAction.merge);
    expect(
      plan.candidates.single.diffs.map((item) => item.key),
      containsAll(['number', 'operator', 'tags', 'activation']),
    );

    final report = planner.resolveSimHub(
      report: SimHubImportReport(
        subscriptions: [incoming],
        activityRecords: [
          ActivityRecord(
            id: 'activity-1',
            subscriptionId: incoming.id,
            type: ActivityType.topUp,
            occurredAt: DateTime.utc(2026, 8, 9),
          ),
        ],
        issues: const [],
        sourceRecordCount: 1,
      ),
      plan: plan,
      actions: plan.defaultActions,
      nowUtc: DateTime.utc(2026, 8, 10),
    );
    final merged = report.subscriptions.single;
    expect(merged.id, local.id);
    expect(merged.number.value, '10086');
    expect(merged.operator, '导入运营商');
    expect(merged.tags, containsAll(['本地', '导入']));
    expect(merged.activation, incoming.activation);
    expect(report.activityRecords.single.subscriptionId, local.id);
  });

  test('关键元数据完全相同的强匹配默认跳过', () {
    final local = _subscription(id: 'local', iccid: '8900-2');
    final incoming = local.copyWith(
      id: 'incoming',
      createdAt: DateTime.utc(2026, 8, 8),
      updatedAt: DateTime.utc(2026, 8, 8),
    );
    final plan = ImportMergePlanner(
      existingSubscriptions: [local],
      existingAssets: AssetInventory(),
    ).inspect([incoming]);

    expect(plan.candidates.single.matchKind, ImportMatchKind.iccid);
    expect(plan.candidates.single.diffs, isEmpty);
    expect(plan.candidates.single.defaultAction, ImportMergeAction.skip);
    expect(plan.duplicateCount, 1);
  });

  test('只有手机号和运营商相同时是弱匹配，默认新增', () {
    final local = _subscription(
      id: 'local',
      number: '+3725550001',
      operator: 'Example',
    );
    final incoming = _subscription(
      id: 'incoming',
      number: '+3725550001',
      operator: ' example ',
    );
    final candidate = ImportMergePlanner(
      existingSubscriptions: [local],
      existingAssets: AssetInventory(),
    ).inspect([incoming]).candidates.single;

    expect(candidate.matchKind, ImportMatchKind.phoneAndOperator);
    expect(candidate.defaultAction, ImportMergeAction.create);
    expect(candidate.availableActions, contains(ImportMergeAction.merge));
  });

  test('选定目标 EID 只为没有资产关系的新 Profile 建立关联', () {
    final inventory = _targetInventory();
    final incoming = _subscription(id: 'incoming', iccid: '8900-3');
    final planner = ImportMergePlanner(
      existingSubscriptions: const [],
      existingAssets: inventory,
    );
    final plan = planner.inspect([incoming]);
    final report = planner.resolveSimHub(
      report: SimHubImportReport(
        subscriptions: [incoming],
        activityRecords: const [],
        issues: const [],
        sourceRecordCount: 1,
      ),
      plan: plan,
      actions: plan.defaultActions,
      targetEidId: 'target-eid',
      nowUtc: DateTime.utc(2026, 8, 10),
    );

    expect(report.assets.profiles, hasLength(1));
    expect(report.assets.profiles.single.eidId, 'target-eid');
    expect(report.assets.profiles.single.subscriptionId, incoming.id);
  });

  test('合并已有 Profile 时保留本地资产 ID 和 EID 位置', () {
    final local = _subscription(id: 'local', iccid: '8900-4');
    final incoming = _subscription(id: 'incoming', iccid: '8900-4');
    final localInventory = _targetInventory(
      profiles: [
        EsimProfile(
          id: 'local-profile',
          eidId: 'target-eid',
          iccid: local.iccid,
          subscriptionId: local.id,
          createdAt: DateTime.utc(2026, 8, 8),
          updatedAt: DateTime.utc(2026, 8, 8),
        ),
      ],
    );
    final now = DateTime.utc(2026, 8, 9);
    final sourceCard = RemovableEuiccCard(
      id: 'source-card',
      name: 'Source',
      createdAt: now,
      updatedAt: now,
    );
    final sourceEid = Euicc(
      id: 'source-eid',
      cardId: sourceCard.id,
      value: '89049032000000000000000000000044',
      createdAt: now,
      updatedAt: now,
    );
    final planner = ImportMergePlanner(
      existingSubscriptions: [local],
      existingAssets: localInventory,
    );
    final plan = planner.inspect([incoming]);
    final report = planner.resolveSimHub(
      report: SimHubImportReport(
        subscriptions: [incoming],
        activityRecords: const [],
        issues: const [],
        sourceRecordCount: 1,
        assets: AssetInventory(
          cards: [sourceCard],
          eids: [sourceEid],
          profiles: [
            EsimProfile(
              id: 'source-profile',
              eidId: sourceEid.id,
              iccid: incoming.iccid,
              subscriptionId: incoming.id,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      ),
      plan: plan,
      actions: {incoming.id: ImportMergeAction.merge},
      nowUtc: DateTime.utc(2026, 8, 10),
    );

    expect(report.assets.profiles.single.id, 'local-profile');
    expect(report.assets.profiles.single.eidId, 'target-eid');
    expect(report.assets.profiles.single.subscriptionId, local.id);
  });

  test('目标 EID 属于普通实体 SIM 时拒绝解析', () {
    final now = DateTime.utc(2026, 8, 9);
    final card = PhysicalSimCard(
      id: 'physical',
      name: 'SIM',
      physicalIccid: '8900',
      createdAt: now,
      updatedAt: now,
    );
    final inventory = AssetInventory(
      cards: [card],
      eids: [
        Euicc(
          id: 'bad-eid',
          cardId: card.id,
          value: '89049032000000000000000000000099',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    final incoming = _subscription(id: 'incoming');
    final planner = ImportMergePlanner(
      existingSubscriptions: const [],
      existingAssets: inventory,
    );
    final plan = planner.inspect([incoming]);

    expect(
      () => planner.resolveSimHub(
        report: SimHubImportReport(
          subscriptions: [incoming],
          activityRecords: const [],
          issues: const [],
          sourceRecordCount: 1,
        ),
        plan: plan,
        actions: plan.defaultActions,
        targetEidId: 'bad-eid',
        nowUtc: now,
      ),
      throwsFormatException,
    );
  });

  test('两万条导入匹配保持线性级开销', () {
    const count = 20000;
    final existing = List.generate(
      count,
      (index) => _subscription(
        id: 'local-$index',
        iccid: '898600${index.toString().padLeft(13, '0')}',
      ),
      growable: false,
    );
    final incoming = List.generate(
      count,
      (index) => _subscription(
        id: 'incoming-$index',
        iccid: '898600${index.toString().padLeft(13, '0')}',
      ),
      growable: false,
    );

    final stopwatch = Stopwatch()..start();
    final plan = ImportMergePlanner(
      existingSubscriptions: existing,
      existingAssets: AssetInventory(),
    ).inspect(incoming);
    stopwatch.stop();

    expect(plan.matchedCount, count);
    expect(plan.duplicateCount, count);
    expect(
      stopwatch.elapsed,
      lessThan(const Duration(seconds: 5)),
      reason: '批量匹配不应退化为 existing × incoming 的嵌套扫描',
    );
  }, timeout: const Timeout(Duration(seconds: 10)));
}

Subscription _subscription({
  required String id,
  String? iccid,
  String? number,
  String? operator,
  List<String> tags = const [],
  LpaActivation? activation,
}) => Subscription(
  id: id,
  iccid: iccid,
  number: number == null ? const PhoneNumber.unknown() : PhoneNumber(number),
  operator: operator,
  activation: activation,
  plan: Plan(),
  keepAlive: KeepAlive.notRequired(),
  tags: tags,
  timeZoneId: 'UTC',
  createdAt: DateTime.utc(2026, 8, 8),
  updatedAt: DateTime.utc(2026, 8, 8),
);

AssetInventory _targetInventory({Iterable<EsimProfile> profiles = const []}) {
  final now = DateTime.utc(2026, 8, 8);
  final card = RemovableEuiccCard(
    id: 'target-card',
    name: 'Target',
    createdAt: now,
    updatedAt: now,
  );
  return AssetInventory(
    cards: [card],
    eids: [
      Euicc(
        id: 'target-eid',
        cardId: card.id,
        value: '89049032000000000000000000000001',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    profiles: profiles,
  );
}
