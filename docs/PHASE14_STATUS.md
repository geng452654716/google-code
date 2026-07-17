# 阶段 14 状态：Release 构建与供应链审计基线

- 完成日期：2026-07-17
- 实现提交：`f7a1a67ef01caed388eb26e780c7c09176a1c707`
- 校验兼容修复：`7ba11499eae48780b20f840b5b73343a5ef19b86`
- 当前结论：已建立可手动触发的 Release Readiness 流程，对锁定依赖执行来源和许可证审计，并在 macOS 15、Windows Server 2022 生成 Release 模式桌面产物、第三方许可证报告和 SHA-256 校验值。产物明确标记为未完成可信发布签名：macOS 只有构建系统的 ad hoc 签名，没有 Apple Developer ID 签名或公证；Windows 没有 Authenticode 签名。当前产物只用于发布准备和可信设备真机验收，不是可公开分发的正式安装包。

## 本阶段目标

1. 对 `pubspec.lock` 中的全部锁定依赖建立来源白名单，阻止未知镜像、Git 和本地 path 依赖进入发布构建。
2. 为直接、开发和传递依赖生成机器可读清单及去重后的第三方许可证报告。
3. 在独立工作流中生成 macOS、Windows Release 模式产物，不增加每次普通 push 的 CI 负担。
4. 为每个平台归档生成 SHA-256 校验值，并在产物中明确写入未签名/未公证风险提示。
5. 保持最小 GitHub Actions 权限、固定 Flutter 版本和 Action 完整提交 SHA。

## 本阶段已完成

### 发布元数据审计工具

新增 `tool/release_metadata.dart`：

- [x] 使用 `package:yaml` 解析 `pubspec.lock`，不通过目录名或当前网络状态推断依赖来源。
- [x] hosted 依赖只允许锁定 URL `https://pub.dev`。
- [x] 允许 Flutter SDK 依赖，拒绝 Git、path 和未知 source。
- [x] 读取 `.dart_tool/package_config.json` 定位已解析的包目录；本机 package cache 即使位于镜像目录，也不会改变对 lockfile 来源的判断。
- [x] hosted 包只在自身根目录查找许可证，避免错误继承父目录中的无关文件。
- [x] Flutter SDK 包缺少包内许可证时，回退到带 Flutter 启动器标记的 SDK 根许可证。
- [x] 识别 `LICENSE`、`LICENSE.txt`、`LICENSE.md`、`COPYING`、`COPYING.txt`、`NOTICE` 和 `NOTICE.txt`。
- [x] 缺少包目录、缺少许可证、非文件 package root、无效 JSON/YAML 或不受信任来源时失败并阻止 Release 工作流继续。
- [x] 不把本机 package cache 的绝对路径写入发布清单。

默认输出目录为 `build/release-metadata/`：

```text
build/release-metadata/
  dependency-manifest.json
  THIRD_PARTY_NOTICES.txt
```

`dependency-manifest.json` 包含：

- schema 版本和生成时间；
- `pubspec.lock` 的 SHA-256；
- 每个依赖的名称、精确版本、依赖关系、来源和许可证摘要；
- 按许可证内容 SHA-256 去重后的包名和来源文件列表。

`THIRD_PARTY_NOTICES.txt` 包含：

- 每组唯一许可证文本；
- 使用该文本的包列表；
- 许可证文件来源标签和内容 SHA-256；
- “锁定依赖快照不等同于法律意见”的明确声明。

当前锁文件审计结果：

| 项目 | 结果 |
| --- | --- |
| 锁定依赖 | 116 |
| hosted 依赖 | 112，全部来自 `https://pub.dev` |
| Flutter SDK 依赖 | 4：`flutter`、`flutter_test`、`flutter_web_plugins`、`sky_engine` |
| 唯一许可证文本 | 47 |
| Git/path/未知来源 | 0 |

### 自动化测试

新增 `test/tool/release_metadata_test.dart`，覆盖：

