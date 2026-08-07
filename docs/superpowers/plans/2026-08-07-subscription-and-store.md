# 订阅域模型与 SQLite 持久化 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 `iesim_core` 订阅域模型（`PhoneNumber` / `Plan` / `Appearance` / `Subscription` / `ActivityRecord`）与 SQLite 持久化层，资产域按 v1 边界仅建表，产出可独立测试的完整数据层。

**Architecture:** 在计划 1 已建立的 `iesim_core` 基础上扩展。模型为不可变类、字段扁平化存入 SQLite 单表（值对象展开为多列，不存 JSON blob）；仓库层以 `Result<T>` 返回 IO 结果，可预期失败不抛裸异常。资产域（Device/Slot/Card/EID/Profile）仅建表不写代码，换取 v2 免全量迁移。

**Tech Stack:** Dart 3.12.2，新增 `sqlite3` ^3.5.1（纯 FFI、hooks 捆绑 SQLite，**已验证**可在无 GUI 的 Linux 服务器 `dart test` 通过；若 hooks 构建失败则回退 `^2.9.0` 动态链接系统 libsqlite3，本机已具备）。其余沿用 `timezone` ^0.11.1、`test` ^1.25.0。

## Global Constraints

- Dart SDK 下限 `^3.10.0`（与 NekokoLPA2 对齐，便于 v2 复用其代码）。
- 时间存储一律 UTC（SQLite 中为 ISO8601 字符串，`toIso8601String()`）；显示与天数计算一律在订阅的 `timeZoneId`（IANA 标识）下进行。
- 所有领域实体为不可变类，更新通过 `copyWith` 返回新实例，禁止字段可变；`List` 字段构造时 `List.unmodifiable` 包裹。
- `iesim_core` 不得直接依赖平台插件（含原生实现的包，如 `flutter_timezone`、`flutter_local_notifications`）。`sqlite3` 为 FFI 包而非平台插件，符合约束；平台能力仍通过抽象接口注入。
- 金额一律以最小货币单位整数（`minorUnits`）存储，禁止使用 `double` 表示金额。
- 缺失数据不得呈现为「安全」。缺失字段落空（`null`），由 UI 呈现为「未知」；不得在导入或持久化层为缺失值伪造回退（如「缺失到期日 = 今天 + 30 天」）。
- 单文件 200-400 行为宜，上限 800 行。
- 测试覆盖率目标 80%（spec §8），沿计划 1 的 lcov 方法验收。
- 提醒时刻推算（`schedule/` 模块）不在本计划范围，随计划 5（Flutter UI + 本地通知）引入。

---

## 前置条件

开发在 netcup 服务器（Debian 13）进行，仓库位于 `~/code/Yeats33/iesim`，git 身份由目录自动套用为 Yeats33。

Flutter SDK 解压于 `~/flutter`。每个 shell 会话执行任务前须确保 PATH 就绪：

```bash
export PATH="$HOME/flutter/bin:$PATH"
dart --version   # 期望 Dart SDK version: 3.12.2
```

`sqlite3` ^3.5.1 已在本机验证：纯 Dart FFI 包，hooks 捆绑 SQLite，`dart test` 在无 GUI 的 Linux 上直接可用（探针项目 `/tmp/sqlite3_probe` 已验证，可删除）。若 `dart pub get` 后运行测试报 native assets 相关错误，将依赖改为 `sqlite3: ^2.9.0`（动态链接系统 libsqlite3，本机已有 `/lib/x86_64-linux-gnu/libsqlite3.so.0`）。

## File Structure

```
iesim/packages/iesim_core/
├── lib/
│   ├── iesim_core.dart               统一导出（随任务追加）
│   └── src/
│       ├── value/
│       │   ├── money.dart            [已有] 金额值对象
│       │   └── phone_number.dart     [新增] 号码值对象，规范化存储
│       ├── time/                     [已有] clock / calendar，本计划不修改
│       ├── model/
│       │   ├── keep_alive.dart       [已有] 保号策略（Subscription 复用）
│       │   ├── plan.dart             [新增] 套餐模型
│       │   ├── appearance.dart       [新增] 外观展示模型
│       │   ├── subscription.dart     [新增] 订阅聚合根
│       │   └── activity_record.dart  [新增] 续存动作记录
│       ├── result.dart               [新增] Result<T> / Failure / StoreError
│       └── store/
│           ├── database.dart         [新增] 打开库 + 幂等建表（含资产域表）
│           ├── subscription_repository.dart   [新增] 订阅 CRUD
│           └── activity_record_repository.dart [新增] 动作记录读写
└── test/
    ├── value/phone_number_test.dart
    ├── model/plan_test.dart
    ├── model/appearance_test.dart
    ├── model/subscription_test.dart
    ├── model/activity_record_test.dart
    ├── result_test.dart
    ├── store/database_test.dart
    ├── store/subscription_repository_test.dart
    └── store/activity_record_repository_test.dart
```

**职责边界**：`value/` 与 `model/` 只定义数据不含 IO；`store/` 只做持久化不含业务判定；仓库方法一律返回 `Result<T>`。时间换算与保号判定复用计划 1 的 `time/` 与 `keepalive/`。

**与 spec §3.2/§3.3 的两处模型偏差（均注明理由，实现按本计划）**：

1. `Subscription` 增加 `final DateTime createdAt`（UTC）。spec §5.1 的 SimHub JSON 含 `createdAt` 字段，计划 3 往返需要；新建订阅的 KeepAlive 推测（spec §4.2）也以创建时刻为基准。
2. `ActivityRecord` 增加 `final String id`。spec §6.5 将 ActivityRecord 纳入同步并支持墓碑，墓碑按 id 配对，无 id 无法实现。

---

### Task 1: PhoneNumber 值对象

**Files:**
- Create: `packages/iesim_core/lib/src/value/phone_number.dart`
- Create: `packages/iesim_core/test/value/phone_number_test.dart`
- Modify: `packages/iesim_core/lib/iesim_core.dart`

**Interfaces:**
- Consumes: 无
- Produces: `class PhoneNumber`，构造 `PhoneNumber(String number)` 自动规范化（去空格/连字符/括号，仅允许数字、`+` 前缀与 `#*`），规范化结果非法时抛 `ArgumentError`；`String get value`；`operator ==`、`hashCode`、`toString`

- [x] **Step 1: 写失败测试**

写入 `packages/iesim_core/test/value/phone_number_test.dart`：

```dart
import 'package:test/test.dart';
import 'package:iesim_core/src/value/phone_number.dart';

void main() {
  group('PhoneNumber', () {
    test('去除空格、连字符与括号并保留 + 前缀', () {
      final p = PhoneNumber('+86 138-0000-0000');
      expect(p.value, equals('+8613800000000'));
    });

    test('无国际前缀的号码保持原样', () {
      expect(PhoneNumber('(021) 1234-5678').value, equals('02112345678'));
    });

    test('USSD 号码保留 # 与 *', () {
      expect(PhoneNumber('#100#').value, equals('#100#'));
      expect(PhoneNumber('*101*6#').value, equals('*101*6#'));
    });

    test('空输入抛出 ArgumentError', () {
      expect(() => PhoneNumber('   '), throwsArgumentError);
    });

    test('含字母抛出 ArgumentError', () {
      expect(() => PhoneNumber('138-0000-0000a'), throwsArgumentError);
    });

    test('仅一个 + 号抛出 ArgumentError', () {
      expect(() => PhoneNumber('+'), throwsArgumentError);
    });

    test('相同号码视为相等', () {
      expect(
        PhoneNumber('+86 138-0000-0000'),
        equals(PhoneNumber('+8613800000000')),
      );
    });

    test('不同号码不相等且 hashCode 不同', () {
      final a = PhoneNumber('13800000000');
      final b = PhoneNumber('13900000000');
      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });
  });
}
```

- [x] **Step 2: 运行测试确认失败**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/value/phone_number_test.dart
```

Expected: FAIL，找不到 `phone_number.dart`。

- [x] **Step 3: 实现 PhoneNumber**

写入 `packages/iesim_core/lib/src/value/phone_number.dart`：

```dart
/// 电话号码值对象。
///
/// 规范化存储：去除空格、连字符与括号，仅保留数字、国际前缀 + 以及
/// # 与 *（USSD 拨号场景）。规范化结果为空或含非法字符时抛 ArgumentError。
class PhoneNumber {
  final String _normalized;

  /// [number] 为任意常见书写形式（如 +86 138-0000-0000），构造时自动规范化。
  PhoneNumber(String number) : _normalized = _normalize(number);

  /// 规范化后的号码（保留 + 前缀）。
  String get value => _normalized;

