# ieSIM v0.0.1-bate 功能矩阵

| 范围 | 状态 | 说明 |
|---|---:|---|
| 订阅、套餐、保号、动作历史 | 完成 | UTC 存储，按订阅时区计算日历日 |
| Profile 余额管理 | 完成 | 支持设定/增减、币种与备注；当前余额和期末流水原子写入，可经 SimHub/WebDAV 往返 |
| AFF 与内置推荐 | 完成 | Profile 可维护推广项目；内置 9eSIM、eSTK.me、eSIM.gg、RedteaGO、CTExcel UK，统一推广披露、复制码与 HTTPS 外链 |
| Profile 三态生命周期 | 完成 | 已激活（含 enabled/disabled）、未激活与过期博物馆；支持激活期限/要求、手动/删除/导入归档及可配置自动归档 |
| 四档本地提醒 | 完成 | 与订阅修改同事务重排，开机恢复 |
| Device → Slot → Card → EID → Profile → Subscription | 完成 | 支持库存、内置/可拆 eUICC 和多 EID |
| GitHub 设备型号预设 | 完成 | schema v1、型号搜索、一键填充、ETag 缓存与 last-known-good 离线回退 |
| 资产迁移事件 | 完成 | 换机、入库、Profile 迁移与擦除 |
| QR / 相册 / 粘贴 LPA 导入 | 完成 | 支持独立确认码，先预览后写入 |
| euicc.info 公共目录匹配 | 完成 | 本地精确匹配 SM-DP+/PLMN，展示 Profile 容量估算与 EUM 差异，不上传激活凭据 |
| SimHub v5 | 完成 | 真实备份 12/12 订阅、7 设备、4 卡、3 EID、5 Profile 验证通过 |
| SimJ JSON | 完成 | 扁平订阅格式双向兼容 |
| Nekoko nickname 标签 | 完成 | `t:` / `d:` 编解码及转义 |
| Nekoko SQLite 备份 | 完成 | 只读转换全部 Profile 到 ieSIM 原生模型；名称、标签、运营商、`enabled`、EID/ICCID、类别、GID 与占用空间可落库/同步，导入后回首页标准编辑；不导入敏感 LPA 状态 |
| WebDAV 订阅 + 资产同步 | 完成 | 开发基线 schema v1，不兼容旧开发快照；ETag/412 重试与 90 天墓碑 |
| 真实 eSIM 下载/安装/读卡 | 不在本版 | v0.0.1-alpha 是管理和迁移工具，不代替系统 LPA 或 Nekoko 的写卡协议栈 |

真实 SimHub 备份验证只记录聚合数量，测试与文档不输出号码、EID、SM-DP+ 或激活码。
