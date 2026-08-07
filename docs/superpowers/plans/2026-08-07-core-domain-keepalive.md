# iesim 核心领域模型与保号逻辑 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `iesim_core` 包的领域模型与保号状态计算，产出一个可独立测试、不依赖 Flutter 平台插件的业务核心库。

**Architecture:** monorepo 分包。`packages/iesim_core` 承载全部业务规则，时间一律以 UTC 存储、按订阅的 IANA 基准时区做日历日运算。平台能力（设备时区、通知）通过接口注入，core 内不直接调用平台插件，以保证测试可在无 GUI 的 Linux 服务器执行。

**Tech Stack:** Dart 3.12.2 / Flutter 3.44.9，`timezone` ^0.11.1（IANA 时区数据库），`test` ^1.25.0。

## Global Constraints

- Dart SDK 下限 `^3.10.0`（与 NekokoLPA2 对齐，便于 v2 复用其代码）。
- 时间存储一律 UTC；显示与天数计算一律在订阅的 `timeZoneId`（IANA 标识）下进行。
- 所有领域实体为不可变类，更新通过 `copyWith` 返回新实例，禁止字段可变。
- `iesim_core` 不得直接依赖平台插件（含原生实现的包，如 `flutter_timezone`、`flutter_local_notifications`）。平台能力通过抽象接口注入。
- 金额一律以最小货币单位整数（`minorUnits`）存储，禁止使用 `double` 表示金额。
- 缺失数据不得呈现为「安全」。`lastActivityAt` 缺失且无从推测时，状态必须为 `Unknown`。
- 单文件 200-400 行为宜，上限 800 行。
- 测试覆盖率目标 80%，`keepalive/` 模块要求 90% 以上。

## 前置条件

开发在 netcup 服务器（Debian 13）进行，仓库位于 `~/code/Yeats33/iesim`，git 身份由目录自动套用为 Yeats33。

Flutter SDK 解压于 `~/flutter`。每个 shell 会话执行任务前须确保 PATH 就绪：

```bash
export PATH="$HOME/flutter/bin:$PATH"
dart --version   # 期望 Dart SDK version: 3.12.2
```

如需持久生效，追加至 `~/.bashrc`：

```bash
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
```

首次运行 `dart` 或 `flutter` 命令时 SDK 会自解压并下载少量依赖，耗时数分钟，属正常现象。

---

## File Structure

```
iesim/
├── packages/
│   └── iesim_core/
│       ├── pubspec.yaml
│       ├── lib/
│       │   ├── iesim_core.dart              统一导出
│       │   └── src/
│       │       ├── value/
│       │       │   ├── money.dart           金额值对象
│       │       │   └── phone_number.dart    号码值对象
│       │       ├── time/
│       │       │   ├── clock.dart           时钟接口与实现（可注入）
│       │       │   └── calendar.dart        基准时区下的日历日运算
│       │       ├── model/
│       │       │   ├── plan.dart            套餐
│       │       │   ├── keep_alive.dart      保号策略与可信度
│       │       │   └── subscription.dart    订阅聚合根
│       │       └── keepalive/
│       │           ├── status.dart          KeepAliveStatus sealed 类
│       │           └── evaluator.dart       状态计算
│       └── test/
│           ├── value/money_test.dart
│           ├── time/calendar_test.dart
│           ├── model/subscription_test.dart
│           └── keepalive/evaluator_test.dart
```

**职责边界**：`time/` 只做时间换算不含业务语义；`keepalive/` 只做状态判定不碰持久化；`model/` 只定义数据不含计算。这样 `evaluator` 可以用假时钟完整测试，无需构造数据库。

---

### Task 1: 初始化 monorepo 与 iesim_core 包骨架

**Files:**
- Create: `packages/iesim_core/pubspec.yaml`
- Create: `packages/iesim_core/lib/iesim_core.dart`
- Create: `packages/iesim_core/test/smoke_test.dart`
- Create: `packages/iesim_core/analysis_options.yaml`

**Interfaces:**
- Consumes: 无（首个任务）
- Produces: 可运行 `dart test` 的包结构；库入口 `package:iesim_core/iesim_core.dart`

- [ ] **Step 1: 创建包目录与 pubspec**

```bash
mkdir -p ~/code/Yeats33/iesim/packages/iesim_core/lib/src
mkdir -p ~/code/Yeats33/iesim/packages/iesim_core/test
```

写入 `packages/iesim_core/pubspec.yaml`：

```yaml
name: iesim_core
description: iesim 业务核心：订阅、保号、资产模型。不依赖平台插件。
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.10.0

dependencies:
  timezone: ^0.11.1

dev_dependencies:
  test: ^1.25.0
  lints: ^5.0.0
```

- [ ] **Step 2: 写入 lint 配置**

写入 `packages/iesim_core/analysis_options.yaml`：

```yaml
include: package:lints/recommended.yaml

linter:
  rules:
    - prefer_final_fields
    - prefer_const_constructors
    - avoid_print
    - always_declare_return_types
```

- [ ] **Step 3: 写入库入口占位与冒烟测试**