  static String _normalize(String input) {
    final cleaned = input
        .trim()
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('(', '')
        .replaceAll(')', '');
    if (cleaned.isEmpty) {
      throw ArgumentError.value(input, 'number', '号码不能为空');
    }
    if (!RegExp(r'^\+?[0-9#*]+$').hasMatch(cleaned)) {
      throw ArgumentError.value(
        input,
        'number',
        '仅允许数字、国际前缀 + 及 #/*（USSD）',
      );
    }
    return cleaned;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhoneNumber && other._normalized == _normalized;

  @override
  int get hashCode => _normalized.hashCode;

  @override
  String toString() => 'PhoneNumber($value)';
}
```

- [x] **Step 4: 运行测试确认通过**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/value/phone_number_test.dart
```

Expected: 8 个测试全部 PASS。

- [x] **Step 5: 导出并提交**

在 `packages/iesim_core/lib/iesim_core.dart` 追加：

```dart
export 'src/value/phone_number.dart';
```

```bash
cd ~/code/Yeats33/iesim
git add packages/iesim_core/lib/src/value/phone_number.dart \
        packages/iesim_core/test/value/phone_number_test.dart \
        packages/iesim_core/lib/iesim_core.dart
git commit -m "feat: 添加 PhoneNumber 值对象，规范化存储号码"
```

---

### Task 2: Plan 与 Appearance 模型

**Files:**
- Create: `packages/iesim_core/lib/src/model/plan.dart`
- Create: `packages/iesim_core/test/model/plan_test.dart`
- Create: `packages/iesim_core/lib/src/model/appearance.dart`
- Create: `packages/iesim_core/test/model/appearance_test.dart`
- Modify: `packages/iesim_core/lib/iesim_core.dart`

**Interfaces:**
- Consumes: `Money({required int minorUnits, required String currencyCode})`（计划 1）
- Produces:
  - `class Plan`：`name`、`cyclePrice`（`Money?`）、`cycleDays`（`int?`，>0）、`startDate`（`DateTime?` UTC）、`expiryDate`（`DateTime?` UTC）、`isLongTerm`（`bool`，默认 false）；含 `copyWith`、`operator ==`、`hashCode`
  - `class Appearance`：`flag`、`cardColorHex`、`cardBackgroundAssetName`、`websiteURL`、`customPrompt`（均 `String?`）；含 `copyWith`、`operator ==`、`hashCode`

- [x] **Step 1: 写失败测试（Plan）**

写入 `packages/iesim_core/test/model/plan_test.dart`：

```dart
import 'package:test/test.dart';
import 'package:iesim_core/src/model/plan.dart';
import 'package:iesim_core/src/value/money.dart';

void main() {
  group('Plan', () {
    test('默认构造为可空全空、非长期', () {
      final plan = Plan();
      expect(plan.name, isNull);
      expect(plan.cyclePrice, isNull);
      expect(plan.cycleDays, isNull);
      expect(plan.startDate, isNull);
      expect(plan.expiryDate, isNull);
      expect(plan.isLongTerm, isFalse);
    });

    test('cycleDays 必须为正数', () {
      expect(() => Plan(cycleDays: 0), throwsArgumentError);
      expect(() => Plan(cycleDays: -30), throwsArgumentError);
    });

    test('拒绝非 UTC 的日期', () {
      expect(
        () => Plan(startDate: DateTime(2026, 8, 1)),
        throwsArgumentError,
      );
      expect(
        () => Plan(expiryDate: DateTime(2026, 8, 1)),
        throwsArgumentError,
      );
    });

    test('copyWith 仅覆盖指定字段', () {
      final plan = Plan(name: 'A', cycleDays: 30);
      final next = plan.copyWith(cyclePrice: Money.zero('CNY'));
      expect(next.name, equals('A'));
      expect(next.cycleDays, equals(30));
      expect(next.cyclePrice, equals(Money.zero('CNY')));
    });

    test('相同字段视为相等', () {
      expect(
        Plan(name: 'A', cycleDays: 30),
        equals(Plan(name: 'A', cycleDays: 30)),
      );
      expect(
        Plan(name: 'A', cycleDays: 30),
        isNot(equals(Plan(name: 'A', cycleDays: 60))),
      );
    });
  });
}
```

- [x] **Step 2: 运行测试确认失败**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/model/plan_test.dart
```

Expected: FAIL，找不到 `plan.dart`。

- [x] **Step 3: 实现 Plan**

写入 `packages/iesim_core/lib/src/model/plan.dart`：

```dart
import '../value/money.dart';

/// 套餐信息。
///
/// 一订阅一套餐（spec §11）；多套餐叠加的卡片需建多条订阅表达。
/// 全部字段可空——导入数据常常不完整，空字段由 UI 呈现为「未知」。
class Plan {
  /// 套餐名称。
  final String? name;

  /// 每周期资费。
  final Money? cyclePrice;

  /// 计费周期天数。
  final int? cycleDays;

  /// 套餐开始时刻，UTC。
  final DateTime? startDate;

  /// 套餐到期时刻，UTC。
  final DateTime? expiryDate;

  /// 长期套餐（与「是否需保号」无关，见 KeepAlive.required）。
  final bool isLongTerm;

  Plan({
    this.name,
    this.cyclePrice,
    this.cycleDays,
    this.startDate,
    this.expiryDate,
    this.isLongTerm = false,
  }) {
    final cycle = cycleDays;
    if (cycle != null && cycle <= 0) {
      throw ArgumentError.value(cycle, 'cycleDays', '必须为正数');
    }
    if (startDate != null && !startDate!.isUtc) {
      throw ArgumentError.value(startDate, 'startDate', '必须为 UTC 时刻');
    }
    if (expiryDate != null && !expiryDate!.isUtc) {
      throw ArgumentError.value(expiryDate, 'expiryDate', '必须为 UTC 时刻');
    }
  }

  Plan copyWith({
    String? name,
    Money? cyclePrice,
    int? cycleDays,
    DateTime? startDate,
    DateTime? expiryDate,
    bool? isLongTerm,
  }) =>
      Plan(
        name: name ?? this.name,
        cyclePrice: cyclePrice ?? this.cyclePrice,
        cycleDays: cycleDays ?? this.cycleDays,
        startDate: startDate ?? this.startDate,
        expiryDate: expiryDate ?? this.expiryDate,
        isLongTerm: isLongTerm ?? this.isLongTerm,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Plan &&
          other.name == name &&
          other.cyclePrice == cyclePrice &&
          other.cycleDays == cycleDays &&
          other.startDate == startDate &&
          other.expiryDate == expiryDate &&
          other.isLongTerm == isLongTerm;

  @override
  int get hashCode =>
      Object.hash(name, cyclePrice, cycleDays, startDate, expiryDate, isLongTerm);
}
```

注意：Dart 禁止 const 构造函数带构造体（`const_constructor_with_body` 编译错误），因此 `Plan` 为非 const 构造，校验在构造体中 throw `ArgumentError`——与 KeepAlive 的校验模式一致（实测 2026-08-08 修正，原计划误写 const）。

- [x] **Step 4: 运行测试确认通过**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/model/plan_test.dart
```

Expected: 5 个测试全部 PASS。

- [x] **Step 5: 写失败测试（Appearance）**

写入 `packages/iesim_core/test/model/appearance_test.dart`：

```dart
import 'package:test/test.dart';
import 'package:iesim_core/src/model/appearance.dart';

void main() {
  group('Appearance', () {
    test('默认构造为全空', () {
      const a = Appearance();
      expect(a.flag, isNull);
      expect(a.cardColorHex, isNull);
      expect(a.cardBackgroundAssetName, isNull);
      expect(a.websiteURL, isNull);
      expect(a.customPrompt, isNull);
    });

    test('copyWith 仅覆盖指定字段', () {
      const a = Appearance(flag: '🇨🇳');
      expect(a.copyWith(cardColorHex: '#0a84ff').flag, equals('🇨🇳'));
      expect(a.copyWith(cardColorHex: '#0a84ff').cardColorHex, equals('#0a84ff'));
    });

    test('相同字段视为相等', () {
      expect(
        const Appearance(flag: '🇨🇳'),
        equals(const Appearance(flag: '🇨🇳')),
      );
      expect(
        const Appearance(flag: '🇨🇳'),
        isNot(equals(const Appearance(flag: '🇯🇵'))),
      );
    });
  });
}
```

- [x] **Step 6: 运行测试确认失败**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/model/appearance_test.dart
```

Expected: FAIL，找不到 `appearance.dart`。

- [x] **Step 7: 实现 Appearance**

写入 `packages/iesim_core/lib/src/model/appearance.dart`：

```dart
/// 卡片外观与展示信息。
///
/// 全部为非业务字段，与 SimHub JSON 的对应字段一一映射（spec §5.1），
/// 便于互操作往返。不做内容校验，保持宽松。
class Appearance {
  /// 国旗 emoji。
  final String? flag;

