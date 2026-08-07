# iesim 设计文档

- 日期：2026-08-07
- 状态：待评审
- 域名：`ies.im`

## 1. 背景与定位

多卡用户（尤其持有多张预付费卡与实体 eSIM 卡的人）面临两类问题，现有工具都只解决了一半：

1. **订阅会失效** —— 套餐到期需续费；预付费号码若长期无动作会被运营商回收。
2. **资产分散** —— 卡在哪台设备上、哪些卡在抽屉里、某个 profile 装在哪个 EID 上，全靠记忆。

`iesim` 同时解决这两件事，并主动与相邻生态互通，而非要求用户二选一。

### 1.1 竞品

| 项目 | 平台 | 定位 | 结构性弱点 |
|---|---|---|---|
| SimJ (`yanglh1/SimJ`) | Android，Kotlin，约 7100 行 | 保号 + eSIM 管理 | 扁平号码列表；日期为字符串；无历史记录 |
| SimHub (iOS) | iOS，闭源 | 订阅管理 | 同为扁平列表；无资产关系 |
| esimSubscription | iOS，$0.99 | 订阅记录 | 封闭，无互通 |
| NekokoLPA2 (`iebb/NekokoLPA2`) | 六平台，Flutter，MIT | 专业 LPA（写卡） | 不做订阅管理，仅 profile 层标签 |

SimJ 与 SimHub 是直接竞品。二者共同的结构性弱点是**只有号码列表，没有资产关系**——无法回答「这张卡现在在哪台设备上」。

### 1.2 差异化

1. **资产关系模型** —— 设备 / 卡 / EID / Profile / 订阅的完整关系与迁移留痕。
2. **保号截止日与套餐到期日分离** —— 竞品均无「上次动作时间」，无法计算真实的保号风险。
3. **生态枢纽** —— 采用 SimHub JSON 作为交换格式，兼容 Nekoko 标签，用户不必被单一生态锁定。
4. **WebDAV 同步** —— 数据存于用户自有网盘，作者不持有用户数据。

### 1.3 非目标（v1）

- 不实现 LPA 协议栈（写卡、profile 下载）。该能力在 v2 直接复用 NekokoLPA2（MIT）。
- 不实现读卡（OMAPI / CCID）。
- 不做自建云服务与账号体系。

## 2. 技术选型

**纯 Dart（Flutter），不引入 Rust。**

最初考虑 Rust + Flutter，评估后放弃，理由：

- FFI 成本（Android NDK 四 ABI 交叉编译、iOS 静态库、跨语言调试、Rust 改动使 hot reload 失效）在本项目规模上无法收回。
- 本项目非性能敏感场景，数据量为数十至数百条记录。
- v2 要复用 NekokoLPA2 的 LPA 代码（Dart）。若核心为 Rust，项目将变为三语言，单人维护负担显著上升。
- Dart 3.10 的 sealed class、模式匹配、records 已能胜任领域建模与穷尽匹配。

### 2.1 分层

```
iesim/
├── packages/
│   └── iesim_core/           纯 Dart，不依赖 Flutter
│       ├── lib/
│       │   ├── model/        实体定义（资产域 + 订阅域）
│       │   ├── keepalive/    保号周期计算
│       │   ├── schedule/     提醒时刻推算
│       │   ├── sync/         WebDAV 同步与合并
│       │   ├── interop/      SimHub JSON、Nekoko 标签
│       │   └── store/        SQLite 持久化
│       └── test/             dart test，无需模拟器
└── app/                      Flutter UI（移动优先）
    └── lib/  pages/ widgets/ theme/ l10n/
```

**分层原则**：`app/` 不含任何业务规则。到期判定、保号推算、同步冲突裁决全在 `iesim_core`。

**收益**：`iesim_core` 仅依赖 `dart:core` 与 `sqflite_common_ffi`，可在无 GUI 的 Linux 服务器上直接 `dart test`，覆盖全部业务逻辑。UI 调试在 macOS 进行。

**代价**：Dart 侧无法使用 Flutter 专有的状态管理便利；跨包引用需配置 path 依赖。

## 3. 数据模型

### 3.1 资产域

