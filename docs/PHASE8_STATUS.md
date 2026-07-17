# 阶段 8 / 加密备份与恢复状态

- 更新时间：2026-07-16
- 当前结论：已完成独立 `.gcbak` 加密备份导出、恢复预览、合并与替换闭环；备份密码和解密 payload 只在当前操作内存中短暂存在，恢复校验或持久化失败不会修改当前 Vault。

## 本阶段已完成

### 独立加密备份格式

- [x] 定义 `google-code-backup` 独立 format 和 formatVersion 1，不复制设备 `vault.gcvault`。
- [x] 每次导出生成新的 salt、Argon2id 派生 KEK、随机 DEK 和 AES-256-GCM nonce。
- [x] 包装 DEK 与 payload 使用备份专用且互不相同的 AAD，不与设备 Vault envelope 混淆。
- [x] 备份包含账号、TOTP 参数、分组、排序、置顶、偏好、schema 版本和时间戳。
- [x] Secret、issuer 和账号名不会以明文出现在 `.gcbak` 文件中。
- [x] 不提供 CSV/JSON 明文导出，不包含设备快速解锁材料。

### 导出流程

- [x] 账号页左侧增加“备份与恢复”入口。
- [x] 用户设置并确认独立备份密码，执行至少 8 个字符的本地校验。
- [x] 通过系统保存对话框选择 `.gcbak` 位置，直接写入加密字节，不创建明文临时文件。
- [x] 成功后显示用户选择的保存位置；取消或失败不会创建应用内副本。
- [x] 密码在完成加密后立即从输入框清除，Vault 锁定时关闭导出路由。

### 恢复校验与预览

- [x] 系统文件对话框只选择 `.gcbak`，并在读取前限制最大 32 MiB。
- [x] 校验 format、版本、KDF 参数、salt、nonce、MAC 和 ciphertext 结构。
- [x] 错误密码、篡改、损坏文件、非备份文件和未来版本均返回安全错误。
- [x] 认证解密后通过 `VaultPayload.fromJson` 校验当前 schemaVersion。
- [x] 预览只展示账号、分组、可新增、完全重复、同名冲突数量和备份时间。
- [x] 备份密码在预览生成后清空；失焦、后台、关闭或 Vault 锁定时释放临时解密 payload。

### 合并与替换

- [x] 合并模式跳过 issuer、accountName、Secret 完全相同的账号。
- [x] 同 issuer/accountName 但 Secret 不同的账号计为冲突并保留为新账号。
- [x] 导入账号追加到当前排序，保留置顶状态，并处理账号 ID 与分组 ID 冲突。
- [x] 合并时当前设备偏好优先；替换时完整采用备份账号、分组和偏好。
- [x] 替换模式执行前二次确认并明确建议先导出当前 Vault。
- [x] 最终候选 payload 只通过 `VaultSessionController` 和当前设备 Vault DEK 单次保存。
- [x] repository 保存成功前不替换会话状态；失败时当前 Vault 保持不变。
- [x] `VaultFileStore` 的现有 `.bak` 原子恢复机制继续保护替换前数据。

## 当前验证结果

| 检查项 | 结果 |
| --- | --- |
| `fvm dart format lib test tool` | 通过，83 files，0 changed |
| `fvm flutter analyze` | 通过，0 issues |
| `fvm flutter test` | 通过，77 tests |
| Windows 原生构建与运行 | 仍待 Windows 环境验证 |
| macOS/Windows `.gcbak` 文件对话框人工验收 | 待目标平台人工验证 |

自动化测试覆盖正确密码往返、备份密文不含账号明文、错误密码、密文篡改、非备份格式、未来版本、32 MiB 限制、预览统计、完全重复跳过、同名冲突保留、分组 ID 冲突、完整替换、恢复保存失败不修改当前状态、导出密码清理、替换二次确认和 Vault 锁定关闭恢复路由。

## 当前限制与风险

- [ ] 只接受 `VaultPayload.currentSchemaVersion`；未来 schema 上线前需增加显式 migration 管线和旧版本 fixtures。
- [ ] 文件保存与选择对话框需在 macOS sandbox、Windows 10 和 Windows 11 真机验证路径、扩展名和覆盖提示行为。
- [ ] 当前冲突策略以“保留同名不同 Secret 账号”为默认，不提供逐账号勾选、改名或覆盖选项。
- [ ] 恢复预览只展示聚合数量，不展示账号清单；这是首版减少敏感暴露的安全取舍。
- [ ] Dart 垃圾回收无法保证解密字符串立即物理清零，当前通过短生命周期、无日志、无缓存和无明文临时文件降低风险。

## 下一阶段建议

1. [已由阶段 9 完成] 接入 macOS Keychain / Windows Credential Manager 与 Touch ID / Windows Hello，完成快速解锁和敏感操作重新认证；见 `docs/PHASE9_STATUS.md`。
2. 完成自动锁定策略、系统锁屏事件和睡眠/唤醒行为。
3. 在 macOS sandbox 与 Windows 真机验收 `.gcbak` 导入导出、覆盖、权限和异常恢复。
4. 使用真实 Google Authenticator 导出样本继续完成阶段 6 兼容性回归。
