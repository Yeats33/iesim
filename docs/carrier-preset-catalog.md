# 运营商与保号预设

ieSIM 默认从独立仓库读取运营商目录：

```text
https://raw.githubusercontent.com/Yeats33/iesim-presets/main/catalog/v1/carriers.json
```

应用内置 CTExcel UK 与 eSIM.gg 两条兜底数据。远程目录下载成功后会校验并缓存；网络不可用或远程 JSON 损坏时，不会覆盖上一次可用数据。

可直接复制：

- `docs/examples/carrier-presets-v1.json` → `catalog/v1/carriers.json`
- `docs/schemas/carrier-presets-v1.schema.json` → `schema/carrier-presets-v1.schema.json`

一个运营商预设包含基础名称、国家、时区、官网以及以下保号结构：

- `cycleDays`：主周期，用于计算下一次保号截止日。
- `qualifyingActions`：能重置主周期的动作，可组合流量、通话、短信、充值、购买套餐、续费、余额变动与其他动作。
- `summary`：给用户看的规则说明，套用后仍可修改。
- `constraints`：不直接混入主周期的附加条件，例如激活后首次使用、套餐到期后续订、付费保号或自定义要求。
- `sourceLabel`、`sourceUrl`、`sourceCheckedAt`：规则出处及最后核对时间。

发布时应同时更新 `catalogVersion` 与 UTC `updatedAt`。规则必须来自运营商官网或其正式条款；如果套餐之间规则不同，应拆成不同预设，不能用一个未经核实的天数覆盖全部套餐。

远程目录只包含数据，不能下发代码。应用只接受 HTTPS、最大 2 MB 的 JSON，并校验枚举、字段长度、唯一 id 和来源地址。构建时可以覆盖目录地址：

```bash
flutter build apk --dart-define=IESIM_CARRIER_PRESET_URL=https://example.com/catalog/v1/carriers.json
```
