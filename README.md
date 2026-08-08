# ieSIM

SIM/eSIM 订阅、保号与设备资产管理 Android 应用。产品名称为 **ieSIM**，当前版本为 **v0.0.1-alpha**（build 1，`0.0.1-alpha+1`）。

## 已实现

- 订阅总览、搜索筛选、详情编辑、充值/通话/短信/续费历史
- Profile 余额管理：设定、增加或减少余额，当前余额与期末流水同事务保存并参与同步
- Profile AFF 管理：自定义推荐项目、优惠码复制、HTTPS 外链及清晰推广披露；内置 9eSIM、eSTK.me、eSIM.gg、RedteaGO 与 CTExcel UK 推荐
- Profile 分为已激活、未激活与过期博物馆；支持激活期限/要求、归档原因及可配置的到期自动归档
- 保号截止与套餐到期独立计算，按订阅 IANA 时区展示
- Android 本地通知预排程，开机后恢复，点击直达订阅
- 设备、物理/内置卡槽、实体 SIM、可拆 eUICC、内置 eUICC、EID 与 Profile 的完整关系
- 从独立 GitHub 数据仓库热更新手机型号预设，支持搜索、一键填写、ETag 缓存与离线回退
- 卡片换机/入库、Profile 迁移/擦除的独立资产事件流，并对内置 eUICC 强制不可拆卸约束
- 相机扫码、从相册/截图识别或粘贴 `LPA:1$...` 导入；支持需要独立确认码的 QR
- 按 SM-DP+ 与 PLMN 从 EUICC.Info 公共目录精确匹配 Profile/服务商
- SimHub v5 完整备份导入导出：设备归属、休眠卡、余额流水、AFF、自动充值、备用号码、国家、运营商 App 与交易备注等字段均可往返
- SimJ 兼容扁平 JSON 导入导出
- Nekoko nickname 标签双向转换，以及 Nekoko SQLite 备份的只读导入；名称、运营商、标签、enabled、EID/ICCID、类别、GID、实际占用空间与缓存号码会转换成 ieSIM 原生 Profile，导入后直接回首页编辑
- WebDAV 单快照同步、ETag 乐观锁、订阅与资产的记录级合并、删除墓碑与冲突日志
- 浅色、深色与跟随系统主题

`packages/iesim_core` 包含可在无图形环境运行的领域、SQLite、互操作与同步逻辑；`app` 是 Flutter Android 客户端。完成度见 `docs/feature-matrix.md`，设备与运营商预设仓库格式分别见 `docs/device-preset-catalog.md`、`docs/carrier-preset-catalog.md`，设计决策见 `docs/superpowers/specs/2026-08-07-iesim-design.md`。

## 安全边界

LPA 导入会安全保存凭据并创建订阅，不会擅自下载、安装、启用或删除真实 eSIM Profile。服务商匹配只下载公共目录，不会把用户的 SM-DP+、Matching ID 或确认码发送给匹配服务。Nekoko 导入不读取写卡密钥、通知载荷或远端服务器历史。SimHub 备份中非 SIM 资产的 `services` / `boundServices` 可能带有账户或服务器信息，导入预览会显示数量但不写入。
