# 阶段 15 状态：个人安装与本机使用闭环

更新日期：2026-07-17

## 阶段目标

在不公开发布、不上架应用商店、不申请管理员权限的前提下，让所有者能够从可信的本地源码完成 macOS/Windows Release 构建、当前用户安装、重复升级和卸载。

本阶段明确取代“立即进入可信公开发布”的方向。Apple Developer ID、公证、Windows Authenticode、MSIX/MSI、应用商店、公开 GitHub Release 和自动更新服务不再是当前退出条件。

## 已实现内容

### macOS 当前用户安装器

新增 `tool/install_macos.sh`：

- 默认从 `build/macos/Build/Products/Release/google_code.app` 安装。
- 默认目标为 `~/Applications/Google Code.app`，不写 `/Applications`，不需要 `sudo`。
- 默认先执行 FVM/Flutter Release 构建；`--skip-build` 可复用已有产物。
- 支持 `--source`、`--destination`、`--skip-build`、`--launch`、`--uninstall` 和 `--dry-run`。
- 安装前验证 `.app`、主执行文件和 `codesign --verify --deep --strict`。
- 使用 `ditto` 复制到 staging；已安装版本先移动到 backup，再提升新版本；失败时恢复旧版本。
- 安装、升级和卸载前检查 `google_code` 是否仍在运行。
- 默认不自动启动；只有显式传入 `--launch` 才调用 `open`。
- 不移除 `com.apple.quarantine`，不绕过 Gatekeeper，不把 ad hoc 签名称为可信发布签名。
- 卸载只删除目标 `.app`，保留 Vault、Keychain 记录和用户备份。

### Windows 当前用户安装器

新增 `tool/install_windows.ps1`：

- 默认从 `build\\windows\\x64\\runner\\Release` 安装。
- 默认目标为 `%LOCALAPPDATA%\\Programs\\Google Code`，不需要管理员权限。
- 默认先执行 FVM/Flutter Release 构建；`-SkipBuild` 可复用已有产物。
- 支持 `-Source`、`-Destination`、`-SkipBuild`、`-Launch`、`-Uninstall`、`-DryRun` 和 `-SkipShortcut`。
- 验证完整 Release 运行目录及 `google_code.exe`。
- 使用 staging + backup 完成可恢复覆盖升级；首次安装若后续步骤失败，也会删除未完成的新目录。
- 默认用 `WScript.Shell` 在当前用户开始菜单创建 `Google Code.lnk`；CI 可用 `-SkipShortcut` 避免真实用户目录副作用。
- 不修改 PATH、系统级注册表、防火墙或执行策略，不绕过 SmartScreen，不宣称 Authenticode 已签名。
- 卸载删除安装目录和脚本管理的快捷方式，保留 Vault、Windows Credential Manager 记录和用户备份。

### 自动化测试与 CI

新增 `test/tool/personal_installer_test.dart`：

- 检查双平台脚本包含 dry run、卸载和平台安全约束。
- macOS 验证缺少源应用时安全失败。
- macOS 验证 dry run 不产生目标目录。
- macOS 使用临时 ad hoc 签名 `.app` 完成首次安装、重复升级、transaction 目录清理、卸载和外部数据保留。

`.github/workflows/release-readiness.yml` 已调整为手动 **Personal Install Readiness**：

- macOS Runner 在 Release 构建后，对临时目录执行 dry run、首次安装、重复升级、执行文件检查和卸载。
- Windows Runner 在 Release 构建后，对临时目录执行同等闭环，并使用 `-SkipShortcut` 避免写 Runner 的真实开始菜单。
- 工作流仍保留阶段 14 的依赖/许可证审计、unsigned 归档和 SHA-256，以便本人设备安装前核验与排障；不会创建 GitHub Release。

## 本地验证

| 检查项 | 结果 |
| --- | --- |
| `fvm dart format --output=none --set-exit-if-changed lib test tool` | 通过，107 files，0 changed |
| `fvm flutter analyze --no-pub` | 通过，0 issues |
| `fvm flutter test --no-pub` | 通过，118 tests |
| `fvm flutter build macos --release --no-pub` | 通过，生成 48.4MB universal `.app` |
| 临时目录 dry run / 安装 / 重复升级 / `codesign` / 卸载 | 通过，transaction 目录已清理 |
| `git diff --check` | 通过 |

构建仍报告 `objective_c` native asset 在不同架构使用不同 framework 名称的上游警告；本次构建成功，风险与阶段 14 一致。

## 本机安装验收

