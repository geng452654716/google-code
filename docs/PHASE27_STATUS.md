# Phase 27：公开仓库与 GitHub Release 自动发布

日期：2026-07-21

## 阶段目标

在保留个人使用定位和未可信签名安全提示的前提下，公开源码仓库，并把原有短期 GitHub Actions Artifact 打包流程升级为可直接下载的 GitHub Release。

## 已完成

### 1. Release 工作流

- 将 `.github/workflows/release-readiness.yml` 替换为 `.github/workflows/release.yml`；
- 工作流名称改为 `Build GitHub Release`；
- 支持推送 `v*` tag 和从 `main` 手动触发；
- 手动触发未填写 tag 时，自动读取 `pubspec.yaml` 并生成 `v<version>`；
- tag 必须严格匹配 `pubspec.yaml` 的 `x.y.z+build` 版本；
- 默认权限为 `contents: read`，只有最终发布 Job 使用 `contents: write`；
- macOS、Windows 和 metadata Job 使用临时 Artifact 传递产物，最终 Job 验证 SHA-256 后才允许发布；
- 同名 Release 已存在时直接失败，避免覆盖现有发布资产。

### 2. Release 资产

当前 `1.0.3+4` 版本计划发布：

```text
TOTPVault-1.0.3-build4-macos-universal.dmg
TOTPVault-1.0.3-build4-macos-universal.dmg.sha256
TOTPVault-1.0.3-build4-windows-x64-setup.exe
TOTPVault-1.0.3-build4-windows-x64-setup.exe.sha256
TOTPVault-1.0.3-build4-release-metadata.zip
TOTPVault-1.0.3-build4-release-metadata.zip.sha256
```

Actions Summary 会输出 Release 页面和所有 asset 下载链接。

### 3. 发布前验证

- 依赖来源和许可证 metadata 生成；
- macOS Release 构建、用户目录首次安装、重复升级、卸载、DMG 挂载和代码签名完整性检查；
- Windows Release 构建、用户目录首次安装、重复升级、卸载、Setup EXE 静默安装和外部 Vault fixture 保留检查；
- 最终发布前执行 3 组 `sha256sum --check`；
- Release 工作流关键权限、固定 Action SHA、资产和 README 下载入口由静态测试覆盖。

### 4. README 与文档

- 增加 Desktop CI 和 Build GitHub Release badges；
- 增加 Latest Release 下载入口、资产说明、安装步骤、功能、安全模型、云备份和项目状态；
- 明确 macOS 使用 ad hoc 签名、Windows 未使用 Authenticode；
- 明确 Windows 10/11 真机完整验收仍未完成；
- 明确仓库当前尚未声明开源许可证；
- 更新 PRD、技术设计和 Phase 25 中已经变化的发布决策及工作流名称。

## 公开仓库安全检查

公开前检查当前 Git 历史中是否包含：

- GitHub Token 和 GitHub fine-grained token；
- PEM 私钥；
- AWS Access Key；
- Google API Key；
- Client Secret 或 GitHub App private key；
- `.gcvault`、`.gcbak`、`.env`、证书、数据库和 provisioning profile。

扫描只记录命中的 commit/path，不输出疑似 Secret 内容。本地 `.local-recovery/` 已被忽略，不提交、不删除。

## 发布边界

- GitHub Release 只是个人安装包下载渠道；
- macOS 包没有 Apple Developer ID 和公证；
- Windows 包没有 Authenticode；
- 不绕过 Gatekeeper 或 SmartScreen；
- 不提供应用商店和自动更新；
- CI 成功不能替代 Windows 10/11 真机对摄像头、Windows Hello、截图、分享、高 DPI、中文路径和锁屏/睡眠恢复的验收。

## 验证记录

完成本阶段时需要记录：

- 本地格式、静态分析、全量测试和 `git diff --check` 结果；
- GitHub 仓库 Public 可见性验证；
- 首次 Release tag、Actions run ID、Release 页面和资产数量；
- DMG、Setup EXE 和 metadata 的下载链接。