- [x] 合法 pub.dev hosted 与 Flutter SDK lockfile 解析。
- [x] 非 pub.dev hosted 地址拒绝。
- [x] Git/path 等未知来源拒绝。
- [x] package config 相对 URI 解析。
- [x] hosted 包不向父目录错误查找许可证。
- [x] Flutter SDK 根许可证回退。
- [x] 相同许可证文本按 SHA-256 去重。
- [x] 生成清单不泄露本机绝对路径。
- [x] 缺少 package root 时安全失败。

全量自动化测试由 106 项增加到 114 项。

### Release Readiness 工作流

新增 `.github/workflows/release-readiness.yml`：

- 仅通过 `workflow_dispatch` 手动触发，不在每次 push 重复执行 Release 构建。
- 默认令牌权限保持 `contents: read`。
- Flutter 固定为 `3.44.0`。
- `actions/checkout`、`subosito/flutter-action` 和 `actions/upload-artifact` 均固定完整提交 SHA。
- 同一 ref 不自动取消已开始的 Release Readiness，避免半途丢失长时间构建结果。

工作流包含三个 Job：

| Job | Runner | 职责 |
| --- | --- | --- |
| Dependency and license audit | `ubuntu-24.04` | `flutter pub get`、来源/许可证审计、上传发布元数据 |
| macOS unsigned release build | `macos-15` | Release 构建、元数据、tar.gz、SHA-256、未可信签名声明 |
| Windows unsigned release build | `windows-2022` | Release 构建、元数据、zip、SHA-256、未签名声明 |

生成的 Artifact：

```text
google-code-release-metadata
google-code-macos-unsigned-release
google-code-windows-unsigned-release
```

Artifact 保留 14 天。平台归档同时包含：

```text
应用目录或 .app
dependency-manifest.json
THIRD_PARTY_NOTICES.txt
UNSIGNED_BUILD.txt
```

归档旁提供独立 `.sha256` 文件。SHA-256 只用于检查下载内容是否完整，不能证明发布者身份，也不能替代代码签名、公证或安全分发渠道。

## 本地验证

执行日期：2026-07-17。

| 验证项 | 结果 |
| --- | --- |
| `fvm dart format --output=none --set-exit-if-changed lib test tool` | 通过，106 files 无变化 |
| `fvm flutter analyze --no-pub` | 通过，0 issues |
| `fvm flutter test --no-pub` | 通过，114 tests |
| `fvm flutter build macos --release --no-pub` | 通过，生成 48.4MB universal `.app` |
| `fvm dart run tool/release_metadata.dart` | 通过，116 dependencies / 47 unique license texts |
| `git diff --check` | 通过 |

本机 macOS Release 产物经 `codesign -dv --verbose=4` 确认为 `Signature=adhoc`、`TeamIdentifier=not set`。这不是 Apple Developer ID 发布签名，不能作为正式分发完成的证据。

构建期间仍出现 `objective_c` native asset 在不同架构使用不同 framework 名称的上游警告；当前构建成功，但升级 Flutter 或相关依赖时应持续观察。

## GitHub Actions 验证

### 最终实现 Desktop CI

- 运行编号：`29568997087`
- 提交：`7ba11499eae48780b20f840b5b73343a5ef19b86`
- 结果：全部通过
- 运行地址：`https://github.com/geng452654716/google-code/actions/runs/29568997087`

| Job | Runner | 结果 | 用时 |
| --- | --- | --- | --- |
| Quality checks | `ubuntu-24.04` | 通过，114 tests | 1m49s |
| macOS debug build | `macos-15` | 通过，产物已上传 | 1m54s |
| Windows debug build | `windows-2022` | 通过，产物已上传 | 3m54s |

### 最终实现 Release Readiness

- 运行编号：`29568998326`
- 提交：`7ba11499eae48780b20f840b5b73343a5ef19b86`
- 结果：全部通过
- 运行地址：`https://github.com/geng452654716/google-code/actions/runs/29568998326`

| Job | Runner | 结果 | 用时 |
| --- | --- | --- | --- |
| Dependency and license audit | `ubuntu-24.04` | 通过，元数据已上传 | 39s |
| macOS unsigned release build | `macos-15` | 通过，Release 归档与 SHA-256 已上传 | 2m23s |
| Windows unsigned release build | `windows-2022` | 通过，Release 归档与 SHA-256 已上传 | 5m8s |

## Artifact 下载后验证

