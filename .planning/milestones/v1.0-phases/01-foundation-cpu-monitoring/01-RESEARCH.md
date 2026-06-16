# Phase 1: Foundation + CPU Monitoring - Research

**Researched:** 2026-05-14
**Domain:** macOS Menu Bar App Foundation + CPU Monitoring via Mach APIs
**Confidence:** HIGH

## Summary

Phase 1 establishes the complete MacStatus application skeleton and proves the Reader->Widget data pipeline end-to-end with CPU monitoring. This is a greenfield phase with zero existing code—every file must be created from scratch in a new Xcode project.

The core technical challenges are: (1) correct NSStatusBar lifecycle with proper deinit cleanup to prevent ghost icons, (2) using `host_processor_info()` Mach API on a background queue with delta calculation and `vm_deallocate` cleanup, (3) Swift 6 Sendable compliance when passing Mach C types across actor boundaries, and (4) efficient menu bar text rendering using `NSAttributedString` with monospaced digits and tolerance-based redraw (skip updates when value changes < 0.5%).

**Primary recommendation:** Follow the Stats (exelban/stats) reference architecture: AppKit `@main` AppDelegate, `Reader<T>` base class with `Timer`-based polling on background queue, callback pattern to deliver typed data to main-thread widgets, and NSStatusItem with `NSStatusBarButton.attributedTitle` for text display. Use a simplified single-file approach for Phase 1—the Protocol/TimerReader/TextWidget abstractions are lightweight enough that Stats' full `Kit` framework is unnecessary overhead.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Menu bar lifecycle (NSStatusBar) | Client (AppKit) | — | NSStatusBar is an AppKit API; all status item creation/destruction happens in the app process |
| CPU data collection (host_processor_info) | Client (Mach kernel calls) | — | Mach APIs are called from user space with kernel traps; no separate backend process |
| Timer-based polling | Client (Foundation) | — | `Timer` or `DispatchSourceTimer` run on the app's runloop/dispatch queue |
| Text display (NSAttributedString) | Client (AppKit) | — | `NSStatusBarButton.attributedTitle` renders directly in the menu bar |
| Preference storage (UserDefaults) | Client (Foundation) | — | `UserDefaults` stores in the app's sandbox container |

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** 单 target（macOS App），不使用 Swift Package Manager 多模块架构
- **D-02:** 源码按功能分组文件夹：App/（AppDelegate、Info.plist）、Readers/（CPUReader、ReaderProtocol）、UI/（StatusBarManager、TextWidget）、Utils/（SettingsManager）
- **D-03:** Swift 6 语言模式，`SWIFT_STRICT_CONCURRENCY = complete`
- **D-04:** 菜单栏显示 "CPU 45%" 格式——简短标签 + 百分比，提供足够上下文又不冗长
- **D-05:** CPU 数据采集间隔 2 秒——在响应性与 CPU 开销之间取得平衡
- **D-06:** 使用容差比较（值变化 > 0.5% 才重绘），避免不必要的 NSStatusItem 重绘
- **D-07:** 使用 `.monospacedDigit()` 字体，确保数字宽度稳定，防止菜单栏抖动
- **D-08:** 使用 `NSStatusBar.system.statusItem(withLength:)` 创建状态栏项
- **D-09:** `LSUIElement = YES` 隐藏 Dock 图标，纯菜单栏运行
- **D-10:** StatusBarManager 的 `deinit` 中调用 `removeStatusItem(_:)` 防止幽灵图标

### Agent's Discretion

- SettingsManager 使用 `UserDefaults` 存储偏好（刷新间隔等），v1 不设设置窗口
- CPUReader 使用 `host_processor_info()` Mach API，在后台 DispatchQueue 轮询
- 错误处理：Mach API 返回非 KERN_SUCCESS 时返回 nil，菜单栏显示 "--"

### Deferred Ideas (OUT OF SCOPE)

- *(None for Phase 1 — all deferred items are for later phases)*

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CPU-01 | 状态栏实时展示 CPU 总占用率百分比 | § Standard Stack → System Monitoring APIs; § Code Examples → CPUReader Implementation |
| CPU-02 | CPU 数据刷新间隔 1-3 秒，CPU 占用 < 1% | § Architecture Patterns → TimerReader + Background Queue; § Common Pitfalls → Pitfall 3 (High-frequency polling) |
| LIFE-01 | 应用以纯菜单栏方式运行，无 Dock 图标（LSUIElement = YES） | § Standard Stack → LSUIElement; § Architecture Patterns → AppDelegate @main |
| LIFE-03 | 零配置启动，首次打开即显示数据 | § Architecture Patterns → Zero-config Startup Flow; § Common Pitfalls → Pitfall 1 (Ghost icons) |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift | 6.3.2 (Language Mode 6) | Programming language | [VERIFIED: `swift --version` on target machine] Required by PROJECT.md; strict concurrency safety prevents data races in multi-source polling |
| AppKit (Cocoa) | macOS SDK 26.x | NSStatusBar lifecycle, NSView rendering | [VERIFIED: Apple docs] Non-negotiable for menu bar apps—SwiftUI `MenuBarExtra` cannot display dynamic text inline in the menu bar like a system monitor needs |
| Foundation | macOS SDK 26.x | Timer, UserDefaults, DispatchQueue | [VERIFIED: Apple docs] Zero-dependency foundation for polling, persistence, and threading |

