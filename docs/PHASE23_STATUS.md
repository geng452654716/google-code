# 阶段 23：快速解锁保存损坏修复

日期：2026-07-20

## 问题现象

用户通过 Touch ID / 设备凭据快速解锁后，可以正常查看已有账号；但只要新增、编辑、移动或删除数据并重新启动应用，主密码和快速解锁都无法打开最新 Vault。连续保存后，主文件与自动备份都会出现正文认证失败。

## 根因

`QuickUnlockService` 从 Keychain 读取临时 DEK 缓冲区，完成解锁后会主动将该缓冲区清零。`cryptography` 2.9.0 的 `SecretKey(List<int>)` 默认保留传入 List 的引用，而不是复制字节。

旧实现直接使用临时缓冲区构造活动 `SecretKey`，导致清理临时缓冲区时，当前解锁会话持有的 DEK 也被清零。后续保存会使用全零 AES-256 密钥重新认证 Vault 正文，但 `wrappedDek` 仍然保存由主密码包装的原 DEK，因此应用重启后：

- 主密码可以正确解开原 DEK，但原 DEK无法认证被全零密钥写入的正文；
- Keychain 中的快速解锁 DEK仍是原 DEK，同样无法认证正文；
- 第一次错误保存后 `.bak` 仍可能有效，连续两次保存会让主文件和 `.bak` 都进入错误状态。

安装、签名和 Bundle ID 不会改变 Vault；重新打包只是触发应用重启，使已经写入磁盘的密钥失配暴露出来。

## 修复

1. `openWithDataEncryptionKey` 使用 `Uint8List.fromList` 创建由活动会话独占的 DEK 副本，之后清零 Keychain 临时缓冲区不会再影响会话密钥。
2. 主密码成功解开 `wrappedDek` 后，如果正常 DEK无法认证正文，会兼容检测历史全零 DEK故障格式。
3. 兼容恢复成功后，立即用主密码验证得到的原 DEK原子重写主 Vault，并保留原 `.bak`，避免恢复过程覆盖唯一备份。
4. 全零 DEK兼容恢复只允许出现在主密码路径；快速解锁路径不会使用该回退，避免陈旧设备密钥绕过 Vault 归属验证。
5. 新增回归测试覆盖：
   - 快速解锁临时缓冲区清零后连续保存；
   - 重启后主密码和原设备密钥仍能打开最新数据；
   - 历史全零 DEK正文只能由正确主密码触发恢复；
   - 恢复后的主文件重新使用原 DEK，可再次正常解锁。

## 数据保护

- 调查前已只读复制当前 `vault.gcvault` 与 `vault.gcvault.bak` 到本地忽略目录 `.local-recovery/20260720-170552/`。
- 未读取或输出主密码、TOTP Secret、二维码内容、Keychain 密钥值或 Vault 解密正文。
- 未删除或重置 Vault、Keychain、`.gcbak`、TCC 或系统隐私权限。
- 修复版本安装前必须再次校验当前 Vault 哈希；安装后首次恢复必须由用户输入正确主密码触发。

## 修复版本

- 应用版本：`1.0.1+2`
- macOS 包名：`TOTPVault-1.0.1-build2-macos-universal.dmg`

## 验证结果

- 定向 Vault 加密与仓库测试：26 项通过；
- `flutter analyze --no-pub`：无问题；
- 完整 Flutter 测试：148 项通过；
- macOS Release 构建成功，使用项目锁定的 FVM Flutter SDK；
- 修复版已使用稳定本地签名 `TOTP Vault Local Signing` 安装：
  - `CFBundleIdentifier=com.gengyujian.googleCode`
  - `CFBundleShortVersionString=1.0.1`
  - `CFBundleVersion=2`
- 安装前后主 Vault 与 `.bak` 的 SHA-256 完全一致，证明覆盖安装未改写用户数据；
- 用户使用正确主密码成功打开原数据，主 Vault 随即自动重写为原始 DEK 格式；
- 自动恢复过程中 `.bak` 的修改时间与 SHA-256 保持不变；
- 用户随后已确认 Touch ID 快速解锁恢复正常。

修复版 DMG：

```text
dist/macos/TOTPVault-1.0.1-build2-macos-universal.dmg
SHA-256: 5dda8b02b08387e7e17ade5738a66f978d5787c4f7afa30059b3167af9b69a35
```