  /// 卡片主题色，如 #0a84ff。
  final String? cardColorHex;

  /// 卡片背景资源名。
  final String? cardBackgroundAssetName;

  /// 运营商官网。
  final String? websiteURL;

  /// 自定义提示语。
  final String? customPrompt;

  const Appearance({
    this.flag,
    this.cardColorHex,
    this.cardBackgroundAssetName,
    this.websiteURL,
    this.customPrompt,
  });

  Appearance copyWith({
    String? flag,
    String? cardColorHex,
    String? cardBackgroundAssetName,
    String? websiteURL,
    String? customPrompt,
  }) =>
      Appearance(
        flag: flag ?? this.flag,
        cardColorHex: cardColorHex ?? this.cardColorHex,
        cardBackgroundAssetName:
            cardBackgroundAssetName ?? this.cardBackgroundAssetName,
        websiteURL: websiteURL ?? this.websiteURL,
        customPrompt: customPrompt ?? this.customPrompt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Appearance &&
          other.flag == flag &&
          other.cardColorHex == cardColorHex &&
          other.cardBackgroundAssetName == cardBackgroundAssetName &&
          other.websiteURL == websiteURL &&
          other.customPrompt == customPrompt;

  @override
  int get hashCode =>
      Object.hash(flag, cardColorHex, cardBackgroundAssetName, websiteURL, customPrompt);
}
```

- [x] **Step 8: 运行测试确认通过**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/model/appearance_test.dart
```

Expected: 3 个测试全部 PASS。

- [x] **Step 9: 导出并提交**

在 `packages/iesim_core/lib/iesim_core.dart` 追加：

```dart
export 'src/model/plan.dart';
export 'src/model/appearance.dart';
```

```bash
cd ~/code/Yeats33/iesim
git add packages/iesim_core/lib/src/model/plan.dart \
        packages/iesim_core/lib/src/model/appearance.dart \
        packages/iesim_core/test/model/plan_test.dart \
        packages/iesim_core/test/model/appearance_test.dart \
        packages/iesim_core/lib/iesim_core.dart
git commit -m "feat: 添加 Plan 与 Appearance 模型"
```

---

### Task 3: Subscription 聚合根

**Files:**
- Create: `packages/iesim_core/lib/src/model/subscription.dart`
- Create: `packages/iesim_core/test/model/subscription_test.dart`
- Modify: `packages/iesim_core/lib/iesim_core.dart`

**Interfaces:**
- Consumes: `PhoneNumber(String)`（Task 1）；`Plan`（Task 2）；`Appearance`（Task 2）；`KeepAlive`（计划 1）
- Produces: `class Subscription`，构造 `Subscription({required String id, String? iccid, required PhoneNumber number, String? operator, required Plan plan, required KeepAlive keepAlive, List<String>? tags, Appearance appearance = const Appearance(), required String timeZoneId, required DateTime createdAt, required DateTime updatedAt})`；`tags` 为不可变 `List<String>`；含 `copyWith`、`operator ==`、`hashCode`

- [x] **Step 1: 写失败测试**

写入 `packages/iesim_core/test/model/subscription_test.dart`：

```dart
import 'package:test/test.dart';
import 'package:iesim_core/src/model/appearance.dart';
import 'package:iesim_core/src/model/keep_alive.dart';
import 'package:iesim_core/src/model/plan.dart';
import 'package:iesim_core/src/model/subscription.dart';
import 'package:iesim_core/src/value/phone_number.dart';

void main() {
  Subscription base() => Subscription(
        id: 'sub-1',
        iccid: '89000000000000000001',
        number: PhoneNumber('+8613800000000'),
        operator: '中国移动',
        plan: Plan(name: '畅享 5G', cycleDays: 30),
        keepAlive: KeepAlive.notRequired(),
        tags: const ['主力号'],
        appearance: const Appearance(flag: '🇨🇳'),
        timeZoneId: 'Asia/Shanghai',
        createdAt: DateTime.utc(2026, 8, 7, 4, 0),
        updatedAt: DateTime.utc(2026, 8, 7, 4, 0),
      );

  group('Subscription', () {
    test('完整构造保留全部字段', () {
      final s = base();
      expect(s.id, equals('sub-1'));
      expect(s.iccid, equals('89000000000000000001'));
      expect(s.number.value, equals('+8613800000000'));
      expect(s.operator, equals('中国移动'));
      expect(s.plan.name, equals('畅享 5G'));
      expect(s.keepAlive.required, isFalse);
      expect(s.tags, equals(['主力号']));
      expect(s.appearance.flag, equals('🇨🇳'));
      expect(s.timeZoneId, equals('Asia/Shanghai'));
      expect(s.createdAt, equals(DateTime.utc(2026, 8, 7, 4, 0)));
      expect(s.updatedAt, equals(DateTime.utc(2026, 8, 7, 4, 0)));
    });

    test('iccid 与 operator 可空（直接构造）', () {
      final s = Subscription(
        id: 'sub-2',
        number: PhoneNumber('+8613800000000'),
        plan: Plan(name: '畅享 5G', cycleDays: 30),
        keepAlive: KeepAlive.notRequired(),
        tags: const ['主力号'],
        timeZoneId: 'Asia/Shanghai',
        createdAt: DateTime.utc(2026, 8, 7, 4, 0),
        updatedAt: DateTime.utc(2026, 8, 7, 4, 0),
      );
      expect(s.iccid, isNull);
      expect(s.operator, isNull);
    });

    test('拒绝非 UTC 的时间戳', () {
      expect(
        () => base().copyWith(createdAt: DateTime(2026, 8, 7)),
        throwsArgumentError,
      );
      expect(
        () => base().copyWith(updatedAt: DateTime(2026, 8, 7)),
        throwsArgumentError,
      );
    });

    test('tags 不可被外部修改', () {
      final s = base();
      expect(() => s.tags.add('x'), throwsUnsupportedError);
    });

    test('copyWith 修改后原实例不变', () {
      final s = base();
      final next = s.copyWith(operator: '中国联通');
      expect(s.operator, equals('中国移动'));
      expect(next.operator, equals('中国联通'));
      expect(next.id, equals(s.id));
    });

    test('相同字段视为相等，tags 顺序敏感', () {
      expect(base(), equals(base()));
      expect(
        base().copyWith(tags: const ['备胎', '主力号']),
        isNot(equals(base())),
      );
    });
  });
}
```

- [x] **Step 2: 运行测试确认失败**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/model/subscription_test.dart
```

Expected: FAIL，找不到 `subscription.dart`。

- [x] **Step 3: 实现 Subscription**

写入 `packages/iesim_core/lib/src/model/subscription.dart`：

```dart
import 'appearance.dart';
import 'keep_alive.dart';
import 'plan.dart';
import '../value/phone_number.dart';

/// 订阅聚合根。
///
/// 商业属性跟随号码而非硬件（spec §3.1 决定 3）：订阅挂在 Profile 下，
/// 这里建模为独立聚合，由 [iccid] 与资产域关联。
///
/// 全部字段不可变；时间戳一律 UTC。
/// 时区标识不在构造时校验（校验需时区数据库，构造保持无副作用），
/// 由 KeepAliveEvaluator / ZonedCalendar 在使用时以 ArgumentError 暴露问题。
class Subscription {
  final String id;

  /// 与 Nekoko 关联的键（spec §5.2），也作 SimHub JSON 扩展字段。
  final String? iccid;

  final PhoneNumber number;

  /// 运营商名称。
  final String? operator;

  final Plan plan;

  final KeepAlive keepAlive;

  /// 标签，不可变。
  final List<String> tags;

  final Appearance appearance;

  /// IANA 基准时区标识，如 Asia/Shanghai（spec §4.3）。
  final String timeZoneId;

  /// 创建时刻，UTC。SimHub JSON 往返（spec §5.1）与 KeepAlive 推测基准用。
  final DateTime createdAt;

  /// 最后修改时刻，UTC。同步 last-write-wins 比较用（spec §6.2）。
  final DateTime updatedAt;

  Subscription({
    required this.id,
    this.iccid,
    required this.number,
    this.operator,
    required this.plan,
    required this.keepAlive,
    List<String>? tags,
    this.appearance = const Appearance(),
    required this.timeZoneId,
    required this.createdAt,
    required this.updatedAt,
  })  : tags = List.unmodifiable(tags ?? const []) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', '不能为空');
    }
    if (timeZoneId.isEmpty) {
      throw ArgumentError.value(timeZoneId, 'timeZoneId', '不能为空');
    }
    if (!createdAt.isUtc) {
      throw ArgumentError.value(createdAt, 'createdAt', '必须为 UTC 时刻');
    }
    if (!updatedAt.isUtc) {
      throw ArgumentError.value(updatedAt, 'updatedAt', '必须为 UTC 时刻');
    }
  }