首轮 Release Readiness 运行 `29568294266` 的三个 Job 均通过，但下载 Artifact 后发现 Windows `.sha256` 由 PowerShell `Set-Content` 写成 CRLF。macOS/Linux 的 `shasum -c` 会把行尾 `\r` 当作文件名的一部分，因此该运行不能作为跨平台校验闭环。提交 `7ba1149` 改为使用 .NET API 写入无 BOM 的 ASCII + LF 文件，并重新执行全部流程。

最终运行 `29568998326` 下载验证结果：

| Artifact | 下载后验证 |
| --- | --- |
| `google-code-release-metadata` | 清单为 schema 1，116 dependencies / 47 unique license texts |
| `google-code-macos-unsigned-release` | `shasum -a 256 -c` 通过；包含 `.app`、manifest、notices 和 unsigned 声明 |
| `google-code-windows-unsigned-release` | 校验文件以单个 LF 结尾且不含 CR；`shasum -a 256 -c` 通过；包含 `.exe`、manifest、notices 和 unsigned 声明 |

这次下载后复核证明校验文件不只在生成 Runner 内存在，而且可在另一平台按标准工具验证。

## 安全与隐私约束

- Release 工作流从干净仓库检出开始，不读取本机 Vault、`.gcbak`、TOTP Secret、验证码、`otpauth://` URI 或真实二维码。
- 工作流不配置签名证书、私钥或密码，不会在日志中输出签名材料。
- 发布清单只记录依赖元数据、许可证摘要和非绝对来源标签，不记录 Runner 的 package cache 绝对路径。
- 工作流只读仓库内容，不创建 GitHub Release，不修改代码、Issue、Package 或仓库配置。
- 许可证文本可能较大，当前报告约 1.4MB；它只随 CI Artifact 保存，不提交进 Git。

## 当前限制与风险

- [ ] macOS 产物没有 Apple Developer ID 签名和公证；ad hoc 签名不认证发布者。
- [ ] Windows 产物没有 Authenticode 签名，也没有生成 MSIX/MSI/安装程序。
- [ ] 当前归档是发布准备产物，不处理 Gatekeeper、SmartScreen、安装升级、卸载和自动更新。
- [ ] SHA-256 只验证内容完整性；如果校验文件和归档来自同一被篡改渠道，不能提供发布者真实性保证。
- [ ] 第三方许可证报告是 `pubspec.lock` 与本次 package cache 的自动快照，不是完整法律意见；正式分发前仍需人工审查许可证兼容性和通知义务。
- [ ] 当前来源审计不等同于漏洞扫描，也没有生成 CycloneDX/SPDX SBOM。
- [ ] GitHub 仓库级 Dependabot、CodeQL、Secret scanning 和依赖审查策略尚未纳入本阶段。
- [ ] macOS/Windows 原生能力与摄像头仍未完成目标真机人工验收。

## 下一阶段建议

1. 在 macOS 和 Windows 10/11 真机下载阶段 14 Artifact，验证启动、权限、摄像头、系统分享、安全存储、设备认证、系统会话自动锁定和备份恢复。
2. 准备 Apple Developer ID 和 Windows 代码签名证书，设计密钥隔离、短期凭证、日志脱敏及签名失败策略。
3. 增加 macOS 公证与 stapling、Windows 安装包及 SmartScreen 验证，不直接把当前 unsigned Artifact 作为公开 Release。
4. 增加 CycloneDX/SPDX SBOM、已知漏洞扫描、Dependabot/依赖审查和仓库 Secret scanning 基线。
5. 在可信签名和真机验收完成后，再设计版本 Tag、GitHub Release、更新策略和发布回滚流程。

## 阶段 15 范围调整（2026-07-17）

用户已确认 Google Code 只供自己安装和使用，不需要公开发布。因此本页“当前限制与风险”中关于可信签名、公证、MSIX/MSI、GitHub Release 和商店发布的项目仍是客观分发限制，但不再是近期阶段退出条件。阶段 15 转为实现 macOS/Windows 当前用户级安装、可恢复升级、卸载默认保留数据和 CI 安装冒烟验证；详见 `docs/PHASE15_STATUS.md`。
