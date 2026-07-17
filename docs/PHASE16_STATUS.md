# 阶段 16 状态：个人安装包与屏幕扫描稳定性

更新日期：2026-07-17

## 阶段目标

在阶段 15 当前用户级安装脚本的基础上，提供本人可直接安装的 macOS DMG 和 Windows Setup EXE，并修复 macOS“扫描本机二维码”过程中唯一窗口消失、用户误认为应用闪退的问题。

本阶段仍坚持个人自用边界：不公开发布、不创建公开 GitHub Release、不上架应用商店、不绕过 Gatekeeper/SmartScreen；卸载保留 Vault、Keychain/Credential Manager 记录和 `.gcbak` 备份。

## 屏幕二维码扫描修复

### 现象与根因

原 macOS 截图实现会在启动系统区域截图前对唯一应用窗口调用 `orderOut(nil)`。窗口立即从屏幕和 Dock 窗口状态中消失，同时 `/usr/sbin/screencapture -i -s -c -x` 会把鼠标切换为系统截图十字光标，因此操作表现很像应用闪退。

2026-07-17 复核本机最近 14 天的 `~/Library/Logs/DiagnosticReports`，没有找到 Google Code 相关崩溃报告。现有证据支持“窗口被隐藏造成的闪退错觉”，而不是进程崩溃。

### 已实施修复

- 入口名称统一为“扫描屏幕二维码”。
- 启动系统截图前显示说明对话框，明确窗口会暂时离开屏幕、鼠标会变为十字光标、拖动框选二维码以及按 `Esc` 取消。
- 用户可以在原生截图启动前取消，不会改变窗口状态。
- macOS 原生窗口从 `orderOut(nil)` 改为 `miniaturize(nil)`，等待 250ms 后再调用系统截图。
- 截图成功、取消或异常后统一执行 `deminiaturize(nil)`、`makeKeyAndOrderFront(nil)` 和 `NSApp.activate(ignoringOtherApps: true)`。
- 原生截图取消时显示“已取消屏幕二维码扫描，应用窗口已恢复。”
- 新增 UI 流程和 macOS 原生 runner 源码回归测试，防止重新引入直接隐藏唯一窗口的行为。

### 人工操作预期

1. 点击“扫描屏幕二维码”。
2. 阅读说明后点击继续。
3. Google Code 窗口最小化，鼠标变为系统截图十字光标。
4. 拖动框选二维码；或按 `Esc` 取消。
5. 应用窗口自动恢复并重新获得焦点。

鼠标变为十字光标是 macOS 系统区域截图的正常状态，不代表应用崩溃。

## macOS DMG

新增 `tool/package_macos_dmg.sh`：

- 默认构建 Flutter macOS Release，也支持 `--source`、`--output`、`--skip-build` 和 `--dry-run`。
- DMG 内包含 `Google Code.app` 和指向 `/Applications` 的快捷方式。
- 使用 `ditto` 保留 app bundle 内容与签名。
- 生成后执行 `hdiutil verify` 和 `codesign --verify --deep --strict`。
- 同时生成独立 `.sha256` 文件。
- 不删除 quarantine，不关闭 Gatekeeper，不把 ad hoc 签名称为可信发布签名。

最终 CI Artifact 已下载到：

```text
dist/downloaded/macos/GoogleCode-1.0.0-build1-macos-universal.dmg
```

| 属性 | 值 |
| --- | --- |
| 文件大小 | 22,484,185 bytes，约 21.4 MiB |
| SHA-256 | `fa598464ebe200f60551be0dbba76cdec5226de7f594ea962510efd912b4ae9b` |
| CI Artifact | `google-code-macos-personal-dmg` |
| 本机复核 | `hdiutil verify` 通过 |

本机较早从同一源码自行构建的 `dist/macos/GoogleCode-1.0.0-build1-macos-universal.dmg` 也已完成真实挂载、Applications 链接、主执行文件和 bundle 签名检查。压缩 DMG 并非可重复字节构建，因此本机构建与 CI 构建的 SHA-256 不要求相同；安装时应以对应文件旁的 `.sha256` 为准。

## Windows Setup EXE

新增 `tool/package_windows_exe.ps1` 和 `windows/installer/google_code.iss`：

- 使用 Inno Setup 6 生成标准 Setup EXE。
- 安装到 `%LOCALAPPDATA%\Programs\Google Code`，`PrivilegesRequired=lowest`，不请求管理员权限。
- 创建当前用户开始菜单快捷方式，支持覆盖升级和标准卸载。
- 同时生成独立 `.sha256` 文件，并记录 Authenticode 状态；当前预期为 `NotSigned`。
- 不修改 PowerShell 执行策略，不绕过 SmartScreen。
- 卸载不处理应用目录外的 Vault、Credential Manager 记录和 `.gcbak` 备份。
- Inno Setup 定义只依赖每个安装版本都自带的 `compiler:Default.isl`，避免 CI 因可选语言包缺失而无法编译。

最终 CI Artifact 已下载到：

```text
dist/downloaded/windows/GoogleCode-1.0.0-build1-windows-x64-setup.exe
```