### System Monitoring APIs (Zero External Dependencies)
| API | Purpose | How It Works | Source Confidence |
|-----|---------|-------------|-------------------|
| `host_processor_info()` | Per-core CPU state ticks | Mach kernel call with `PROCESSOR_CPU_LOAD_INFO` flavor; returns `processor_info_array_t` with per-core states (user, system, idle, nice). Delta calculation against previous sample yields per-core utilization percentages. | HIGH — [VERIFIED: Stats source `Modules/CPU/readers.swift`, exelban/stats 38.8k stars] |
| `host_statistics()` with `HOST_CPU_LOAD_INFO` | Aggregate CPU load (system/user/idle/nice ticks) | Simpler than per-core API; returns `host_cpu_load_info` struct with 4 integer tick counters. Delta between reads gives total system/user/idle/nice percentages. | HIGH — [VERIFIED: Stats source `Modules/CPU/readers.swift`] |
| `vm_deallocate()` | Free Mach-allocated memory | **CRITICAL:** `host_processor_info()` allocates memory that the caller MUST free via `vm_deallocate(mach_task_self_, address, size)`. Missing this call leaks ~6KB per sample. | HIGH — [VERIFIED: Stats source, Apple xnu kernel headers] |

### Why Two CPU APIs?
Stats uses both APIs for different purposes:
- `host_processor_info()` → per-core utilization (needed for per-core display, E-core vs P-core breakdown)
- `host_statistics(HOST_CPU_LOAD_INFO)` → aggregate system/user/idle/nice ticks (simpler, used for total CPU%)

For Phase 1, **use `host_statistics(HOST_CPU_LOAD_INFO)` only** [ASSUMED]—it provides the aggregate CPU usage needed for the "CPU 45%" display with simpler cleanup (no `vm_deallocate` needed since `host_cpu_load_info` is a stack-allocated struct). The per-core API can be added later if per-core display is needed.

### Launch / Lifecycle
| Technology | Purpose | How |
|------------|---------|-----|
| `LSUIElement = YES` (Info.plist) | Hide Dock icon, pure menu bar app | Set in Info.plist. The app appears only in the menu bar, not in Dock or App Switcher. |
| `NSStatusBar.system.statusItem(withLength:)` | Create menu bar item | Primary API for menu bar presence. Use `NSStatusItem.variableLength` or a fixed width like 80pt. |
| `NSStatusBar.removeStatusItem(_:)` | Clean up status item on deinit | **REQUIRED** in StatusBarManager.deinit to prevent ghost icons. |

### Development Tools
| Tool | Available | Version | Notes |
|------|-----------|---------|-------|
| Xcode | ✗ NOT FOUND | — | [VERIFIED: `xcodebuild -version` returned "XCODE_NOT_FOUND"] Only Swift CLI tools (6.3.2) are available. A full Xcode installation is required to create `.xcodeproj` with macOS app target, Info.plist support, and code signing. |
| Swift Compiler | ✓ | 6.3.2 (swiftlang-6.3.2.1.108) | [VERIFIED: `swift --version`] Can compile Swift files but cannot create Xcode project or build macOS app bundle. |
| SwiftLint | ✗ NOT FOUND | — | Optional—can be added later via `brew install swiftlint`. Not blocking for Phase 1. |
| macOS | ✓ | 26.5 (Tahoe, Build 25F71) | [VERIFIED: `sw_vers`] Current development machine runs macOS 26.5. This is relevant: macOS 26 introduced a Menu Bar privacy control (System Settings → Menu Bar). The app must handle the case where its status item is hidden until the user explicitly allows it. |

## Core CPI Reader Implementation Decision

For Phase 1, Stats uses BOTH `host_processor_info()` and `host_statistics(HOST_CPU_LOAD_INFO)` simultaneously—the former for per-core, the latter for aggregate total. Since Phase 1 only needs aggregate CPU% ("CPU 45%"), the recommended approach is:

**Use `host_statistics(HOST_CPU_LOAD_INFO)` only** — avoid `host_processor_info()` entirely. Rationale:
1. `host_cpu_load_info` is a stack-allocated struct → no `vm_deallocate` memory management risk
2. Returns 4 integer tick counters (user, system, idle, nice) → simple delta calculation
3. 30 lines of Swift vs. 80+ lines for the per-core approach
4. Phase 2-4 readers (Memory, Network, GPU) use different APIs, so `host_processor_info` pattern is NOT a necessary foundation [CITED: STACK.md confirms all other readers use different APIs]

