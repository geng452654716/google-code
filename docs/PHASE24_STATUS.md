# 阶段 24：桌面端整体 UI 优化

日期：2026-07-20

## 目标

在不改变 Vault 加密、二维码解析、导入、分享、分组拖动和快速解锁业务流程的前提下，统一 TOTP Vault 的桌面视觉语言，降低界面密度，并改善账号列表和操作菜单的可读性。

## 完成内容

### 全局视觉体系

新增统一的浅色与深色主题：

- 以柔和靛蓝为主色，重新定义 surface 层级和边框对比度；
- 统一 Card、Dialog、输入框、SearchBar、PopupMenu、按钮、Snackbar 和 Tooltip；
- 统一圆角、间距、字体字重和轻量阴影；
- 首次切换主题时根据系统当前实际亮暗模式切换，避免系统深色下第一次点击没有视觉变化。

### 首次创建、锁屏与异常状态

新增可复用的安全页面容器：

- 使用统一品牌标识、渐变背景和居中安全面板；
- 统一首次创建 Vault、主密码解锁、Touch ID / 设备验证入口；
- 错误和提示信息改为语义明确的内嵌反馈块；
- 保留现有 `quick-unlock-button` 测试入口和快速解锁行为。

### 主账号界面

- 左侧主导航缩窄并统一按钮尺寸、选中层级和品牌区域；
- 分组侧栏增加账号数量胶囊、拖放提示和更清晰的操作菜单；
- 顶部增加账号总数、本地加密说明、搜索框和常驻“添加账号”按钮；
- 移除桌面端冗余 FloatingActionButton；
- 空状态改为统一说明面板；
- 账号卡片改为紧凑桌面布局，并保留窄窗口响应式排列；
- 服务标识、账号信息、验证码、倒计时、复制和更多操作形成稳定视觉分区；
- 编辑、分享和删除菜单使用统一图标，删除项使用危险色，菜单高度和宽度均收紧。

### 添加账号面板

原默认 `SimpleDialog` 改为桌面端分层选择面板：

- 手动输入或链接作为常用主入口；
- 摄像头、二维码图片、屏幕截图和剪贴板导入使用统一选项卡；
- 增加每种方式的简短说明和本地处理安全提示；
- 保持所有原有导入 action 和业务流程不变；
- 顶部按钮增加稳定测试标识 `add-account-button`。

## 数据保护

- UI 验证使用完全合成的假账号数据，临时预览文件在检查后已删除；
- 未截图或读取真实已解锁账号列表；
- 未读取或输出主密码、TOTP Secret、二维码正文、Keychain 值或 Vault 解密正文；
- 未修改 TCC 数据库，未运行 `tccutil reset`，未绕过 Gatekeeper；
- 覆盖安装前后主 Vault 与 `.bak` 的 SHA-256、大小和修改时间完全一致。

安装前后哈希：

```text
vault.gcvault
96a979c02d679bf5077920156a0c00d67567c1f2dec232cb3388a40271f3d773

vault.gcvault.bak
011bb9a4987258f7376d5702a844f7faaf87e27c7317feaa2cd51c034ece5903
```

## 验证结果

- `flutter analyze --no-pub`：无问题；
- UI 与导入定向回归：15 项通过；
- 完整 Flutter 测试：150 项通过；
- 合成数据桌面布局预览：1280 × 820 无溢出；
- macOS Release 构建成功；
- DMG 创建、挂载校验和 SHA-256 校验成功；
- 覆盖安装成功，严格代码签名验证通过；
- 安装信息：
  - `CFBundleIdentifier=com.gengyujian.googleCode`
  - `CFBundleShortVersionString=1.0.2`
  - `CFBundleVersion=3`
  - `Authority=TOTP Vault Local Signing`

## 安装包

```text
dist/macos/TOTPVault-1.0.2-build3-macos-universal.dmg
SHA-256: 3fe53e68c62addf48eb177c2b2b026b76220e3284a209b59b65cb8a86992a917
```