写入 `packages/iesim_core/lib/iesim_core.dart`：

```dart
/// iesim 业务核心库。
library;
```

写入 `packages/iesim_core/test/smoke_test.dart`：

```dart
import 'package:test/test.dart';

void main() {
  test('测试工具链可运行', () {
    expect(1 + 1, equals(2));
  });
}
```

- [ ] **Step 4: 拉取依赖并运行测试**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart pub get
dart test
```

Expected: 1 个测试通过。若 `dart` 命令不存在，先确认 `~/flutter/bin` 已加入 PATH。

- [ ] **Step 5: 提交**

```bash
cd ~/code/Yeats33/iesim
git add packages/
git commit -m "chore: 初始化 iesim_core 包骨架"
```

---

### Task 2: Money 值对象

**Files:**
- Create: `packages/iesim_core/lib/src/value/money.dart`
- Create: `packages/iesim_core/test/value/money_test.dart`
- Modify: `packages/iesim_core/lib/iesim_core.dart`

**Interfaces:**
- Consumes: 无
- Produces: `Money({required int minorUnits, required String currencyCode})`，含 `operator ==`、`hashCode`、`copyWith`、`Money.zero(String currencyCode)`，以及跨币种相加时抛出的 `CurrencyMismatchError`

- [ ] **Step 1: 写失败测试**

写入 `packages/iesim_core/test/value/money_test.dart`：

```dart
import 'package:test/test.dart';
import 'package:iesim_core/src/value/money.dart';