| 属性 | 值 |
| --- | --- |
| 文件大小 | 11,788,272 bytes，约 11.2 MiB |
| SHA-256 | `dbb9c22504d892ab32fcc1b273d8666d3a221a3a4d71a3d937dfc250b9c9930f` |
| CI Artifact | `google-code-windows-personal-setup` |
| 安装器界面 | 当前使用 Inno Setup 默认英文界面 |
| 签名状态 | 未进行 Authenticode 可信发布签名 |

## 自动化测试

新增或扩展：

- `test/platform/macos_screen_capture_runner_test.dart`
- `test/features/accounts/account_screenshot_import_test.dart`
- `test/tool/personal_package_test.dart`

覆盖范围：

- macOS 截图前说明、启动前取消、系统截图取消提示和窗口恢复。
- macOS 原生实现使用最小化/恢复，不再使用 `orderOut(nil)`。
- DMG 打包定义保留平台安全机制。
- 临时 ad hoc 签名 `.app` 真实生成 DMG、校验、挂载并检查 Applications 链接。
- Windows 打包定义为当前用户级安装，不修改执行策略或绕过 SmartScreen。
- Inno Setup 不依赖可选的 `ChineseSimplified.isl`。

## 本地验证

| 检查项 | 结果 |
| --- | --- |
| `fvm dart format --output=none --set-exit-if-changed lib test tool` | 通过，109 files，0 changed |
| `fvm flutter analyze --no-pub` | 通过，0 issues |
| `fvm flutter test --no-pub` | 通过，122 tests |
| `fvm flutter build macos --release --no-pub` | 通过，生成约 48.4MB universal `.app` |
| 本机 DMG 创建、verify、挂载、Applications 链接和 codesign 检查 | 通过 |
| 最终 CI DMG 下载后再次执行 `hdiutil verify` | 通过 |
| `git diff --check` | 通过 |

运行全量测试前，已正常退出之前安装并运行的 Google Code；安装器测试按设计会拒绝覆盖正在运行的应用。

## GitHub Actions 验证

阶段实现提交：`d1ce3e766506c141c1d196f47cd74cdf2c85e3d1`

Windows 打包兼容性修复提交：`e498042ab7b4bd9ab90da01e51395ed43f868a0e`

### 最终 Desktop CI

- 运行编号：`29575452467`
- 提交：`e498042ab7b4bd9ab90da01e51395ed43f868a0e`
- 结果：全部通过
- 运行地址：`https://github.com/geng452654716/google-code/actions/runs/29575452467`

| Job | 结果 | 用时 |
| --- | --- | --- |
| Quality checks | 通过，包含格式、analyze 和 122 tests | 1m49s |
| macOS debug build | 通过，产物已上传 | 1m46s |
| Windows debug build | 通过，产物已上传 | 4m6s |

### 最终 Personal Install Readiness

- 运行编号：`29575859931`
- 提交：`e498042ab7b4bd9ab90da01e51395ed43f868a0e`
- 结果：全部通过
- 运行地址：`https://github.com/geng452654716/google-code/actions/runs/29575859931`

| Job | 结果 | 用时 |
| --- | --- | --- |
| Dependency and license audit | 通过，元数据已上传 | 54s |
| macOS personal build and install | 通过，Release、脚本安装/升级/卸载、DMG 构建/校验/上传 | 3m24s |
| Windows personal build and install | 通过，Release、脚本安装/升级/卸载、EXE 编译、两次安装、卸载、上传 | 5m13s |

Windows Job 已在真实 `windows-2022` runner 上完成 Inno Setup EXE 编译、首次静默安装、重复静默安装/覆盖升级、标准卸载，以及外部 Vault fixture 保留检查。

先前运行 `29574896887` 暴露出 Chocolatey 的 Inno Setup 6 不附带可选 `ChineseSimplified.isl`。该问题已由 `e498042` 修复，并由最终运行 `29575859931` 验证闭环。

## 安全与隐私约束

- 安装包、安装脚本和 CI 不读取、记录或上传 Vault、TOTP Secret、当前/历史验证码、二维码内容或 `.gcbak` 内容。
- 公开发布签名不在当前个人自用范围；SHA-256 只能检查文件完整性，不能认证发布者身份。
- macOS DMG 不绕过 Gatekeeper，Windows Setup EXE 不绕过 SmartScreen。
- 升级前应退出正在运行的 Google Code。
- 卸载应用不会自动清除 Vault 和系统安全存储；若要彻底清除敏感数据，需要在确认备份后单独处理。

## 当前限制与人工验收项

- [ ] 在已安装的 macOS Release 应用中解锁 Vault，实际点击“扫描屏幕二维码”，确认最小化、框选、取消和恢复体验符合预期。
- [ ] 在自己的 Windows 10/11 设备双击最终 Setup EXE，确认 SmartScreen 提示、开始菜单快捷方式和 GUI 首次启动。
- [ ] 在 Windows 真机确认 Credential Manager、Windows Hello、摄像头、屏幕截图和原生分享。
- [ ] macOS 仍为 ad hoc 签名，Windows 仍未进行 Authenticode 签名；仅适合本人从可信仓库和可信 CI 获取后安装。
- [ ] 当前没有自动更新，后续升级需要重新构建或下载新的个人安装包。
