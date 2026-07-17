# Google Code

个人使用、离线优先的 Flutter Desktop TOTP 验证器，目标平台为 macOS 和 Windows。

## 当前状态

项目已完成阶段 1 至阶段 13 的主要开发闭环：本地加密 Vault、账号 CRUD、TOTP、多入口二维码导入、Google Authenticator 迁移二维码批量导入、单账号安全分享、独立 `.gcbak` 加密备份恢复、设备快速解锁、系统锁屏/会话断开/睡眠自动锁定、macOS/Windows 原生系统分享、跨平台 GitHub Actions，以及 macOS/Windows 摄像头二维码扫描 PoC 均已实现。摄像头入口支持实时预览、设备切换和周期静态帧识别，并复用单账号及 Google 迁移批次导入流程；画面不上传，插件临时截图读取后立即删除。当前验证为 `flutter analyze` 0 issues、`flutter test` 106 tests；GitHub Actions 已在 Ubuntu 完成质量检查，并在 macOS 15 与 Windows Server 2022 分别完成包含桌面摄像头插件的 Debug 构建和产物归档。阶段 13 详情见 `docs/PHASE13_STATUS.md`。这些结果代表代码与双平台编译闭环完成，不代表摄像头真机交互已经验收；macOS 真实扫码、Windows 10/11 真机摄像头及其他原生能力、真实 Google Authenticator 导出样本和目标平台交互矩阵仍待人工验证。

详细进度见：

- `docs/PRD.md`
- `docs/TECHNICAL_DESIGN.md`
- `docs/PHASE0_STATUS.md`
- `docs/PHASE1_STATUS.md` 至 `docs/PHASE13_STATUS.md`
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
  workflows/      跨平台质量检查与桌面 Debug 构建
```

应用不依赖后端，不应上传或记录 Secret、验证码、`otpauth://` URI 或二维码内容。
