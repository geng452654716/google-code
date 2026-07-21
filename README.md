# TOTP Vault

个人使用、离线优先的 Flutter Desktop TOTP 验证器，目标平台为 macOS 和 Windows。

## 当前状态

项目已完成阶段 1 至阶段 20 的主要开发闭环：本地加密 Vault、账号 CRUD、TOTP、多入口二维码导入、Google Authenticator 迁移二维码批量导入、单账号安全分享、独立 `.gcbak` 加密备份恢复、设备快速解锁、系统事件自动锁定、macOS/Windows 原生系统分享、跨平台 GitHub Actions、摄像头二维码扫描 PoC、依赖供应链审计、个人安装/升级/卸载工具、macOS DMG / Windows Setup EXE 个人安装包，macOS 屏幕录制授权恢复流程，以及本地分组管理与账号拖拽归类。

本项目明确为**个人自用软件**，不计划公开发布、上架应用商店或创建公开 GitHub Release。阶段 15 提供无需管理员权限的用户级安装脚本；阶段 16 在此基础上提供可双击使用的 DMG 和 Setup EXE。安装、升级和卸载默认只处理应用及安装器管理的快捷方式，不删除 Vault、系统安全存储记录或 `.gcbak` 备份。

macOS 构建默认只有 ad hoc 签名，Windows 构建没有 Authenticode 签名；安装脚本和安装包不会移除 `com.apple.quarantine`、绕过 Gatekeeper/SmartScreen，也不等同于可信发布签名。macOS 脚本支持显式指定本机稳定代码签名 identity，以减少升级后 TCC 权限失配；摄像头与其他 Windows 原生能力仍待目标真机人工验收。最新验证结果见 `docs/PHASE20_STATUS.md`。

详细进度见：

- `docs/PRD.md`
- `docs/TECHNICAL_DESIGN.md`
- `docs/PHASE0_STATUS.md`
- `docs/PHASE1_STATUS.md` 至 `docs/PHASE20_STATUS.md`
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

### 生成个人安装包

macOS 在当前设备生成可拖拽安装的 DMG：

```bash
# 默认先构建 Release，再输出 dist/macos/TOTPVault-<版本>-macos-universal.dmg
bash tool/package_macos_dmg.sh

# 已有 Release .app 时跳过构建
bash tool/package_macos_dmg.sh --skip-build

# 脚本会自动使用本机的 “TOTP Vault Local Signing” identity；
# 也可显式指定 Apple Development 等其他稳定 identity
TOTP_VAULT_CODESIGN_IDENTITY='Apple Development: 你的名字 (TEAMID)' \
  bash tool/package_macos_dmg.sh
```

打开 DMG 后，把 `TOTP Vault.app` 拖到其中的 `Applications` 快捷方式即可。也可以继续使用下方用户级安装脚本安装到 `~/Applications`。

Windows 在 Windows 10/11 PowerShell 中生成 Setup EXE：

```powershell
# 需要已安装 Inno Setup 6；默认先构建 Release
.\tool\package_windows_exe.ps1

# 已有 Release 目录时跳过构建
.\tool\package_windows_exe.ps1 -SkipBuild
```

输出位于 `dist\windows\TOTPVault-<版本>-windows-x64-setup.exe`，安装范围仅为当前用户。两个打包脚本都会同时生成 `.sha256` 文件。

### macOS