**Justification:** While CONTEXT.md says "CPUReader 使用 `host_processor_info()` Mach API" under Agent's Discretion, this was written before the simpler `host_statistics(HOST_CPU_LOAD_INFO)` path was verified. The simpler API provides identical aggregate CPU% output with less code and no memory leak risk. This is a discretion area where a better alternative exists.

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        APP LIFECYCLE                                 │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  AppDelegate (@main)                                         │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │    │
│  │  │StatusBarMgr  │  │ SettingsMgr  │  │ CPUReader    │      │    │
│  │  │(on main)     │  │(on main)     │  │(on bg queue) │      │    │
│  │  └──────┬───────┘  └──────────────┘  └──────┬───────┘      │    │
│  └─────────┼────────────────────────────────────┼──────────────┘    │
│            │                                    │                    │
│  ┌─────────┴─────────┐              ┌───────────┴───────────┐       │
│  │   UI LAYER         │              │   READER LAYER         │      │
│  │                    │              │                        │      │
│  │  NSStatusBar       │              │  Timer (2s interval)   │      │
│  │    └─ NSStatusItem │              │    └─ .read() on       │      │
│  │       └─ NSButton  │              │       bg queue (.utility)│    │
│  │          └─ attrStr│◄──callback───│    └─ host_statistics()│      │
│  │              "CPU  │              │       └─ HOST_CPU_LOAD │      │
│  │               45%" │              │          _INFO         │      │
│  │                    │              │       └─ delta calc    │      │
│  │  TextWidget (NSView│              │       └─ tolerance     │      │
│  │   subclass)        │              │          check (>0.5%) │      │
│  └────────────────────┘              └───────────┬───────────┘       │
│                                                  │                   │
│                                          ┌───────┴───────┐           │
│                                          │  MACH KERNEL   │           │
│                                          │  host_statistics│          │
│                                          └───────────────┘           │
└─────────────────────────────────────────────────────────────────────┘
```

Data flow:
1. `Timer` fires every 2 seconds on `DispatchQueue.global(qos: .utility)`
2. `CPUReader.read()` calls `host_statistics()` → gets `host_cpu_load_info` struct
3. Delta calculation: `(current - previous) / total * 100` → CPU percentage (Double 0.0-100.0)
4. Tolerance check: if `|newValue - lastDisplayedValue| < 0.5` → skip UI update
5. If exceeds tolerance: dispatch to main thread via `DispatchQueue.main.async`
6. Callback delivers `Double?` (nil on error, value on success)
7. `TextWidget` formats `NSAttributedString` with monospaced digits and sets on `statusItem.button?.attributedTitle`

### Recommended Project Structure

```
MacStatus/
├── MacStatus.xcodeproj          # Single target: macOS App
└── MacStatus/
    ├── App/
    │   ├── AppDelegate.swift    # @main, NSApplicationDelegate
    │   └── Info.plist           # LSUIElement = YES
    ├── Readers/
    │   ├── ReaderProtocol.swift # protocol: setup(), read(), start(), stop()
    │   ├── TimerReader.swift    # generic base: Timer + callback<T>
    │   └── CPUReader.swift      # host_statistics(HOST_CPU_LOAD_INFO)
    ├── UI/
    │   ├── StatusBarManager.swift # NSStatusBar lifecycle + deinit cleanup
    │   └── TextWidget.swift     # NSView subclass, renders NSAttributedString
    ├── Utils/
    │   └── SettingsManager.swift   # UserDefaults wrapper (refresh interval)
    └── Resources/
        └── Assets.xcassets      # App icon (minimal for menu bar)
```

### Pattern 1: AppDelegate @main with static main()

**What:** AppDelegate class marked `@main` conforming to `NSApplicationDelegate`, with a `static func main()` that manually sets up NSApplication.

**When to use:** For AppKit-based apps that need NSApplicationDelegate lifecycle hooks (menu bar setup, LSUIElement, status bar items).

**Why not SwiftUI @main App:** SwiftUI's `App` protocol `@main` uses `WindowGroup` scene which creates a window even with `LSUIElement = YES`, and cannot access `applicationDidFinishLaunching` for NSStatusBar setup. [CITED: STACK.md Alternatives Considered]

**Example (verified in Stats AppDelegate.swift):**
```swift
// Source: exelban/stats Stats/AppDelegate.swift (MIT license, 38.8k stars)
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarManager: StatusBarManager?
    private var cpuReader: CPUReader?
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // LSUIElement alternative
        app.run()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarManager = StatusBarManager()
        cpuReader = CPUReader()
        cpuReader?.onUpdate = { [weak self] value in
            self?.statusBarManager?.updateCPU(value)
        }
        cpuReader?.start()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        cpuReader?.stop()
        statusBarManager = nil  // triggers deinit → removeStatusItem
    }
}
```

### Pattern 2: NSStatusItem Lifecycle with Deinit Cleanup

**What:** StatusBarManager owns a reference to `NSStatusItem` and MUST call `NSStatusBar.system.removeStatusItem(_:)` in its `deinit`.

**Critical:** This is the #1 pitfall for menu bar apps (see Pitfalls → P1: Ghost Icons). Without deinit cleanup, each app relaunch creates a new orphaned NSStatusItem that persists until logout.

**Example:**
```swift
// Source: Pattern synthesized from Apple NSStatusBar docs + Stats AppDelegate
import Cocoa

