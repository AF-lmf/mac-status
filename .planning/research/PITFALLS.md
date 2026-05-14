# Pitfalls Research (项目研究 — 常见陷阱)

**Domain:** macOS 菜单栏系统资源监控应用
**Researched:** 2026-05-14
**Confidence:** HIGH

> 主要数据来源：exelban/stats 38.8k stars 实际 issue 分析、yujitach/MenuMeters 3.1k stars issues、Apple Developer 官方 API 文档（Context7 验证）、Apple Developer Forums。
> 同类成熟项目的已知问题是最可靠的 pitfall 来源。

## Critical Pitfalls

### Pitfall 1: NSStatusItem 循环引用与幽灵图标

**What goes wrong:**
每次应用重启或某些窗口操作（如 Dock 图标点击 reopen），菜单栏会出现新的重复状态图标。旧的 `NSStatusItem` 没有被释放（orphaned），随应用生命周期不断累积，最终菜单栏出现一排相同的图标。

**Root Cause:**
`NSStatusBar.system.statusItem(withLength:)` 创建 `NSStatusItem` 后，系统持有强引用。如果 AppDelegate/StatusBarController 也持有强引用但未在 `deinit` 中调用 `NSStatusBar.system.removeStatusItem(_:)`，图标对象永远不会被回收。同样地，用 `@State private var statusItems: [NSStatusItem]` 数组存储多个 status item 时（如 iStat Menus 式多图标方案），SwiftUI 的状态管理导致数组元素被替换时旧 item 未被 remove。

**How to avoid:**
- `StatusBarController` 必须实现 `deinit`，在其中调用 `NSStatusBar.system.removeStatusItem(statusItem)`
- 对持有的 `NSStatusItem` 使用 `weak` 或可选引用，在重建前先 remove
- 用 `NSStatusItem.autosaveName` 让系统记住位置，而非重新创建新的 item
- 避免在 `@State` 或 SwiftUI 的 observable 集合中管理 `NSStatusItem`——它属于 AppKit 层，应放在 AppDelegate/Controller 中管理

**Warning signs:**
- 重启应用后菜单栏多出一个重复图标
- `deinit` 从未被调用（添加 `print` 验证）
- 切换 activationPolicy 后图标消失，但旧 item 仍在内存中

**Phase to address:**
菜单栏集成阶段（Menu Bar Integration Phase）

**Evidence:**
- GitHub issue search 发现多个项目报告 ghost icons 问题：`StatusBarController has no deinit, orphaned NSStatusItems accumulate`
- Apple Developer Forums：`@State private var statusItems: [NSStatusItem]` 导致 "all icons except the first one flash and disappear"
- Context7 Apple docs: `NSStatusBar.removeStatusItem(_:)` is the proper cleanup method

---

### Pitfall 2: 休眠/唤醒导致的传感器数据冻结

**What goes wrong:**
Mac 合盖休眠后重新打开，传感器读数冻结在休眠前的值不再更新。CPU/GPU/网络/功耗数据显示同一个数值数分钟甚至永久冻结，需要重启应用才能恢复。

**Root Cause:**
macOS 休眠期间系统层级暂停了大部分 IOKit sensor ticks 和 kernel statistics 的收集。应用未监听 `NSWorkspace.willSleepNotification` / `NSWorkspace.didWakeNotification` 去重新初始化或验证数据源连接。IOKit 的 IOService 在唤醒后可能返回 stale 数据，需要重新执行 matching 和 open。

**How to avoid:**
- 监听 `NSWorkspace.didWakeNotification`，在回调中：
  1. 标记数据为 "stale"，下一轮采样时跳过首次或做 sanity check（当前值是否异常偏离上一有效值）
  2. 重新打开 IOKit IOService（如果是通过 IOKit 读取传感器）
  3. 重置 CPU tick 累加器的基础值
- 监听 `NSWorkspace.willSleepNotification`，在回调中暂停 Timer 轮询
- 添加 "数据 stuck 检测"：连续 N 个采样周期数值完全不变，触发重新连接

**Warning signs:**
- 唤醒后相同数值持续超过预期的采样周期数（如 30 秒无变化）
- 功耗读取在休眠后显示明显错误的值（Stats #3203: stuck at 20W, reality was 6W）

**Phase to address:**
系统监控引擎阶段（System Monitoring Engine Phase）