```bash
# 默认先构建 Release，再安装到 ~/Applications/TOTP Vault.app
bash tool/install_macos.sh

# 已经完成 Release 构建时跳过构建
bash tool/install_macos.sh --skip-build

# 安装后主动启动
bash tool/install_macos.sh --skip-build --launch

# 若登录钥匙串存在 “TOTP Vault Local Signing”，脚本会自动使用；
# 也可显式指定其他稳定 identity
TOTP_VAULT_CODESIGN_IDENTITY='Apple Development: 你的名字 (TEAMID)' \
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

两个脚本都支持自定义源目录、目标目录、dry run 和显式启动参数。升级前必须先退出正在运行的 TOTP Vault。macOS 脚本参数见 `bash tool/install_macos.sh --help`；Windows 参数见 `Get-Help .\tool\install_windows.ps1 -Detailed`。

## 账号分组

解锁后，验证码列表左侧提供“全部账号”“未分组”和自定义分组：

- 点击分组标题旁的按钮可创建分组。
- 每个自定义分组都可重命名或删除；删除分组只会把账号移到“未分组”，不会删除验证码账号。
- 从账号卡片左侧的拖拽手柄拖到目标分组，即可立即写入加密 Vault。
- 分组筛选与搜索可组合使用，分组名称大小写不敏感且不可重复。

## 屏幕二维码扫描

选择“扫描屏幕二维码”后，应用会先说明系统截图流程。开始框选时应用窗口会暂时离开屏幕，鼠标变为系统区域截图的十字光标；拖动框选二维码即可，按 `Esc` 取消。macOS 会最小化而不是直接隐藏唯一窗口，并在成功、取消或异常后恢复并激活窗口。

如果系统设置里已经开启 `TOTP Vault` 的“录屏与系统录音”，应用仍提示权限尚未生效，请点击弹窗中的“退出并重新打开”。首次授权后当前进程可能必须彻底重启；默认 ad hoc 签名的应用在重新构建后身份也会变化，因此升级后可能需要再次确认权限。若本机 Keychain 已有稳定的代码签名 identity，可通过上述环境变量或 `--codesign-identity` 参数打包/安装。

## Vault 解锁与恢复

- 本地 Vault 每次更新会保留前一版本为同目录下的 `vault.gcvault.bak`。
- 解锁时会分别验证主文件与自动备份；主文件损坏但备份有效时可直接进入，后续保存会修复主文件且不会用损坏文件覆盖良好备份。
- 解锁提示进一步区分 wrapped DEK 认证失败、payload AES-GCM 认证失败、已认证正文 JSON 无效和 payload schema 不兼容；AES-GCM 无法区分错误密码和已损坏的 wrapped key，因此密码错误提示仍保留这两种可能性。
- schema-v1 兼容恢复允许早期可选字段缺失、旧 `period` 字段和数字字符串；账号引用不存在的分组时回退到“未分组”，不会删除账号。
- 当前 payload AAD 失败时只尝试有限的历史候选，并且每个候选仍必须通过 AES-GCM MAC；应用不会进行未认证解密或输出明文诊断。
- 快速解锁失败不再自动删除 Keychain/Credential Manager 中的设备 DEK；只有用户在安全设置中明确禁用时才删除。
- 忘记主密码且设备快速解锁材料已经缺失时，应用无法绕过加密恢复 Secret；请保留主文件、`.bak` 和所有 `.gcbak`，不要重置 Vault。

## 阶段 19 Vault 恢复摘要

- 主密码正确后的失败已细分到 AES-GCM 正文认证、JSON 和 schema 三层。
- 增加受认证的历史 AAD 尝试与早期 schema-v1 兼容解析，不降低密码学校验。
- 完整实现与测试见 `docs/PHASE19_STATUS.md`。

## 阶段 18 验证摘要

- 验证码首页支持创建、重命名和删除本地分组。
- 账号可通过明确拖拽手柄移入自定义分组或“未分组”。
- 分组筛选可与搜索组合，删除分组不会删除账号。
- 完整实现与测试见 `docs/PHASE18_STATUS.md`。

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

## 云备份

应用支持手动将独立密码加密的 `.gcbak` 备份到：

- iCloud Drive 同步目录；
- Google Drive 桌面版同步目录；
- GitHub App 获得授权的专用私有仓库。

iCloud 与 Google Drive 由系统或桌面客户端负责登录和同步。GitHub 使用 Device Flow，用户可以登录自己选择的 GitHub 账号；Token 仅保存到当前设备的 macOS Keychain 或 Windows Credential Manager。 当前 GitHub App 允许任意个人或组织账号安装；安装时建议选择 `Only select repositories`，并只授权专用私有备份仓库。

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

GitHub Actions 的 `Personal Install Readiness` 使用 Repository Variable `TOTP_VAULT_GITHUB_CLIENT_ID`。不要提交 Client Secret、GitHub App private key 或用户 Token。完整配置与安全边界见 `docs/PHASE25_STATUS.md`。
