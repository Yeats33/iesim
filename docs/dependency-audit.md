# 依赖升级审计

审计时间：2026-08-09。

ieSIM 以最新稳定 Flutter SDK 为解析边界，不使用 `dependency_overrides` 绕过 Flutter SDK 或上游插件的约束。应用和核心库声明的可独立升级依赖均已解析到当前最新稳定兼容版本。

## 工具链

| 范围 | 版本 |
|---|---:|
| Flutter | 3.44.9 stable |
| Dart | 3.12.2 stable |
| Android Gradle Plugin | 9.3.1 |
| Gradle | 9.7.0 |
| Kotlin Gradle Plugin | 2.4.10 |
| desugar_jdk_libs | 2.1.5 |

| GitHub Action | 版本 |
|---|---:|
| actions/checkout | 7.0.1 |
| actions/setup-java | 5.7.0 |
| actions/upload-artifact | 7.0.1 |
| actions/download-artifact | 8.0.1 |
| android-actions/setup-android | 4.0.1 |
| subosito/flutter-action | 2.23.0 |

Gradle 使用 `bin` 分发包并校验官方 SHA-256，减少 CI 下载体积。GitHub Actions 均固定到审计时的最新稳定补丁版本，Dependabot 每周检查 Pub、Gradle 与 Actions 更新。

## Flutter SDK 或上游锁定项

`flutter pub outdated` 仍会列出以下不可由 ieSIM 单独升级的包：

| 包 | 当前 | 上游最新 | 约束来源 |
|---|---:|---:|---|
| intl | 0.20.2 | 0.20.3 | `flutter_localizations` 精确固定 0.20.2 |
| meta | 1.18.0 | 1.19.0 | Flutter SDK 精确固定 1.18.0 |
| vector_math | 2.2.0 | 2.4.2 | Flutter SDK 精确固定 2.2.0 |
| matcher | 0.12.19 | 0.12.20 | `flutter_test` 精确固定 0.12.19 |
| test_api | 0.7.11 | 0.7.13 | `flutter_test` 精确固定 0.7.11 |
| hooks | 2.0.2 | 2.1.0 | 新版需要 `meta 1.19.0`，与 Flutter 固定版本冲突 |
| native_toolchain_c | 0.19.2 | 0.19.3 | 新版依赖 `hooks 2.1.0` / `meta 1.19.0` |
| record_use | 0.6.0 | 1.0.0 | 新版需要 `meta 1.19.0` |
| qr | 3.0.2 | 4.0.0 | 最新 `qr_flutter 4.1.0` 仍依赖 `qr ^3.0.1` |
| dbus | 0.7.13 | 0.7.14 | 0.7.14 要求 `xml ^6.6.1`，与业务使用的最新 `xml 7.0.1` 冲突 |

这些包应随 Flutter stable 或直接上游插件的新版本升级。强制覆盖会让 SDK 测试库、本地化、二维码或 XML 解析运行在上游未声明支持的组合上，因此不纳入项目 override。