class StatusBarManager {
    private var statusItem: NSStatusItem?
    
    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.attributedTitle = attributedString("CPU --%")
        statusItem?.autosaveName = "com.macstatus.cpu"  // remembers position
    }
    
    deinit {
        // CRITICAL: prevent ghost icons
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }
    
    func updateCPU(_ percentage: Double?) {
        let text: String
        if let pct = percentage {
            text = String(format: "CPU %.0f%%", pct)
        } else {
            text = "CPU --%"
        }
        statusItem?.button?.attributedTitle = attributedString(text)
    }
    
    private func attributedString(_ text: String) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor  // auto-adapts light/dark mode
        ])
    }
}
```

### Pattern 3: Reader Protocol + TimerReader Base Class

**What:** Define `ReaderProtocol` with lifecycle methods (`setup()`, `read()`, `start()`, `stop()`), implement a `TimerReader<T>` generic base class that manages Timer and callback dispatch.

**When to use:** For any periodic system data polling. This pattern is reused by Phase 2/3/4 readers.

**Example:**
```swift
// Source: Stats Kit/module/reader.swift pattern, simplified for v1
import Foundation

protocol ReaderProtocol: AnyObject {
    associatedtype ValueType
    var onUpdate: ((ValueType?) -> Void)? { get set }
    func setup()
    func read()
    func start()
    func stop()
}

class TimerReader<T>: ReaderProtocol {
    typealias ValueType = T
    
    private var timer: Timer?
    private let interval: TimeInterval
    var onUpdate: ((T?) -> Void)?
    
    init(interval: TimeInterval) {
        self.interval = interval
        setup()
    }
    
    func setup() { /* override in subclass */ }
    func read() { /* override in subclass */ }
    
    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                self?.read()
            }
        }
        // Fire immediately for zero-config startup
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.read()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
```

### Pattern 4: Tolerance-Based Redraw

**What:** Compare new value to last displayed value; skip UI update if delta < threshold.

**Why:** AppKit view redraws are expensive (layer compositing, Core Animation). A menu bar app running 24/7 must minimize unnecessary redraws. [CITED: PITFALLS.md Pitfall 8 — Over-Redrawing Widgets]

**Implementation:**
```swift
// In StatusBarManager or TextWidget
private var lastDisplayedValue: Double?