**Evidence:**
- Stats #3203: Sensor widget gets "stuck", average system total not changing after closing & opening laptop — M1 Pro MBP macOS 26.4.1
- Stats #2977: Fan control spin fan to 100% after sleep — 休眠唤醒后传感器读数异常
- Apple docs (Context7): `NSWorkspace.sleepNotification` 和 `NSWorkspace.didWakeNotification` 是 recommended API

---

### Pitfall 3: 高频轮询导致 CPU 消耗和电池续航问题

**What goes wrong:**
系统监控应用进行高频轮询（如每秒 1 次 `host_statistics` + `getifaddrs` + GPU 查询），看似单个调用开销不大，但 24 小时持续运行导致 System Report 中该应用成为 top CPU/energy consumer。用户发现电池续航明显下降，最终卸载。

**Root Cause:**
- `host_statistics()` / `host_processor_info()` 的底层 mach 调用每次都会 kernel trap
- `getifaddrs` 遍历所有网络接口，频繁调用有显著开销
- Timer 即使使用 `.default` run loop mode 也不会在休眠期间暂停——如果 Timer 在休眠期间积压了 fire 事件，唤醒后一次性全部执行
- 未根据机器状态动态调整采样频率（如电池供电降低频率、空闲状态降低频率）

**How to avoid:**
- 默认采样间隔设为 **2-3 秒**（对用户视觉延迟感知 < 3s 无法区分）
- CPU/内存/GPU：2-3s，网络速率：使用计数器差值计算（高频读计数器，低频更新 UI）
- 区分「数据采集频率」和「UI 刷新频率」：计数器可以在 0.5s 级别读取（开销极低，仅仅是取一个 int64），但 UI 文本/图标更新控制在 1-2s
- 监听电池状态：`IOPSNotificationCreateRunLoopSource` 或 `NSProcessInfo.processInfo.isLowPowerModeEnabled`，在低电量模式下降低到 5s+
- 使用 `Timer.scheduledTimer(withTimeInterval:repeats:block:)` 并确保在 `RunLoop.Mode.common` 而非 `.default` 运行
- 唤醒时检查 Timer 是否有效，避免积压 fire

**Warning signs:**
- Activity Monitor 显示应用持续 3-5% CPU（一个简单的状态栏应用应该 < 1%）
- `Energy` tab 中应用排在前面
- Instruments 的 Energy Log 显示过多 "wake-ups"

**Phase to address:**
性能优化阶段（Performance Optimization Phase）

**Evidence:**
- Stats #2733: high disk writes due to widget update bug on macOS 26 — 每帧都触发写盘
- Stats #2407: refresh interval setting does not work
- Apple Energy Efficiency Guide: 菜单栏应用应尽量减少 wake-up 次数

---

### Pitfall 4: LSUIElement / 激活策略与窗口生命周期的冲突

**What goes wrong:**
菜单栏应用设置 `LSUIElement = YES` 后，仍然弹出一个空白主窗口；或者设置后主菜单不响应点击；或者从 `LSUIElement` 切换到 `.regular` 再切回时 Dock 图标闪现/消失，菜单栏功能异常。

**Root Cause:**
- `LSUIElement = YES`（即 `NSApplication.shared.setActivationPolicy(.accessory)`）会隐藏 Dock 图标和主菜单栏，但 **SwiftUI 的 `WindowGroup` / `Window` Scene 仍然会创建一个窗口**（Scene 是 SwiftUI 的顶层概念，Info.plist 的 LSUIElement 只影响 AppKit 层面）
- SwiftUI @main App 使用 `WindowGroup` 时，即使 Info.plist 设置了 LSUIElement，SwiftUI 依然会 render body 中的 ContentView 作为一个窗口
- 在运行时通过 `NSApp.setActivationPolicy(.regular)` 临时切换到普通模式再切回 `.accessory` 时，AppKit 的激活状态机存在已知 bug——状态切换不是原子的，导致中间态暴露给用户

**How to avoid:**
- 在 SwiftUI `App` 中，使用：
  ```swift
  var body: some Scene {
      MenuBarExtra("MacStatus", systemImage: "gauge") {
          ContentView()
      }
  }
  ```
  （macOS 13+ `MenuBarExtra` API 是最干净的方式）——它自动处理 LSUIElement，并消隐窗口
