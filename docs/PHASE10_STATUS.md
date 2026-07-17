# 阶段 10 / 系统会话事件自动锁定状态

- 更新时间：2026-07-17
- 当前结论：已完成 macOS 与 Windows 系统锁屏、活动会话断开和系统睡眠事件到 Flutter Vault 的统一自动锁定链路。事件到达后先无动画移除全部敏感模态路由，再清理 repository 持有的解锁 DEK 与 payload，并在同一锁定帧销毁账号页；唤醒或会话恢复不会自动解锁。macOS Debug 构建已通过，Windows 原生实现已完成静态审查，仍需 Windows 10/11 真机编译与事件矩阵验收。

## 本阶段已完成

### Dart 平台边界

- [x] 新增 `SystemSessionEvent`，统一表示 `screenLocked`、`sessionDisconnected` 和 `systemSleeping`。
- [x] 新增 `SystemSessionEventService` 接口及 `MethodChannelSystemSessionEventService` 实现。
- [x] 使用 `google_code/system_session_events` / `systemSessionEvent` 作为 macOS、Windows 的统一 MethodChannel 协议。
- [x] 事件流使用同步 broadcast controller，确保原生安全事件按到达顺序立即交给协调器。
- [x] `start()` 与 `dispose()` 幂等；非 macOS/Windows 平台不注册 handler。
- [x] 原生 handler 注册失败不会阻塞 Vault 初始化，手动锁定和现有超时锁定仍可工作。

### 自动锁定协调

- [x] 新增 `SystemAutoLockCoordinator`，先订阅事件流再启动原生 handler，降低初始化事件丢失窗口。
- [x] Vault 已锁定时忽略事件，避免锁屏、显示器睡眠与系统睡眠的重复通知多次调用 repository lock。
- [x] Vault 已解锁时严格按“清除敏感路由 -> 锁定 Vault”顺序执行。
- [x] 新增根 `Navigator` observer，追踪 push、pop、remove 和 replace，并通过 `Navigator.removeRoute` 无动画移除首页以上全部路由。
- [x] 分享、备份导出、备份恢复、安全设置、账号编辑、导入确认等根路由会在系统锁定前立即关闭。
- [x] 锁定状态不保留 `AnimatedSwitcher` 的旧账号页，避免验证码缓存或敏感 widget 在退出动画期间继续存在。
- [x] `VaultSessionController.lock()` 继续调用 `repository.lock()`，清理 repository 中解锁 DEK、envelope 和解密 payload 引用。
- [x] 不响应系统解锁、会话重连或唤醒事件；用户必须重新输入主密码或完成已配置的设备认证。

### 原有锁定策略保留

- [x] 用户点击“立即锁定”继续立即清理 Vault。
- [x] 用户交互超时继续按 `autoLockMinutes` 执行，默认 5 分钟，可配置范围 1 至 60 分钟。
- [x] Flutter `paused`、`inactive`、`hidden` 状态继续记录后台时间，恢复时超过配置时长才锁定。
- [x] 普通窗口短暂失焦不会因本阶段改动而立即锁定。
- [x] 系统级事件与原有后台超时互为降级，不依赖单一事件来源。

### macOS 原生实现

- [x] `DistributedNotificationCenter` 监听 `com.apple.screenIsLocked`。
- [x] `NSWorkspace` 监听系统睡眠、显示器睡眠和用户会话失去活动状态。
- [x] 原生 emitter 由 `MainFlutterWindow` 强引用，确保通道与 observer 覆盖应用窗口生命周期。
- [x] 所有 Flutter MethodChannel 调用在主线程执行。
- [x] emitter 销毁时注销全部 workspace 与 distributed observers。
- [x] macOS Debug 应用已完成 Swift 原生编译。

### Windows 原生实现

- [x] 窗口创建时调用 `WTSRegisterSessionNotification`，只订阅当前 session。
- [x] `WTS_SESSION_LOCK` 映射为屏幕锁定。
- [x] console/remote disconnect、logoff 与 terminate 映射为会话断开。
- [x] `PBT_APMSUSPEND` 映射为系统睡眠。
- [x] 安全消息在 Flutter/plugin 顶层窗口消息处理之前检查，降低被提前消费的风险。
- [x] 窗口销毁时注销 WTS 通知并释放 MethodChannel。
- [x] runner 已链接 `wtsapi32.lib`。
- [ ] Windows 原生实现尚未在当前 macOS 环境编译；必须在 Windows 10/11 真机完成 MSVC 构建和运行验收。

## 当前验证结果

| 检查项 | 结果 |
| --- | --- |
| `fvm dart format lib test tool` | 通过，98 files，0 changed |
| `fvm flutter analyze` | 通过，0 issues |
| `fvm flutter test` | 通过，96 tests |
| `fvm flutter build macos --debug` | 通过，生成 `build/macos/Build/Products/Debug/google_code.app` |
| Windows 原生构建与运行 | 当前环境不可执行；已完成静态审查，待 Windows 10/11 真机验证 |

新增自动化测试覆盖 Vault 已锁定时忽略事件、敏感路由先于 Vault 锁定清除、重复系统事件只锁定一次、协调器销毁后停止处理、原生注册失败不阻塞启动，以及打开“安全设置”时收到系统锁定事件会在单次 pump 内关闭弹窗、销毁账号页并只调用一次 repository lock。

## 当前限制与风险

- [ ] Windows WTS 与电源事件只能静态审查，尚未完成 MSVC 编译、锁屏、远程桌面断开、注销和睡眠真机验证。
- [ ] macOS 已通过 Debug 编译，但 `com.apple.screenIsLocked`、快速用户切换、显示器睡眠和系统睡眠仍需在目标签名/Sandbox 环境人工验收。
- [ ] 原生事件名称与行为依赖操作系统；未来 macOS/Windows 版本升级时需回归通知是否仍按预期到达。
- [ ] 系统事件发生在 Flutter engine 完成启动之前时无法进入 Dart；应用启动后默认处于锁定页，仍不会暴露已解密 Vault。
- [ ] Dart 垃圾回收无法保证对象立即物理清零；当前通过立即移除路由、销毁账号页、清理 repository/session 引用、无日志和无明文临时文件降低风险。
- [ ] Windows 远程桌面、快速用户切换、多显示器和不同电源策略可能产生重复或顺序不同的事件；Dart 层已幂等，但仍需真机矩阵验证。

## 下一阶段建议

1. 在 Windows 10/11 真机完成 MSVC 构建，并验收本地锁屏、远程桌面断开、注销、系统睡眠和重复事件。
2. 在 macOS Sandbox/签名环境验收屏幕锁定、快速用户切换、显示器睡眠、系统睡眠及唤醒后必须重新认证。
3. 在 macOS 与 Windows 真机验收 `.gcbak` 文件对话框、二维码保存、截图和系统安全存储权限行为。
4. 使用真实 Google Authenticator 导出样本继续完成阶段 6 兼容性回归。
5. 评估 macOS `NSSharingServicePicker` 与 Windows `DataTransferManager`，增加系统分享面板并保留复制/保存降级路径。
