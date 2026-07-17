# 阶段 1 / 本地 Vault 核心闭环状态

- 更新时间：2026-07-16
- 当前结论：主密码、本地加密 Vault、账号 CRUD、真实 TOTP 列表、搜索、复制和会话锁已经形成可运行闭环。后续已完成本地单二维码图片导入，详见 [阶段 2 状态](./PHASE2_STATUS.md)；剪贴板导入已在 [阶段 3](./PHASE3_STATUS.md) 完成；macOS 区域截图已在 [阶段 4](./PHASE4_STATUS.md) 完成；Windows 自有区域选择器已在 [阶段 5](./PHASE5_STATUS.md) 实现，仍待 Windows 环境编译和实测；Google Authenticator 多账号迁移导入已在 [阶段 6](./PHASE6_STATUS.md) 完成。

## 本阶段已完成

### 数据与安全

- [x] 建立 `Account`、`AccountDraft` 与版本化 `VaultPayload` schema。
- [x] 建立 `VaultRepository` 边界和设备本地文件实现。
- [x] 首次创建 Vault 时生成随机 256-bit DEK，并使用 Argon2id + AES-256-GCM 信封加密。
- [x] 保存账号时保留已包装的 DEK，仅使用新 nonce 重新加密 Payload。
- [x] 锁定时释放 repository 与应用状态中的已解密 Payload 引用，不保存主密码。
- [x] Vault 文件写入继续使用临时文件、flush 和 `.bak` 恢复策略。

### 应用流程

- [x] 首次启动主密码创建页，最低长度 8 个字符并要求二次确认。
- [x] 已有 Vault 的主密码解锁页与错误提示。
- [x] 手动锁定、后台超时锁定和无交互自动锁定。
- [x] 鼠标、滚轮和键盘活动重置无交互计时器。
- [x] 锁定后整个账号与验证码界面被替换，不继续展示敏感内容。

### 账号与验证码

- [x] 手动输入 Base32 Secret 添加账号。
- [x] 粘贴 `otpauth://totp` 链接并预填账号参数。
- [x] 编辑和永久删除账号。
- [x] 对 issuer、账号名和 Secret 的重复组合进行拦截。
- [x] 在解锁内存中搜索并排序账号。
- [x] 使用真实 Vault 账号生成动态 TOTP、倒计时并自动刷新。
- [x] 一键复制验证码，并在 60 秒后尽力清理未被覆盖的剪贴板内容。

## 当前验证结果

| 检查项 | 结果 |
| --- | --- |
| `fvm flutter analyze` | 通过，0 issues |
| `fvm flutter test` | 通过，23 tests |
| `fvm flutter build macos --debug` | 通过 |
| `fvm flutter build macos --release` | 通过，43.7 MB |
| Windows 构建 | 待 Windows 真机或 CI 验证 |

自动化测试已覆盖 Base32、RFC 6238 TOTP、`otpauth://`、QR 编解码、Vault 加密与篡改检测、备份恢复、Payload schema、repository 持久化、错误密码、锁定保存保护、状态控制器 CRUD/搜索/锁定以及首次启动页面。

macOS Release 构建出现 `objective_c` code asset 在不同架构使用不同 framework 名称的上游警告，但构建和打包成功。后续升级相关依赖时需要重新验证该警告。

## 尚未完成的 P0 工作

- [x] 从本地二维码图片识别并进入导入确认流程（阶段 2 已完成）。
- [x] 读取剪贴板二维码图片并识别（阶段 3 已完成）。
- [x] 调用 macOS 区域截图并识别二维码（阶段 4 已完成）；Windows 区域截图代码已在阶段 5 完成，仍待平台验证。
- [x] 将本地单二维码识别结果与手动/URI 输入统一到同一导入确认和重复处理流程（阶段 2 已完成）。
- [x] macOS 截屏权限引导（阶段 4 已完成）；Windows 自有区域截图已在阶段 5 实现，平台验证仍待完成。
- [ ] Windows Debug/Release 构建与基础功能实测。
- [ ] macOS 签名、sandbox entitlement 和公证前置验证。

## 后续阶段

本地单二维码图片导入已在阶段 2 完成，当前实现和验证结果见 [阶段 2 状态](./PHASE2_STATUS.md)。剪贴板图片/文本与快捷键粘贴已在 [阶段 3](./PHASE3_STATUS.md) 完成，macOS 区域截图已在 [阶段 4](./PHASE4_STATUS.md) 完成。Windows 自有区域截图已在 [阶段 5](./PHASE5_STATUS.md) 实现，Google Authenticator 单码多账号与多张迁移二维码导入已在 [阶段 6](./PHASE6_STATUS.md) 完成。下一步完成 Windows 真机验证，并继续同一图片中多个独立二维码的识别。

摄像头、安全分享、生物识别、备份恢复 UI、分组和置顶继续保留到后续阶段。