- 如果必须用 AppKit 方式：在 `applicationDidFinishLaunching` 中显式关闭所有窗口 `NSApp.windows.forEach { $0.close() }`
- 避免在运行时动态切换 `.accessory` 和 `.regular`。如果确实需要弹出设置窗口，使用独立的 `NSWindowController` 并用 `window.makeKeyAndOrderFront(nil)` + `NSApp.activate(ignoringOtherApps: true)` 而非切换 activationPolicy
- 测试路径：至少测试 3 次激活/停用循环来发现瞬态 bug

**Warning signs:**
- 启动时闪现一个空白窗口后消失
- 菜单栏点击菜单无响应（Apple Developer Forums: "Menu Bar App's Menu Not Working"）
- Dock 图标间歇性出现

**Phase to address:**
菜单栏集成阶段（Menu Bar Integration Phase）

**Evidence:**
- Apple Developer Forums 多个帖子报告 LSUIElement + SwiftUI 窗口问题
- Apple Developer Forums #1.2k views: "Menu Bar App's Menu Not Working" — setActivationPolicy 导致菜单失效
- Apple Developer Forums #379 views: "How to create multiple NSStatusItem on the menu bar" — array management issues
- Apple docs (Context7): `NSApplication.ActivationPolicy.accessory` — the app doesn't appear in the Dock but may appear in the menu bar

---

### Pitfall 5: 网络接口枚举硬编码和虚拟接口污染

**What goes wrong:**
应用通过硬编码 "en0" 来读取 Wi-Fi 速率，但用户在切换网络环境后（VPN 连接、USB-C 以太网适配器、虚拟网卡），实际活跃接口变成了 "en1"、"en10"、"utun"、"bridge" 等。数据要么是零，要么错误地报告了一个虚拟接口的流量。

**Root Cause:**
- macOS 的网络接口命名是动态的：`en0` 不总是 Wi-Fi，`enX` 随硬件插入顺序变化
- 虚拟接口（`utun` 用于 VPN tunnel、`awdl` 用于 AirDrop、`llw` 用于 Low-Latency WLAN）也有网络流量，但不应计入「用户感知的上下行速率」
- `getifaddrs()` 返回所有接口，应用需要过滤："哪些是真实的、活跃的、用于互联网连接的接口"

**How to avoid:**
- 使用 `SystemConfiguration` 框架的动态 store 获取当前 primary 接口，而非硬编码名称：
  ```swift
  let dynamicStore = SCDynamicStoreCreate(nil, "MacStatus" as CFString, nil, nil)
  let globalState = SCDynamicStoreCopyValue(dynamicStore, "State:/Network/Global/IPv4" as CFString)
  let primaryInterface = (globalState as? [String: Any])?["PrimaryInterface"] as? String
  ```
- 过滤虚拟接口：排除 `awdl`、`llw`、`utun`、`bridge`、`gif`、`stf`、`XHC` 等前缀
- 区分上下行：`ifa_data` 中的 `ifi_obytes` / `ifi_ibytes`
- 定期（每 10s）重新检查 primary interface，处理网络变化

**Warning signs:**
- 连接 VPN 后速率变成 0 或者异常低
- 速率数据在 Wi-Fi ↔ 有线切换时中断
- 显示的接口名称与实际网卡不匹配（MenuMeters #314: "Wrong label: Wi-Fi (en0) - Ethernet 54 Mbps"）

**Phase to address:**
网络监控模块阶段（Network Monitoring Phase）

**Evidence:**
- MenuMeters #314: Wrong label: Wi-Fi (en0) - Ethernet 54 Mbps — 接口命名混淆
- MenuMeters #155: 类似网络接口识别问题（被 #314 引用）
- Stats #3175: Daily network Upload/Download total did not reset automatically — 接口切换导致计数异常

---

### Pitfall 6: Sandbox vs. IOKit 传感器访问的二选一困境

**What goes wrong:**
应用启用了 App Sandbox 为了上架 App Store，但发现 CPU 温度、GPU 传感器、风扇转速等 IOKit 数据无法读取。如果关闭 Sandbox，则无法上架 App Store。开发者陷入两难，最终要么放弃上架，要么放弃传感器功能。

