# Vault 恢复与快速解锁保护修复

- 完成日期：2026-07-20
- 类型：阶段 18 后的紧急数据恢复修复
- 数据格式：保持 Vault schema version 1，不迁移、不重置用户数据

## 问题

旧实现只在主 Vault envelope 无法解析时读取 `.bak`。如果主文件 JSON 结构合法，但 AES-GCM payload 损坏，主密码和设备快速解锁都会直接失败，不会尝试自动备份。

快速解锁服务还会在任意 `VaultUnlockException` 后自动删除 Keychain/Credential Manager DEK。该异常既可能表示 DEK 已过期，也可能表示主文件 payload 损坏，因此自动删除可能永久移除唯一不依赖主密码的恢复凭据。

## 修复

1. 主密码和设备 DEK 解锁都依次验证主文件与 `.bak`。
2. 区分 wrapped DEK 认证失败、payload 损坏和 envelope 不可读三类安全错误。
3. 快速解锁失败不再自动删除设备 DEK；仅允许用户显式禁用时删除。
4. 从 `.bak` 打开的会话在首次保存时直接修复主文件，并保留原有良好 `.bak`。
5. 不输出主密码、DEK、明文 payload、TOTP Secret、URI 或账号信息。

## 当前用户数据保护

在修改和安装前，已对现有 `vault.gcvault` 与 `vault.gcvault.bak` 创建同目录加密恢复副本，并通过 SHA-256 确认副本与原文件逐字节一致。恢复副本不进入 Git 仓库。

外层 envelope 检查确认两份文件均为结构合法的 v1 Vault，并使用相同 salt 与 wrapped DEK。此结果排除了明显截断或被新 Vault 覆盖，但在没有正确主密码或设备 DEK 时，无法从密码学上绝对区分“密码错误”和“wrapped DEK 损坏”。

## 自动化覆盖

- 密码错误与 payload 篡改的错误分类。
- 主 payload 损坏时从 `.bak` 解锁。
- recovery 会话首次保存不覆盖良好 `.bak`。
- 两份 envelope 均不可读时返回恢复错误。
- 快速解锁 DEK 无法打开 Vault 时不会自动删除设备材料。

## 本机安装修复

本次 Flutter Release 构建出现 `App.framework` 自身签名有效、但顶层 app bundle 的嵌套代码封印不同步。安装器会拒绝此类产物并完整回滚。现在无稳定签名 identity 时，会对 transaction staging 副本执行标准 ad hoc 深度签名，再运行 `codesign --verify --deep --strict`；不会移除 quarantine，也不会绕过 Gatekeeper。