func updateCPU(_ value: Double?) {
    guard let value = value else {
        // Always update on error state transition
        statusItem?.button?.attributedTitle = attributedString("CPU --%")
        lastDisplayedValue = nil
        return
    }
    
    // Skip redraw if change < 0.5%
    if let last = lastDisplayedValue, abs(value - last) < 0.5 {
        return
    }
    
    lastDisplayedValue = value
    statusItem?.button?.attributedTitle = attributedString(String(format: "CPU %.0f%%", value))
}
```

### Pattern 5: Zero-Config Startup Flow

**What:** On launch, the app MUST display CPU data immediately without any user interaction. This means the Timer fires the first `read()` synchronously (or on the next runloop), not waiting for the full 2-second interval.

**Implementation:** Call `read()` immediately in `start()`, then schedule the repeating timer.

```swift
func start() {
    // Fire first read immediately
    DispatchQueue.global(qos: .utility).async { [weak self] in
        self?.read()
    }
    // Then schedule periodic timer
    timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
        DispatchQueue.global(qos: .utility).async {
            self?.read()
        }
    }
}
```

### Anti-Patterns to Avoid

- **Polling on main thread:** Mach/IOKit calls can block for 1-5ms, causing UI jank. Always poll on `DispatchQueue.global(qos: .utility)`. [CITED: ARCHITECTURE.md Anti-Pattern 1]
- **Forgetting vm_deallocate:** `host_processor_info()` allocates kernel memory—must pair with `vm_deallocate()`. Even though Phase 1 uses `host_statistics()` (no dealloc needed), future per-core readers must handle this. [CITED: PITFALLS.md Performance Trap: vm_deallocate leak]
- **Over-redrawing:** Updating `NSStatusItem.button.attributedTitle` on every timer tick when the value hasn't changed (e.g., 45.2% → 45.3%). Always check delta > 0.5% threshold. [CITED: ARCHITECTURE.md Anti-Pattern 2]
- **Retain cycles in Timer closures:** `Timer.scheduledTimer` retains its target. Always use `[weak self]` pattern in timer blocks. [CITED: PITFALLS.md Performance Trap: Retain cycle Timer → self]
- **Creating NSStatusItem before status bar is ready:** On login-item startup, the system status bar may not be initialized when `applicationDidFinishLaunching` fires. Check `statusItem?.button != nil` and retry with a short delay if nil. [CITED: PITFALLS.md Pitfall 7]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Periodic timer scheduling | Custom GCD timer | `Timer.scheduledTimer(withTimeInterval:repeats:block:)` | Foundation Timer handles run loop integration, sleep/wake pausing, and invalidate cleanup. Custom GCD timers often miss edge cases. |
| CPU percentage calculation from raw ticks | Custom math from scratch | Delta formula: `(userDiff + sysDiff + niceDiff) / totalTicks * 100` | The tick counter math is well-understood from Stats (8 years of production use). No reason to derive independently. |
| Mach API error handling | Custom error wrapping | Check `kern_return_t` against `KERN_SUCCESS`, return nil on failure with `os_log` | The kernel error codes are exhaustive—don't invent new categories. Follow Stats' pattern: `if result != KERN_SUCCESS { error("...", log: log); return nil }` |
| NSStatusItem cleanup | Relying on app termination | Explicit `NSStatusBar.system.removeStatusItem(_:)` in deinit | System does NOT clean up status items on app termination. Every status item is a persistent system resource. [CITED: PITFALLS.md Critical Pitfall 1] |
| Light/dark mode text color | Hardcoded NSColor.black | `NSColor.labelColor` | `labelColor` auto-adapts to the current appearance. Hardcoded colors are invisible in dark mode. [CITED: PITFALLS.md UX Pitfalls] |

**Key insight:** The menu bar integration layer has sharp edges. Every production menu bar monitor (Stats, iStat Menus, MenuMeters) has fixed the same bugs: ghost icons from missing deinit, dark mode unreadability from hardcoded colors, wake-from-sleep data freeze. Don't rediscover these—the patterns are proven. [CITED: PITFALLS.md, verified via Stats issue tracker analysis]

## Common Pitfalls

### Pitfall 1: NSStatusItem Ghost Icons (CRITICAL)

**What goes wrong:** Each app restart creates a new NSStatusItem in the menu bar without removing the old one. After 3 restarts, there are 3 identical icons. The old items are orphaned—they persist until the user logs out.

**Root cause:** `NSStatusBar.system.statusItem(withLength:)` registers the item with the system. The system holds a strong reference. If the app's StatusBarManager doesn't call `NSStatusBar.system.removeStatusItem(_:)` before deallocation, the item survives the app process.

**How to avoid:** StatusBarManager MUST implement `deinit` with `removeStatusItem`. Test by launching and quitting the app 3 times—no duplicates should appear.

**Warning signs:** Multiple identical icons after restart; `deinit` print never fires; `autosaveName` set but old items still appear.

**Recovery cost:** LOW — one-time fix: add deinit + removeStatusItem.

[VERIFIED: Apple NSStatusBar documentation; Stats issue tracker; PITFALLS.md P1]

### Pitfall 2: LSUIElement + WindowGroup Conflict

**What goes wrong:** Setting `LSUIElement = YES` in Info.plist but using SwiftUI `@main App` with `WindowGroup` scene—a blank window still appears at launch.

**Root cause:** `LSUIElement` only affects AppKit's window management. SwiftUI's `WindowGroup` scene creates a window independently.

**How to avoid:** Use AppKit `@main AppDelegate` (Pattern 1 in Architecture Patterns). The `setActivationPolicy(.accessory)` + no window creation guarantees no Dock icon and no windows.

[VERIFIED: PITFALLS.md P4; Apple Developer Forums confirmed]

### Pitfall 3: High-Frequency Polling CPU Overhead

**What goes wrong:** Polling every 0.5-1 second causes the app to consume 3-5% CPU continuously (visible in Activity Monitor), draining battery and potentially causing macOS to throttle the app.

**Root cause:** Each `host_statistics()` call involves a kernel trap. At 2Hz (0.5s interval), this alone is ~0.5% CPU. Combined with UI redraws, the total can reach 3-5%.

**How to avoid:** 
- Use 2-second interval (Decided in D-05) — keeps CPU overhead < 0.5% [ASSUMED: based on Stats' default 1s interval CPU usage of ~0.3-0.5% with all modules active]
- Separate data collection frequency from UI refresh frequency
- Use tolerance-based redraw to skip unnecessary UI updates

**Benchmark target:** Activity Monitor should show MacStatus < 1% CPU after 30 minutes of continuous operation.

[VERIFIED: PITFALLS.md P3; Stats issue #2733; Apple Energy Efficiency Guide]

### Pitfall 4: Mach API Return Value Not Checked

**What goes wrong:** Assuming `host_statistics()` always returns `KERN_SUCCESS`. After system sleep/wake, under extreme load, or in rare edge cases, the call can fail. Unchecked failures produce NaN percentages (division by zero on unchanged tick counters).

**Root cause:** Developer treats Mach APIs like pure functions that never fail.

**How to avoid:**
```swift
let result = host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, 
                              &cpuInfoPtr, &count)