**Root Cause:**
- IOKit 的 `IOServiceGetMatchingService` / `IORegistryEntryCreateCFProperty` 需要访问 `/dev/` 和 IOKit registry
- App Sandbox 的默认 entitlements 不能访问 IOKit 的内核服务层
- `host_statistics()` / `host_processor_info()` (CPU)、`host_statistics64()` (memory) 属于 Host.framework，即使在 Sandbox 下也可用——这些是公开 API
- 但风扇转速、温度传感器、GPU 利用率（非 Metal-based）等没有公开的 Sandbox-compatible API

**How to avoid:**
- **明确取舍：** MacStatus v1 只监控「有公开 API 的指标」：CPU 占用率（`host_processor_info`）、内存使用量（`host_statistics64`）、GPU 使用率（Metal `MTLDevice.sampleTimestamps` 或 IOKit AGXAccelerator）、网络速率（`getifaddrs` + `SystemConfiguration`）
- 温度/风扇等指标放到 Out of Scope，或作为非 App Store 版本的 opt-in 功能
- 如果确实需要 IOKit 深度访问：不走 App Store 分发，用 Sparkle 自更新 + DMG 分发
- 如果必须上架：检查哪个 API level 足够——`host_statistics` 级别的 CPU/memory 在 Sandbox 下可用（已验证），Metal GPU 计数器页在 Sandbox 下可用

**Warning signs:**
- Sandbox 开启后 `IORegistryEntryCreateCFProperty` 返回 nil
- Console.app 中出现 sandboxd deny log

**Phase to address:**
系统监控引擎阶段（System Monitoring Engine Phase）—— 第一个可工作的 CPU 读数就应该在 Sandbox 内验证

**Evidence:**
- Apple App Sandbox docs (Context7): entitlements 白名单，IOKit 不在可授权列表中
- Stats 代码：不使用 App Sandbox（直接通过 DMG 分发）
- MenuMeters 代码：不使用 App Sandbox（开源社区分发）
- 本项目的 Key Decisions 要求 "尽量小，无外部依赖" —— 避免因 Sandbox 问题引入复杂 helper tool 架构

---

### Pitfall 7: SMAppService 自启动在不同 macOS 版本上的兼容性

**What goes wrong:**
应用实现了登录自启动，但在某些 macOS 版本上不工作，或启动后菜单栏图标不显示，或用户关闭自启后仍自动启动。

**Root Cause:**
- `LSSharedFileList`（老的 `LSSharedFileListInsertItemURL`）在 macOS 13+ 废弃，Xcode 会报 deprecation warning
- `SMAppService.mainApp.register()` 是 macOS 13+ 的现代 API，但：
  - 在 macOS 12 及以下不可用
  - 如果应用是 LSUIElement=true（Dock 不显示），`SMAppService.mainApp` 的行为与 `WindowGroup` 应用不同——某些 macOS 版本有 bug
  - `SMAppService.loginItem(identifier:)` 需要创建独立的 helper app bundle（在 App.app/Contents/Library/LoginItems/ 下），增加项目复杂度
- Stats #2768: "Widget doesn't show up on login in menubar" —— 登录启动后菜单栏没有显示
- Stats #3147: "battery icon failing to show in menubar on fresh startup" —— 自启动时部分图标缺失

**How to avoid:**
- 最简单的方案（macOS 13+）：`SMAppService.mainApp.register()`，在设置界面用 Toggle 绑定
- 需要在 `Info.plist` 中设置 `SMBackgroundMode` 为 `false`（因为我们不想做 full background mode，只是 login item）
- 在 `applicationDidFinishLaunching` 中验证 statusItem 是否真的有 button（statusItem.button != nil），因为自启动时创建可能早于系统的状态栏初始化
- 使用 `NSStatusBar.system` 在 applicationDidFinishLaunching 中创建 item，不要在 `init` 中创建

**Warning signs:**
- 自启动后 statusItem.button 为 nil
- `SMAppService.isEnabled` 返回的状态与实际状态不一致

**Phase to address:**
自启动阶段（Launch at Login Phase）

**Evidence:**
- Context7 Apple docs: `SMAppService.mainApp` — "Returns an SMAppService object that corresponds to the main application as a login item"
- Stats #2768: Widget doesn't show up on login in menubar
- Stats #3147: battery icon failing to show in menubar on fresh startup

---

### Pitfall 8: 可变宽度 StatusItem 导致菜单栏布局抖动

