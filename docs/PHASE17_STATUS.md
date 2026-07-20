# 阶段 17 状态：macOS 屏幕录制权限恢复与 TOTP 二维码兼容

更新日期：2026-07-20

## 阶段目标

修复 macOS 系统设置已开启 `Google Code` 的“录屏与系统录音”，应用却持续提示需要权限的问题；让首次授权后的重启操作可在应用内完成，并为个人安装包提供可选稳定代码签名入口。

本阶段继续遵守个人自用边界：不关闭或绕过 TCC、Gatekeeper，不修改 TCC 数据库，不自动创建或信任证书，不创建公开 Release，也不删除 Vault、Keychain 或 `.gcbak` 数据。

## 现象与根因

用户截图确认系统设置中的 `Google Code` 开关已经开启，但当前进程的 `CGPreflightScreenCaptureAccess()` 与 `CGRequestScreenCaptureAccess()` 仍返回 `false`。

本机安装应用的 bundle identifier 为 `com.gengyujian.googleCode`，签名为 ad hoc，未设置 Team Identifier；本机 Keychain 当前没有有效 code-signing identity。ad hoc 构建的应用身份依赖会随重新构建变化的代码哈希，因此系统设置可能保留同名旧授权，但当前新二进制无法匹配。首次授权后，当前进程本身也可能必须完全退出并重新打开，权限状态才会生效。

## 已实施修复

### 应用内权限恢复

- 权限错误文案改为“当前进程尚未获得屏幕录制权限”，不再断言用户一定没有开启开关。
- 弹窗标题改为“屏幕录制权限尚未生效”。
- 弹窗同时提供“打开系统设置”和“退出并重新打开”。
- 新增 `restartApplication` MethodChannel 方法。
- macOS runner 启动一个延迟 relauncher，目标固定为当前 `Bundle.main.bundleURL`；原生调用成功返回后正常终止当前进程，新实例随后重新打开。
- 自动重启失败时提示用户手动完全退出并重新打开，不暴露原生诊断细节。

### 可选稳定签名

`tool/package_macos_dmg.sh` 和 `tool/install_macos.sh` 新增：

```text
--codesign-identity NAME
GOOGLE_CODE_CODESIGN_IDENTITY
```

指定 identity 时只对 staging app 重新签名，并保留原 identifier 和 entitlements；随后执行 `codesign --verify --deep --strict`。未指定时仍保持原有 ad hoc/个人安装行为，并明确提示升级后隐私权限可能需要重新确认。

本机当前 `security find-identity -v -p codesigning` 返回 `0 valid identities found`，因此本阶段不会擅自创建自签名证书。若后续通过 Xcode/Apple ID 创建 Apple Development identity，可直接用上述参数生成稳定身份的个人安装包；这不要求创建公开 Release。

诊断期间使用 Apple 官方 `tccutil reset ScreenCapture com.gengyujian.googleCode` 一次性删除该 bundle identifier 的陈旧屏幕录制授权记录，然后由用户重新通过系统授权。该操作不绕过 TCC，也不读取或修改 Vault、Keychain、验证码或 `.gcbak`；应用和安装脚本不会自动执行权限重置。

### TOTP 二维码兼容

用户提供的二维码已经由项目自身 `QrCodeService` 成功解码，确认协议为标准 `otpauth://totp`。失败点不是二维码图像或协议，而是 label 采用 `Issuer:` 结构：发行方存在，但冒号后的独立账号名为空。原 `OtpAuthUriCodec` 因此抛出“账号名缺失”，导入层又将具体错误统一转换成“不支持的 TOTP 账号”。

修复保持严格边界：只有 label issuer 与 query issuer 都存在、去除首尾空白后完全一致，且 label 明确包含冒号时，才把 issuer 回退为显示账号名。缺少 issuer、issuer 冲突、HOTP、非法 Base32 Secret 或不支持的 TOTP 参数仍被拒绝。用户原图只用于本地脱敏回归，验证字段非空且可导入，不输出或记录原始 URI、Secret、账号和发行方内容。

