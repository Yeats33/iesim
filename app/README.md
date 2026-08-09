# iesim

ieSIM Flutter 客户端：管理 SIM/eSIM 订阅、保号动作、套餐到期、本地提醒与用户自有 WebDAV 同步。

## 本地验证

```bash
flutter analyze
flutter test
flutter build apk --release --split-per-abi
# iOS 需要在 macOS 上构建
flutter build ios --release --no-codesign
```

日常侧载优先使用按 ABI 拆分的 APK，避免把三套原生架构一起打进一个安装包；
Play 商店发布使用 `flutter build appbundle --release`。只有需要一个文件兼容多种
Android 架构时，才构建不带 `--split-per-abi` 的通用 APK。仓库 CI 还会把
无签名 iOS `.app` 封装为 IPA，并在版本 Tag 上统一发布全部产物。

业务规则位于 `../packages/iesim_core`；Flutter 层只负责界面、平台通知、文件选择、安全凭据和 WebDAV 传输。

## 数据与权限

- SQLite 数据库保存在应用私有目录。
- 通知为本地预排程，不依赖后台常驻。
- WebDAV 密码通过 Android Keystore 支持的安全存储加密。
- WebDAV 远端只写入单个 `iesim-v1.json` 快照。