**What goes wrong:**
使用 `NSStatusItem.variableLength` 展示网络速率时（如 "0 KB/s" → "12.3 MB/s"），文本宽度不断变化，导致：
1. StatusItem 在菜单栏抖动（宽度不断调整）
2. 相邻的 macOS 系统图标（WiFi、时钟等）被挤得左右移动
3. MacBook Pro 带 notch 时，部分图标被 notch 遮挡

**Root Cause:**
- `NSStatusItem.variableLength` 会根据内容自动调整宽度
- 网络速率文本的长度动态变化幅度大（"0 B/s" 是 4 字符，"125.3 MB/s" 是 10 字符）
- 每次 `statusItem.button?.title` 更新都会触发 layout pass

**How to avoid:**
- **使用固定宽度**：设置 `statusItem.length = 80` (points)，确保最宽文本（如 "888 KB/s ↓"）也能容纳
- **格式化策略**：统一使用 `fixed-width` 数字字体（如 `.monospacedDigit()`）和固定最大宽度
- **分列设计**：上下行分别在不同 StatusItem 中，每个使用 `squareLength`（高度等于菜单栏高度），但 MacStatus v1 可将上下行合为一行用简洁表示
- **Notch 适配**：动态检测 notch（`NSScreen.main?.safeAreaInsets.top > 0`），如果存在则进一步压缩文本格式

**Warning signs:**
- 刷新时菜单栏图标整体跳动
- 用户反馈 "WiFi 图标在菜单栏左右飘"

**Phase to address:**
菜单栏 UI 优化阶段（Menu Bar UI Phase）

**Evidence:**
- Stats #3148: Feature Request: Adjustable spacing for menu bar icons on MacBook with Notch
- Stats #2987: Menubar icons position cannot be remembered, or managed by menubar managers
- Apple docs (Context7): `NSStatusItem.length` — `squareLength` and `variableLength` options

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| 硬编码网络接口名 "en0" | 零配置，直接能读取 | 网络切换、VPN连接、硬件变更后数据错误，用户报告 bug | Never — 用 SystemConfiguration 检测 primary interface |
| 用 Timer 每秒刷新所有指标并重绘 UI | 代码简单直观 | Energy Impact 显著，macOS 会自动 throttling 导致刷新间隔不稳定 | Never — 分离数据采集频率和 UI 刷新频率 |
| 全量文本重绘 statusItem.button?.title | 一步更新简单 | 每次都会触发字符 layout + 位置移动 + 相邻元素 re-layout | MVP 可接受，但需预留性能优化阶段 |
| 跳过 deinit 中的 NSStatusBar.removeStatusItem | 代码少写一行 | 幽灵图标累积，用户需要注销才能清除 | Never |
| 不用 SMAppService 而用老的 LSSharedFileList | Xcode 不报警 | macOS 15+ 可能失效，App Review 可能拒绝 | 永远不应该 |
| 忽略 notched MacBook 布局 | 开发机无 notch | 20%+ 用户受影响，菜单栏图标被遮挡 | MVP 阶段可用 `.fixedLength` + 短文本规避 |

---

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| IOKit / IOService | `IOServiceGetMatchingService(kIOMainPortDefault, matching)` 在主线程同步调用（阻塞 UI） | 在后台队列调用 IOKit，主线程只做 UI 更新 |
| Host.framework (`host_statistics`) | 直接取 raw value 累加显示，未处理计数器溢出（uint32 在 macOS 上跨版本可能变化） | 使用差值法（current - previous），处理 wrap-around case |
| Metal GPU | `MTLCreateSystemDefaultDevice()` 在初始化时只调用一次，但设备切换（外接显示器）后不更新 | 监听 `MTLDeviceWasAddedNotification` / `MTLDeviceWasRemovedNotification` |
| SystemConfiguration | 直接读 `State:/Network/Interface/en0/IPv4` 而非通过 Global/PrimaryInterface | 通过 `/Network/Global/IPv4` → `PrimaryInterface` 间接获取，再读对应接口 |
| SMAppService | 直接调用 register() 而不先检查状态（已注册再注册会怎样？） | `if !SMAppService.mainApp.isEnabled { try? SMAppService.mainApp.register() }` |
| NSWorkspace | 只监听 `didWakeNotification` 但未处理「网络在唤醒后花费数秒重连」的情况 | 唤醒后延迟 3-5s 再恢复网络统计数据采集 |

