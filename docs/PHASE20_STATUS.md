# 阶段 20：二维码图片导入恢复与 TOTP Vault 品牌更新

- 完成日期：2026-07-20
- 目标：修复 macOS 点击“从二维码图片导入”后文件选择窗口不可见、解析长期转圈的问题，并统一应用名称与图标。
- 数据兼容：保留原 Bundle ID、可执行文件名、Vault 路径、Keychain 服务名和 MethodChannel 前缀。

## 二维码图片导入

1. macOS 通过原生 `NSOpenPanel` 打开图片选择窗口，并主动激活应用、置前主窗口，以避免文件窗口出现在 Flutter 对话框后方。
2. 添加账号对话框关闭后等待一帧和短暂窗口动画，再打开原生文件窗口。
3. 文件选择和二维码解析使用独立状态：
   - 选择文件期间显示“等待选择图片…”；
   - 选到图片后才显示“正在解析…”；
   - 用户取消选择后立即恢复“添加账号”。
4. 原生窗口直接把图片字节交给 Flutter，不创建包含二维码的临时明文文件。
5. 图片解码在受控 Isolate 中运行，默认 12 秒超时；超时后终止后台任务并提示裁剪到二维码区域后重试。
6. 解码前限制像素尺寸，并减少大图旋转、反色产生的内存副本，降低大图片导致界面假死的风险。

## 品牌更新

用户可见品牌统一为 `TOTP Vault`：

- macOS 应用显示名、DMG 卷标和应用包名称；
- Windows 窗口标题、安装目录、产品描述和 Setup 文件名；
- Flutter 页面标题、权限提示、快速解锁提示和备份文案；
- 新增蓝紫渐变盾牌与六位动态码元素的新图标，并生成 macOS AppIcon 和 Windows ICO。

为确保升级后继续读取原有数据，以下内部标识保持不变：

- Dart package：`google_code`
- 可执行文件：`google_code`
- Bundle ID：`com.gengyujian.googleCode`
- MethodChannel 前缀：`google_code/`

## 自动化与构建验证

- 二维码导入定向测试：16 项通过。
- 完整 Flutter 测试：142 项通过。
- `flutter analyze --no-pub`：无问题。
- macOS Release 构建成功。
- 构建与安装后的代码签名严格验证通过。
- 安装前后 Vault SHA-256 一致；安装脚本未修改 Vault、Keychain、`.gcbak` 或恢复归档。

## 当前安装说明

新应用安装在：

```text
~/Applications/TOTP Vault.app
```

旧的 `~/Applications/Google Code.app` 暂时保留，避免自动删除用户已有应用。测试时应从 `TOTP Vault.app` 启动本阶段版本。

当前本机仍使用 ad hoc 签名。因为没有稳定的本地代码签名 identity，macOS 屏幕录制权限在后续重新构建后仍可能要求重新授权；本阶段没有修改 TCC 数据库、绕过 Gatekeeper 或创建受信任证书。
