# TOTP Vault

[![Desktop CI](https://github.com/geng452654716/google-code/actions/workflows/desktop-ci.yml/badge.svg)](https://github.com/geng452654716/google-code/actions/workflows/desktop-ci.yml)
[![Build GitHub Release](https://github.com/geng452654716/google-code/actions/workflows/release.yml/badge.svg)](https://github.com/geng452654716/google-code/actions/workflows/release.yml)

个人使用、离线优先的 Flutter Desktop TOTP 验证器，支持 macOS 和 Windows。账号 Secret 由本机加密 Vault 保存，生成验证码不依赖后端服务。

> 仓库源码公开，但应用仍按个人使用场景设计。当前安装包没有面向公众分发所需的可信代码签名，也尚未声明开源许可证。

## 下载

[前往 Latest Release 下载最新版本](https://github.com/geng452654716/google-code/releases/latest)

每个 GitHub Release 提供：

- macOS DMG；
- Windows x64 Setup EXE；
- 每个安装包对应的 SHA-256 文件；
- 依赖和许可证审计 metadata。

下载后建议先校验同名 `.sha256`。macOS 包使用 ad hoc 签名，Windows 包未使用 Authenticode；项目不会引导绕过 Gatekeeper 或 SmartScreen。Windows 构建和安装冒烟测试由 GitHub Actions 执行，但 Windows 10/11 真机完整验收仍需在实际设备完成。

## 功能

- 标准 TOTP 验证码、倒计时和一键复制；
- 账号搜索、编辑、排序、置顶和深色模式；
- 自定义分组，以及将账号拖拽到分组；
- 手动 Secret、`otpauth://`、二维码图片、剪贴板图片、系统截图和摄像头导入；
- Google Authenticator 迁移二维码批量导入；
- 单账号 Secret、URI 和二维码分享；
- 主密码加密 Vault，macOS Touch ID / Windows Hello 快速解锁；
- 独立密码加密的 `.gcbak` 备份、恢复和跨设备迁移；
- iCloud Drive、Google Drive 同步目录和 GitHub 私有仓库云备份；
- 可选的“新增账号后自动备份到 GitHub”；
- macOS DMG、Windows Setup EXE 与 GitHub Release 自动打包。

## 安全模型

- Secret、验证码、`otpauth://` URI 和二维码内容不应上传到项目后端或写入日志；
- 本地 Vault 使用主密码保护，并在保存时保留一份设备本地 `vault.gcvault.bak`；
- `.gcbak` 是跨设备迁移文件，使用独立备份密码加密，不包含设备快速解锁材料；
- GitHub Device Flow Token、Touch ID / Windows Hello 材料和自动备份密码只保存在当前设备的 Keychain 或 Credential Manager；
- GitHub 云备份只允许选择私有仓库，云服务看到的是加密后的 `.gcbak`；
- 新设备恢复后仍需设置本机主密码，并重新启用 Touch ID 或 Windows Hello。

忘记主密码且设备快速解锁材料已经丢失时，应用无法绕过加密恢复 Secret。请妥善保存 `.gcbak` 的独立备份密码。

## 安装

### macOS

打开 Release 中的 DMG，将 `TOTP Vault.app` 拖到 `Applications`。首次使用截图或摄像头功能时，请按系统提示授权；权限变更后可能需要彻底退出并重新打开应用。

也可以从源码构建：

```bash
# 生成 dist/macos/TOTPVault-<版本>-macos-universal.dmg
bash tool/package_macos_dmg.sh

# 已有 Release .app 时跳过构建
bash tool/package_macos_dmg.sh --skip-build
```

若本机 Keychain 已配置稳定的代码签名 identity，可显式指定：

```bash
TOTP_VAULT_CODESIGN_IDENTITY='Apple Development: 你的名字 (TEAMID)' \
  bash tool/package_macos_dmg.sh
```

### Windows

在 Windows 10/11 x64 中运行 Release 提供的 Setup EXE，安装范围仅为当前用户。

从源码打包需要 Inno Setup 6：

```powershell
# 生成 dist\windows\TOTPVault-<版本>-windows-x64-setup.exe
.\tool\package_windows_exe.ps1

# 已有 Release 构建目录时跳过构建
.\tool\package_windows_exe.ps1 -SkipBuild
```

安装、覆盖升级和卸载只处理应用及安装器创建的快捷方式，不删除 Vault、系统安全存储记录或 `.gcbak` 备份。

## 云备份

应用支持把独立密码加密的 `.gcbak` 备份到：

- iCloud Drive 同步目录；
- Google Drive 桌面版同步目录；
- GitHub App 获得授权的专用私有仓库。

iCloud 与 Google Drive 由系统或桌面客户端负责登录和同步。GitHub 使用 Device Flow，用户可以登录自己的 GitHub 账号并选择专用私有仓库。Token 只保存在当前设备。

GitHub 功能需要在构建时提供 GitHub App Client ID：

```bash
export TOTP_VAULT_GITHUB_CLIENT_ID=Ivxxxxxxxxxxxxxxxxxx
bash tool/package_macos_dmg.sh
```

Windows PowerShell：

```powershell
$env:TOTP_VAULT_GITHUB_CLIENT_ID = 'Ivxxxxxxxxxxxxxxxxxx'
.\tool\package_windows_exe.ps1
```

GitHub Actions 的 `Build GitHub Release` 工作流读取 Repository Variable `TOTP_VAULT_GITHUB_CLIENT_ID`。Client ID 可以公开，但不要提交 Client Secret、GitHub App private key、用户 Token、Vault 或真实备份文件。

## 开发

### 环境

- Flutter 3.44.0（FVM）；
- Dart 3.12.0；
- macOS 12+；
- Windows 10 19041+。

最低系统版本和 Windows 原生功能仍以真机验收结果为准。

### 常用命令

```bash
fvm flutter pub get
fvm flutter analyze
fvm flutter test
fvm flutter run -d macos
fvm flutter build macos --release
fvm dart run tool/vault_benchmark.dart
fvm dart run tool/release_metadata.dart
```

### GitHub Actions

- `Desktop CI`：在 push、Pull Request 和手动触发时执行格式、静态分析、测试以及 macOS / Windows Debug 构建；
- `Build GitHub Release`：由 `v*` tag 或手动触发，验证版本、构建并冒烟测试 DMG / Setup EXE、校验 SHA-256，最后创建 GitHub Release。

手动发布必须从 `main` 运行。未填写 tag 时，工作流根据 `pubspec.yaml` 的版本生成 `v<version>`，例如 `v1.0.3+4`。

## 项目结构

```text
lib/
  app/            应用入口、主题和路由
  core/           编码、错误及跨功能基础能力
  domain/         无 Flutter 平台依赖的 TOTP 领域逻辑
  data/vault/     Vault envelope、加解密与文件存储
  data/backup/    独立备份 envelope 与加解密
  platform/       二维码、剪贴板、截图、摄像头、安全存储和原生分享
  features/       桌面端功能页面
.github/
  workflows/      跨平台质量检查与 GitHub Release 打包
```

## 技术文档

- [产品需求](docs/PRD.md)
- [技术设计](docs/TECHNICAL_DESIGN.md)
- [基础技术栈架构决策](docs/adr/0001-foundation-stack.md)

## 当前限制

- macOS Release 未使用 Apple Developer ID，也未公证；
- Windows Release 未使用 Authenticode；
- 不提供应用商店分发或自动更新；
- Windows 10/11 的摄像头、Windows Hello、截图、系统分享和高 DPI 等仍需真机完整验收；
- 仓库当前没有 LICENSE 文件，公开源码不代表自动授予复制、修改或分发许可。
