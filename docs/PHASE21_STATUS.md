# 阶段 21：稳定本地签名与 macOS 权限身份修复

- 完成日期：2026-07-20
- 目标：统一 `TOTP Vault` 的用户可见身份，使用稳定的本地代码签名，修复屏幕录制授权后重新打开不可靠的问题。
- 数据兼容：继续保留原 Bundle ID、可执行文件名、Vault 路径、Keychain 服务名和 MethodChannel 前缀。

## 问题根因

1. `~/Applications` 中同时存在旧的 `Google Code.app` 和新的 `TOTP Vault.app`，两个应用使用相同 Bundle ID。旧 Dock 或 LaunchServices 记录可能继续启动旧应用，因此软件内仍会显示 `Google Code`。
2. 以前的本地构建使用 ad hoc 签名。重新构建会改变代码身份，macOS TCC 可能无法将新版识别为已授权的同一个应用。
3. 旧的“退出并重新打开”使用延迟 shell 子进程调用 `/usr/bin/open -n`。父应用退出时子进程可能同时结束，导致应用退出后没有重新启动。
4. macOS 工程内部继续使用 `google_code` 作为兼容名称，窗口标题未显式使用 `CFBundleDisplayName`，因此部分窗口表面仍可能显示内部名称。

## 修复内容

### 稳定代码签名

- 用户已明确批准创建并信任本地代码签名身份 `TOTP Vault Local Signing`。
- 身份保存在当前用户的登录钥匙串中，不提交证书私钥、PKCS#12 文件或密码到仓库。
- 证书仅用于代码签名：`CA:FALSE`、`Digital Signature`、`Extended Key Usage: Code Signing`。
- 证书 SHA-1：`817A487662BA3779B79274EA97C64453908BCB3C`。
- 安装与 DMG 脚本在未显式指定其他 identity 时，自动检测并使用该身份。
- 仍支持通过 `TOTP_VAULT_CODESIGN_IDENTITY` 显式指定 Apple Development 等其他稳定身份。

### 应用身份与重启

- 主窗口和最小化窗口标题从 `CFBundleDisplayName` 读取，用户可见名称统一为 `TOTP Vault`。
- 内部 `PRODUCT_NAME` 和可执行文件名继续保持 `google_code`，避免影响既有数据与集成。
- 权限授权后的重启改为 `NSWorkspace.OpenConfiguration` 和 `openApplication`，成功启动替代实例后才退出当前实例。
- 移除旧的 shell relauncher，不再依赖 `/usr/bin/open -n`。

### 旧应用处理

旧应用已从：

```text
~/Applications/Google Code.app
```

移动到保留备份：

```text
~/Applications/Legacy App Backups/Google Code legacy 20260720-161050.bundle-backup
```

没有删除 Vault、Keychain、`.gcbak` 或恢复归档。

## 验证结果

- `flutter analyze --no-pub`：无问题。
- 完整 Flutter 测试：143 项通过。
- `git diff --check`：通过。
- macOS Release 构建成功。
- 新安装应用严格签名验证通过：
  - `Identifier=com.gengyujian.googleCode`
  - `Authority=TOTP Vault Local Signing`
  - designated requirement 绑定证书 SHA-1 `817A487662BA3779B79274EA97C64453908BCB3C`
- 安装前后 Vault SHA-256 一致：

```text
1ccd272b62b91ae15c3ebb1bb5742ff017cce341722a2c45857dd47daaf04b99
```

- 新 DMG 已生成并通过只读挂载、校验和及包内签名验证：

```text
dist/macos/TOTPVault-1.0.0-build1-macos-universal.dmg
SHA-256: ebb73f523a078209771d0805b7ed877b8b43b084bd38560a76daeb6bb5575452
```

## 权限说明

本阶段没有修改 TCC 数据库，没有运行 `tccutil reset`，也没有移除 quarantine 或绕过 Gatekeeper。

由于之前的授权记录可能对应旧应用或 ad hoc 身份，首次切换到稳定签名版本后，可能仍需在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中确认只保留当前 `TOTP Vault.app` 并重新开启一次。后续持续使用同一个本地签名身份构建和安装时，macOS 代码身份将保持稳定。
