# 阶段 5 / Windows 区域截图选择器状态

- 更新时间：2026-07-16
- 当前结论：已完成 Windows 自有区域选择遮罩、虚拟桌面内存截图、BMP 裁剪、取消处理和 Flutter 平台通道接入。Dart 静态检查与跨平台回归测试已通过，但当前开发机是 macOS，Windows C++ runner 尚未在 Windows 环境编译和运行验收。

## 本阶段已完成

### 自有区域选择器

- [x] 不依赖 Snipping Tool URI、外部截图应用或系统剪贴板。
- [x] 使用 `SM_XVIRTUALSCREEN`、`SM_YVIRTUALSCREEN`、`SM_CXVIRTUALSCREEN` 和 `SM_CYVIRTUALSCREEN` 获取完整虚拟桌面范围。
- [x] 截图前隐藏 Flutter 主窗口并调用 `DwmFlush`，完成、取消和失败后通过 RAII 恢复原窗口及焦点。
- [x] 使用 GDI `BitBlt` 和 `CAPTUREBLT` 将虚拟桌面捕获为 32 位 top-down DIB。
- [x] 创建无边框、置顶的全虚拟桌面选择遮罩，显示冻结桌面和半透明暗层。
- [x] 鼠标拖动区域保持原亮度并绘制蓝色边框，最小有效区域为 4×4 像素。
- [x] 支持 `Esc` 和鼠标右键取消；取消返回 `null`，不进入二维码解析或保存流程。
- [x] 选择完成后直接裁剪并编码为内存 BMP，不创建临时文件，不修改剪贴板。

### 内存与资源安全

- [x] 使用 RAII 管理桌面 DC、内存 DC、DIB、选择器窗口和 Flutter 主窗口恢复。
- [x] 每次 `GetDC`、`CreateCompatibleDC`、`CreateDIBSection` 和 GDI 对象选择均有对应释放或恢复路径。
- [x] 裁剪前检查宽高、文件头、像素大小以及 `uint32_t` / `size_t` 上限。
- [x] 全桌面像素缓冲在释放前使用 `SecureZeroMemory` 清理，减少敏感屏幕内容在进程内存中的残留时间。
- [x] 平台通道只向 Dart 返回选区 BMP，不返回完整桌面截图或原生错误细节。
- [x] Windows GDI 截图不需要屏幕录制权限页，`openScreenRecordingSettings` 在 Windows 安全返回成功。

### Flutter 导入闭环

- [x] `google_code/screen_capture` 的 `captureRegion` 已连接 Windows 自有实现。
- [x] 成功返回 BMP 字节，取消返回空结果，原生失败返回 `capture_failed`。
- [x] Dart 层继续使用安全中文错误，不展示原生诊断。
- [x] Windows BMP 继续复用现有图片限制、QR 解码、TOTP 校验、确认编辑、重复检测和 Vault 加密保存流程。
- [x] 增加 BMP 二维码解码回归测试，确认当前 `image` + `zxing2` 处理链支持 Windows 截图输出格式。

## 当前验证结果

| 检查项 | 结果 |
| --- | --- |
| `fvm flutter analyze` | 通过，0 issues |
| `fvm flutter test` | 通过，46 tests |
| Windows C++ 格式检查 | 已使用 Google C++ 风格格式化 |
| Windows Debug/Release 构建 | 待 Windows 真机或 CI 验证 |
| Windows 单显示器框选 | 待 Windows 真机验证 |
| Windows 多显示器与混合 DPI | 待 Windows 真机验证 |

新增回归测试覆盖 Windows 输出 BMP 的二维码识别，以及原生 `capture_failed` 不向用户暴露敏感诊断。现有截图成功、取消、权限错误、设置入口和完整加密保存测试继续全部通过。

## 当前限制与风险

- [ ] 当前 macOS 开发机没有 MSVC/Windows SDK，新增 `screen_capture.cpp` 尚未经过 Windows 编译器和 `/W4 /WX` 验证。
- [ ] 需要验证 Windows 10 19041、Windows 11、单屏、多屏、负坐标显示器及不同缩放比例。
- [ ] HDR、受 DRM 保护的窗口、UAC Secure Desktop 和部分硬件叠加层可能返回黑色或不可捕获内容。
- [ ] 选择器当前只支持鼠标拖动，不支持键盘微调、窗口吸附或显示器快速选择。
- [ ] 同一张截图中的多个二维码仍只读取首个可识别内容。
- [x] Google Authenticator 迁移二维码批量协议已在阶段 6 实现。

## 下一阶段建议

1. 在 Windows 环境执行 Debug/Release 构建并修复所有 MSVC `/W4 /WX` 问题。
2. 人工验收取消、反向拖动、最小选区、跨显示器、混合 DPI、窗口恢复及二维码识别。
3. Google Authenticator 迁移二维码和多账号批量确认已在阶段 6 完成。
4. 随后实现单账号安全分享：重新认证后分享 Secret、`otpauth://` 链接和二维码。
