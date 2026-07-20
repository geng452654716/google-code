# 阶段 19：Vault 正文兼容恢复与安全诊断

- 完成日期：2026-07-20
- 目标：在不覆盖、删除或输出任何 Vault 明文的前提下，继续缩小“主密码正确但 Vault 无法打开”的原因并恢复可兼容数据。
- 数据格式：继续写入 Vault payload schema version 1。

## 结论与边界

对 2026-07-17 的旧 macOS 安装包进行只读核对后，确认旧版与当前版都使用 `google-code:v1:payload` 作为设备 Vault payload 的 AES-GCM AAD；阶段 18 也没有修改 `Account` 或 `VaultPayload` 的磁盘字段。因此不能把当前故障直接归因于新增分组功能。

本阶段不会绕过 AES-GCM 认证。只有候选格式的 MAC 校验成功后才会解析正文；认证失败的密文不会进入 JSON 或领域解析。

## 实现

1. 将原来的笼统 `corruptedPayload` 拆分为：
   - `payloadAuthenticationFailed`：DEK 已解开，但 AES-GCM 正文认证失败。
   - `payloadJsonInvalid`：正文认证成功，但 UTF-8/JSON 对象无效。
   - `payloadSchemaIncompatible`：JSON 已安全解密，但领域结构不兼容。
2. 主文件和 `.bak` 会分别完成上述完整诊断，任一副本可恢复即正常解锁。
3. 在当前 AAD 失败时，尝试少量历史/误用候选 AAD，包括无 AAD、wrapped-DEK AAD、备份正文 AAD 和早期命名候选；仍然必须通过 AES-GCM MAC，不进行未认证解密。
4. schema-v1 兼容解析支持早期可选字段缺失、数字字符串、整数时间戳和旧 `period` 字段。
5. `groups` 缺失时使用空列表；账号引用不存在的分组时只清空 `groupId`，不会删除账号。
6. `id`、`accountName`、`secret` 等账号核心字段保持严格校验；错误只包含字段路径，不包含 Secret、账号名、URI 或正文值。
7. 解锁失败 UI 会明确显示失败位于加密认证、JSON 还是 schema 层，避免继续误判为密码错误。

## 自动化验证

- 当前格式加解密与密文篡改分类。
- 无 AAD 的早期正文通过认证后可恢复。
- 认证成功但非 JSON 的正文独立分类。
- 早期 schema-v1 缺省字段恢复且账号数量不变。
- 无效 `groupId` 回退到未分组。
- schema 错误消息不包含测试 Secret。
- 主文件损坏时继续从 `.bak` 恢复。
- 除真实安装器进程检查外的完整测试集通过 136 项。
- macOS Release 构建成功。

## 用户验证顺序

1. 正常退出旧应用并安装本阶段构建。
2. 使用已经验证正确的主密码解锁。
3. 若成功，第一时间导出新的 `.gcbak`，核对账号数量，再重新启用 Touch ID。
4. 若仍失败，根据新的精确提示继续处理；不得重置、删除或覆盖现有 Vault、`.bak` 和恢复副本。
