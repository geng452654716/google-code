# 阶段 12 状态：跨平台 CI 与 Windows 编译闭环

- 完成日期：2026-07-17
- 当前结论：已建立 GitHub Actions 跨平台桌面持续集成，固定使用 Flutter 3.44.0，在 Linux 执行格式、静态分析和 100 项自动化测试，并在 macOS 15 与 Windows Server 2022 分别完成 Debug 构建和短期产物归档。CI 首次暴露了 Linux 平台测试分支和 Windows 原生链接问题，均已修复；最终运行 `29553852497` 全部通过。Windows 原生代码现已通过 MSVC 编译，但 Windows 10/11 真机运行、设备认证、安全存储、截图、系统会话事件和系统分享交互仍需人工验收。

## 本阶段已完成

### GitHub Actions 工作流

- [x] 新增 `.github/workflows/desktop-ci.yml`。
- [x] 支持推送到 `main`、Pull Request 和手动 `workflow_dispatch` 三种触发方式。
- [x] 使用 `permissions: contents: read` 限制默认令牌权限。
- [x] 使用 `concurrency` 取消同一 ref 上已过时的运行，避免重复消耗 Runner。
- [x] 统一固定 Flutter 3.44.0，与 `.fvm/fvm_config.json` 和 `pubspec.lock` 保持一致。
- [x] 固定 GitHub Action 的完整提交 SHA，避免 tag 漂移或供应链版本被静默替换：
  - `actions/checkout` v6：`df4cb1c069e1874edd31b4311f1884172cec0e10`
  - `subosito/flutter-action` v2.23.0：`1a449444c387b1966244ae4d4f8c696479add0b2`
  - `actions/upload-artifact` v7：`043fb46d1a93c77aae656e7c1c64a875d1fc6a0a`
- [x] 所有 Job 均设置超时，避免异常任务无限占用 Runner。

### 质量检查 Job

Linux `ubuntu-24.04` Runner 执行：

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
```

- [x] 格式检查覆盖 `lib`、`test` 和 `tool`。
- [x] 静态分析要求 0 issues。
- [x] 自动化测试当前共 100 项。
- [x] macOS 和 Windows 构建 Job 仅在质量检查通过后运行。

### macOS 构建 Job

- [x] 使用 `macos-15` Runner 执行 `flutter build macos --debug`。
- [x] 将 `.app` 打包为 `google-code-macos-debug.tar.gz`，保留应用包目录结构和可执行权限。
- [x] 上传 `google-code-macos-debug` 构建产物，保留 7 天。
- [x] 缺少产物时主动失败，而不是产生空的成功记录。

### Windows 构建 Job

- [x] 使用 `windows-2022` Runner 和 MSVC 执行 `flutter build windows --debug`。
- [x] 上传 `build/windows/x64/runner/Debug/` 完整运行目录。
- [x] 上传 `google-code-windows-debug` 构建产物，保留 7 天。
- [x] Windows 原生截图、安全存储、系统会话事件和系统分享代码均已进入真实 MSVC 编译与链接闭环。

## CI 发现并修复的问题

### 1. Linux 平台测试未进入 MethodChannel 分支

首次 CI 运行中，`MethodChannelSecureKeyStore` 根据 `Platform.isMacOS || Platform.isWindows` 判断能力，导致 Linux Runner 直接返回 `null`，原生错误映射测试未实际调用 Mock MethodChannel。

修复方式：

- 为 `MethodChannelSecureKeyStore` 增加有注释的 `platformSupportedOverride` 构造参数。
- 生产代码默认继续使用真实平台检测。
- 测试显式传入 `true`，保证 Linux、macOS 和 Windows 上均执行同一个原生错误映射分支。

### 2. Windows Flutter PluginRegistrar 链接失败

Windows 首次 MSVC 构建报告 `PluginRegistrar` 和 `PluginRegistrarManager` 未解析符号。Runner 已链接 `flutter_wrapper_app`，而应用内自定义 MethodChannel 不需要借用插件注册器。

修复方式：

- 移除 Runner 自定义通道对 `PluginRegistrarWindows` 的依赖。
- 剪贴板图片、区域截图、安全存储、系统会话事件和原生分享统一直接使用 `FlutterEngine::messenger()`。
- 避免为应用内通道额外引入 `flutter_wrapper_plugin`，减少重复 wrapper 依赖和链接复杂度。

### 3. Windows C++/WinRT 事件委托链接失败

Windows 分享代码的 `TypedEventHandler` 模板缺少完整的 Windows Foundation 定义，导致 `DataRequested` lambda 委托构造函数未解析。

修复方式：

- 按 C++/WinRT 依赖顺序引入 `winrt/base.h`。
- 显式引入 `winrt/Windows.Foundation.h`。
- 保留 DataTransfer 和 Storage Streams 的投影头文件。

## 最终验证结果

### 本地验证

| 检查项 | 结果 |
| --- | --- |
| `fvm dart format --output=none --set-exit-if-changed lib test tool` | 通过，100 files，0 changed |
| `fvm flutter analyze` | 通过，0 issues |
| `fvm flutter test` | 通过，100 tests |
| `fvm flutter build macos --debug` | 通过，生成 `build/macos/Build/Products/Debug/google_code.app` |
| `git diff --check` | 通过 |

### GitHub Actions 最终运行

- 运行编号：`29553852497`
- 提交：`f37947d39be4365f6e7622aca053924f147ac62e`
- 结果：全部通过
- 运行地址：`https://github.com/geng452654716/google-code/actions/runs/29553852497`