---

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| 每帧全量重绘 NSStatusItem | Activity Monitor 显示此应用 3-5% CPU | 缓存上一个渲染值，仅当数据变化超过阈值（如 >1% CPU 或 >1KB 网络）才更新 UI | 持续运行 1 小时以上 |
| Timer 不在 correct run loop mode | 滚动/拖拽操作时 UI 冻结不更新 | 使用 `RunLoop.main.add(timer, forMode: .common)` | 用户打开菜单/拖动任何内容 |
| 循环引用 Timer → self | 内存泄漏，deinit 不调用，Timer 永不停止 | Timer 闭包使用 `[weak self]` + `guard let self` 模式 | 应用运行数小时后 |
| 网络速率使用「累积 byte 除以运行时间」 | 速率数值与实际网速完全不符（早期显示极低，后期趋于稳定） | 使用滑动时间窗口：记录最近 N 秒的 delta bytes， `rate = delta / window_size` | 立即体现 |
| `host_processor_info` 每次 `vm_deallocate` 失败 | 内存泄漏速度：每次采样泄漏 ~6KB CPU info buffer | 确保配对 `host_processor_info(..., &processorInfoOut, &processorInfoCnt)` 与 `vm_deallocate(..., vm_page_size * processorInfoCnt)` | 运行数分钟后开始 |

---

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| SMJobBless 安装 privileged helper tool 后未验证 code signature | 恶意替换 helper 后获得 root 权限 | SMJobBless 自带签名验证，但需在 helper plist 中正确设置 `SMAuthorizedClients` 和 `SMPrivilegedExecutables` |
| 开放 XPC Service 给外部进程 | 任意进程可以向你的监听服务发消息 | XPC listener 的 `NSXPCListener` 只用 `machServiceName` 对应 bundle identifier，不暴露给 `*` |
| 未清理 `autosaveName` 中的 user path | autosaveName 可能被别的应用读取（低风险，但违反最佳实践） | 使用 `Bundle.main.bundleIdentifier! + ".statusItem"` 作为 autosaveName |
| Settings 窗口通过 `NSApp.activate(ignoringOtherApps: true)` 打开 | 在用户全屏应用/游戏时弹出设置窗口体验极差 | 在 `applicationDidBecomeActive` 中检查当前是否处于 fullscreen space，如果是则使用 requestUserAttention |

---

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| 菜单栏文字使用系统默认字体+默认颜色，在亮/暗模式下对比度不足 | 无法阅读（Stats #3199: "RAM usage unreadable when medium-high (yellow)"） | 使用 `.monospacedDigit()` + `NSColor.labelColor`（自动适配亮暗模式），对 warning 级别使用高对比度颜色 |
| 点击菜单栏图标时出现完整设置窗口而非下拉菜单 | 用户只是想看一眼详细数据，但不想要一个窗口挡住屏幕 | 菜单栏图标点击 → Popover 显示详细数据；右键/Option+点击 → 设置；Stats #3176: "Stats setting window opens when clicking on menubar widget" |
| 菜单栏图标多而无序 | 4 个独立 StatusItem（CPU/内存/网络/GPU）占据大量菜单栏空间 | 合并为一个 StatusItem + 文本格式（如 "C 23% M 45% ↓2.3M ↑1.2M"），点击展开 Popover 看详情 |
| 没有提供速率单位切换（KB/s vs Mbps） | 网络速度 KB/s 对普通用户不直观，但 Mbps 对开发者不精确 | 设置中提供切换，默认 KB/s |
| 状态栏更新延迟过高（>5s） | 用户感觉数据"不准"，失去信任 | 网络数据：1-2s 刷新 UI；CPU/内存：2-3s 刷新 |

