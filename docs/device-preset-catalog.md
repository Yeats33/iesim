# 设备型号预设仓库

ieSIM 会从一个独立、公开的 GitHub 仓库读取设备型号目录。应用默认地址是：

```text
https://raw.githubusercontent.com/Yeats33/iesim-presets/main/catalog/v1/devices.json
```

因此建议创建公开仓库 `Yeats33/iesim-presets`，并使用下面的结构：

```text
iesim-presets/
├── catalog/
│   └── v1/
│       ├── devices.json
│       └── carriers.json
└── schema/
    ├── device-presets-v1.schema.json
    └── carrier-presets-v1.schema.json
```

可直接复制本仓库的：

- `docs/examples/device-presets-v1.json` → `catalog/v1/devices.json`
- `docs/schemas/device-presets-v1.schema.json` → `schema/device-presets-v1.schema.json`

## 发布规则

1. 每次修改 `devices.json` 时更新 `catalogVersion` 和 UTC `updatedAt`。
2. 同一个设备的 `id` 必须永久稳定且不可重复。不同地区版本应使用不同 `id`。
3. `aliases` 用来保存监管型号、内部代号或常见别名，方便用户搜索。
4. `slots` 应描述该地区版本实际可用的卡槽；不确定时可以省略，并把 `simCapability` 写为 `unknown`。
5. 合并到 `main` 后，用户下一次打开“手机型号库”就会读取新目录；GitHub 返回未变化时应用会继续使用本地缓存。

建议为 `main` 开启分支保护，只允许通过 Pull Request 更新，并要求至少一人核对设备型号、地区版本和 SIM 能力。远程仓库必须公开；应用不会保存 GitHub Token。

## 兼容与安全

- `schemaVersion` 表示数据结构。目前只接受整数 `1`；结构变化时新增 v2 路径，不要原地改变 v1 含义。
- `catalogVersion` 只是内容版本，可按日期递增，例如 `2026.08.2`。
- 应用只接受 HTTPS、最大 2 MB 的 JSON，并校验字段、枚举、数量和唯一 id。
- 新目录解析失败或网络不可用时，应用保留并使用上一次成功下载的目录。
- 目录只能填写设备资料，不能下发代码、脚本或应用配置。

若以后仓库地址变化，可在构建时覆盖：

```bash
flutter build apk --dart-define=IESIM_DEVICE_PRESET_URL=https://example.com/catalog/v1/devices.json
```
