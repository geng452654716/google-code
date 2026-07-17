# 阶段 0 / 基础核心开发状态

- 更新时间：2026-07-16
- 当前结论：基础工程、macOS 构建链路和核心算法 PoC 可运行；剪贴板和区域截图能力已在后续阶段实现，阶段 0 剩余项主要是 Windows 真机、系统安全存储、生物识别和发布链路验证。

## 已完成

- [x] 初始化 Flutter Desktop 工程（macOS、Windows）。
- [x] 使用 FVM 固定 Flutter 3.44.0 / Dart 3.12.0。
- [x] 直接依赖精确版本及 `pubspec.lock`。
- [x] macOS Debug 构建。
- [x] macOS Release 构建，产物约 42.1 MB。
- [x] TOTP 引擎：SHA-1、SHA-256、SHA-512，6/8 位及自定义周期。
- [x] RFC 6238 三组算法测试向量。
- [x] Base32 标准化、编码和解码。
- [x] `otpauth://totp` 解析与生成，包含默认值、百分号编码、issuer 冲突和 HOTP 拒绝测试。
- [x] Vault 加密 PoC：Argon2id、随机 DEK、AES-256-GCM、错误密码和篡改检测。
- [x] Vault 文件临时写入及 `.bak` 恢复测试。
- [x] QR PNG 生成后由 ZXing 解码回原始 `otpauth://` URI。
- [x] 初始桌面应用壳、动态验证码和倒计时预览。
- [x] ADR-0001，记录基础栈和安全决策。

## 当前验证结果

| 检查项 | 结果 |
| --- | --- |
| `fvm flutter analyze` | 通过，0 issues |
| `fvm flutter test` | 通过，15 tests |
| `fvm flutter build macos --debug` | 通过 |
| `fvm flutter build macos --release` | 通过 |
| Vault 创建基准 | 110 ms |
| Vault 解锁基准 | 64 ms |

基准使用生产 KDF 参数（Argon2id，19 MiB、2 iterations、parallelism 1），结果只代表当前开发机单次采样，不作为所有目标设备的性能保证。

## 尚未完成的阶段 0 项目

- [ ] Windows 真机/CI Release 构建。
- [x] 剪贴板图片读取与 QR 解码 PoC 已在阶段 3 实现；Windows 原生位图读取仍待真机验证。
- [x] macOS 区域截图与权限流程已在阶段 4 验证，Windows 自有区域选择器已在阶段 5 实现并待真机验证。
- [ ] Keychain、Windows Credential/安全存储适配验证。
- [ ] `local_auth` 的 Touch ID / Windows Hello 验证。
- [ ] macOS 最低版本 12 和 Windows 10 19041 的真机确认。
- [ ] Release 签名、macOS sandbox entitlement 和公证前置验证。

## 已提前进入的阶段 1 内容

虽然阶段 0 的平台能力尚未验证完，低平台耦合的本地 Vault 核心闭环已经完成。最新实现和验证结果见 `docs/PHASE1_STATUS.md`。

## 下一步建议

1. 在 Windows 真机或 CI 上验证 Debug/Release 构建、剪贴板位图和自有区域截图选择器。
2. 验证 Keychain、Windows 安全存储、Touch ID 与 Windows Hello，并接入快速解锁和敏感操作重新认证。
3. 完成 macOS sandbox entitlement、签名、公证和 Windows 发布链路验证。
4. 阶段 7 单账号安全分享已完成；下一步继续加密备份恢复 UI。
