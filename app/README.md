# iesim

iesim Android 客户端：管理 SIM/eSIM 订阅、保号动作、套餐到期、本地提醒与用户自有 WebDAV 同步。

## 本地验证

```bash
flutter analyze
flutter test
flutter build apk --release
```

业务规则位于 `../packages/iesim_core`；Flutter 层只负责界面、平台通知、文件选择、安全凭据和 WebDAV 传输。

## 数据与权限

- SQLite 数据库保存在应用私有目录。
- 通知为本地预排程，不依赖后台常驻。
- WebDAV 密码通过 Android Keystore 支持的安全存储加密。
- WebDAV 远端只写入单个 `iesim-v1.json` 快照。