```
Device (设备)                手机 / 移动WiFi / 平板
  └── Slot (卡槽)            物理槽 | 内置eSIM槽
        └── [装载] Card

Card (卡片)
  ├── PhysicalSim            传统实体卡，自带 ICCID
  ├── RemovableEuicc         实体 eSIM 卡，可插拔
  └── EmbeddedEuicc          内置 eSIM，不可拆卸
        └── EID (1..N)
              └── Profile    ICCID + 运营商 profile
                    └── Subscription
```

**四项关键决定**：

1. **`Card → EID` 为 1:N。** 多 eUICC 芯片的实体卡确实存在。1:N 同时容纳 N=1（绝大多数）与多 EID 卡，避免未来迁移。
2. **`EmbeddedEuicc` 不可拆卸的约束写入类型系统**，而非运行时校验。内置 eSIM「拆到另一台手机」应在编译期即不可表达。
3. **`Subscription` 挂在 `Profile` 下，不直接挂 `Card`。** Profile 可迁移至其他 EID（补卡场景），而订阅的商业属性跟随号码而非硬件。
4. **未激活库存用状态表达，不单独建表。** 卡不在任何 Slot 即在库存；profile 未下载到任何 EID 即待用。避免同一实体在两处重复、状态不一致。

### 3.2 订阅域

```dart
class Subscription {
  final String id;
  final String? iccid;          // 与 Nekoko 关联的键
  final PhoneNumber number;
  final String? operator;
  final Plan plan;
  final KeepAlive keepAlive;
  final List<String> tags;
  final Appearance appearance;
  final DateTime updatedAt;     // 同步用
}

class Plan {
  final String? name;
  final Money? cyclePrice;
  final int? cycleDays;
  final DateTime? startDate;
  final DateTime? expiryDate;
  final bool isLongTerm;
}

class KeepAlive {
  final bool required;
  final int? cycleDays;
  final DateTime? lastActivityAt;
}

class Money {
  final int minorUnits;         // 整数存储，避免浮点误差
  final String currencyCode;
}
```

`Money` 使用最小货币单位整数存储，此做法沿用自 SimJ（`cyclePaymentMinorUnits`），是其模型中值得保留的部分。

所有实体为不可变类，更新通过 `copyWith` 生成新实例。

### 3.3 两条独立事件流

```dart
class ActivityRecord {          // 订阅续存动作
  final String subscriptionId;
  final ActivityType type;      // topUp | call | sms | renewal
  final DateTime occurredAt;
  final Money? amount;
}

sealed class AssetEvent {       // 资产物理变迁
  final DateTime occurredAt;
}
class CardMoved    extends AssetEvent { Slot? from, to; }
class ProfileMoved extends AssetEvent { Eid from, to; }
class CardStored   extends AssetEvent { Slot from; }
class ProfileWiped extends AssetEvent { Eid from; }
```

二者刻意不合并：一条回答「号码为何仍然有效」，一条回答「这张卡去过哪里」。合并会使两类查询互相干扰。

## 4. 保号逻辑

### 4.1 核心区分

**保号截止日 ≠ 套餐到期日。** 二者独立：

- **套餐到期日** = `plan.expiryDate`，套餐用尽的时间。
- **保号截止日** = `keepAlive.lastActivityAt + keepAlive.cycleDays`，预付费卡必须产生动作（充值/通话/短信）否则号码被回收。

SimJ 与 SimHub 均只有到期日与周期天数，无「上次动作时间」，因而无法表达「套餐尚余 20 天，但保号动作 3 天内必须完成」——而这正是最易踩坑的场景。

### 4.2 状态

```dart
sealed class KeepAliveStatus {}
class NotRequired extends KeepAliveStatus {}
class Safe        extends KeepAliveStatus { final int daysLeft; }
class DueSoon     extends KeepAliveStatus { final int daysLeft; }
class Overdue     extends KeepAliveStatus { final int daysOver; }
class Unknown     extends KeepAliveStatus {}
```

`Unknown` 为刻意保留的状态：当 `lastActivityAt` 缺失时显示「未知」而非默认「安全」。静默误判是保号工具最不可接受的失败模式。

sealed class 使 UI 侧 `switch` 强制穷尽，遗漏分支在编译期即报错。

### 4.3 日期与时区

