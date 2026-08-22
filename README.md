# ieSIM

[![Build ieSIM](https://github.com/Yeats33/iesim/actions/workflows/build.yml/badge.svg)](https://github.com/Yeats33/iesim/actions/workflows/build.yml)

SIM/eSIM 订阅、保号与设备资产管理 Flutter 应用。产品名称为 **ieSIM**，当前版本为 **v0.0.3**（构建号由 CI 运行编号生成）。

## 已实现

- 订阅总览、搜索筛选、详情编辑、充值/通话/短信/续费历史
- 首页缓存 Profile 聚合、搜索索引与排序投影，筛选输入不重复计算完整资产关系和价值看板
- Profile 余额管理：设定、增加或减少余额，当前余额与期末流水同事务保存并参与同步
- Profile AFF 管理：自定义推荐项目、优惠码复制、HTTPS 外链及清晰推广披露；内置 9eSIM、eSTK.me、eSIM.gg、RedteaGO 与 CTExcel UK 推荐
- Profile 号码绑定管理：记录号码关联的 App、账号用途、验证状态与商店资料；内置 WhatsApp 预设且不读取短信或验证码
- Profile 分为已激活、未激活与过期博物馆；支持激活期限/要求、归档原因及可配置的到期自动归档
- 保号截止与套餐到期独立计算，按订阅 IANA 时区展示
- Android/iOS 本地通知预排程，点击直达订阅；Android 开机后恢复
- 用户自有 HTTPS Webhook：可配置优先级、标签、自定义 payload、事件类别和隐私字段，Profile/动作/同步操作成功后发送
- 设备、物理/内置卡槽、实体 SIM、可拆 eUICC、内置 eUICC、EID 与 Profile 的完整关系
- 从独立 GitHub 数据仓库热更新手机型号预设，支持搜索、一键填写、ETag 缓存与离线回退
- 卡片换机/入库、Profile 迁移/擦除的独立资产事件流，并对内置 eUICC 强制不可拆卸约束
- 相机扫码、从相册/截图识别或粘贴 `LPA:1$...` 导入；支持需要独立确认码的 QR
- 按 SM-DP+ 与 PLMN 从 EUICC.Info 公共目录精确匹配 Profile/服务商
- 按 MCC/MNC、GID1/GID2、Profile 名和服务商名匹配网络运营商与 Logo；兼容 NekokoLPA2 的 operator-icons 目录，Logo 本地缓存并支持离线显示
- SimHub v5 完整备份导入导出：设备归属、休眠卡、余额流水、AFF、自动充值、备用号码、国家、运营商 App 与交易备注等字段均可往返
- SimJ 兼容扁平 JSON 导入导出
- Nekoko Tag 独立保存为默认隐藏的外部元数据，以及 Nekoko SQLite 备份的只读导入；用户确认后可提取手机号、标签和日期到 ieSIM 原生字段
- WebDAV 单快照同步、ETag 乐观锁、订阅与资产的记录级合并、删除墓碑与冲突日志
- 浅色、深色与跟随系统主题
- 设置页可导出不含号码、ICCID、EID、激活凭据或远端地址的脱敏诊断 JSON

`packages/iesim_core` 包含可在无图形环境运行的领域、SQLite、互操作与同步逻辑；`app` 是 Flutter Android/iOS 客户端。完成度见 `docs/feature-matrix.md`，设备与运营商预设仓库格式分别见 `docs/device-preset-catalog.md`、`docs/carrier-preset-catalog.md`，设计决策见 `docs/superpowers/specs/2026-08-07-iesim-design.md`。

第三方代码与数据源说明见 `THIRD_PARTY_NOTICES.md`。

## CI 构建

`.github/workflows/build.yml` 参考 NekokoLPA2 的多 job 流程：先读取 `app/pubspec.yaml` 版本并完成分析和测试，再并行构建 Android 与 iOS。每次 `main` push、PR 和手动运行都会上传以下 Actions Artifact：

- Android 通用、ARM64、ARMv7、x86_64 APK，以及 AAB
- iOS 未签名 IPA（安装前需要使用自己的证书签名）
- 每个平台的 SHA-256 校验文件

推送与 `pubspec.yaml` 完整版本一致的 Tag（例如 `v0.0.3`）会自动创建或更新 GitHub Release，并附加全部产物；版本含 `-beta` 等预发布后缀时标记为 prerelease。Android Release 必须配置 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS` 和 `ANDROID_KEY_PASSWORD` 四个 Actions Secrets，确保 Obtainium 等更新工具可以持续覆盖升级。

Android ARM64 Release 资产使用 `ieSIM-im.ies.iesim-v0.0.3-android-arm64-v8a.apk` 格式，依次包含产品名、包名、版本、平台和 ABI。

Android 构建号使用 GitHub Actions 运行编号并传入所有 APK/AAB 构建，确保后续测试包可以覆盖升级。依赖由 `.github/dependabot.yml` 每周检查；当前升级快照与 Flutter SDK 锁定的传递依赖见 `docs/dependency-audit.md`。

## 安全边界

LPA 导入会安全保存凭据并创建订阅，不会擅自下载、安装、启用或删除真实 eSIM Profile。服务商匹配只下载公共目录，不会把用户的 SM-DP+、Matching ID 或确认码发送给匹配服务。运营商 Logo 匹配只按 MCC 下载对应的 operator-icons 目录；MNC、GID、Profile 名和服务商名均在本机参与打分，不会作为请求参数发送。Nekoko 导入不读取写卡密钥、通知载荷或远端服务器历史。SimHub 备份中非 SIM 资产的 `services` / `boundServices` 可能带有账户或服务器信息，导入预览会显示数量但不写入。Webhook 地址仅存本机安全存储且不会进入 WebDAV；通知默认不发送号码、运营商、Profile 名或 Profile ID，用户可在设置中明确开启这些详情。