导入错误提示同时细分为账号名称为空、发行方冲突、Secret 无效、参数不支持和未知格式，避免把结构合法但字段有问题的 TOTP 二维码统一误报为协议不受支持。

## 自动化测试

新增或扩展：

- `test/platform/screenshot/screen_capture_service_test.dart`
- `test/features/accounts/account_screenshot_import_test.dart`
- `test/platform/macos_screen_capture_runner_test.dart`
- `test/tool/personal_installer_test.dart`
- `test/tool/personal_package_test.dart`
- `test/domain/otp_auth_uri_codec_test.dart`
- `test/application/import/otp_import_service_test.dart`

覆盖范围：

- Dart 平台服务发出 `restartApplication` 原生调用。
- 权限弹窗同时展示设置与重启入口。
- 已开启权限场景可选择应用内重启，不会再次打开系统设置。
- macOS runner 包含延迟 relaunch 与当前进程正常退出。
- DMG/安装脚本暴露稳定签名参数，并保留 entitlements、identifier 和安全验证。
- 匹配 issuer 的 `Issuer:` 空账号 label 可安全回退导入。
- 缺少双 issuer 或 issuer 冲突的空账号仍被拒绝。
- issuer 冲突和非法 Secret 返回不泄露原始数据的具体错误类别。

## 本地验证

| 检查项 | 结果 |
| --- | --- |
| `bash -n tool/install_macos.sh tool/package_macos_dmg.sh` | 通过 |
| `fvm dart format --output=none --set-exit-if-changed lib test tool` | 通过，109 files，0 changed |
| `fvm flutter analyze --no-pub` | 通过，0 issues |
| `fvm flutter test --no-pub` | 通过，130 tests |
| `fvm flutter build macos --release --no-pub` | 通过，生成 48.4MB universal `.app` |
| `codesign --verify --deep --strict` | Release 与安装后 app 均通过 |
| DMG 创建与 `hdiutil verify` | 通过 |
| 新 DMG SHA-256 | `ec70dc23262af3517ed4907dc4e76b02ba97ac81980d251b0a7800091b08c67e` |
| 用户级安装与启动 | 通过，`~/Applications/Google Code.app` 已启动 |
| `git diff --check` | 通过 |

安装后应用仍为预期的 ad hoc 签名，bundle identifier 为 `com.gengyujian.googleCode`，当前 CDHash 为 `0d81c7e66b788c22c06ca01cfa475ebd5d678758`，再次证明新构建身份已不同于阶段 16 安装包。

## GitHub Actions 验证

本节在提交推送后记录实际运行结果。

## 本机人工验收步骤

1. 安装修复后的同一个 `.app`，打开并解锁 Vault。
2. 点击“扫描屏幕二维码”并确认开始框选。
3. 如果弹出“屏幕录制权限尚未生效”，确认系统设置里的 `Google Code` 已开启。
4. 返回应用，点击“退出并重新打开”。
5. 应用自动重新启动后再次扫描，确认窗口最小化、十字光标框选、二维码识别和窗口恢复。
6. 使用本阶段报告的 `Issuer:` 空账号二维码再次扫描，确认进入账号确认页，发行方和显示账号名均非空，验证码参数可保存。
7. 如果安装的是新的 ad hoc build，系统可能要求对新身份重新切换一次权限；有稳定 Apple Development identity 后，应改用稳定签名参数安装并验证升级授权保持情况。

## 当前限制

- 本机尚无 Apple Development 或其他有效 code-signing identity，当前本地构建仍为 ad hoc 签名。
- ad hoc 新构建仍可能被 macOS 视为新应用身份；应用内重启解决首次授权后的进程刷新，但无法替代稳定代码签名。
- 应用不会自动重置 TCC；诊断时的一次性官方 `tccutil reset` 不能替代稳定签名，也不会作为常规升级流程。不会直接修改 TCC 数据库、关闭系统保护或绕过 Gatekeeper。