| Job | Runner | 结果 | 用时 |
| --- | --- | --- | --- |
| Quality checks | `ubuntu-24.04` | 通过 | 1m45s |
| macOS debug build | `macos-15` | 通过，产物已上传 | 2m27s |
| Windows debug build | `windows-2022` | 通过，产物已上传 | 7m57s |

## 安全与隐私约束

- CI 不配置、不读取也不输出真实 TOTP Secret、验证码、`otpauth://` URI、Vault 或 `.gcbak` 备份。
- 自动化测试只使用专用虚假 Secret 和临时目录。
- 构建产物不包含本地用户 Vault；Runner 从干净仓库检出开始构建。
- 工作流仅使用仓库只读权限，不写入 Release、Issue、Package 或其他 GitHub 资源。
- Debug 构建产物仅用于编译闭环和测试，不视为已签名、可公开分发的正式安装包。

## 当前限制与风险

- [ ] Windows Debug 构建已通过 MSVC，但尚未在 Windows 10/11 真机启动并逐项验证功能。
- [ ] Windows Hello、Credential Manager、区域截图、剪贴板图片、系统锁屏事件和系统分享仍需真机运行矩阵。
- [ ] macOS CI 构建未签名、未公证，也未覆盖 Sandbox 下的系统分享和权限行为。
- [ ] 当前 CI 未生成 Release 构建、安装包、签名、公证、SHA-256 校验值或 SBOM。
- [ ] 当前未启用依赖漏洞扫描、许可证检查和 Secret scanning 的项目级验证。
- [ ] Windows 产物上传前未额外压缩；GitHub Artifact 适合测试下载，不等同于正式分发格式。

## 下一阶段建议

1. 进入阶段 13：实现 macOS/Windows 摄像头二维码扫描 PoC，并保持 CI 的双平台编译闭环。
2. 在可用 Windows 10/11 设备上下载 CI 产物，完成启动、截图、安全存储、设备认证、系统事件和系统分享人工验收。
3. 后续发布阶段增加 Release 构建、macOS 签名/公证、Windows 代码签名和安装包。
4. 增加依赖审计、许可证清单和发布产物校验值。

## 阶段 13 后续进展

- 阶段 13 已实现 macOS/Windows 摄像头二维码扫描 PoC，统一支持标准 `otpauth://` 和 Google Authenticator 迁移二维码导入。
- `camera` + `camera_desktop` 已通过 Linux 106 项测试、macOS AVFoundation Debug 构建和 Windows Media Foundation/MSVC Debug 构建；实现提交对应 GitHub Actions 运行 `29564583502`。
- 摄像头真实扫码尚未完成人工验收，Windows 10/11 真机平台能力矩阵仍需继续执行；详见 `docs/PHASE13_STATUS.md`。

## 阶段 14 后续进展

- 阶段 14 已新增独立的手动 Release Readiness 工作流；普通 push 仍保留阶段 12 的 Debug CI，不额外承担 Release 构建开销。
- macOS/Windows Release 模式归档、独立 SHA-256、锁定依赖清单和第三方许可证报告已在运行 `29568998326` 通过，并完成下载后校验。
- 当前 Release Artifact 仍没有可信发布签名：macOS 未使用 Apple Developer ID 且未公证，Windows 未使用 Authenticode 且没有安装包；详见 `docs/PHASE14_STATUS.md`。
