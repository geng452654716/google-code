# Phase 25：iCloud、Google Drive 与 GitHub 云备份

日期：2026-07-21

## 阶段目标

在不把 Vault 主密码、TOTP Secret 或设备快速解锁材料交给第三方的前提下，为个人桌面版增加三种手动云备份入口：

- iCloud Drive 同步目录；
- Google Drive 桌面版同步目录；
- GitHub App Device Flow 登录和私有仓库备份。

云端只接收现有备份模块生成的独立密码加密 `.gcbak`。恢复继续复用既有预览、合并、替换和原子保存流程。

## 已完成

### 1. 统一云备份抽象

新增 `CloudBackupProvider` 和 `CloudBackupService`：

- Provider 只处理已经加密的 `.gcbak` 字节；
- 加密仍由现有 `BackupService` 完成；
- 上传完成后清零临时密文缓冲区；
- 下载结果直接进入既有恢复预览，不允许 Provider 直接修改 Vault。

### 2. iCloud Drive 与 Google Drive

当前个人自签名版本采用用户选择同步目录的方式：

- 每次由用户明确选择 iCloud Drive 或 Google Drive 桌面版中的目录；
- 写入 `TOTP-Vault-latest.gcbak`；
- 同时保留带 UTC 时间戳的版本文件；
- 默认只保留最近 30 个时间版本；
- 通过临时文件和重命名完成替换；
- 应用不接触 Apple ID 或 Google 密码。

此方式不依赖 Apple iCloud Container provisioning，也不要求应用内 Google OAuth。系统或桌面云盘客户端负责账号登录与同步。

### 3. GitHub 自定义账号登录

GitHub 不再依赖本机 Git 命令或系统 Git 凭据，改为 GitHub App Device Flow：

1. 应用请求一次性授权码；
2. 打开 GitHub 官方授权页面；
3. 用户可登录任意 GitHub 账号并输入授权码；
4. 应用只列出该 GitHub App installation 可访问、且具有 Contents 写入权限的私有仓库；
5. 用户选择专用私有仓库；
6. 加密备份写入 `totp-vault-backup/latest.gcbak`。

GitHub user access token 和 refresh token：

- macOS：保存在 Keychain，`WhenUnlockedThisDeviceOnly`；
- Windows：保存在 Credential Manager，`CRED_PERSIST_LOCAL_MACHINE`；
- 不写入 Vault、`.gcbak`、日志或仓库；
- 断开 GitHub 时删除当前设备保存的 session；
- 授权过期或 API 返回未授权时删除 session 并要求重新连接。

### 4. macOS 与 Windows 平台支持

macOS：

- 用户选择目录 entitlement 从只读改为读写；
- 增加网络客户端 entitlement；
- 保留原有固定 32 字节 Touch ID 快速解锁 Keychain 逻辑；
- 新增独立的 cloud secret Keychain service。

Windows：

- 保留原有固定 32 字节 Windows Hello 快速解锁 Credential；
- 新增独立的 cloud secret credential target；
- Secret 限制为 1～4096 bytes；
- Credential Manager 返回的内存和写入临时缓冲区会被清零。

### 5. 构建配置

GitHub Client ID 通过编译参数注入：

```bash
--dart-define=TOTP_VAULT_GITHUB_CLIENT_ID=Ivxxxxxxxxxxxxxxxxxx
```

本地 macOS / Windows 打包脚本会读取环境变量：

```bash
export TOTP_VAULT_GITHUB_CLIENT_ID=Ivxxxxxxxxxxxxxxxxxx
```

GitHub Actions `Personal Install Readiness` 会读取 Repository Variable：

```text
TOTP_VAULT_GITHUB_CLIENT_ID
```

Client ID 可公开出现在桌面客户端中，不属于私钥；不得提交 Client Secret、GitHub App private key 或真实 Token。

未配置 Client ID 的安装包仍可使用 iCloud Drive 和 Google Drive，GitHub 卡片会明确显示“当前安装包未配置 GitHub App Client ID”。

### 6. GitHub App 与专用备份仓库

已完成个人实测资源配置：

- GitHub App：`TOTP Vault Backup - gengyujian`；
- App slug：`totp-vault-backup-gengyujian`；
- App ID：`4352078`；
- 安装账号：`geng452654716`；
- Installation ID：`147957358`；
- 专用私有仓库：`geng452654716/totp-vault-backup`；
- Repository access：`Only select repositories`；
- 当前只选择 1 个仓库：`totp-vault-backup`；
- 权限核对：Metadata 只读、Contents/Code 读写。

GitHub 设置页已显示 installation 更新成功。专用仓库为空，不存放应用源码；后续真机测试只允许上传独立密码加密的 `.gcbak`。

## GitHub App 配置步骤

1. 在 GitHub 账号设置中进入 `Developer settings > GitHub Apps`。
2. 创建个人使用的 GitHub App，例如 `TOTP Vault Backup - <账号名>`。
3. 关闭 Webhook。
4. 开启 Device Flow。
5. Repository permissions 仅配置：
   - Metadata：Read-only；
   - Contents：Read and write。
6. Account permissions 不配置。
7. Installation 范围选择 `Any account`，允许用户登录并授权自己选择的个人或组织账号。
8. 创建一个不放其他代码的私有备份仓库。
9. 安装 GitHub App 时选择 `Only select repositories`，只勾选该私有仓库。
10. 将 GitHub App 的 Client ID 配置到本地构建环境和 GitHub Actions Repository Variable。

Device Flow 不使用 Client Secret；本项目也不需要 GitHub App private key。

## 安全边界

- 云服务只能看到加密 `.gcbak` 和不含账号信息的固定提交说明。
- 手动 `.gcbak` 备份不保存备份密码；阶段 26 的可选 GitHub 自动备份会在用户明确开启后，把独立备份密码仅保存到当前设备的系统安全存储。
- 第三方账号 Token 不进入跨设备备份。
- 新设备恢复后需要设置当前设备的主密码，并重新启用 Touch ID 或 Windows Hello。
- GitHub 仓库必须为私有仓库；公开仓库不会出现在可选列表中。
- iCloud / Google Drive 首版是手动同步目录，不是应用内账号 OAuth。

## 自动化验证

新增测试覆盖：

- 同步目录版本文件、latest 文件、版本清理、最新下载、取消和空目录；
- GitHub Device Code、pending、slow_down、取消、Token 安全存储、仓库过滤、上传、更新 sha、下载、刷新和未授权清理；
- 云备份 UI 的三种 Provider、未配置状态、授权码显示和私有仓库选择；
- macOS / Windows 原生 cloud secret 实现与快速解锁逻辑共存；
- macOS 目录读写和网络客户端 entitlement。

## 尚需外部配置和真机验收

- GitHub App `TOTP Vault Backup - gengyujian` 已创建，已开启 Device Flow、允许 `Any account` 安装，并已将 Client ID 配置到 GitHub Actions Repository Variable；
- GitHub App 已安装到 `geng452654716`，并仅授权私有仓库 `geng452654716/totp-vault-backup`；
- 已使用 Client ID 生成 macOS DMG 和 Windows Setup EXE，并完成 CI 安装、升级和卸载 smoke test；
- 尚需 macOS 真机验证 GitHub Device Flow 登录、上传、下载、恢复和断开；
- Windows 10/11 真机验证 Credential Manager、GitHub 登录和恢复；
- Windows 真机验收结果不能由 CI 编译替代。
