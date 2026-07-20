# 阶段 22：macOS 二维码图片选择权限修复

- 完成日期：2026-07-20
- 目标：修复点击“从二维码图片导入”后系统拒绝显示图片选择窗口的问题。
- 数据兼容：不修改 Bundle ID、Vault 路径、Keychain 服务名、账号数据格式或二维码解析逻辑。

## 根因

macOS 系统日志明确报告：应用缺少 User Selected File Read 沙箱 entitlement，因此 AppKit 拒绝显示 `NSOpenPanel`。

本问题发生在文件选择窗口展示阶段，尚未进入图片读取或二维码解析流程，与二维码图片内容、屏幕录制权限和 TCC 授权无关。

## 修复内容

在 Debug/Profile 与 Release entitlement 中加入：

```text
com.apple.security.files.user-selected.read-only = true
```

该权限只允许应用读取用户通过系统文件选择窗口主动选择的文件，不授予任意目录访问权限。

同时补充原生面板 `.abort` 处理：如果 AppKit 无法显示面板，MethodChannel 会返回明确的 `image_picker_unavailable` 错误，不会把系统失败误判成用户取消选择。

## 自动化保护

新增 macOS 图片导入平台测试，验证：

1. `DebugProfile.entitlements` 包含用户选择文件只读权限；
2. `Release.entitlements` 包含用户选择文件只读权限；
3. 原生 `NSOpenPanel` 对 `.abort` 返回明确错误。

## 验证结果

- `flutter analyze --no-pub`：无问题；
- 完整 Flutter 测试：145 项通过；
- `git diff --check`：通过；
- macOS Release 构建成功；
- 构建产物、安装应用和 DMG 内应用均确认包含 `com.apple.security.files.user-selected.read-only`；
- 安装应用继续使用稳定签名 `TOTP Vault Local Signing`；
- 严格代码签名验证通过。

安装前后 Vault SHA-256 保持一致：

```text
f2e7dce7af987a5e27d966178460bdaf7f74c9ea5998c8f601052f0cd50e0ec8
```

修复版 DMG：

```text
dist/macos/TOTPVault-1.0.0-build1-macos-universal.dmg
SHA-256: 153f4f69ded019a9aa4bfbad2dc664e1a34e9bb3179cc766cbe53fcdd494e34f
```

本阶段未修改 TCC 数据库，未运行 `tccutil reset`，未绕过 Gatekeeper，也未读取 Vault 正文、主密码、Secret 或二维码内容。