- 安装目标：`/Users/gengyujian/Applications/Google Code.app`
- 安装方式：使用 Release 产物执行 `tool/install_macos.sh --skip-build --launch`
- 结果：安装成功，主进程已启动；bundle 为 `x86_64 arm64` universal app。
- 签名复核：`Identifier=com.gengyujian.googleCode`、`Signature=adhoc`、`TeamIdentifier=not set`，`codesign --verify --deep --strict` 通过。
- 安装目录大小：约 46MiB（`du`），构建日志显示打包大小 48.4MB。
- 安装器未删除、迁移或重建 Vault；本阶段没有执行数据清除。

## GitHub Actions 验证

实现提交：`0dcca1c8432059838b78cce47893a9474b6e5216`

### Desktop CI

- 运行编号：`29572050531`
- 结果：全部通过
- 运行地址：`https://github.com/geng452654716/google-code/actions/runs/29572050531`

| Job | Runner | 结果 | 用时 |
| --- | --- | --- | --- |
| Quality checks | `ubuntu-24.04` | 通过，118 tests | 2m3s |
| macOS debug build | `macos-15` | 通过，产物已上传 | 1m58s |
| Windows debug build | `windows-2022` | 通过，产物已上传 | 4m1s |

### Personal Install Readiness

- 运行编号：`29572098688`
- 结果：全部通过
- 运行地址：`https://github.com/geng452654716/google-code/actions/runs/29572098688`

| Job | Runner | 结果 | 用时 |
| --- | --- | --- | --- |
| Dependency and license audit | `ubuntu-24.04` | 通过，元数据已上传 | 37s |
| macOS personal build and install | `macos-15` | 通过，dry run / 安装 / 重复升级 / 卸载 / 归档 | 2m22s |
| Windows personal build and install | `windows-2022` | 通过，dry run / 安装 / 重复升级 / 卸载 / 归档 | 7m43s |

Windows Job 的 `Smoke test personal Windows install, upgrade, and uninstall` 步骤明确成功，证明 PowerShell 语法、Release 目录复制、transaction 升级和卸载逻辑已在真实 Windows Runner 执行，而不只是静态检查。

## 安全与隐私约束

- 安装器只处理应用 bundle/运行目录和脚本管理的快捷方式，不读取、复制、记录或上传 Vault、TOTP Secret、验证码、二维码内容或 `.gcbak` 内容。
- 升级必须在应用退出后执行，避免插件 DLL/framework 或 Vault 写入过程被中断。
- 自定义卸载目标仍受根目录与 macOS `.app` 后缀保护；用户不应把目标指向其他应用或数据目录。
- macOS ad hoc 签名和 Windows unsigned 二进制只适合本人从可信源码构建后使用，不认证发布者。
- 脚本不提供 quarantine/SmartScreen 绕过参数。若操作系统阻止未知来源应用，应先核对源码、构建过程和产物，再通过系统提供的人工安全流程决定是否打开。
- 卸载不等于清除敏感数据；需要彻底清除时应在确认备份后，单独处理 Vault 和系统安全存储，避免安装脚本误删。

## 当前限制与风险

- [ ] Windows 脚本已由 CI Runner 验证安装文件闭环，但开始菜单快捷方式和真实启动仍需用户自己的 Windows 10/11 设备验收。
- [ ] macOS 安装脚本验证 bundle 现有签名完整性，但 ad hoc 签名不提供发布者身份认证。
- [ ] Windows unsigned 应用可能触发 SmartScreen；脚本不会绕过该机制。
- [ ] 当前没有自动更新；升级需要从可信源码重新构建并再次运行安装脚本。
- [ ] 安装器不执行应用内摄像头、截图、系统分享、设备认证和系统安全存储的完整真机功能矩阵。
- [ ] 如果未来要把应用分享给其他人，必须重新评估产品命名、可信签名、公证、安装包、许可证义务、更新与回滚策略。

## 下一阶段建议

1. 在自己的 Windows 10/11 设备运行 `tool/install_windows.ps1`，检查开始菜单快捷方式、首次启动、SmartScreen、Credential Manager、设备认证、摄像头、截图和系统分享。
2. 在当前 macOS 安装版中完成功能级人工回归：Vault 解锁、验证码刷新、二维码导入、系统分享、截图、摄像头、睡眠/锁屏自动锁定和备份恢复。
3. 增加一个只读“关于/诊断”页面，展示版本、构建号、Vault 路径类别、平台能力状态和脱敏诊断导出，便于个人设备排障。
4. 评估托盘、全局快捷键和快速显示/隐藏窗口，优化日常个人使用效率。
