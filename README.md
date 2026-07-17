# Google Code

个人使用、离线优先的 Flutter Desktop TOTP 验证器，目标平台为 macOS 和 Windows。

## 当前状态

项目已完成阶段 1 至阶段 14 的主要开发闭环：本地加密 Vault、账号 CRUD、TOTP、多入口二维码导入、Google Authenticator 迁移二维码批量导入、单账号安全分享、独立 `.gcbak` 加密备份恢复、设备快速解锁、系统锁屏/会话断开/睡眠自动锁定、macOS/Windows 原生系统分享、跨平台 GitHub Actions、macOS/Windows 摄像头二维码扫描 PoC，以及 Release 构建和依赖供应链审计基线均已实现。阶段 14 新增手动 Release Readiness 工作流，对 116 个锁定依赖执行来源和许可证审计，为 macOS/Windows Release 归档附带依赖清单、第三方许可证报告、未可信签名声明和 SHA-256 校验值。当前验证为 `flutter analyze` 0 issues、`flutter test` 114 tests；阶段 14 详情见 `docs/PHASE14_STATUS.md`。Release Artifact 只用于发布准备和可信设备真机验收：macOS 没有 Apple Developer ID 签名或公证，Windows 没有 Authenticode 签名或安装包；SHA-256 不能替代代码签名。摄像头与其他双平台原生能力仍待目标真机人工验收。

详细进度见：

- `docs/PRD.md`
- `docs/TECHNICAL_DESIGN.md`
- `docs/PHASE0_STATUS.md`
- `docs/PHASE1_STATUS.md` 至 `docs/PHASE14_STATUS.md`
- `docs/adr/0001-foundation-stack.md`

## 环境

- Flutter 3.44.0（FVM）
- Dart 3.12.0
- macOS 12+（待最低版本真机确认）
- Windows 10 19041+（待真机确认）

## 常用命令

```bash
fvm flutter pub get
fvm flutter analyze
fvm flutter test
fvm flutter run -d macos
fvm flutter build macos --release
# Windows 主机执行：fvm flutter build windows --release
fvm dart run tool/vault_benchmark.dart
fvm dart run tool/release_metadata.dart
```

## 目录

```text
lib/
  app/            应用入口、主题和路由
  core/           编码、错误及跨功能基础能力
  domain/         无 Flutter 平台依赖的 TOTP 领域逻辑
  data/vault/     设备 Vault envelope、加解密与文件存储
  data/backup/    独立备份 envelope 与加解密
  platform/       二维码、剪贴板、截图、摄像头、安全存储、系统会话和原生分享等平台边界
  features/       桌面端功能页面
.github/
  workflows/      跨平台质量检查、Debug 构建与手动 Release Readiness
```

应用不依赖后端，不应上传或记录 Secret、验证码、`otpauth://` URI 或二维码内容。
