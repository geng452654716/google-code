# Google Code

个人使用、离线优先的 Flutter Desktop TOTP 验证器，目标平台为 macOS 和 Windows。

## 当前状态

项目已完成阶段 1 至阶段 10 的主要开发闭环：本地加密 Vault、账号 CRUD、TOTP、多入口二维码导入、Google Authenticator 迁移二维码批量导入、单账号安全分享、独立 `.gcbak` 加密备份恢复、设备快速解锁，以及系统锁屏、会话断开和睡眠触发的立即自动锁定均已实现。分享 Secret、URI 或二维码前可使用 Touch ID / Windows Hello 重新验证，主密码入口和恢复能力始终保留。当前完整验证为 `flutter analyze` 0 issues、`flutter test` 96 tests，macOS Debug 应用构建成功；阶段 10 详情见 `docs/PHASE10_STATUS.md`。Windows 原生代码仍需在 Windows 10/11 真机编译与运行，真实 Google Authenticator 导出样本、系统会话事件真机矩阵、系统分享面板及目标平台文件对话框人工验收仍待后续阶段完成。

详细进度见：

- `docs/PRD.md`
- `docs/TECHNICAL_DESIGN.md`
- `docs/PHASE0_STATUS.md`
- `docs/PHASE1_STATUS.md` 至 `docs/PHASE10_STATUS.md`
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
fvm dart run tool/vault_benchmark.dart
```

## 目录

```text
lib/
  app/            应用入口、主题和路由
  core/           编码、错误及跨功能基础能力
  domain/         无 Flutter 平台依赖的 TOTP 领域逻辑
  data/vault/     设备 Vault envelope、加解密与文件存储
  data/backup/    独立备份 envelope 与加解密
  platform/       二维码、剪贴板、截图、安全存储和系统会话等平台边界
  features/       桌面端功能页面
```

应用不依赖后端，不应上传或记录 Secret、验证码、`otpauth://` URI 或二维码内容。