保号截止日是**日历日期**而非时刻。全部按用户本地时区的日期计算，存储为 ISO 日期字符串（`YYYY-MM-DD`）。

跨时区旅行是本产品的高频场景（用户持多国号码），必须避免「飞越时区后剩余天数跳变」。因此：日期比较一律先归一化到本地日历日，不做 UTC 时刻减法。

## 5. 互操作

### 5.1 SimHub JSON（导入 / 导出）

采用 SimHub 的 JSON 格式作为交换标准，而非自定义格式。该格式已被 SimJ 兼容实现（`SimHubCompat.kt`），故一次实现即打通 iOS 与 Android 两侧生态。

字段规范（逆向自 `SimHubCompat.kt` 的映射逻辑，代码为权威来源，原格式文档仓库 `yanglh1/simj-pp` 已不可访问）：

```jsonc
{
  "id": "...",
  "countryCode": "CN",              // ISO 国家码，非拨号区号
  "countryName": "...",
  "flag": "...",
  "phoneNumber": "...",
  "carrier": "...",                 // 运营商
  "expiryDate": "ISO date",
  "createdAt": "ISO date",
  "plan": "...",                    // 套餐名
  "price": "...",
  "currentBalance": "...",
  "cyclePaymentMinorUnits": 0,
  "currencyCode": "...",
  "renewDays": 30,                  // 周期天数
  "isLongTerm": false,
  "tags": ["...", "..."],           // JSON 数组
  "eid": "...",
  "smdpAddress": "...",
  "activationCode": "...",
  "cardType": "prepaid",            // 亦接受 billingType
  "cardColorHex": "...",
  "cardBackgroundAssetName": "...",
  "websiteURL": "...",
  "customPrompt": "...",
  "transactionNotes": "..."
}
```

**兼容性注意**：`cardType` 与 `billingType` 两个字段名均需接受（格式演进遗留）；`tags` 为数组，而 SimJ 内部转为逗号分隔字符串，导出时须还原为数组。

**扩展字段**：`iccid`、`lastActivityAt`、`activityRecords` 为本项目新增，SimHub 与 SimJ 均无。写入时置于顶层，旧版本读取时会忽略，不破坏兼容。

### 5.2 Nekoko 标签（双向）

NekokoLPA2 将标签内嵌于 profile 的 nickname 字符串，规范（逆向自 `lib/utils/profile_tag_utils.dart`）：

```
文本标签：t:<内容>
日期标签：d:<YYMMDD>[:<备注>]      亦兼容 YYYYMMDD

转义：空格 → \x11   冒号 → \x03   标签间分隔 → \x0A
解析正则：\b([td]:[\S\x11]+)
```

以 **ICCID** 作为与 Nekoko 的关联键。

本项目在 `iesim_core/interop/` 中以纯 Dart 重新实现该编解码（约 200 行字符串处理），而非引入 Nekoko 依赖，以保持 core 包对 Flutter 的零依赖与可独立测试。

## 6. WebDAV 同步

### 6.1 传输与布局

- 库：`webdav_client`（其自述仅支持部分常用方法，但同步所需的 PROPFIND / GET / PUT / MKCOL 均在覆盖范围内）。
- 远端布局：单一 JSON 快照文件 + ETag 乐观锁。不采用每记录一文件，避免同步一次产生数百次请求。

### 6.2 合并策略

1. `PROPFIND` 取远端 ETag。
2. ETag 与本地记录的上次同步值一致 → 直接 `PUT`（携带 `If-Match`）。
3. 不一致 → `GET` 远端快照，执行**记录级合并**：按 `id` 配对，逐条比较 `updatedAt`，取较新者。
4. `PUT` 时携带 `If-Match`；若返回 412（并发写入）则回到步骤 1 重试，最多 3 次。

合并粒度为记录级而非文件级：两台设备分别修改不同订阅时应当都保留，而非一方覆盖另一方。

### 6.3 删除与墓碑

删除不直接移除记录，而是写入墓碑（保留 `id` 与 `deletedAt`）。否则设备 A 的删除会被设备 B 的旧快照「复活」。

墓碑保留 90 天后由本地清理任务移除。该时长的取舍：过短会导致长期离线设备复活已删记录，过长会使快照持续膨胀。

