# Google Code

个人使用、离线优先的 Flutter Desktop TOTP 验证器，目标平台为 macOS 和 Windows。

## 当前状态

项目已完成阶段 1 至阶段 15 的主要开发闭环：本地加密 Vault、账号 CRUD、TOTP、多入口二维码导入、Google Authenticator 迁移二维码批量导入、单账号安全分享、独立 `.gcbak` 加密备份恢复、设备快速解锁、系统事件自动锁定、macOS/Windows 原生系统分享、跨平台 GitHub Actions、摄像头二维码扫描 PoC、依赖供应链审计，以及个人安装/升级/卸载工具。

本项目明确为**个人自用软件**，不计划公开发布、上架应用商店或创建公开 GitHub Release。阶段 15 提供无需管理员权限的用户级安装脚本：macOS 安装到 `~/Applications/Google Code.app`，Windows 安装到 `%LOCALAPPDATA%\Programs\Google Code` 并可创建当前用户的开始菜单快捷方式。重复执行脚本即完成可恢复升级；卸载默认只删除应用和脚本管理的快捷方式，不删除 Vault、系统安全存储记录或 `.gcbak` 备份。

当前 macOS 构建只有 ad hoc 签名，Windows 构建没有 Authenticode 签名；安装脚本不会移除 `com.apple.quarantine`、绕过 Gatekeeper/SmartScreen，也不等同于可信发布签名。摄像头与其他 Windows 原生能力仍待目标真机人工验收。阶段详情见 `docs/PHASE15_STATUS.md`。

详细进度见：

- `docs/PRD.md`
- `docs/TECHNICAL_DESIGN.md`
- `docs/PHASE0_STATUS.md`
- `docs/PHASE1_STATUS.md` 至 `docs/PHASE15_STATUS.md`
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
fvm dart run tool/release_metadata.dart
```

## 个人安装

### macOS

```bash
# 默认先构建 Release，再安装到 ~/Applications/Google Code.app
bash tool/install_macos.sh

# 已经完成 Release 构建时跳过构建
bash tool/install_macos.sh --skip-build

# 安装后主动启动
bash tool/install_macos.sh --skip-build --launch

# 只卸载应用，保留 Vault、Keychain 记录和备份
bash tool/install_macos.sh --uninstall
```

### Windows

在 PowerShell 中执行：

```powershell
# 默认先构建 Release，再安装到当前用户目录并创建开始菜单快捷方式
.\tool\install_windows.ps1

# 已经完成 Release 构建时跳过构建
.\tool\install_windows.ps1 -SkipBuild

# 只卸载应用和脚本创建的快捷方式，保留 Vault、凭据和备份
.\tool\install_windows.ps1 -Uninstall
```

两个脚本都支持自定义源目录、目标目录、dry run 和显式启动参数。升级前必须先退出正在运行的 Google Code。macOS 脚本参数见 `bash tool/install_macos.sh --help`；Windows 参数见 `Get-Help .\tool\install_windows.ps1 -Detailed`。

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
  workflows/      跨平台质量检查、Debug 构建与手动个人安装验收
```

应用不依赖后端，不应上传或记录 Secret、验证码、`otpauth://` URI 或二维码内容。
