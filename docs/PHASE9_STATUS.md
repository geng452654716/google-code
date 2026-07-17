# 阶段 9 / 设备快速解锁与本机认证状态

- 更新时间：2026-07-16
- 当前结论：已完成 macOS Keychain、Windows Credential Manager、Touch ID / Windows Hello 设备认证、Vault 快速解锁、安全设置和分享前设备重新认证闭环。主密码包装与主密码重新认证始终保留，快速解锁材料不会进入 `.gcbak`。macOS Debug 构建已通过；Windows 原生实现已完成静态审查，仍需 Windows 10/11 真机编译与运行验收。

## 本阶段已完成

### 快速解锁安全边界

- [x] 系统安全存储只保存当前 Vault 的 32 字节数据加密密钥 DEK 副本，不保存主密码。
- [x] 不修改现有 Vault envelope；主密码包装后的 DEK 始终保留，主密码仍是恢复根凭据。
- [x] `.gcbak` 继续只包含独立备份 envelope，不包含 Keychain、Credential Manager 或其他设备快速解锁材料。
- [x] `VaultRepository` 增加已解锁 DEK 导出与使用 DEK 解锁接口，错误 DEK 必须经过现有 AES-GCM payload 认证校验。
- [x] 只接受 32 字节 DEK；Dart 和原生层在可控生命周期结束时尝试覆盖临时密钥字节。
- [x] 不记录、不上传 Secret、二维码、`otpauth://`、主密码、备份密码或快速解锁 DEK。

### 设备认证与应用服务

- [x] 接入 `local_auth` 3.0.2；锁定解析版本为 `local_auth_darwin` 2.0.3、`local_auth_windows` 2.0.1。
- [x] UI 根据平台显示“Touch ID 或设备密码”“Windows Hello”或通用“设备认证”。
- [x] 启用快速解锁前先重新验证主密码，再执行设备认证；错误主密码不会触发设备认证。
- [x] 用户取消设备认证时不写入新材料，也不删除已有有效材料。
- [x] 快速解锁成功后使用设备安全存储中的 DEK 认证解密当前 Vault。
- [x] 快速解锁材料缺失时安全回退主密码；材料损坏、长度非法或与当前 Vault 不匹配时删除材料并提示重新启用。
- [x] 禁用快速解锁只删除当前设备材料，不锁定、重写或删除 Vault。
- [x] 分享 Secret、URI 或二维码前可使用设备认证重新验证；主密码重新认证始终保留为回退。

### 桌面 UI

- [x] 解锁页启动时检查设备认证与快速解锁状态，并在已配置时显示平台对应的快速解锁按钮。
- [x] 认证取消不显示错误；认证失败、不可用和失效材料均提供安全且不泄露底层信息的文案。
- [x] 账号页增加“安全设置”入口。
- [x] 安全设置展示设备认证可用性和快速解锁启用状态。
- [x] 启用流程要求输入主密码；成功后刷新为已启用状态，禁用后恢复为未启用状态。
- [x] 安全设置明确说明主密码恢复边界和 `.gcbak` 不包含快速解锁材料。
- [x] 阶段 7 的 60 秒隐藏、失焦隐藏、锁定关闭和敏感剪贴板清理逻辑保持不变。

### macOS 原生实现

- [x] 通过 `google_code/secure_key_store` MethodChannel 暴露 `contains`、`read`、`write` 和 `delete`。
- [x] 使用 Security.framework Keychain，service 为 `com.gengyujian.google-code.quick-unlock`，account 为 `vault-dek-v1`。
- [x] 使用 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，避免材料迁移到其他设备。
- [x] macOS Debug 应用已完成原生编译。

### Windows 原生实现

- [x] 使用 `CredWriteW`、`CredReadW` 和 `CredDeleteW` 访问 Windows Credential Manager。
- [x] Credential target 为 `com.gengyujian.google-code.quick-unlock.v1`，类型为 `CRED_TYPE_GENERIC`，持久化为 `CRED_PERSIST_LOCAL_MACHINE`。
- [x] runner 已链接 `advapi32.lib` 并注册统一 MethodChannel。
- [x] 使用 RAII 包装 `CredReadW` 返回值，在 `CredFree` 前对 CredentialBlob 调用 `SecureZeroMemory`。
- [x] `std::vector<uint8_t>` 与 Flutter Windows `EncodableValue` 的 typed-data 分支保持一致，写入前校验固定 32 字节。
- [x] `CredReadW` 的 `GetLastError()` 在失败后立即捕获，明确区分缺失、非法长度和系统读取失败，避免使用过期错误码。
- [x] 原生 `invalid_key` 映射为 Dart `FormatException`，由快速解锁服务删除损坏材料并回退主密码。
- [ ] Windows 原生实现尚未在当前 macOS 环境编译；必须在 Windows 10/11 真机完成构建、Credential Manager 读写和 Windows Hello 运行验收。

## 当前验证结果

| 检查项 | 结果 |
| --- | --- |
| `fvm dart format lib test tool` | 通过，92 files，0 changed |
| `fvm flutter analyze` | 通过，0 issues |
| `fvm flutter test` | 通过，90 tests |
| `fvm flutter build macos --debug` | 通过，生成 `build/macos/Build/Products/Debug/google_code.app` |
| Windows 原生构建与运行 | 当前环境不可执行；已完成静态审查，待 Windows 10/11 真机验证 |

自动化测试覆盖主密码前置验证、设备认证取消、DEK 写入与临时引用清理、快速解锁往返、错误 DEK、失效材料删除、敏感操作重新认证、禁用、安全设置启用/禁用 UI、解锁页设备认证入口、分享设备认证成功与取消回退，以及原生非法凭据错误到 Dart 可清理错误的映射。

## 当前限制与风险

- [ ] Windows Credential Manager 与 Windows Hello 只能静态审查，尚未完成 MSVC 编译和 Windows 10/11 真机运行。
- [ ] macOS 当前完成 Debug 编译，仍需在目标签名、Sandbox、不同 Touch ID/设备密码状态下人工验收 Keychain 行为。
- [ ] `local_auth` 的认证界面和可用回退由操作系统决定；Windows Hello 可能通过 PIN 完成，不能将其统一描述为指纹。
- [ ] 系统安全存储降低离线文件被复制后的风险，但不抵御已经完全控制当前用户会话或已解锁进程的恶意软件。
- [ ] Dart 垃圾回收无法保证对象立即物理清零；当前通过短生命周期、显式覆盖字节数组、无日志和不进入备份降低风险。
- [x] 系统锁屏、会话断开和睡眠事件已由阶段 10 接入立即自动锁定；见 `docs/PHASE10_STATUS.md`。

## 下一阶段建议

1. 在 Windows 10/11 真机完成 MSVC 构建、Credential Manager 创建/覆盖/读取/删除、Windows Hello 成功/取消/PIN 回退和损坏凭据回归。
2. [已由阶段 10 完成] 接入 macOS NSWorkspace 会话/休眠通知与 Windows WTS session change/电源事件；见 `docs/PHASE10_STATUS.md`。
3. 在 macOS Sandbox、签名环境和 Windows 真机验收 `.gcbak` 文件对话框、二维码保存、截图与安全存储权限行为。
4. 使用真实 Google Authenticator 导出样本继续完成阶段 6 兼容性回归。
5. 评估 macOS NSSharingServicePicker 与 Windows DataTransferManager，增加系统分享面板并保留复制/保存降级路径。
