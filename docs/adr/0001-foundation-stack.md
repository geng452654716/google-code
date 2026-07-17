# ADR-0001：桌面端基础技术栈与安全核心

- 状态：已接受
- 日期：2026-07-16

## 背景

Google Code 是仅供个人使用、默认离线的桌面 TOTP 工具。核心风险集中在本地 Secret 的存储、动态验证码正确性、二维码导入链路以及 macOS/Windows 平台能力差异。

## 决策

1. 客户端使用 Flutter Desktop，首发目标为 macOS 与 Windows。
2. SDK 固定为 Flutter 3.44.0 / Dart 3.12.0，使用 FVM 2.x 的 `.fvm/fvm_config.json` 固定版本。
3. TOTP 不引入完整 OTP SDK，基于 `cryptography 2.9.0` 实现 HMAC-SHA1/SHA256/SHA512，并以 RFC 6238 测试向量验证。
4. 数据使用单一版本化 Vault 文件：Argon2id 派生 KEK，随机 256-bit DEK，AES-256-GCM 分别包装 DEK 和加密载荷。
5. Vault 文件采用临时文件写入、flush、保留 `.bak` 的恢复策略。平台专项验证阶段继续评估更严格的原子替换实现。
6. 标准二维码使用 `qr 4.0.0` 生成，使用 `image 4.9.1` 处理像素，使用 `zxing2 0.2.4` 解码。
7. 剪贴板、区域截图、安全存储、生物识别和摄像头必须位于 `lib/platform` 接口之后，业务层不得直接引用具体平台插件。
8. 应用不请求网络能力，不依赖后端，不记录 Secret、URI、验证码或二维码内容。
9. 直接依赖在 `pubspec.yaml` 中使用精确版本，完整传递依赖由 `pubspec.lock` 固定。

## 影响

- 安全核心较小，便于审计和测试，但需要自行维护 URI 边界行为和 Vault schema 迁移。
- 单文件 Vault 不支持密文内查询，解锁后必须在内存中完成搜索、分组和排序。
- Windows 构建和平台插件必须在 Windows 真机/CI 上验证，不能以 macOS 构建结果替代。
- `cryptography` 的纯 Dart Argon2id 性能必须在目标设备继续采样，必要时只调整新 Vault 的参数，不降低既有 Vault 的兼容性。