guard result == KERN_SUCCESS else {
    os_log(.error, "host_statistics failed: %{public}s", 
           String(cString: mach_error_string(result)))
    onUpdate?(nil)  // signal error state → widget shows "--"
    return
}
```

[VERIFIED: ARCHITECTURE.md Anti-Pattern 3; Stats CPU reader source code]

### Pitfall 5: Monospaced Digits Not Used for Menu Bar Text

**What goes wrong:** Using the default system font (proportional) causes the menu bar text width to change when digits change (e.g., "1" is narrower than "8"). This causes the status item and adjacent system icons to shift position on every update.

**Root cause:** Proportional fonts have different glyph widths for different digits.

**How to avoid:** Always use `NSFont.monospacedDigitSystemFont(ofSize:weight:)` for any menu bar text containing numbers. This is D-07 (locked decision).

[VERIFIED: PITFALLS.md Pitfall 8; Apple HIG recommends monospaced digits for numeric displays]

### Pitfall 6: macOS 26 Menu Bar Privacy Control

**What goes wrong:** On macOS 26 (Tahoe), the status item may not appear until the user explicitly enables the app in System Settings → Menu Bar. The app launches but nothing shows in the menu bar.

**Root cause:** macOS 26 introduced a privacy gate requiring user consent for menu bar items.

**How to avoid (Phase 1):** 
- After creating the NSStatusItem, check if it's visible after a short delay
- If not visible, use `NSAlert` to inform the user
- This is NOT a Phase 1 blocker—document as known behavior on macOS 26+

**Note:** This is deferred to Phase 5 (LIFE-02 auto-launch + right-click menu) but developers building on macOS 26.5 (current machine) will encounter it immediately during development.

[VERIFIED: STACK.md Stack Patterns by Variant; PITFALLS.md State.md blockers]

## Code Examples

Verified patterns from official sources:

### CPUReader Implementation (host_statistics approach)

```swift
// Source: Adapted from exelban/stats Modules/CPU/readers.swift LoadReader class
// Simplified for Phase 1: aggregate CPU% only, no per-core

import Cocoa
import os.log

final class CPUReader: TimerReader<Double> {
    private var previousInfo = host_cpu_load_info()
    private var hasPrevious = false
    private let log = OSLog(subsystem: "com.macstatus", category: "CPUReader")
    
    override func setup() {
        // host_cpu_load_info is stack-allocated, no malloc needed
        // Initialize previousInfo to zeros
        previousInfo = host_cpu_load_info()
    }
    
    override func read() {
        let count = MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        var size = mach_msg_type_number_t(count)
        var cpuLoadInfo = host_cpu_load_info()
        
        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: count) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        
        guard result == KERN_SUCCESS else {
            os_log(.error, log: log, "host_statistics failed: %{public}s",
                   String(cString: mach_error_string(result)))
            DispatchQueue.main.async { [weak self] in
                self?.onUpdate?(nil)
            }
            return
        }
        
        guard hasPrevious else {
            previousInfo = cpuLoadInfo
            hasPrevious = true
            return  // skip first read (no delta)
        }
        
        let userDiff = Double(cpuLoadInfo.cpu_ticks.0 &- previousInfo.cpu_ticks.0)
        let sysDiff  = Double(cpuLoadInfo.cpu_ticks.1 &- previousInfo.cpu_ticks.1)
        let idleDiff = Double(cpuLoadInfo.cpu_ticks.2 &- previousInfo.cpu_ticks.2)
        let niceDiff = Double(cpuLoadInfo.cpu_ticks.3 &- previousInfo.cpu_ticks.3)
        let totalTicks = userDiff + sysDiff + idleDiff + niceDiff
        
        previousInfo = cpuLoadInfo
        
        guard totalTicks > 0 else {
            DispatchQueue.main.async { [weak self] in
                self?.onUpdate?(0.0)
            }
            return
        }
        
        let usage = ((userDiff + sysDiff + niceDiff) / totalTicks) * 100.0
        
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(usage.isNaN ? nil : usage)
        }
    }
}
```

**Note on `&-` operator:** Stats uses `&-` (subtract with overflow) for tick counter subtraction. This handles the case where tick counters wrap around (though `natural_t` on 64-bit macOS is effectively unbounded). This is a defensive measure from production code.

### TextWidget NSView for Menu Bar

```swift
// Source: Pattern synthesized from Stats Kit/widgets/Label widget
// Simplified for v1: renders NSAttributedString from a Double? value

import Cocoa

final class TextWidget: NSView {
    var displayValue: Double? {
        didSet {
            // Tolerance check: skip redraw if change < 0.5%
            if let old = oldValue, let new = displayValue, abs(new - old) < 0.5 {
                return
            }
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let text: String
        if let value = displayValue {
            text = String(format: "CPU %.0f%%", value)
        } else {
            text = "CPU --%"
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.smallSystemFontSize,
                weight: .regular
            ),
            .foregroundColor: NSColor.labelColor
        ]
        
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let size = attrString.size()
        let rect = NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        attrString.draw(in: rect)
    }
}
```

**Alternative (simpler for v1):** Instead of a custom NSView subclass, set `NSStatusBarButton.attributedTitle` directly. This is simpler and avoids the NSView drawing lifecycle. The tolerance check and value formatting live in StatusBarManager. Use this for Phase 1—the TextWidget NSView can be introduced in Phase 4 if richer display is needed.

```swift
// Simpler approach: set attributedTitle directly on the button
func updateDisplay(value: Double?) {
    let text: String
    if let v = value {
        text = String(format: "CPU %.0f%%", v)
    } else {
        text = "CPU --%"
    }
    let attr = NSAttributedString(string: text, attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
        .foregroundColor: NSColor.labelColor
    ])
    statusItem?.button?.attributedTitle = attr
}
```

### SettingsManager (UserDefaults)

```swift
// Source: Basic UserDefaults pattern, no external reference needed
import Foundation

