# 阶段 3 / 剪贴板图片与链接导入状态

- 更新时间：2026-07-16
- 当前结论：已完成用户主动触发的剪贴板二维码图片与 `otpauth://` 文本导入，并支持 `Cmd+V` / `Ctrl+V` 快捷入口；macOS 原生实现已通过 Debug/Release 构建，Windows 原生实现已提交但仍需在 Windows 环境编译和实测。后续 macOS 区域截图已在 [阶段 4](./PHASE4_STATUS.md) 完成，Google Authenticator 迁移二维码的剪贴板导入与批量确认已在 [阶段 6](./PHASE6_STATUS.md) 完成。

## 本阶段已完成

### 剪贴板平台边界

- [x] 建立可测试的 `ClipboardImportReader`，将系统剪贴板与应用导入逻辑隔离。
- [x] 优先读取剪贴板图片；没有图片时再读取并裁剪纯文本。
- [x] 图片和文本仅在内存中传递，不写入临时文件，不上传网络。
- [x] 仅在用户点击导入或按下粘贴快捷键时读取，不后台监听剪贴板。
- [x] 平台通道异常转换为安全中文提示，不向界面暴露原生异常或敏感内容。

### macOS 与 Windows 适配

- [x] macOS 使用 `NSPasteboard` 读取 PNG/TIFF，并在需要时从 `NSImage` 获取 TIFF 数据。
- [x] macOS 剪贴板图片通过 `FlutterStandardTypedData` 直接返回 Dart 内存。
- [x] Windows 使用 `CF_DIBV5` / `CF_DIB` 读取位图，将 DIB 包装为内存 BMP 后交给现有图片解码器。
- [x] Windows 使用 RAII 确保 `OpenClipboard` 与 `CloseClipboard` 成对执行。
- [x] 文本继续使用 Flutter 标准 Clipboard 通道，避免重复维护平台文本编码逻辑。

### 应用流程与快捷键

- [x] 添加账号菜单新增“从剪贴板导入”。
- [x] 剪贴板图片复用现有 QR 解码、图片限制和 TOTP 校验流程。
- [x] 剪贴板文本在本阶段接受标准 `otpauth://totp` 链接；阶段 6 已扩展为同时识别 `otpauth-migration://` 迁移数据。
- [x] 标准 TOTP 图片与文本进入统一编辑确认、重复检测和 Vault 加密保存流程；阶段 6 的迁移数据进入独立批量确认与单次加密保存流程。
- [x] 支持 macOS `Cmd+V` 和 Windows `Ctrl+V` 快捷导入。
- [x] 当搜索框或其他可编辑文本控件获得焦点时，不拦截其正常粘贴操作。
- [x] 导入来源显示为“剪贴板图片”或“剪贴板链接”，不展示原始 URI。

## 当前验证结果

| 检查项 | 结果 |
| --- | --- |
| `fvm flutter analyze` | 通过，0 issues |
| `fvm flutter test` | 通过，37 tests |
| `fvm flutter build macos --debug` | 通过 |
| `fvm flutter build macos --release` | 通过，46.4 MB |
| Windows 构建 | 原生代码已实现，待 Windows 真机或 CI 验证 |

新增测试覆盖图片优先、文本回退、空剪贴板、剪贴板安全来源标签、剪贴板 URI 解析、菜单导入完整流程，以及 `Ctrl+V` 打开确认页面。macOS 原生剪贴板代码已由 Debug 和 Release 构建完成编译验证。

## 当前限制

- [ ] Windows 原生剪贴板位图适配尚未在 Windows 编译和真实剪贴板环境验证。
- [x] 已在阶段 4 实现 macOS 区域截图和屏幕录制权限引导；Windows 自有区域选择器已在阶段 5 实现，仍待平台验证。
- [ ] 同一张图片中的多个二维码尚不能批量识别。
- [x] Google Authenticator 导出/迁移二维码中的批量账号协议已在阶段 6 实现。
- [x] 迁移二维码的批量确认、跳过、无效项和成功数量汇总已在阶段 6 实现。
- [ ] 尚未支持直接从摄像头扫描二维码。

## 下一阶段建议

区域截图导入闭环的 macOS 部分已在 [阶段 4](./PHASE4_STATUS.md) 完成；后续建议按以下顺序推进：

1. 在真实 macOS 发布形态验证 App Sandbox、TCC 权限、取消和多显示器交互。
2. 在 Windows 真机验证阶段 5 的自有区域选择遮罩和内存截图。
3. 扩展同一图片中多个独立二维码的识别；Google Authenticator 迁移二维码和批量确认已在阶段 6 完成。
4. 开始单账号安全分享，并继续生物识别和加密备份恢复 UI。

同图多个独立二维码、账号安全分享、生物识别、备份恢复 UI、分组和置顶继续保留到后续阶段。