---

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **菜单栏图标显示:** 自启动后图标真的出现吗？→ 验证：重启 Mac 且不手动打开应用
- [ ] **菜单栏图标显示:** Notch 机型上图标可见吗？→ 验证：在 MacBook Pro 14"/16" (M1 Pro+) 真机测试
- [ ] **网络速率:** VPN 连接后数据对吗？→ 验证：连接 VPN 看数据是否切换到对应接口
- [ ] **网络速率:** 休眠唤醒后速率恢复吗？→ 验证：合盖 30 分钟，醒来后数据是否继续更新
- [ ] **GPU:** Apple Silicon + Intel 都测试了吗？→ 验证在两代芯片上 GPU 数据是否都有值
- [ ] **CPU:** 在 100% 负载时百分比对吗？→ 验证：用 `yes > /dev/null &` 跑满一个核看读数
- [ ] **内存:** 内存压力用 `memoryPressure` 而非单纯百分比？→ macOS 内存管理不同于百分比，压力级别更有参考价值
- [ ] **性能:** Activity Monitor 中应用 CPU < 1%（采样周期 2s）？→ 验证：运行 30 分钟后检查
- [ ] **Sandbox:** Application Sandbox = YES 时所有公开 API 都正常工作了？→ 验证：在 Sandbox 开启状态下跑一遍全部指标
- [ ] **暗色模式:** 菜单栏文字在所有外观模式下可读？→ 验证：切换 Light/Dark mode，检查对比度

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| NSStatusItem 循环引用 | LOW | 在 `StatusBarController` 加入 `deinit` + remove，一次性提交修复 |
| 休眠后传感器冻结 | MEDIUM | 实现 `didWakeNotification` 监听，添加 sensor health check 逻辑 |
| 高频轮询电池消耗 | LOW | 调整 default interval 为 2-3s + 低电量模式下 5s，仅修改配置常量 |
| 网络接口硬编码 | MEDIUM | 重构网络监控代码，引入 SystemConfiguration primary interface detection |
| LSUIElement 窗口闪烁 | MEDIUM | 迁移到 `MenuBarExtra` API (macOS 13+)，或显式关闭所有窗口 |
| Sandbox 与 IOKit 冲突 | HIGH | 需重写采集层，或决策放弃 App Store / 放弃某些传感器 |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| NSStatusItem 循环引用 | Phase: Menu Bar Integration | `deinit` 被调用日志 + 重启后无幽灵图标 |
| LSUIElement 生命周期 | Phase: Menu Bar Integration | 启动无多余窗口 + 菜单响应正常 |
| 可变宽度抖动 | Phase: Menu Bar UI Optimization | 固定宽度 + notch 机型测试通过 |
| 休眠传感器冻结 | Phase: System Monitoring Engine | `didWakeNotification` 实现 + 唤醒后数据在 5s 内恢复更新 |
| Sandbox vs IOKit | Phase: System Monitoring Engine | Sandbox=YES 条件下所有 v1 指标读数正常 |
| 高频轮询功耗 | Phase: Performance Optimization | 30min Activity Monitor 监控 <1% CPU |
| 网络接口硬编码 | Phase: Network Monitoring | VPN 连接/断联测试 + 不同网络环境下 primary interface 正确 |
| SMAppService 自启动 | Phase: Launch at Login | 重启 Mac 后图标显示 + 设置中开关功能正常 |
| GPU 跨芯片兼容 | Phase: GPU Monitoring | M-series + Intel Mac 双平台验证 |

---

## Sources

- **Stats (exelban/stats) Issues** (38.8k stars): #3203 (sensor stuck after sleep), #3199 (RAM unreadable), #3193 (fan helper install fail), #3176 (settings window on click), #3148 (notch spacing), #2987 (icon position not remembered), #2977 (fan 100% after sleep), #2768 (no show on login), #2733 (widgets not update/high disk writes), #2407 (refresh interval not working) — MEDIUM confidence (real-world issue tracker)
- **MenuMeters (yujitach/MenuMeters) Issues** (3.1k stars): #319 (conflict with Little Snitch), #317 (CPU meter on Apple M), #314 (wrong Wi-Fi label), #155 (network interface identification) — MEDIUM confidence
- **Apple Developer Documentation** (via Context7): NSStatusBar, NSStatusItem, SMAppService, App Sandbox entitlements — HIGH confidence (official docs)
- **Apple Developer Forums**: Multiple NSStatusItem in array issue, LSUIElement + WindowGroup problem, Menu Bar App's Menu Not Working, NSStatusItem performance warnings on macOS Tahoe — MEDIUM confidence (community reports)
- **GitHub issue search**: Ghost NSStatusItem / retain cycle across multiple menu bar app projects — MEDIUM confidence
- **Apple Energy Efficiency Guide**: Best practices for background apps and wake-up minimization — HIGH confidence

---

*Pitfalls research for: macOS 菜单栏系统资源监控应用 (MacStatus)*
*Researched: 2026-05-14*