### 6.4 冲突的诚实呈现

记录级合并按 `updatedAt` 取新，属于 last-write-wins，会静默丢弃较旧的一侧修改。当检测到同一记录两侧均有改动时，将该次合并结果记入同步日志并在 UI 提示，不做无声覆盖。

### 6.5 同步范围

v1 同步 `Subscription`、`ActivityRecord` 及其墓碑。资产域（Device / Slot / Card / EID / Profile）虽在 v1 建表，但**不纳入 v1 同步**——其 UI 未开放，不会产生数据，纳入只会增加快照体积与合并分支。

快照顶层携带 `schemaVersion`。v2 开放资产域时递增该版本并扩展快照结构；读取到高于自身的 `schemaVersion` 时拒绝合并并提示升级，避免旧版本客户端截断新字段后写回造成数据丢失。

## 7. 错误处理

- 所有网络与 IO 操作以 `Result` 类型返回，不抛裸异常穿透到 UI 层。
- WebDAV 认证失败、网络不可达、磁盘写入失败三类错误分别建模，UI 据类型给出可操作提示（而非统一的「同步失败」）。
- 导入 SimHub JSON 时逐条校验，单条记录格式错误不中断整批导入，收集为错误报告呈现。
- 日期解析失败不静默回退到「今天」（SimJ 的 `DateTag.parse` 有此行为），而是标记该字段为空并计入导入报告。

## 8. 测试策略

`iesim_core` 为纯 Dart 包，全部测试可在服务器上 `dart test` 执行，无需模拟器。

| 层 | 内容 | 重点 |
|---|---|---|
| 单元 | 保号计算 | 边界日期、跨月、闰年、时区归一化 |
| 单元 | 标签编解码 | 转义字符往返、畸形输入不崩溃 |
| 单元 | SimHub JSON | 往返一致性（round-trip）、缺字段容错、`cardType`/`billingType` 双名 |
| 单元 | 状态机 | `KeepAliveStatus` 全分支覆盖 |
| 集成 | 同步合并 | 双设备并发修改、删除墓碑、412 重试 |
| Widget | UI | 在 macOS 端进行 |

覆盖率目标 80%，`keepalive/` 与 `sync/` 两个模块要求 90% 以上——它们是错误代价最高的部分。

## 9. v1 / v2 边界

| 能力 | v1 | v2 |
|---|---|---|
| 完整数据模型（含 Device/Slot/Card/EID） | 建表 | — |
| 订阅管理 + 保号提醒 | ✅ | |
| WebDAV 同步 | ✅ | |
| SimHub JSON 互通 | ✅ | |
| Nekoko 标签互通 | ✅ | |
| 设备 / 卡片管理 UI | 表存在，不暴露 | ✅ |
| 资产迁移事件流 | ❌ | ✅ |
| 读卡与 LPA（复用 NekokoLPA2） | ❌ | ✅ |
| 桌面端 | ❌ | ✅ |

v1 建表但不开放 UI，代价为若干空表；换取的是避免一次全量数据迁移。

## 10. 许可与合规

- 本项目复用 NekokoLPA2（MIT）的 LPA 代码于 v2，届时须在仓库根保留 `NOTICE` 文件注明来源与原版权声明。MIT 要求保留版权声明，这是义务而非可选项。
- Nekoko 标签格式为逆向实现，不含其代码，无许可义务，但仍在文档中注明来源。
- SimHub JSON 格式为事实标准的逆向实现，不含其代码。

## 11. 实现约束与已定取舍

- **提醒不可依赖后台轮询。** iOS 对后台执行限制严格。保号与到期提醒一律使用本地通知预排程（`flutter_local_notifications` 的 `zonedSchedule`），在订阅变更时即刻重排，不依赖应用被唤醒。这意味着提醒时刻的计算必须在写入订阅的同一事务中完成。
- **多套餐叠加推迟至 v2。** v1 按一订阅一套餐处理。一张卡叠加主套餐与流量包的场景，v1 需用户建两条订阅记录表达。
- **v1 不做 iOS 构建验证。** 开发在 Linux 服务器进行，iOS 构建需 macOS。v1 以 Android 为验证目标，iOS 构建在具备 macOS 环境后补验。