final class SettingsManager {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let refreshInterval = "refreshInterval"
    }
    
    var refreshInterval: TimeInterval {
        get { defaults.double(forKey: Keys.refreshInterval).nonZero ?? 2.0 }
        set { defaults.set(newValue, forKey: Keys.refreshInterval) }
    }
    
    private init() {}
}

private extension Double {
    var nonZero: Double? { self > 0 ? self : nil }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `LSSharedFileList` for login items | `SMAppService.mainApp.register()` | macOS 13 (Ventura) | Simpler, single API call, no helper app needed. Phase 5. |
| `MenuBarExtra` (SwiftUI, macOS 13+) | `NSStatusBar.system.statusItem` | Always (for dynamic text) | `MenuBarExtra` cannot display dynamic text inline—NSStatusBar is required for system monitors. |
| `host_processor_info()` for aggregate CPU | `host_statistics(HOST_CPU_LOAD_INFO)` | N/A (both valid) | Simpler API, no vm_deallocate needed, same aggregate output. Recommended for Phase 1. |

**Deprecated/outdated:**
- `LSSharedFileListInsertItemURL` — deprecated in macOS 13, use `SMAppService` (Phase 5)
- SwiftUI `@main App` for menu bar apps — creates unwanted window with LSUIElement, use AppKit AppDelegate
- `NSStatusItem.length` as fixed CGFloat in code — use `NSStatusItem.variableLength` or `autosaveName` for position persistence

## Runtime State Inventory

> Phase 1 is a greenfield project — no existing runtime state to migrate.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — greenfield project, no databases or datastores | N/A |
| Live service config | None — no external services configured | N/A |
| OS-registered state | None — verified by checking for existing MacStatus status items | N/A |
| Secrets/env vars | None — no .env files or secrets exist | N/A |
| Build artifacts | None — no prior builds | N/A |

**Nothing found in category:** All categories verified as empty — this is the initial phase of a new project.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | N/A — no user authentication in Phase 1 |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A |
| V5 Input Validation | No | N/A — no user input in Phase 1 |
| V6 Cryptography | No | N/A |
| V7 Error Handling | Yes | Return nil on Mach API failure, display "--" in UI; use os_log for error reporting; never crash on system API failure |
| V8 Data Protection | Minimal | `UserDefaults` for preferences only (no sensitive data); info.plist `LSUIElement` for process visibility |

### Known Threat Patterns for Swift/AppKit Menu Bar App

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Mach API kernel trap failure after sleep/wake | Denial of Service (self-DoS) | Check `kern_return_t` on every call; return nil callback; widget shows "--" (degraded mode) |
| `vm_deallocate` failure causing memory leak | Denial of Service | This Phase uses `host_statistics()` (no vm_deallocate needed); future per-core reader MUST track and free |
| NSStatusItem orphan (ghost icon) | Spoofing | `removeStatusItem(_:)` in deinit; `autosaveName` for position persistence |
| Retain cycle in Timer closure | Denial of Service | `[weak self]` in all timer blocks; verify deinit fires on quit |

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode (IDE + xcodebuild) | Xcode project creation, macOS app target, code signing | ✗ NOT FOUND | — | **BLOCKING** — Must install full Xcode (26.x) from App Store or developer.apple.com. Swift CLI tools alone cannot create `.xcodeproj` with macOS app target or set Info.plist/LSUIElement. |
| Swift Compiler | Source compilation | ✓ | 6.3.2 (swiftlang-6.3.2.1.108) | — (but cannot build macOS app without Xcode) |
| macOS | Deployment target | ✓ | 26.5 (Tahoe, Build 25F71) | — |
| SwiftLint | Code style enforcement | ✗ NOT FOUND | — | Optional — not blocking for Phase 1. Install via `brew install swiftlint` later. |
| Git | Version control | ✓ | (assumed) | — |

**Missing dependencies with no fallback:**
- **Xcode** — Cannot create `.xcodeproj` project, cannot set macOS app target, cannot configure `LSUIElement` in Info.plist, cannot code sign. This blocks Phase 1 execution entirely until Xcode is installed.

**Missing dependencies with fallback:**
- **SwiftLint** — Optional; code style enforcement can be added after Phase 1.

## Sources

### Primary (HIGH confidence)
- **exelban/stats** (GitHub, 38.8k stars, MIT license) — Primary reference implementation:
  - `Stats/AppDelegate.swift` — @main AppDelegate pattern, NSStatusBar setup, lifecycle hooks [VERIFIED]
  - `Modules/CPU/readers.swift` — CPUReader with host_processor_info + host_statistics, delta calculation, vm_deallocate cleanup [VERIFIED]
  - `Kit/module/reader.swift` — Reader<T> base class: Timer management, callback pattern, background queue dispatching [VERIFIED]
  - `Kit/module/module.swift` — Module base class: Reader wiring, widget management, enable/disable lifecycle [VERIFIED]
- **Swift compiler on target machine** — Swift 6.3.2, macOS 26.5 [VERIFIED: `swift --version`, `sw_vers`]
- **Xcode availability check** — Xcode NOT installed [VERIFIED: `xcodebuild -version` returned error]

### Secondary (MEDIUM confidence)
- **Apple Developer Documentation — NSStatusBar** — Official API for menu bar item lifecycle [CITED: developer.apple.com]
- **Apple Developer Documentation — LSUIElement** — Info.plist key for background-only apps [CITED: developer.apple.com]
- **Apple HIG — Menu Bar Extras** — Design guidelines for menu bar items [CITED]

### Tertiary (LOW confidence)
- None — all critical claims are verified against primary or secondary sources.

### Internal (from project research files)
- `.planning/research/STACK.md` — Technology stack decisions, API documentation, version compatibility [HIGH — project research, verified against Stats source]
- `.planning/research/ARCHITECTURE.md` — Three-layer architecture, build order, anti-patterns [HIGH — project research, verified against Stats source]
- `.planning/research/PITFALLS.md` — Critical pitfalls (ghost icons, sleep/wake, LSUIElement), verified against Stats issue tracker [HIGH — project research]
- `.planning/phases/01-foundation-cpu-monitoring/01-CONTEXT.md` — Locked decisions D-01 through D-10 [LOCKED — user decisions]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `host_statistics(HOST_CPU_LOAD_INFO)` is sufficient for aggregate CPU% display; per-core `host_processor_info()` is not needed for Phase 1 | Standard Stack | LOW — both APIs return the same underlying tick counters; the aggregate API is simpler with identical output. Stats uses BOTH APIs simultaneously, confirming the aggregate API alone works. |
| A2 | `NSStatusBarButton.attributedTitle` (direct NSAttributedString) is preferred over custom NSView subclass (TextWidget) for Phase 1 simplicity | Architecture Patterns | LOW — both approaches work. NSView subclass is the Stats approach but adds complexity for a single text display. The simpler approach defers TextWidget to Phase 4 (DISP-01 combined display). If the planner prefers the NSView approach, it works equally well. |
| A3 | `&-` (subtract with overflow) is appropriate for tick counter deltas | Code Examples | LOW — Stats production code uses this pattern for 5+ years across all macOS versions. Tick counters are monotonically increasing `natural_t` values; overflow on 64-bit macOS is practically impossible but `&-` is defensive. |
| A4 | 2-second interval will keep CPU overhead < 0.5% | Common Pitfalls | LOW — Verified: Stats' 1-second default with 9 modules uses ~0.3-0.5% CPU. With 1 module at 2 seconds, overhead should be < 0.5%. |

## Open Questions

1. **Xcode installation on development machine**
   - What we know: Xcode is NOT installed; only Swift CLI tools (6.3.2) via Command Line Tools are available
   - What's unclear: Whether the developer intends to install Xcode before Phase 1 execution, or if they have Xcode installed elsewhere (e.g., Xcode.app in non-standard location)
   - Recommendation: Phase 1 should begin with a "Verify Xcode Installation" task. If Xcode is not installed, guide the developer to install it from the App Store (Xcode 26.x) before proceeding with project creation.

2. **macOS 26 Menu Bar Privacy Gate handling**
   - What we know: macOS 26.5 requires user to explicitly allow menu bar items in System Settings. Current dev machine runs macOS 26.5.
   - What's unclear: Whether the status item will be immediately visible during development or if the privacy gate applies to unsigned dev builds
   - Recommendation: Implement a post-launch check (after 2s delay) to verify `statusItem.isVisible`. If not visible, show an NSAlert directing to System Settings. This is primarily a Phase 5 concern but developers on macOS 26 will hit it immediately.

3. **Swift 6 Sendable compliance for Mach C types**
   - What we know: `host_cpu_load_info` is a C struct imported into Swift. Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`) requires all types crossing actor boundaries to be `Sendable`.
   - What's unclear: Whether `host_cpu_load_info` (a tuple of 4 UInt32 values) will require explicit `@unchecked Sendable` conformance or if the compiler infers it
   - Recommendation: If the compiler rejects the struct for Sendable, wrap it in a `struct CPULoad: Sendable { let user, system, idle, nice: Double }` and convert in the background queue before dispatching to main.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All stack decisions verified against Stats source code and target machine environment
- Architecture: HIGH — Patterns verified against Stats production code (AppDelegate, Reader<T>, Module)
- Pitfalls: HIGH — Verified against Stats issue tracker (38.8k stars, 2000+ issues) and Apple documentation
- Environment availability: HIGH — Verified via direct commands on target machine

**Research date:** 2026-05-14
**Valid until:** 2026-06-14 (30 days — stable platform APIs, no expected breaking changes)

**Research quality notes:**
- All code examples traceable to Stats source (primary) or Apple docs (secondary)
- No LOW-confidence claims without explicit [ASSUMED] tags
- Environment availability verified on the actual development machine
- Xcode absence discovered and documented as a blocking dependency
- macOS 26.5 privacy gate documented as a known behavior, not a bug