void main() {
  group('Money', () {
    test('相同金额与币种视为相等', () {
      expect(
        const Money(minorUnits: 1990, currencyCode: 'CNY'),
        equals(const Money(minorUnits: 1990, currencyCode: 'CNY')),
      );
    });

    test('币种不同则不相等', () {
      expect(
        const Money(minorUnits: 1990, currencyCode: 'CNY'),
        isNot(equals(const Money(minorUnits: 1990, currencyCode: 'USD'))),
      );
    });

    test('同币种相加', () {
      const a = Money(minorUnits: 1000, currencyCode: 'CNY');
      const b = Money(minorUnits: 990, currencyCode: 'CNY');
      expect(a + b, equals(const Money(minorUnits: 1990, currencyCode: 'CNY')));
    });

    test('跨币种相加抛出 CurrencyMismatchError', () {
      const a = Money(minorUnits: 1000, currencyCode: 'CNY');
      const b = Money(minorUnits: 1000, currencyCode: 'USD');
      expect(() => a + b, throwsA(isA<CurrencyMismatchError>()));
    });

    test('zero 构造出对应币种的零值', () {
      expect(
        Money.zero('JPY'),
        equals(const Money(minorUnits: 0, currencyCode: 'JPY')),
      );
    });

    test('负数金额允许（用于退款与调整）', () {
      expect(
        const Money(minorUnits: -500, currencyCode: 'CNY').minorUnits,
        equals(-500),
      );
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/value/money_test.dart
```

Expected: FAIL，报错 `Error: Couldn't resolve the package 'iesim_core'` 或找不到 `money.dart`。

- [ ] **Step 3: 实现 Money**

写入 `packages/iesim_core/lib/src/value/money.dart`：

```dart
/// 跨币种运算错误。金额禁止隐式换算。
class CurrencyMismatchError extends Error {
  final String left;
  final String right;

  CurrencyMismatchError(this.left, this.right);

  @override
  String toString() => '币种不匹配：$left 与 $right 不可直接运算';
}

/// 金额值对象。
///
/// 以最小货币单位的整数存储（如人民币的分、日元的円），
/// 避免浮点误差。此做法沿用自 SimJ 的 cyclePaymentMinorUnits。
class Money {
  /// 最小货币单位数量。允许为负，用于表示退款或调整。
  final int minorUnits;

  /// ISO 4217 币种代码，如 CNY、USD、JPY。
  final String currencyCode;

  const Money({required this.minorUnits, required this.currencyCode});

  factory Money.zero(String currencyCode) =>
      Money(minorUnits: 0, currencyCode: currencyCode);

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(
      minorUnits: minorUnits + other.minorUnits,
      currencyCode: currencyCode,
    );
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(
      minorUnits: minorUnits - other.minorUnits,
      currencyCode: currencyCode,
    );
  }

  void _assertSameCurrency(Money other) {
    if (currencyCode != other.currencyCode) {
      throw CurrencyMismatchError(currencyCode, other.currencyCode);
    }
  }

  Money copyWith({int? minorUnits, String? currencyCode}) => Money(
        minorUnits: minorUnits ?? this.minorUnits,
        currencyCode: currencyCode ?? this.currencyCode,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money &&
          other.minorUnits == minorUnits &&
          other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(minorUnits, currencyCode);

  @override
  String toString() => 'Money($minorUnits $currencyCode)';
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/value/money_test.dart
```

Expected: 6 个测试全部 PASS。

- [ ] **Step 5: 导出并提交**

将 `packages/iesim_core/lib/iesim_core.dart` 改为：

```dart
/// iesim 业务核心库。
library;

export 'src/value/money.dart';
```

```bash
cd ~/code/Yeats33/iesim
git add packages/iesim_core/lib/src/value/money.dart \
        packages/iesim_core/test/value/money_test.dart \
        packages/iesim_core/lib/iesim_core.dart
git commit -m "feat: 添加 Money 值对象，金额以最小货币单位整数存储"
```

---

### Task 3: 可注入时钟

**Files:**
- Create: `packages/iesim_core/lib/src/time/clock.dart`
- Create: `packages/iesim_core/test/time/clock_test.dart`
- Modify: `packages/iesim_core/lib/iesim_core.dart`

**Interfaces:**
- Consumes: 无
- Produces: 抽象类 `Clock` 含 `DateTime nowUtc()`；实现 `SystemClock()` 与 `FixedClock(DateTime utcInstant)`。后续 `KeepAliveEvaluator` 依赖 `Clock` 而非 `DateTime.now()`

**为什么需要**：业务逻辑若直接调用 `DateTime.now()`，保号状态测试将无法构造「距截止还有 3 天」这类场景，只能依赖真实时间，测试不可重现。

- [ ] **Step 1: 写失败测试**

写入 `packages/iesim_core/test/time/clock_test.dart`：

```dart
import 'package:test/test.dart';
import 'package:iesim_core/src/time/clock.dart';

void main() {
  group('FixedClock', () {
    test('始终返回构造时给定的时刻', () {
      final instant = DateTime.utc(2026, 8, 7, 12, 0);
      final clock = FixedClock(instant);
      expect(clock.nowUtc(), equals(instant));
      expect(clock.nowUtc(), equals(instant));
    });

    test('拒绝非 UTC 时刻，避免基准歧义', () {
      final local = DateTime(2026, 8, 7, 12, 0);
      expect(() => FixedClock(local), throwsArgumentError);
    });
  });

  group('SystemClock', () {
    test('返回的时刻标记为 UTC', () {
      expect(const SystemClock().nowUtc().isUtc, isTrue);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/time/clock_test.dart
```

Expected: FAIL，找不到 `clock.dart`。

- [ ] **Step 3: 实现 Clock**

写入 `packages/iesim_core/lib/src/time/clock.dart`：

```dart
/// 时钟抽象。
///
/// 业务逻辑一律通过此接口取当前时刻，不直接调用 DateTime.now()，
/// 否则依赖时间的测试无法构造确定场景。
abstract class Clock {
  const Clock();

  /// 当前时刻，始终为 UTC。
  DateTime nowUtc();
}

/// 生产环境时钟。
class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// 测试用固定时钟。
class FixedClock extends Clock {
  final DateTime _instant;

  /// [instant] 必须为 UTC，否则抛出 ArgumentError。
  FixedClock(DateTime instant) : _instant = instant {
    if (!instant.isUtc) {
      throw ArgumentError.value(instant, 'instant', '必须为 UTC 时刻');
    }
  }

  @override
  DateTime nowUtc() => _instant;
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/time/clock_test.dart
```

Expected: 3 个测试全部 PASS。

- [ ] **Step 5: 导出并提交**

在 `packages/iesim_core/lib/iesim_core.dart` 追加：

```dart
export 'src/time/clock.dart';
```

```bash
cd ~/code/Yeats33/iesim
git add packages/iesim_core/lib/src/time/clock.dart \
        packages/iesim_core/test/time/clock_test.dart \
        packages/iesim_core/lib/iesim_core.dart
git commit -m "feat: 添加可注入时钟，使依赖时间的逻辑可测"
```

---

### Task 4: 基准时区下的日历日运算

**Files:**
- Create: `packages/iesim_core/lib/src/time/calendar.dart`
- Create: `packages/iesim_core/test/time/calendar_test.dart`
- Modify: `packages/iesim_core/lib/iesim_core.dart`

**Interfaces:**
- Consumes: 无
- Produces: `ZonedCalendar(String timeZoneId)`，含 `int daysBetween(DateTime fromUtc, DateTime toUtc)` 与 `DateTime addDays(DateTime utc, int days)`；顶层函数 `void initializeIesimTimeZones()`

**核心规则**：剩余天数是「翻多少页日历」，不是「相差多少小时除以 24」。夏令时切换日只有 23 或 25 小时，用时长相除会得出错误天数。因此实现必须先在目标时区取出年月日，再做纯日期减法。

- [ ] **Step 1: 写失败测试**

写入 `packages/iesim_core/test/time/calendar_test.dart`：

```dart
import 'package:test/test.dart';
import 'package:iesim_core/src/time/calendar.dart';

void main() {
  setUpAll(initializeIesimTimeZones);

  group('ZonedCalendar.daysBetween', () {
    test('同一日历日内的不同时刻相差 0 天', () {
      final cal = ZonedCalendar('Asia/Shanghai');
      // 北京时间 2026-08-07 01:00 与 23:00
      final a = DateTime.utc(2026, 8, 6, 17, 0);
      final b = DateTime.utc(2026, 8, 7, 15, 0);
      expect(cal.daysBetween(a, b), equals(0));
    });

    test('跨日历日相差 1 天，即便实际间隔不足 24 小时', () {
      final cal = ZonedCalendar('Asia/Shanghai');
      // 北京时间 2026-08-07 23:00 与 2026-08-08 01:00，实际仅隔 2 小时
      final a = DateTime.utc(2026, 8, 7, 15, 0);
      final b = DateTime.utc(2026, 8, 7, 17, 0);
      expect(cal.daysBetween(a, b), equals(1));
    });

    test('各时区按各自本地日历计数', () {
      final a = DateTime.utc(2026, 8, 7, 20, 0);
      final b = DateTime.utc(2026, 8, 9, 20, 0);
      // 上海：8/8 04:00 → 8/10 04:00，相差 2 天
      expect(ZonedCalendar('Asia/Shanghai').daysBetween(a, b), equals(2));
      // 纽约：8/7 16:00 → 8/9 16:00，相差 2 天
      expect(ZonedCalendar('America/New_York').daysBetween(a, b), equals(2));
    });

    test('落在时区分界两侧的同一时刻归属不同日历日', () {
      // 2026-08-07 20:00 UTC：上海已是 8/8 凌晨，纽约仍是 8/7 下午
      final instant = DateTime.utc(2026, 8, 7, 20, 0);
      final dayStart = DateTime.utc(2026, 8, 7, 0, 0);
      // 上海：8/7 08:00 → 8/8 04:00，跨了一个日历日
      expect(ZonedCalendar('Asia/Shanghai').daysBetween(dayStart, instant),
          equals(1));
      // 纽约：8/6 20:00 → 8/7 16:00，同样跨一日但起点不同
      expect(ZonedCalendar('America/New_York').daysBetween(dayStart, instant),
          equals(1));
    });

    test('夏令时切换日仍按日历日计数', () {
      final cal = ZonedCalendar('America/New_York');
      // 2026-03-08 是美国夏令时开始日，当天只有 23 小时
      final a = DateTime.utc(2026, 3, 8, 12, 0); // 纽约 3/8 07:00 EST→EDT
      final b = DateTime.utc(2026, 3, 9, 12, 0); // 纽约 3/9 08:00 EDT
      expect(cal.daysBetween(a, b), equals(1));
    });

    test('起点晚于终点时返回负数', () {
      final cal = ZonedCalendar('Asia/Shanghai');
      final a = DateTime.utc(2026, 8, 10, 0, 0);
      final b = DateTime.utc(2026, 8, 7, 0, 0);
      expect(cal.daysBetween(a, b), equals(-3));
    });

    test('极端时区 UTC+14 可用', () {
      final cal = ZonedCalendar('Pacific/Kiritimati');
      final a = DateTime.utc(2026, 8, 7, 0, 0);
      final b = DateTime.utc(2026, 8, 8, 0, 0);
      expect(cal.daysBetween(a, b), equals(1));
    });

    test('未知时区标识抛出 ArgumentError', () {
      expect(() => ZonedCalendar('Not/AZone'), throwsArgumentError);
    });
  });

  group('ZonedCalendar.addDays', () {
    test('加天数保持当地时钟时间', () {
      final cal = ZonedCalendar('Asia/Shanghai');
      final start = DateTime.utc(2026, 8, 7, 4, 0); // 北京 12:00
      final result = cal.addDays(start, 30);
      expect(cal.daysBetween(start, result), equals(30));
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/time/calendar_test.dart
```

Expected: FAIL，找不到 `calendar.dart`。

- [ ] **Step 3: 实现 ZonedCalendar**

写入 `packages/iesim_core/lib/src/time/calendar.dart`：

```dart
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _initialized = false;

/// 加载 IANA 时区数据库。使用 ZonedCalendar 前必须调用一次。
/// 重复调用安全。
void initializeIesimTimeZones() {
  if (_initialized) return;
  tzdata.initializeTimeZones();
  _initialized = true;
}

/// 在指定基准时区下进行日历日运算。
///
/// 剩余天数的语义是「翻过多少页日历」，而非「相差多少小时除以 24」。
/// 夏令时切换日只有 23 或 25 小时，按时长相除会得出错误结果。
class ZonedCalendar {
  final tz.Location _location;

  /// [timeZoneId] 为 IANA 标识，如 Asia/Shanghai。
  /// 标识无效时抛出 ArgumentError。
  ZonedCalendar(String timeZoneId) : _location = _resolve(timeZoneId);

  static tz.Location _resolve(String timeZoneId) {
    try {
      return tz.getLocation(timeZoneId);
    } catch (_) {
      throw ArgumentError.value(
        timeZoneId,
        'timeZoneId',
        '未知的 IANA 时区标识（是否忘记调用 initializeIesimTimeZones）',
      );
    }
  }

  /// 两个 UTC 时刻在基准时区下相隔的日历天数。
  /// [toUtc] 早于 [fromUtc] 时返回负数。
  int daysBetween(DateTime fromUtc, DateTime toUtc) {
    final from = _calendarDay(fromUtc);
    final to = _calendarDay(toUtc);
    return to.difference(from).inDays;
  }

  /// 在基准时区下推进 [days] 个日历日，返回对应的 UTC 时刻。
  DateTime addDays(DateTime utc, int days) {
    final zoned = tz.TZDateTime.from(utc, _location);
    final shifted = tz.TZDateTime(
      _location,
      zoned.year,
      zoned.month,
      zoned.day + days,
      zoned.hour,
      zoned.minute,
      zoned.second,
    );
    return shifted.toUtc();
  }

  /// 取该时刻在基准时区下所属的日历日，归一化为 UTC 零点。
  /// 归一化后两日期相减不受时区偏移与夏令时影响。
  DateTime _calendarDay(DateTime utc) {
    final zoned = tz.TZDateTime.from(utc, _location);
    return DateTime.utc(zoned.year, zoned.month, zoned.day);
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/time/calendar_test.dart
```

Expected: 9 个测试全部 PASS。若 `Pacific/Kiritimati` 或夏令时用例失败，先确认 `initializeIesimTimeZones()` 已在 `setUpAll` 中调用。

- [ ] **Step 5: 导出并提交**

在 `packages/iesim_core/lib/iesim_core.dart` 追加：

```dart
export 'src/time/calendar.dart';
```

```bash
cd ~/code/Yeats33/iesim
git add packages/iesim_core/lib/src/time/calendar.dart \
        packages/iesim_core/test/time/calendar_test.dart \
        packages/iesim_core/lib/iesim_core.dart
git commit -m "feat: 添加基准时区日历日运算，消除跨时区与夏令时误差"
```

---

### Task 5: KeepAlive 模型与数据可信度

**Files:**
- Create: `packages/iesim_core/lib/src/model/keep_alive.dart`
- Create: `packages/iesim_core/test/model/keep_alive_test.dart`
- Modify: `packages/iesim_core/lib/iesim_core.dart`

**Interfaces:**
- Consumes: 无
- Produces: `enum DataConfidence { confirmed, inferred }`；`KeepAlive({required bool required, int? cycleDays, DateTime? lastActivityAt, DataConfidence confidence})`，含 `copyWith`、`KeepAlive.notRequired()`、`KeepAlive.inferredFrom(DateTime createdAtUtc, int cycleDays)`

- [ ] **Step 1: 写失败测试**

写入 `packages/iesim_core/test/model/keep_alive_test.dart`：

```dart
import 'package:test/test.dart';
import 'package:iesim_core/src/model/keep_alive.dart';

void main() {
  group('KeepAlive', () {
    test('notRequired 表示长期卡，无需保号', () {
      final k = KeepAlive.notRequired();
      expect(k.required, isFalse);
      expect(k.cycleDays, isNull);
      expect(k.lastActivityAt, isNull);
    });

    test('inferredFrom 以创建时刻作为推测的上次动作时间', () {
      final created = DateTime.utc(2026, 8, 7, 10, 0);
      final k = KeepAlive.inferredFrom(created, 90);
      expect(k.required, isTrue);
      expect(k.cycleDays, equals(90));
      expect(k.lastActivityAt, equals(created));
      expect(k.confidence, equals(DataConfidence.inferred));
    });

    test('明确记录的动作时间为 confirmed', () {
      final k = KeepAlive(
        required: true,
        cycleDays: 90,
        lastActivityAt: DateTime.utc(2026, 8, 1),
        confidence: DataConfidence.confirmed,
      );
      expect(k.confidence, equals(DataConfidence.confirmed));
    });

    test('拒绝非 UTC 的 lastActivityAt', () {
      expect(
        () => KeepAlive(
          required: true,
          cycleDays: 90,
          lastActivityAt: DateTime(2026, 8, 1),
          confidence: DataConfidence.confirmed,
        ),
        throwsArgumentError,
      );
    });

    test('cycleDays 必须为正数', () {
      expect(
        () => KeepAlive(
          required: true,
          cycleDays: 0,
          lastActivityAt: DateTime.utc(2026, 8, 1),
          confidence: DataConfidence.confirmed,
        ),
        throwsArgumentError,
      );
    });

    test('copyWith 记录确认动作后可信度升为 confirmed', () {
      final inferred = KeepAlive.inferredFrom(DateTime.utc(2026, 8, 1), 90);
      final confirmed = inferred.copyWith(
        lastActivityAt: DateTime.utc(2026, 8, 7),
        confidence: DataConfidence.confirmed,
      );
      expect(confirmed.confidence, equals(DataConfidence.confirmed));
      expect(confirmed.lastActivityAt, equals(DateTime.utc(2026, 8, 7)));
      expect(inferred.confidence, equals(DataConfidence.inferred),
          reason: '原实例不可被修改');
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/model/keep_alive_test.dart
```

Expected: FAIL，找不到 `keep_alive.dart`。

- [ ] **Step 3: 实现 KeepAlive**

写入 `packages/iesim_core/lib/src/model/keep_alive.dart`：

```dart
/// 数据可信度。
///
/// 推测值必须在 UI 上可辨识，不得伪装为确凿数据。
enum DataConfidence {
  /// 用户明确填写，或由实际记录的动作推导而来。
  confirmed,

  /// 系统推测所得（如新建订阅时以创建时刻充当上次动作时间）。
  inferred,
}

/// 保号策略。
///
/// 预付费号码需定期产生动作（充值、通话、短信）以免被运营商回收。
/// 保号截止日 = lastActivityAt + cycleDays，与套餐到期日相互独立。
class KeepAlive {
  /// 是否需要保号。长期卡为 false。
  final bool required;

  /// 保号周期天数。required 为 true 时应当提供。
  final int? cycleDays;

  /// 上次动作时刻，UTC。
  final DateTime? lastActivityAt;

  /// lastActivityAt 的可信度。
  final DataConfidence confidence;

  KeepAlive({
    required this.required,
    this.cycleDays,
    this.lastActivityAt,
    this.confidence = DataConfidence.confirmed,
  }) {
    final activity = lastActivityAt;
    if (activity != null && !activity.isUtc) {
      throw ArgumentError.value(
        activity,
        'lastActivityAt',
        '必须为 UTC 时刻',
      );
    }
    final cycle = cycleDays;
    if (cycle != null && cycle <= 0) {
      throw ArgumentError.value(cycle, 'cycleDays', '必须为正数');
    }
  }

  /// 长期卡，无需保号。
  factory KeepAlive.notRequired() => KeepAlive(required: false);

  /// 以创建时刻推测上次动作时间。
  ///
  /// 依据：多数用户在充值后才录入记录，「创建即最近一次动作」通常成立。
  /// 该值标记为 inferred，UI 须以问号角标等方式区分显示。
  factory KeepAlive.inferredFrom(DateTime createdAtUtc, int cycleDays) =>
      KeepAlive(
        required: true,
        cycleDays: cycleDays,
        lastActivityAt: createdAtUtc,
        confidence: DataConfidence.inferred,
      );

  KeepAlive copyWith({
    bool? required,
    int? cycleDays,
    DateTime? lastActivityAt,
    DataConfidence? confidence,
  }) =>
      KeepAlive(
        required: required ?? this.required,
        cycleDays: cycleDays ?? this.cycleDays,
        lastActivityAt: lastActivityAt ?? this.lastActivityAt,
        confidence: confidence ?? this.confidence,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeepAlive &&
          other.required == required &&
          other.cycleDays == cycleDays &&
          other.lastActivityAt == lastActivityAt &&
          other.confidence == confidence;

  @override
  int get hashCode =>
      Object.hash(required, cycleDays, lastActivityAt, confidence);
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/model/keep_alive_test.dart
```

Expected: 6 个测试全部 PASS。

- [ ] **Step 5: 导出并提交**

在 `packages/iesim_core/lib/iesim_core.dart` 追加：

```dart
export 'src/model/keep_alive.dart';
```

```bash
cd ~/code/Yeats33/iesim
git add packages/iesim_core/lib/src/model/keep_alive.dart \
        packages/iesim_core/test/model/keep_alive_test.dart \
        packages/iesim_core/lib/iesim_core.dart
git commit -m "feat: 添加 KeepAlive 模型与数据可信度标记"
```

---

### Task 6: 保号状态与判定

**Files:**
- Create: `packages/iesim_core/lib/src/keepalive/status.dart`
- Create: `packages/iesim_core/lib/src/keepalive/evaluator.dart`
- Create: `packages/iesim_core/test/keepalive/evaluator_test.dart`
- Modify: `packages/iesim_core/lib/iesim_core.dart`

**Interfaces:**
- Consumes: `KeepAlive`、`DataConfidence`（Task 5）；`Clock`、`FixedClock`（Task 3）；`ZonedCalendar`、`initializeIesimTimeZones`（Task 4）
- Produces: sealed 类 `KeepAliveStatus` 及其子类 `NotRequired`、`Safe`、`DueSoon`、`Overdue`、`Unknown`；类 `KeepAliveEvaluator({required Clock clock, int dueSoonThresholdDays = 7})` 含方法 `KeepAliveStatus evaluate(KeepAlive keepAlive, String timeZoneId)`

- [ ] **Step 1: 写失败测试**

写入 `packages/iesim_core/test/keepalive/evaluator_test.dart`：

```dart
import 'package:test/test.dart';
import 'package:iesim_core/src/keepalive/evaluator.dart';
import 'package:iesim_core/src/keepalive/status.dart';
import 'package:iesim_core/src/model/keep_alive.dart';
import 'package:iesim_core/src/time/calendar.dart';
import 'package:iesim_core/src/time/clock.dart';

void main() {
  setUpAll(initializeIesimTimeZones);

  const zone = 'Asia/Shanghai';
  // 北京时间 2026-08-07 12:00
  final now = DateTime.utc(2026, 8, 7, 4, 0);
  KeepAliveEvaluator evaluatorAt(DateTime instant) =>
      KeepAliveEvaluator(clock: FixedClock(instant));

  group('KeepAliveEvaluator', () {
    test('长期卡返回 NotRequired', () {
      final status =
          evaluatorAt(now).evaluate(KeepAlive.notRequired(), zone);
      expect(status, isA<NotRequired>());
    });

    test('缺少 lastActivityAt 返回 Unknown，不得视为安全', () {
      final k = KeepAlive(required: true, cycleDays: 90);
      final status = evaluatorAt(now).evaluate(k, zone);
      expect(status, isA<Unknown>());
    });

    test('缺少 cycleDays 返回 Unknown', () {
      final k = KeepAlive(
        required: true,
        lastActivityAt: DateTime.utc(2026, 8, 1),
      );
      expect(evaluatorAt(now).evaluate(k, zone), isA<Unknown>());
    });

    test('距截止 30 天返回 Safe', () {
      // 上次动作 2026-07-08（北京），周期 60 天 → 截止 2026-09-06，余 30 天
      final k = KeepAlive(
        required: true,
        cycleDays: 60,
        lastActivityAt: DateTime.utc(2026, 7, 7, 16, 0),
        confidence: DataConfidence.confirmed,
      );
      final status = evaluatorAt(now).evaluate(k, zone);
      expect(status, isA<Safe>());
      expect((status as Safe).daysLeft, equals(30));
      expect(status.inferred, isFalse);
    });

    test('距截止 3 天返回 DueSoon', () {
      // 截止 2026-08-10，余 3 天，低于默认阈值 7
      final k = KeepAlive(
        required: true,
        cycleDays: 30,
        lastActivityAt: DateTime.utc(2026, 7, 11, 4, 0),
        confidence: DataConfidence.confirmed,
      );
      final status = evaluatorAt(now).evaluate(k, zone);
      expect(status, isA<DueSoon>());
      expect((status as DueSoon).daysLeft, equals(3));
    });

    test('已超期返回 Overdue 并给出精确超期天数', () {
      // 北京时间：上次动作 2026-05-07，周期 30 天 → 截止 2026-06-06
      // 距今（2026-08-07）超期 24(6月剩) + 31(7月) + 7(8月) = 62 天
      final k = KeepAlive(
        required: true,
        cycleDays: 30,
        lastActivityAt: DateTime.utc(2026, 5, 6, 16, 0),
        confidence: DataConfidence.confirmed,
      );
      final status = evaluatorAt(now).evaluate(k, zone);
      expect(status, isA<Overdue>());
      expect((status as Overdue).daysOver, equals(62));
    });

    test('截止当日返回 DueSoon 且剩余 0 天', () {
      // 截止恰为 2026-08-07
      final k = KeepAlive(
        required: true,
        cycleDays: 30,
        lastActivityAt: DateTime.utc(2026, 7, 8, 4, 0),
        confidence: DataConfidence.confirmed,
      );
      final status = evaluatorAt(now).evaluate(k, zone);
      expect(status, isA<DueSoon>());
      expect((status as DueSoon).daysLeft, equals(0));
    });

    test('推测值产生的状态带 inferred 标记', () {
      final k = KeepAlive.inferredFrom(DateTime.utc(2026, 7, 7, 16, 0), 60);
      final status = evaluatorAt(now).evaluate(k, zone);
      expect(status, isA<Safe>());
      expect((status as Safe).inferred, isTrue);
    });

    test('基准时区不同导致剩余天数相差一天', () {
      // 上次动作 2026-07-08 20:00 UTC，周期 30 天。
      // 上海：动作日 7/9，截止 8/8，距今(8/7) 余 1 天
      // 纽约：动作日 7/8，截止 8/7，距今(纽约 8/7 00:00) 余 0 天
      final k = KeepAlive(
        required: true,
        cycleDays: 30,
        lastActivityAt: DateTime.utc(2026, 7, 8, 20, 0),
        confidence: DataConfidence.confirmed,
      );
      final shanghai = evaluatorAt(now).evaluate(k, 'Asia/Shanghai');
      final newYork = evaluatorAt(now).evaluate(k, 'America/New_York');
      expect(shanghai, isA<DueSoon>());
      expect(newYork, isA<DueSoon>());
      expect((shanghai as DueSoon).daysLeft, equals(1));
      expect((newYork as DueSoon).daysLeft, equals(0));
    });

    test('自定义阈值改变 Safe 与 DueSoon 的分界', () {
      final k = KeepAlive(
        required: true,
        cycleDays: 60,
        lastActivityAt: DateTime.utc(2026, 7, 7, 16, 0),
        confidence: DataConfidence.confirmed,
      );
      final strict = KeepAliveEvaluator(
        clock: FixedClock(now),
        dueSoonThresholdDays: 45,
      );
      expect(strict.evaluate(k, zone), isA<DueSoon>());
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/keepalive/evaluator_test.dart
```

Expected: FAIL，找不到 `evaluator.dart` 与 `status.dart`。

- [ ] **Step 3: 实现状态类型**

写入 `packages/iesim_core/lib/src/keepalive/status.dart`：

```dart
/// 保号状态。
///
/// 使用 sealed 类，UI 侧 switch 强制穷尽，遗漏分支在编译期报错。
sealed class KeepAliveStatus {
  const KeepAliveStatus();
}

/// 长期卡，无需保号。
class NotRequired extends KeepAliveStatus {
  const NotRequired();
}

/// 距截止尚有余裕。
class Safe extends KeepAliveStatus {
  final int daysLeft;

  /// 该判定基于推测的上次动作时间。
  final bool inferred;

  const Safe({required this.daysLeft, required this.inferred});
}

/// 临近截止，需要尽快处理。
class DueSoon extends KeepAliveStatus {
  final int daysLeft;
  final bool inferred;

  const DueSoon({required this.daysLeft, required this.inferred});
}

/// 已超过保号截止日。
class Overdue extends KeepAliveStatus {
  final int daysOver;
  final bool inferred;

  const Overdue({required this.daysOver, required this.inferred});
}

/// 数据不足以判定。
///
/// 缺失数据一律落入此状态，绝不呈现为「安全」——
/// 静默误判是保号工具最不可接受的失败模式。
class Unknown extends KeepAliveStatus {
  const Unknown();
}
```

- [ ] **Step 4: 实现判定逻辑**

写入 `packages/iesim_core/lib/src/keepalive/evaluator.dart`：

```dart
import '../model/keep_alive.dart';
import '../time/calendar.dart';
import '../time/clock.dart';
import 'status.dart';

/// 保号状态判定。
///
/// 截止日在订阅的基准时区下按日历日计算，
/// 使剩余天数不因用户跨时区而跳变。
class KeepAliveEvaluator {
  final Clock _clock;

  /// 剩余天数不超过此值时判为 DueSoon。
  final int dueSoonThresholdDays;

  const KeepAliveEvaluator({
    required Clock clock,
    this.dueSoonThresholdDays = 7,
  }) : _clock = clock;

  /// [timeZoneId] 为订阅的 IANA 基准时区标识。
  KeepAliveStatus evaluate(KeepAlive keepAlive, String timeZoneId) {
    if (!keepAlive.required) {
      return const NotRequired();
    }

    final lastActivity = keepAlive.lastActivityAt;
    final cycleDays = keepAlive.cycleDays;
    if (lastActivity == null || cycleDays == null) {
      return const Unknown();
    }

    final calendar = ZonedCalendar(timeZoneId);
    final deadline = calendar.addDays(lastActivity, cycleDays);
    final daysLeft = calendar.daysBetween(_clock.nowUtc(), deadline);
    final inferred = keepAlive.confidence == DataConfidence.inferred;

    if (daysLeft < 0) {
      return Overdue(daysOver: -daysLeft, inferred: inferred);
    }
    if (daysLeft <= dueSoonThresholdDays) {
      return DueSoon(daysLeft: daysLeft, inferred: inferred);
    }
    return Safe(daysLeft: daysLeft, inferred: inferred);
  }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test test/keepalive/evaluator_test.dart
```

Expected: 10 个测试全部 PASS。若「距截止 30 天」用例算出 29 或 31，检查 `ZonedCalendar.addDays` 是否在目标时区推进日历日而非直接加 `Duration`。

- [ ] **Step 6: 全量测试与覆盖率**

```bash
cd ~/code/Yeats33/iesim/packages/iesim_core
dart test
dart analyze
```

Expected: 全部测试通过，`dart analyze` 无 issue。

- [ ] **Step 7: 导出并提交**

在 `packages/iesim_core/lib/iesim_core.dart` 追加：

```dart
export 'src/keepalive/status.dart';
export 'src/keepalive/evaluator.dart';
```

```bash
cd ~/code/Yeats33/iesim
git add packages/iesim_core/lib/src/keepalive/ \
        packages/iesim_core/test/keepalive/ \
        packages/iesim_core/lib/iesim_core.dart
git commit -m "feat: 添加保号状态判定，缺失数据落入 Unknown 而非 Safe"
```

---

## 本计划的交付物

完成后 `iesim_core` 提供：

- `Money` — 整数金额，跨币种运算受阻
- `Clock` / `FixedClock` — 时间可注入，依赖时间的逻辑可测
- `ZonedCalendar` — 基准时区日历日运算，夏令时与极端时区已覆盖
- `KeepAlive` / `DataConfidence` — 保号策略与推测值标记
- `KeepAliveStatus` / `KeepAliveEvaluator` — 状态判定，穷尽匹配

全部可在无 GUI 的 Linux 服务器上 `dart test` 验证。

## 后续计划（不在本计划范围）

- **计划 2**：`Plan`、`PhoneNumber`、`Subscription` 聚合根，`ActivityRecord` 事件流，SQLite 持久化
- **计划 3**：互操作——SimHub JSON 导入导出、Nekoko `t:`/`d:` 标签编解码
- **计划 4**：WebDAV 同步——ETag 乐观锁、记录级合并、墓碑
- **计划 5**：Flutter UI

资产域（Device / Slot / Card / EID / Profile）按 spec §9 在计划 2 中仅建表，不开放 UI。