  Subscription copyWith({
    String? id,
    String? iccid,
    PhoneNumber? number,
    String? operator,
    Plan? plan,
    KeepAlive? keepAlive,
    List<String>? tags,
    Appearance? appearance,
    String? timeZoneId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Subscription(
        id: id ?? this.id,
        iccid: iccid ?? this.iccid,
        number: number ?? this.number,
        operator: operator ?? this.operator,
        plan: plan ?? this.plan,
        keepAlive: keepAlive ?? this.keepAlive,
        tags: tags ?? this.tags,
        appearance: appearance ?? this.appearance,
        timeZoneId: timeZoneId ?? this.timeZoneId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Subscription &&
          other.id == id &&
          other.iccid == iccid &&
          other.number == number &&
          other.operator == operator &&
          other.plan == plan &&
          other.keepAlive == keepAlive &&
          _listEquals(other.tags, tags) &&
          other.appearance == appearance &&
          other.timeZoneId == timeZoneId &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        iccid,
        number,
        operator,
        plan,
        keepAlive,
        Object.hashAll(tags),
        appearance,
        timeZoneId,
        createdAt,
        updatedAt,
      );
}
```

注：`copyWith` 与 KeepAlive 一致，无法将可空字段（`iccid`/`operator`）置回 null；确需清空时直接构造新实例。

- [x] **Step 4: 运行测试确认通过**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/model/subscription_test.dart
```

Expected: 6 个测试全部 PASS。

- [x] **Step 5: 导出并提交**

在 `packages/iesim_core/lib/iesim_core.dart` 追加：

```dart
export 'src/model/subscription.dart';
```

```bash
cd ~/code/Yeats33/iesim
git add packages/iesim_core/lib/src/model/subscription.dart \
        packages/iesim_core/test/model/subscription_test.dart \
        packages/iesim_core/lib/iesim_core.dart
git commit -m "feat: 添加 Subscription 聚合根"
```

---

### Task 4: ActivityRecord 动作记录模型

**Files:**
- Create: `packages/iesim_core/lib/src/model/activity_record.dart`
- Create: `packages/iesim_core/test/model/activity_record_test.dart`
- Modify: `packages/iesim_core/lib/iesim_core.dart`

**Interfaces:**
- Consumes: `Money`（计划 1）
- Produces: `enum ActivityType { topUp, call, sms, renewal }`；`class ActivityRecord`，构造 `ActivityRecord({required String id, required String subscriptionId, required ActivityType type, required DateTime occurredAt, Money? amount})`；含 `copyWith`、`operator ==`、`hashCode`

- [x] **Step 1: 写失败测试**

写入 `packages/iesim_core/test/model/activity_record_test.dart`：

```dart
import 'package:test/test.dart';
import 'package:iesim_core/src/model/activity_record.dart';
import 'package:iesim_core/src/value/money.dart';

void main() {
  group('ActivityRecord', () {
    test('完整构造保留全部字段', () {
      final r = ActivityRecord(
        id: 'act-1',
        subscriptionId: 'sub-1',
        type: ActivityType.topUp,
        occurredAt: DateTime.utc(2026, 8, 7, 4, 0),
        amount: const Money(minorUnits: 10000, currencyCode: 'CNY'),
      );
      expect(r.id, equals('act-1'));
      expect(r.subscriptionId, equals('sub-1'));
      expect(r.type, equals(ActivityType.topUp));
      expect(r.occurredAt, equals(DateTime.utc(2026, 8, 7, 4, 0)));
      expect(r.amount, equals(const Money(minorUnits: 10000, currencyCode: 'CNY')));
    });

    test('amount 可空（通话与短信无金额）', () {
      final r = ActivityRecord(
        id: 'act-2',
        subscriptionId: 'sub-1',
        type: ActivityType.call,
        occurredAt: DateTime.utc(2026, 8, 7, 5, 0),
      );
      expect(r.amount, isNull);
    });

    test('拒绝非 UTC 的 occurredAt', () {
      expect(
        () => ActivityRecord(
          id: 'act-3',
          subscriptionId: 'sub-1',
          type: ActivityType.sms,
          occurredAt: DateTime(2026, 8, 7, 5, 0),
        ),
        throwsArgumentError,
      );
    });

    test('copyWith 修改后原实例不变', () {
      final r = ActivityRecord(
        id: 'act-4',
        subscriptionId: 'sub-1',
        type: ActivityType.call,
        occurredAt: DateTime.utc(2026, 8, 7, 6, 0),
      );
      final next = r.copyWith(type: ActivityType.renewal);
      expect(r.type, equals(ActivityType.call));
      expect(next.type, equals(ActivityType.renewal));
    });

    test('相同字段视为相等', () {
      ActivityRecord make() => ActivityRecord(
            id: 'act-5',
            subscriptionId: 'sub-1',
            type: ActivityType.topUp,
            occurredAt: DateTime.utc(2026, 8, 7, 4, 0),
          );
      expect(make(), equals(make()));
      expect(make().copyWith(id: 'act-6'), isNot(equals(make())));
    });
  });
}
```

- [x] **Step 2: 运行测试确认失败**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/model/activity_record_test.dart
```

Expected: FAIL，找不到 `activity_record.dart`。

- [x] **Step 3: 实现 ActivityRecord**

写入 `packages/iesim_core/lib/src/model/activity_record.dart`：

```dart
import '../value/money.dart';

/// 续存动作类型。
enum ActivityType {
  /// 充值。
  topUp,

  /// 通话。
  call,

  /// 短信。
  sms,

  /// 续费。
  renewal,
}

/// 订阅续存动作记录（spec §3.3 事件流之一）。
///
/// 回答「号码为何仍然有效」；资产物理变迁走另一条流（AssetEvent，v2）。
/// 含 [id] 以供同步墓碑配对（spec §6.5）。
class ActivityRecord {
  final String id;

  /// 所属订阅。
  final String subscriptionId;

  final ActivityType type;

  /// 动作发生时刻，UTC。
  final DateTime occurredAt;

  /// 金额；通话与短信等无金额动作留空。
  final Money? amount;

  ActivityRecord({
    required this.id,
    required this.subscriptionId,
    required this.type,
    required this.occurredAt,
    this.amount,
  }) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', '不能为空');
    }
    if (subscriptionId.isEmpty) {
      throw ArgumentError.value(subscriptionId, 'subscriptionId', '不能为空');
    }
    if (!occurredAt.isUtc) {
      throw ArgumentError.value(occurredAt, 'occurredAt', '必须为 UTC 时刻');
    }
  }

  ActivityRecord copyWith({
    String? id,
    String? subscriptionId,
    ActivityType? type,
    DateTime? occurredAt,
    Money? amount,
  }) =>
      ActivityRecord(
        id: id ?? this.id,
        subscriptionId: subscriptionId ?? this.subscriptionId,
        type: type ?? this.type,
        occurredAt: occurredAt ?? this.occurredAt,
        amount: amount ?? this.amount,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityRecord &&
          other.id == id &&
          other.subscriptionId == subscriptionId &&
          other.type == type &&
          other.occurredAt == occurredAt &&
          other.amount == amount;

  @override
  int get hashCode =>
      Object.hash(id, subscriptionId, type, occurredAt, amount);
}
```

- [x] **Step 4: 运行测试确认通过**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/model/activity_record_test.dart
```

Expected: 5 个测试全部 PASS。

- [x] **Step 5: 导出并提交**

在 `packages/iesim_core/lib/iesim_core.dart` 追加：

```dart
export 'src/model/activity_record.dart';
```

```bash
cd ~/code/Yeats33/iesim
git add packages/iesim_core/lib/src/model/activity_record.dart \
        packages/iesim_core/test/model/activity_record_test.dart \
        packages/iesim_core/lib/iesim_core.dart
git commit -m "feat: 添加 ActivityRecord 动作记录模型"
```

---

### Task 5: Result 类型与 SQLite 存储骨架

**Files:**
- Modify: `packages/iesim_core/pubspec.yaml`（追加 `sqlite3: ^3.5.1`）
- Create: `packages/iesim_core/lib/src/result.dart`
- Create: `packages/iesim_core/lib/src/store/database.dart`
- Create: `packages/iesim_core/test/result_test.dart`
- Create: `packages/iesim_core/test/store/database_test.dart`
- Modify: `packages/iesim_core/lib/iesim_core.dart`

**Interfaces:**
- Consumes: 无（新依赖 sqlite3）
- Produces:
  - `sealed class Result<T>`，`class Ok<T> extends Result<T> { final T value; }`，`class Err<T> extends Result<T> { final Failure failure; }`
  - `sealed class Failure`，`class StoreError extends Failure { final String message; }`
  - `Database openIesimStore(String path)`（`:memory:` 为内存库；开启外键约束并建表）
  - `void createSchema(Database db)`（幂等：订阅表、动作记录表、资产域 5 表、索引；`PRAGMA user_version = 1`）

- [x] **Step 1: 添加依赖**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
export PATH="$HOME/flutter/bin:$PATH"
dart pub add sqlite3:^3.5.1
```

Expected: 依赖解析成功。若因 native assets 报错，改执行 `dart pub add 'sqlite3:^2.9.0'` 并继续（前置条件已说明回退方案）。

- [x] **Step 2: 写失败测试（Result）**

写入 `packages/iesim_core/test/result_test.dart`：

```dart
import 'package:test/test.dart';
import 'package:iesim_core/src/result.dart';

void main() {
  group('Result', () {
    test('Ok 携带值且可模式匹配', () {
      const Ok<int> ok = Ok(42);
      final result = switch (ok) {
        Ok(value: final v) => v,
        Err() => 0,
      };
      expect(result, equals(42));
    });

    test('Err 携带失败原因且可模式匹配', () {
      // 声明为 Result<int> 而非 Err<int>，避免分析器静态判断 Ok 分支不可达
      const Result<int> err = Err(StoreError('磁盘写入失败'));
      final message = switch (err) {
        Ok() => '',
        Err(failure: final f) => f.toString(),
      };
      expect(message, contains('磁盘写入失败'));
    });

    test('失败类型为可辨识密封族', () {
      const StoreError e = StoreError('x');
      expect(e, isA<Failure>());
    });
  });
}
```

- [x] **Step 3: 运行测试确认失败**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/result_test.dart
```

Expected: FAIL，找不到 `result.dart`。

- [x] **Step 4: 实现 Result**

写入 `packages/iesim_core/lib/src/result.dart`：

```dart
/// IO 与网络操作的统一返回类型（spec §7）。
///
/// 领域代码不抛裸异常穿透到 UI 层；可预期的失败一律以 Result 返回，
/// UI 按失败类型给出可操作提示。本计划引入 [StoreError]，计划 4 扩展
/// WebDAV 相关失败子类型。
sealed class Result<T> {
  const Result();
}

/// 成功，携带 [value]。
class Ok<T> extends Result<T> {
  final T value;

  const Ok(this.value);
}

/// 失败，携带可辨识的 [failure]。
class Err<T> extends Result<T> {
  final Failure failure;

  const Err(this.failure);
}

/// 可预期的失败根类型。
sealed class Failure {
  const Failure();
}

/// 本地持久化失败（磁盘错误、约束违反等）。
class StoreError extends Failure {
  final String message;

  const StoreError(this.message);

  @override
  String toString() => 'StoreError($message)';
}
```

- [x] **Step 5: 运行测试确认通过**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/result_test.dart
```

Expected: 3 个测试全部 PASS。

- [x] **Step 6: 写失败测试（数据库与 schema）**

写入 `packages/iesim_core/test/store/database_test.dart`：

```dart
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:iesim_core/src/store/database.dart';

void main() {
  group('openIesimStore / createSchema', () {
    test('内存库建表后七张业务表齐备', () {
      final db = openIesimStore(':memory:');
      final names = db
          .select("SELECT name FROM sqlite_master WHERE type='table' "
              "AND name NOT LIKE 'sqlite_%'")
          .map((row) => row['name'] as String)
          .toSet();
      expect(
        names,
        containsAll([
          'subscriptions',
          'activity_records',
          'devices',
          'slots',
          'cards',
          'eids',
          'profiles',
        ]),
      );
      db.close();
    });

    test('user_version 为 1，为未来迁移留锚点', () {
      final db = openIesimStore(':memory:');
      expect(db.select('PRAGMA user_version').single.values.first, equals(1));
      db.close();
    });

    test('createSchema 幂等，重复调用不报错', () {
      final db = openIesimStore(':memory:');
      createSchema(db);
      createSchema(db);
      expect(
        db.select("SELECT COUNT(*) FROM sqlite_master WHERE type='table'"),
        isNotEmpty,
      );
      db.close();
    });

    test('外键约束开启：孤儿动作记录被拒绝', () {
      final db = openIesimStore(':memory:');
      expect(
        () => db.execute(
          "INSERT INTO activity_records (id, subscription_id, type, occurred_at) "
          "VALUES ('a', 'no-such-sub', 'topUp', '2026-08-07T00:00:00.000Z')",
        ),
        throwsA(isA<SqliteException>()),
      );
      db.close();
    });

    test('文件库可持久化：关闭重开后数据仍在', () {
      final dir = Directory.systemTemp.createTempSync('iesim_store_test');
      final path = '${dir.path}/store.sqlite';
      try {
        var db = openIesimStore(path);
        db.execute(
          "INSERT INTO subscriptions "
          "(id, number, keepalive_required, keepalive_confidence, "
          " plan_is_long_term, tags_json, time_zone_id, created_at, updated_at) "
          "VALUES ('s1', '13800000000', 0, 'confirmed', 0, '[]', "
          " 'Asia/Shanghai', '2026-08-07T00:00:00.000Z', '2026-08-07T00:00:00.000Z')",
        );
        db.close();

        db = openIesimStore(path);
        final rows = db.select('SELECT id FROM subscriptions');
        expect(rows.single['id'], equals('s1'));
        db.close();
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
```

- [x] **Step 7: 运行测试确认失败**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/store/database_test.dart
```

Expected: FAIL，找不到 `database.dart`。

- [x] **Step 8: 实现 database.dart**

写入 `packages/iesim_core/lib/src/store/database.dart`：

```dart
import 'package:sqlite3/sqlite3.dart';

/// 打开 iesim 存储数据库并应用 schema。
///
/// [path] 为 SQLite 文件路径；测试传 `:memory:` 获得内存库。
/// 每次打开均开启外键约束（SQLite 默认关闭）并幂等建表。
Database openIesimStore(String path) {
  final db = sqlite3.open(path);
  db.execute('PRAGMA foreign_keys = ON');
  createSchema(db);
  return db;
}

/// 幂等建表。
///
/// schema 版本记录于 `PRAGMA user_version`，后续迁移（计划 4 起）
/// 以此为锚点递增。
void createSchema(Database db) {
  db.execute('''
CREATE TABLE IF NOT EXISTS subscriptions (
  id TEXT PRIMARY KEY,
  iccid TEXT UNIQUE,
  number TEXT NOT NULL,
  operator TEXT,
  plan_name TEXT,
  plan_cycle_minor INTEGER,
  plan_cycle_currency TEXT,
  plan_cycle_days INTEGER,
  plan_start TEXT,
  plan_expiry TEXT,
  plan_is_long_term INTEGER NOT NULL DEFAULT 0,
  keepalive_required INTEGER NOT NULL,
  keepalive_cycle_days INTEGER,
  keepalive_last_activity_at TEXT,
  -- 无默认值：缺失数据不得回退为「安全」档（Global Constraints），写入方必须显式提供
  keepalive_confidence TEXT NOT NULL,
  tags_json TEXT NOT NULL DEFAULT '[]',
  appearance_flag TEXT,
  appearance_color_hex TEXT,
  appearance_background_asset TEXT,
  appearance_website_url TEXT,
  appearance_custom_prompt TEXT,
  time_zone_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS activity_records (
  id TEXT PRIMARY KEY,
  subscription_id TEXT NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  amount_minor INTEGER,
  amount_currency TEXT
);
CREATE INDEX IF NOT EXISTS idx_activity_sub_occ
  ON activity_records(subscription_id, occurred_at);

-- 资产域（v1 仅建表、不开放 UI，spec §9；类型约束由 v2 Dart 类型系统承担）
CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL DEFAULT 'phone',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS slots (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES devices(id),
  label TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL DEFAULT 'physical',
  position INTEGER NOT NULL DEFAULT 0,
  card_id TEXT UNIQUE REFERENCES cards(id),
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS cards (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  physical_iccid TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS eids (
  id TEXT PRIMARY KEY,
  card_id TEXT NOT NULL REFERENCES cards(id),
  value TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS profiles (
  id TEXT PRIMARY KEY,
  eid_id TEXT NOT NULL REFERENCES eids(id),
  iccid TEXT NOT NULL UNIQUE,
  operator_name TEXT,
  created_at TEXT NOT NULL
);

PRAGMA user_version = 1;
''');
}
```

注：`Database.execute` 内部使用 `sqlite3_exec`，支持一次执行多条语句。

- [x] **Step 9: 运行测试确认通过**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/store/database_test.dart
```

Expected: 5 个测试全部 PASS。

- [x] **Step 10: 导出并提交**

在 `packages/iesim_core/lib/iesim_core.dart` 追加：

```dart
export 'src/result.dart';
export 'src/store/database.dart';
```

```bash
cd ~/code/Yeats33/iesim
git add packages/iesim_core/pubspec.yaml \
        packages/iesim_core/pubspec.lock \
        packages/iesim_core/lib/src/result.dart \
        packages/iesim_core/lib/src/store/database.dart \
        packages/iesim_core/test/result_test.dart \
        packages/iesim_core/test/store/database_test.dart \
        packages/iesim_core/lib/iesim_core.dart
git commit -m "feat: 添加 Result 类型与 SQLite 存储骨架（含资产域建表）"
```

---

### Task 6: SubscriptionRepository

**Files:**
- Create: `packages/iesim_core/lib/src/store/subscription_repository.dart`
- Create: `packages/iesim_core/test/store/subscription_repository_test.dart`
- Modify: `packages/iesim_core/lib/iesim_core.dart`

**Interfaces:**
- Consumes: `openIesimStore` / `createSchema`（Task 5）；`Result`/`Ok`/`Err`/`StoreError`（Task 5）；`Subscription`（Task 3）
- Produces: `class SubscriptionRepository`，构造 `SubscriptionRepository(Database db)`，方法：
  - `Result<void> upsert(Subscription subscription)`（`INSERT OR REPLACE`，幂等按 id）
  - `Result<Subscription?> get(String id)`
  - `Result<List<Subscription>> listAll()`（按 `created_at` 升序）
  - `Result<void> delete(String id)`
  - 一切 sqlite 异常捕获为 `Err(StoreError(...))`

- [x] **Step 1: 写失败测试**

写入 `packages/iesim_core/test/store/subscription_repository_test.dart`：

```dart
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:iesim_core/src/model/appearance.dart';
import 'package:iesim_core/src/model/keep_alive.dart';
import 'package:iesim_core/src/model/plan.dart';
import 'package:iesim_core/src/model/subscription.dart';
import 'package:iesim_core/src/result.dart';
import 'package:iesim_core/src/store/database.dart';
import 'package:iesim_core/src/store/subscription_repository.dart';
import 'package:iesim_core/src/value/money.dart';
import 'package:iesim_core/src/value/phone_number.dart';

void main() {
  late Database db;
  late SubscriptionRepository repo;

  setUp(() {
    db = openIesimStore(':memory:');
    repo = SubscriptionRepository(db);
  });

  tearDown(() => db.close());

  Subscription full() => Subscription(
        id: 'sub-1',
        iccid: '89000000000000000001',
        number: PhoneNumber('+8613800000000'),
        operator: '中国移动',
        plan: Plan(
          name: '畅享 5G',
          cyclePrice: const Money(minorUnits: 2900, currencyCode: 'CNY'),
          cycleDays: 30,
          startDate: DateTime.utc(2026, 8, 1),
          expiryDate: DateTime.utc(2026, 8, 31),
          isLongTerm: false,
        ),
        keepAlive: KeepAlive(
          required: true,
          cycleDays: 90,
          lastActivityAt: DateTime.utc(2026, 7, 7, 16, 0),
          confidence: DataConfidence.inferred,
        ),
        tags: const ['主力号', 'eSIM'],
        appearance: const Appearance(flag: '🇨🇳', cardColorHex: '#0a84ff'),
        timeZoneId: 'Asia/Shanghai',
        createdAt: DateTime.utc(2026, 8, 1, 4, 0),
        updatedAt: DateTime.utc(2026, 8, 7, 4, 0),
      );

  group('SubscriptionRepository', () {
    test('空库 listAll 返回空列表', () {
      expect(repo.listAll(), isA<Ok<List<Subscription>>>());
      expect((repo.listAll() as Ok<List<Subscription>>).value, isEmpty);
    });

    test('upsert 后 get 全字段往返一致', () {
      expect(repo.upsert(full()), isA<Ok<void>>());
      final got = (repo.get('sub-1') as Ok<Subscription?>).value!;
      expect(got, equals(full()));
      expect(got.iccid, equals('89000000000000000001'));
      expect(got.plan.cyclePrice, equals(const Money(minorUnits: 2900, currencyCode: 'CNY')));
      expect(got.keepAlive.confidence, equals(DataConfidence.inferred));
      expect(got.appearance.cardColorHex, equals('#0a84ff'));
      expect(got.tags, equals(['主力号', 'eSIM']));
    });

    test('未存在的 id 返回 null', () {
      expect((repo.get('nope') as Ok<Subscription?>).value, isNull);
    });

    test('再次 upsert 覆盖旧值', () {
      repo.upsert(full());
      final updated = full().copyWith(
        operator: '中国联通',
        updatedAt: DateTime.utc(2026, 8, 8, 4, 0),
      );
      repo.upsert(updated);
      final got = (repo.get('sub-1') as Ok<Subscription?>).value!;
      expect(got.operator, equals('中国联通'));
      expect(got.updatedAt, equals(DateTime.utc(2026, 8, 8, 4, 0)));
    });

    test('listAll 按创建时间升序', () {
      // iccid 必须与 full() 不同：schema 的 iccid UNIQUE 会让
      // INSERT OR REPLACE 第二次 upsert 时替换掉 early 行
      final early = full().copyWith(
        id: 'sub-0',
        iccid: '89000000000000000002',
        createdAt: DateTime.utc(2026, 7, 1),
        updatedAt: DateTime.utc(2026, 7, 1),
      );
      repo.upsert(early);
      repo.upsert(full());
      final ids = (repo.listAll() as Ok<List<Subscription>>)
          .value
          .map((s) => s.id)
          .toList();
      expect(ids, equals(['sub-0', 'sub-1']));
    });

    test('delete 后 get 返回 null', () {
      repo.upsert(full());
      expect(repo.delete('sub-1'), isA<Ok<void>>());
      expect((repo.get('sub-1') as Ok<Subscription?>).value, isNull);
    });

    test('数据库关闭后操作返回 Err(StoreError)', () {
      db.close();
      final result = repo.upsert(full());
      expect(result, isA<Err<void>>());
      expect((result as Err).failure, isA<StoreError>());
    });
  });
}
```

- [x] **Step 2: 运行测试确认失败**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/store/subscription_repository_test.dart
```

Expected: FAIL，找不到 `subscription_repository.dart`。

- [x] **Step 3: 实现 SubscriptionRepository**

写入 `packages/iesim_core/lib/src/store/subscription_repository.dart`：

```dart
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../model/appearance.dart';
import '../model/keep_alive.dart';
import '../model/plan.dart';
import '../model/subscription.dart';
import '../result.dart';
import '../value/money.dart';
import '../value/phone_number.dart';

/// 订阅聚合根的持久化仓库。
///
/// 值对象扁平化为单表多列，不存 JSON blob，保证字段可查询。
/// 一切 sqlite 异常捕获为 [StoreError]，不穿透到调用方。
class SubscriptionRepository {
  final Database _db;

  SubscriptionRepository(this._db);

  /// 写入或覆盖订阅（按 id 幂等）。
  Result<void> upsert(Subscription s) {
    try {
      _db.execute(
        '''INSERT OR REPLACE INTO subscriptions (
  id, iccid, number, operator,
  plan_name, plan_cycle_minor, plan_cycle_currency, plan_cycle_days,
  plan_start, plan_expiry, plan_is_long_term,
  keepalive_required, keepalive_cycle_days, keepalive_last_activity_at,
  keepalive_confidence,
  tags_json,
  appearance_flag, appearance_color_hex, appearance_background_asset,
  appearance_website_url, appearance_custom_prompt,
  time_zone_id, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          s.id,
          s.iccid,
          s.number.value,
          s.operator,
          s.plan.name,
          s.plan.cyclePrice?.minorUnits,
          s.plan.cyclePrice?.currencyCode,
          s.plan.cycleDays,
          _toIso(s.plan.startDate),
          _toIso(s.plan.expiryDate),
          s.plan.isLongTerm ? 1 : 0,
          s.keepAlive.required ? 1 : 0,
          s.keepAlive.cycleDays,
          _toIso(s.keepAlive.lastActivityAt),
          s.keepAlive.confidence.name,
          jsonEncode(s.tags),
          s.appearance.flag,
          s.appearance.cardColorHex,
          s.appearance.cardBackgroundAssetName,
          s.appearance.websiteURL,
          s.appearance.customPrompt,
          s.timeZoneId,
          _toIso(s.createdAt)!,
          _toIso(s.updatedAt)!,
        ],
      );
      return const Ok(null);
    } on SqliteException catch (e) {
      return Err(StoreError(e.message));
    } catch (e) {
      return Err(StoreError(e.toString()));
    }
  }

  Result<Subscription?> get(String id) {
    try {
      final rows = _db.select(
        'SELECT * FROM subscriptions WHERE id = ?',
        [id],
      );
      if (rows.isEmpty) return const Ok(null);
      return Ok(_rowToSubscription(rows.single));
    } on SqliteException catch (e) {
      return Err(StoreError(e.message));
    } catch (e) {
      return Err(StoreError(e.toString()));
    }
  }

  /// 全部订阅，按创建时间升序。
  Result<List<Subscription>> listAll() {
    try {
      final rows = _db.select(
        'SELECT * FROM subscriptions ORDER BY created_at ASC',
      );
      return Ok([for (final row in rows) _rowToSubscription(row)]);
    } on SqliteException catch (e) {
      return Err(StoreError(e.message));
    } catch (e) {
      return Err(StoreError(e.toString()));
    }
  }

  Result<void> delete(String id) {
    try {
      _db.execute('DELETE FROM subscriptions WHERE id = ?', [id]);
      return const Ok(null);
    } on SqliteException catch (e) {
      return Err(StoreError(e.message));
    } catch (e) {
      return Err(StoreError(e.toString()));
    }
  }

  Subscription _rowToSubscription(Row row) {
    final cycleMinor = row['plan_cycle_minor'] as int?;
    return Subscription(
      id: row['id'] as String,
      iccid: row['iccid'] as String?,
      number: PhoneNumber(row['number'] as String),
      operator: row['operator'] as String?,
      plan: Plan(
        name: row['plan_name'] as String?,
        cyclePrice: cycleMinor == null
            ? null
            : Money(
                minorUnits: cycleMinor,
                currencyCode: row['plan_cycle_currency'] as String,
              ),
        cycleDays: row['plan_cycle_days'] as int?,
        startDate: _parseUtc(row['plan_start'] as String?),
        expiryDate: _parseUtc(row['plan_expiry'] as String?),
        isLongTerm: row['plan_is_long_term'] == 1,
      ),
      keepAlive: KeepAlive(
        required: row['keepalive_required'] == 1,
        cycleDays: row['keepalive_cycle_days'] as int?,
        lastActivityAt:
            _parseUtc(row['keepalive_last_activity_at'] as String?),
        confidence: DataConfidence.values.byName(
          row['keepalive_confidence'] as String,
        ),
      ),
      tags: (jsonDecode(row['tags_json'] as String) as List)
          .cast<String>(),
      appearance: Appearance(
        flag: row['appearance_flag'] as String?,
        cardColorHex: row['appearance_color_hex'] as String?,
        cardBackgroundAssetName:
            row['appearance_background_asset'] as String?,
        websiteURL: row['appearance_website_url'] as String?,
        customPrompt: row['appearance_custom_prompt'] as String?,
      ),
      timeZoneId: row['time_zone_id'] as String,
      createdAt: _parseUtc(row['created_at'] as String)!,
      updatedAt: _parseUtc(row['updated_at'] as String)!,
    );
  }

  static String? _toIso(DateTime? t) => t?.toIso8601String();

  static DateTime? _parseUtc(String? s) => s == null ? null : DateTime.parse(s);
}
```

- [x] **Step 4: 运行测试确认通过**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/store/subscription_repository_test.dart
```

Expected: 7 个测试全部 PASS。

- [x] **Step 5: 导出并提交**

在 `packages/iesim_core/lib/iesim_core.dart` 追加：

```dart
export 'src/store/subscription_repository.dart';
```

```bash
cd ~/code/Yeats33/iesim
git add packages/iesim_core/lib/src/store/subscription_repository.dart \
        packages/iesim_core/test/store/subscription_repository_test.dart \
        packages/iesim_core/lib/iesim_core.dart
git commit -m "feat: 添加 SubscriptionRepository 持久化"
```

---

### Task 7: ActivityRecordRepository

**Files:**
- Create: `packages/iesim_core/lib/src/store/activity_record_repository.dart`
- Create: `packages/iesim_core/test/store/activity_record_repository_test.dart`
- Modify: `packages/iesim_core/lib/iesim_core.dart`

**Interfaces:**
- Consumes: `openIesimStore`（Task 5）；`Result`/`StoreError`（Task 5）；`ActivityRecord`/`ActivityType`（Task 4）；`SubscriptionRepository`（Task 6，级联测试用）
- Produces: `class ActivityRecordRepository`，构造 `ActivityRecordRepository(Database db)`，方法：
  - `Result<void> append(ActivityRecord record)`
  - `Result<List<ActivityRecord>> listBySubscription(String subscriptionId)`（按 `occurred_at` 升序）
  - `Result<List<ActivityRecord>> listAll()`（计划 4 同步用，按 `occurred_at` 升序）
  - 一切 sqlite 异常捕获为 `Err(StoreError(...))`

- [x] **Step 1: 写失败测试**

写入 `packages/iesim_core/test/store/activity_record_repository_test.dart`：

```dart
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:iesim_core/src/model/activity_record.dart';
import 'package:iesim_core/src/model/keep_alive.dart';
import 'package:iesim_core/src/model/plan.dart';
import 'package:iesim_core/src/model/subscription.dart';
import 'package:iesim_core/src/result.dart';
import 'package:iesim_core/src/store/activity_record_repository.dart';
import 'package:iesim_core/src/store/database.dart';
import 'package:iesim_core/src/store/subscription_repository.dart';
import 'package:iesim_core/src/value/money.dart';
import 'package:iesim_core/src/value/phone_number.dart';

void main() {
  late Database db;
  late ActivityRecordRepository repo;
  late SubscriptionRepository subs;

  setUp(() {
    db = openIesimStore(':memory:');
    repo = ActivityRecordRepository(db);
    subs = SubscriptionRepository(db);
  });

  tearDown(() => db.close());

  void seedSubscription(String id) {
    subs.upsert(Subscription(
      id: id,
      number: PhoneNumber('13800000000'),
      plan: Plan(),
      keepAlive: KeepAlive.notRequired(),
      timeZoneId: 'Asia/Shanghai',
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
    ));
  }

  ActivityRecord record(String id, String subId, DateTime at) =>
      ActivityRecord(
        id: id,
        subscriptionId: subId,
        type: ActivityType.topUp,
        occurredAt: at,
        amount: const Money(minorUnits: 5000, currencyCode: 'CNY'),
      );

  group('ActivityRecordRepository', () {
    test('append 后 listBySubscription 按时间升序返回', () {
      seedSubscription('sub-1');
      repo.append(record('a', 'sub-1', DateTime.utc(2026, 8, 3)));
      repo.append(record('b', 'sub-1', DateTime.utc(2026, 8, 1)));
      repo.append(record('c', 'sub-1', DateTime.utc(2026, 8, 2)));
      final got = (repo.listBySubscription('sub-1') as Ok<List<ActivityRecord>>)
          .value
          .map((r) => r.id)
          .toList();
      expect(got, equals(['b', 'c', 'a']));
    });

    test('listAll 跨订阅返回全部记录', () {
      seedSubscription('sub-1');
      seedSubscription('sub-2');
      repo.append(record('a', 'sub-1', DateTime.utc(2026, 8, 1)));
      repo.append(record('b', 'sub-2', DateTime.utc(2026, 8, 2)));
      expect((repo.listAll() as Ok<List<ActivityRecord>>).value, hasLength(2));
    });

    test('字段往返一致', () {
      seedSubscription('sub-1');
      repo.append(record('a', 'sub-1', DateTime.utc(2026, 8, 1)));
      final got = (repo.listBySubscription('sub-1') as Ok<List<ActivityRecord>>)
          .value
          .single;
      expect(
        got,
        equals(record('a', 'sub-1', DateTime.utc(2026, 8, 1))),
      );
      expect(got.amount, equals(const Money(minorUnits: 5000, currencyCode: 'CNY')));
    });

    test('不存在的订阅 append 返回 Err(StoreError)（外键约束）', () {
      final result = repo.append(record('a', 'no-such-sub', DateTime.utc(2026, 8, 1)));
      expect(result, isA<Err<void>>());
      expect((result as Err).failure, isA<StoreError>());
    });

    test('删除订阅后其动作记录级联删除', () {
      seedSubscription('sub-1');
      repo.append(record('a', 'sub-1', DateTime.utc(2026, 8, 1)));
      subs.delete('sub-1');
      expect((repo.listBySubscription('sub-1') as Ok<List<ActivityRecord>>).value,
          isEmpty);
    });

    test('数据库关闭后操作返回 Err(StoreError)', () {
      db.close();
      expect(repo.listAll(), isA<Err<List<ActivityRecord>>>());
    });
  });
}
```

- [x] **Step 2: 运行测试确认失败**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/store/activity_record_repository_test.dart
```

Expected: FAIL，找不到 `activity_record_repository.dart`。

- [x] **Step 3: 实现 ActivityRecordRepository**

写入 `packages/iesim_core/lib/src/store/activity_record_repository.dart`：

```dart
import 'package:sqlite3/sqlite3.dart';

import '../model/activity_record.dart';
import '../result.dart';
import '../value/money.dart';

/// 续存动作记录的持久化仓库。
///
/// 按订阅查询供 UI 展示历史；listAll 供计划 4 同步快照使用。
class ActivityRecordRepository {
  final Database _db;

  ActivityRecordRepository(this._db);

  /// 追加一条动作记录。
  Result<void> append(ActivityRecord record) {
    try {
      _db.execute(
        '''INSERT INTO activity_records
  (id, subscription_id, type, occurred_at, amount_minor, amount_currency)
  VALUES (?, ?, ?, ?, ?, ?)''',
        [
          record.id,
          record.subscriptionId,
          record.type.name,
          record.occurredAt.toIso8601String(),
          record.amount?.minorUnits,
          record.amount?.currencyCode,
        ],
      );
      return const Ok(null);
    } on SqliteException catch (e) {
      return Err(StoreError(e.message));
    } catch (e) {
      return Err(StoreError(e.toString()));
    }
  }

  /// 某订阅的全部动作记录，按发生时刻升序。
  Result<List<ActivityRecord>> listBySubscription(String subscriptionId) {
    try {
      final rows = _db.select(
        'SELECT * FROM activity_records WHERE subscription_id = ? '
        'ORDER BY occurred_at ASC',
        [subscriptionId],
      );
      return Ok([for (final row in rows) _rowToRecord(row)]);
    } on SqliteException catch (e) {
      return Err(StoreError(e.message));
    } catch (e) {
      return Err(StoreError(e.toString()));
    }
  }

  /// 全部动作记录，按发生时刻升序（计划 4 同步快照用）。
  Result<List<ActivityRecord>> listAll() {
    try {
      final rows = _db.select(
        'SELECT * FROM activity_records ORDER BY occurred_at ASC',
      );
      return Ok([for (final row in rows) _rowToRecord(row)]);
    } on SqliteException catch (e) {
      return Err(StoreError(e.message));
    } catch (e) {
      return Err(StoreError(e.toString()));
    }
  }

  ActivityRecord _rowToRecord(Row row) {
    final minor = row['amount_minor'] as int?;
    return ActivityRecord(
      id: row['id'] as String,
      subscriptionId: row['subscription_id'] as String,
      type: ActivityType.values.byName(row['type'] as String),
      occurredAt: DateTime.parse(row['occurred_at'] as String),
      amount: minor == null
          ? null
          : Money(
              minorUnits: minor,
              currencyCode: row['amount_currency'] as String,
            ),
    );
  }
}
```

- [x] **Step 4: 运行测试确认通过**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/store/activity_record_repository_test.dart
```

Expected: 6 个测试全部 PASS。

- [x] **Step 5: 导出并提交**

在 `packages/iesim_core/lib/iesim_core.dart` 追加：

```dart
export 'src/store/activity_record_repository.dart';
```

```bash
cd ~/code/Yeats33/iesim
git add packages/iesim_core/lib/src/store/activity_record_repository.dart \
        packages/iesim_core/test/store/activity_record_repository_test.dart \
        packages/iesim_core/lib/iesim_core.dart
git commit -m "feat: 添加 ActivityRecordRepository 持久化"
```

---

### Task 8: 全量验证与覆盖率收尾

**Files:**
- 无新文件；如覆盖率不足 80%，补用例

**Interfaces:**
- Consumes: 全部前置任务产出

- [x] **Step 1: 全量测试与静态分析**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
export PATH="$HOME/flutter/bin:$PATH"
dart test
dart analyze
```

Expected: 全部测试通过（计划 1 的 45 个 + 本计划新增），`dart analyze` 无 issue。

- [x] **Step 2: 覆盖率检查**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
export PATH="$HOME/flutter/bin:$PATH"
dart run test --coverage=.coverage
dart pub global run coverage:format_coverage \
  --packages=.dart_tool/package_config.json \
  --report-on=lib --in=.coverage --out=coverage_report.lcov \
  --check-ignore --lcov
```

写入 `/tmp/cov_lcov.dart` 并运行（解析 lcov，输出每文件与总计覆盖率）：

```dart
import 'dart:io';

void main() {
  final lines = File('coverage_report.lcov').readAsStringSync().split('\n');
  String file = '';
  int fileHit = 0, fileTotal = 0;
  int totalHit = 0, totalTotal = 0;

  void summarize() {
    if (file.isEmpty) return;
    final pct = fileTotal == 0 ? 100.0 : fileHit * 100 / fileTotal;
    print('$file: ${pct.toStringAsFixed(1)}% ($fileHit/$fileTotal)');
  }

  for (final line in lines) {
    if (line.startsWith('SF:')) { file = line.substring(3); continue; }
    if (line.startsWith('DA:')) {
      final parts = line.split(',');
      final count = int.parse(parts[1]);
      fileTotal++;
      if (count > 0) fileHit++;
      continue;
    }
    if (line.startsWith('end_of_record')) {
      summarize();
      totalHit += fileHit;
      totalTotal += fileTotal;
      file = ''; fileHit = 0; fileTotal = 0;
    }
  }
  print('总计: ${(totalHit * 100 / totalTotal).toStringAsFixed(1)}% ($totalHit/$totalTotal)');
}
```

```bash
dart /tmp/cov_lcov.dart
```

Expected: 总计 ≥80%。不足则参照计划 1 的收尾提交（`test: 补齐 Money 与 KeepAlive 用例，覆盖率升至 100%`）的模式补齐用例——重点检查 `model/` 各构造分支与仓库异常分支是否已覆盖。

- [x] **Step 3: 清理产物并提交收尾**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
rm -rf .coverage coverage_report.lcov coverage_report.json
cd ~/code/Yeats33/iesim
git status --short   # 应只剩本计划之外的内容（如 .omc/ 工具目录，不提交）
```

若 Step 2 补了用例，提交：

```bash
git add packages/iesim_core/test/
git commit -m "test: 补齐覆盖率至 80% 以上"
```

- [x] **Step 4: 勾选计划**

将本文件所有任务复选框勾选为 `- [x]`，并提交：

```bash
cd ~/code/Yeats33/iesim
git add docs/superpowers/plans/2026-08-07-subscription-and-store.md
git commit -m "docs: 标记计划 2 完成"
```

---

## 本计划的交付物

完成后 `iesim_core` 提供：

- `PhoneNumber` — 号码值对象，规范化存储
- `Plan` / `Appearance` — 套餐与外观模型（含 SimHub JSON 对应字段）
- `Subscription` — 订阅聚合根（含 `createdAt`/`updatedAt` 同步时间戳）
- `ActivityRecord` / `ActivityType` — 续存动作事件流
- `Result<T>` / `Failure` / `StoreError` — 统一 IO 错误返回（spec §7）
- `openIesimStore` / `createSchema` — SQLite 打开与幂等建表（含资产域 5 表、`user_version=1`）
- `SubscriptionRepository` / `ActivityRecordRepository` — CRUD，异常收敛为 `Err(StoreError)`

全部可在无 GUI 的 Linux 服务器上 `dart test` 验证，覆盖率目标 80%。

## 后续计划（不在本计划范围）

- **计划 3**：互操作——SimHub JSON 导入导出、Nekoko `t:`/`d:` 标签编解码（可交叉对照 `/root/refs/simhubweb` 的 `normalize_dto`，见记忆 `simhubweb-reference`）
- **计划 4**：WebDAV 同步——ETag 乐观锁、记录级合并、墓碑（届时为 `activity_records` 与订阅建墓碑表，`updated_at` 已就位）
- **计划 5**：`schedule/` 提醒时刻推算 + Flutter UI + 本地通知预排程

资产域 Dart 类型（`EmbeddedEuicc` 不可拆卸的编译期约束，spec §3.1 决定 2）与 `AssetEvent` 迁移事件流属 v2，本计划仅完成其表结构。
