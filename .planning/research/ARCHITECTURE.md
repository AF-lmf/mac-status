# Architecture Research

**Domain:** macOS Menu Bar System Monitor  
**Researched:** 2026-05-14  
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PRESENTATION LAYER                              │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐   │
│  │ NSStatusItem │ │ NSStatusItem │ │ NSStatusItem │ │ NSStatusItem │   │
│  │   (CPU)      │ │   (GPU)      │ │   (Memory)   │ │  (Network)   │   │
│  │  ┌────────┐  │ │  ┌────────┐  │ │  ┌────────┐  │ │  ┌────────┐  │   │
│  │  │Widget  │  │ │  │Widget  │  │ │  │Widget  │  │ │  │Widget  │  │   │
│  │  │ View   │  │ │  │ View   │  │ │  │ View   │  │ │  │ View   │  │   │
│  │  └────────┘  │ │  └────────┘  │ │  └────────┘  │ │  └────────┘  │   │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘ └──────┬───────┘   │
│         │                │                │                │           │
├─────────┴────────────────┴────────────────┴────────────────┴───────────┤
│                         MODULE LAYER                                    │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐   │
│  │ CPUModule    │ │ GPUModule    │ │ MemModule    │ │ NetModule    │   │
│  │ ───────────  │ │ ───────────  │ │ ───────────  │ │ ───────────  │   │
│  │  coord:      │ │  coord:      │ │  coord:      │ │  coord:      │   │
│  │  reader→view │ │  reader→view │ │  reader→view │ │  reader→view │   │
│  │  state mgmt  │ │  state mgmt  │ │  state mgmt  │ │  state mgmt  │   │
│  │  settings    │ │  settings    │ │  settings    │ │  settings    │   │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘ └──────┬───────┘   │
│         │                │                │                │           │
├─────────┴────────────────┴────────────────┴────────────────┴───────────┤
│                         READER LAYER                                    │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐   │
│  │ CPULoad      │ │ GPUUsage     │ │ Memory       │ │ Network      │   │
│  │ Reader       │ │ Reader       │ │ Reader       │ │ Reader       │   │
│  │              │ │              │ │              │ │              │   │
│  │ host_proc    │ │ IOKit/Metal  │ │ host_stat    │ │ getifaddrs() │   │
│  │ _info()      │ │              │ │ istics64()   │ │ / SCNetwork  │   │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘ └──────┬───────┘   │
│         │                │                │                │           │
├─────────┴────────────────┴────────────────┴────────────────┴───────────┤
│                         SYSTEM APIs                                     │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌────────────────────┐   │
│  │ Mach APIs │  │  IOKit    │  │  SMC      │  │  SystemConfiguration│  │
│  │ (host_*)  │  │  (GPU)    │  │ (thermal) │  │  (network)          │  │
│  └───────────┘  └───────────┘  └───────────┘  └────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **AppDelegate** | App lifecycle, module instantiation, pause/global state | `NSApplicationDelegate` — creates module instances, handles system sleep/wake |
| **Module** (per resource) | Owns readers, widgets, settings, popup for one resource type | `class CPU: Module` — coordinator between data gathering and display |
| **Reader\<T\>** | Polls system APIs, transforms raw data into typed models, pushes via callback | Generic class wrapping mach/IOKit calls, uses `Repeater` for periodic polling |
| **Widget (SWidget)** | Menu bar visual representation of one metric | `NSView` subclass added to `NSStatusItem.button`; redraws when data arrives |
| **MenuBar** | Manages NSStatusItem lifecycle for a module's widgets | Creates/destroys status items, handles "oneView" merging |
| **Popup/PopupWindow** | Detailed popup panel when user clicks a menu bar item | `NSPanel` — shows historical data, top processes, settings link |
| **Settings** | Per-module configuration UI | Embedded in a settings window, uses `Store` (UserDefaults wrapper) |
| **Store** | Persistent key-value storage for preferences | Wrapper around `UserDefaults` with observation |
| **Kit** | Shared framework — base classes, widgets, utilities, types | Internal Swift package/module depended on by all resource modules |

## Recommended Project Structure

For MacStatus v1, a **simplified single-target architecture** is recommended (vs. Stats' multi-module plugin approach):

```
MacStatus/
├── MacStatusApp.swift              # @main app entry point
├── AppDelegate.swift               # NSApplicationDelegate — NSStatusBar setup
├── Models/
│   ├── CPUInfo.swift               # Codable data models for each resource
│   ├── MemoryInfo.swift
│   ├── NetworkInfo.swift
│   └── GPUInfo.swift
├── Readers/
│   ├── ReaderProtocol.swift        # protocol defining reader lifecycle
│   ├── TimerReader.swift           # generic base: Timer + callback pattern
│   ├── CPUReader.swift             # host_processor_info / host_statistics
│   ├── MemoryReader.swift          # host_statistics64 (vm_statistics64)
│   ├── NetworkReader.swift         # getifaddrs() delta calculation
│   └── GPUReader.swift             # IOKit IOService matching (or Metal fallback)
├── Widgets/
│   ├── WidgetProtocol.swift        # protocol for menu bar views
│   ├── TextWidget.swift            # simple text display (e.g. "CPU 45%")
│   ├── BarWidget.swift             # micro bar chart
│   └── SpeedWidget.swift           # ↑↓ arrows + download/upload speeds
├── Managers/
│   ├── StatusBarManager.swift      # NSStatusBar + NSStatusItem management
│   ├── RefreshManager.swift        # centralized timer orchestration
│   └── SettingsManager.swift       # UserDefaults-backed preferences
├── Views/
│   └── SettingsView.swift          # SwiftUI settings window (if any)
├── Extensions/
│   ├── Double+Formatting.swift     # e.g., "1.2 GB", "45%"
│   └── UnitConversion.swift        # byte formatters, percentage helpers
├── App/
│   └── Info.plist                  # LSUIElement = YES (no Dock icon)
└── Resources/
    └── Assets.xcassets             # app icons, widget tint colors
```

### Structure Rationale

- **`Readers/`**: Isolated from display logic. Each reader is independently testable. All follow the same protocol, making it trivial to add new resource types later.
- **`Widgets/`**: Pure display components. Know nothing about data sources — they receive values via protocol methods (`setValue(...)`). This makes them reusable across resource types (e.g., the same `TextWidget` can show CPU%, memory GB, or network speed).
- **`Managers/`**: Cross-cutting concerns (status bar lifecycle, timer coordination, settings persistence). Separated to avoid polluting the AppDelegate.
- **No plugin/module framework**: Stats uses separate SPM modules per resource — this is overkill for v1. MacStatus should use folder grouping within a single target. The modular code architecture is preserved (protocols, separation of concerns) without the build-system complexity.
- **No AppKit storyboards**: All UI (menu bar views, settings) is built programmatically. Menu bar content must be AppKit `NSView` subclasses (even when wrapping SwiftUI with `NSHostingView`).

## Architectural Patterns

### Pattern 1: Reader-Callback Pipeline

**What:** Each resource type has a dedicated `Reader` that polls system APIs on a configurable timer. When data is ready, it fires a callback (closure). The Module layer receives the callback and fans out to all registered display widgets.

**When to use:** For any periodic system data polling (CPU, memory, network, GPU).

**Trade-offs:** 
- Pro: Decouples data gathering from display. Adding a new widget doesn't touch reader code.
- Pro: Readers are independently configurable (CPU can poll at 1s, network at 2s for lower overhead).
- Con: Callback-based flow can be harder to trace than Combine/async sequences — but simpler to implement with no external dependencies.

**Example:**
```swift
// Reader
class CPUReader: TimerReader {
    private var prevInfo: host_cpu_load_info = ...
    var onUpdate: ((CPUInfo) -> Void)?
    
    override func read() {
        var cpuInfo = host_cpu_load_info()
        // ... mach calls, delta calculation ...
        let info = CPUInfo(totalUsage: total, systemLoad: system, userLoad: user)
        DispatchQueue.main.async { self.onUpdate?(info) }
    }
}

// Module wires reader to widgets
cpuReader.onUpdate = { [weak self] info in
    self?.textWidget.setValue(info.formattedTotal)     // "CPU 45%"
    self?.barWidget.setValue(info.totalUsage)           // 0.45
}
```

### Pattern 2: NSStatusItem Per Metric

**What:** Each monitored resource gets its own `NSStatusItem` in the menu bar. Widget views are added as subviews to `NSStatusItem.button`.

**When to use:** When you need independent click targets, independent reordering (user can ⌘-drag to rearrange), and per-metric tooltips.

**Trade-offs:**
- Pro: Native macOS behavior — users can reorder items with ⌘-drag.
- Pro: Each item has independent click handling and tooltip.
- Con: Too many status items can clutter the menu bar. Stats added "Combined Modules" mode for this reason.
- For MacStatus v1: 4 status items (CPU, GPU, Memory, Network) is a reasonable number — no need for combined mode yet.

**Example:**
```swift
class StatusBarManager {
    func addWidget(_ view: NSView, title: String, length: CGFloat) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: length)
        item.button?.addSubview(view)
        item.button?.image = NSImage()  // clear default image
        item.button?.toolTip = title
        item.autosaveName = "MacStatus_\(title)"
        return item
    }
}
```

### Pattern 3: Delta Calculation for Network Rates

**What:** Raw network byte counters from `getifaddrs()` are absolute (monotonically increasing). To display download/upload *rate*, store the previous reading and calculate `(current - previous) / timeDelta`.

**When to use:** Network bandwidth display. Also applicable to disk I/O if added later.

**Trade-offs:**
- Pro: Only way to get throughput from raw counters. Gives per-second rate.
- Con: Must handle first reading (no delta — show 0) and counter overflow/reset.
- Con: Interface changes (WiFi → Ethernet) cause discontinuities.

```swift
class NetworkReader: TimerReader {
    private var prevBytes: (in: UInt64, out: UInt64)?
    private var prevTime: Date?
    
    override func read() {
        let now = Date()
        let current = getNetworkBytes()  // via getifaddrs()
        defer { prevBytes = current; prevTime = now }
        
        guard let prev = prevBytes, let prevTime = prevTime else { return }
        let dt = now.timeIntervalSince(prevTime)
        let downloadRate = Double(Int64(bitPattern: current.in) - Int64(bitPattern: prev.in)) / dt
        let uploadRate = Double(Int64(bitPattern: current.out) - Int64(bitPattern: prev.out)) / dt
        DispatchQueue.main.async { self.onUpdate?(NetworkInfo(download: downloadRate, upload: uploadRate)) }
    }
}
```

### Pattern 4: LSUIElement = YES for No Dock Icon

**What:** Set `LSUIElement` to `YES` in `Info.plist` to make the app a background (menu-bar-only) application. No Dock icon, no app switcher entry.

**When to use:** Menu bar apps, daemons, status monitors.

**Trade-offs:**
- Pro: Clean — user only sees the menu bar icon(s).
- Con: Must provide another way to access settings/preferences (e.g., click on status item or a global shortcut).

## Data Flow

### Status Bar Update Flow (Primary)

```
┌─────────────┐  Timer fires    ┌──────────────┐  mach/IOKit call   ┌───────────────┐
│  Timer       │ ───────────────→│  Reader       │ ─────────────────→│  System APIs   │
│ (1-2s tick)  │                 │  .read()      │                    │  (kernel)      │
└─────────────┘                  │               │ ←── raw data ────│                │
                                  └───────┬───────┘                    └───────────────┘
                                          │
                                          │ processed typed value
                                          ▼
                                  ┌──────────────┐
                                  │   callback   │
                                  │  (CPUInfo,   │
                                  │   MemInfo,   │
                                  │   etc.)      │
                                  └───────┬──────┘
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    ▼                     ▼                     ▼
            ┌─────────────┐     ┌──────────────┐      ┌──────────────┐
            │ Widget A     │     │  Widget B    │      │  Popup View  │
            │ (status bar) │     │ (status bar) │      │  (if open)   │
            │ .setValue()  │     │ .setValue()  │      │ .callback()  │
            └─────────────┘     └──────────────┘      └──────────────┘
```

### User Interaction Flow

```
┌──────────────────┐   left-click    ┌──────────────────┐
│  NSStatusItem    │ ───────────────→│  Popup Window    │
│  (menu bar icon) │                 │  (NSPanel)       │
│                  │ ←── close ───── │  ─ detailed info │
└──────────────────┘                 │  ─ top processes │
       │                             │  ─ settings btn  │
       │ right-click                  └────────┬─────────┘
       ▼                                       │
┌──────────────────┐                           │ settings click
│  NSMenu          │                           ▼
│  ─ Preferences   │                  ┌──────────────────┐
│  ─ Quit          │                  │  Settings Window │
└──────────────────┘                  │  ─ widget picker │
                                      │  ─ update intvl  │
                                      │  ─ colors        │
                                      └──────────────────┘
```

### Startup Flow

```
App Launch
    │
    ▼
┌──────────────────┐
│ AppDelegate      │
│ didFinishLaunch  │
└────────┬─────────┘
         │
         ├──→ SettingsManager.shared.load()     // load persisted prefs
         │
         ├──→ CPUReader.setup() → .start()      // begin polling
         ├──→ MemoryReader.setup() → .start()
         ├──→ NetworkReader.setup() → .start()
         ├──→ GPUReader.setup() → .start()
         │
         ├──→ StatusBarManager.add(CPUWidget)
         ├──→ StatusBarManager.add(MemoryWidget)
         ├──→ StatusBarManager.add(NetworkWidget)
         └──→ StatusBarManager.add(GPUWidget)
```

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| **v1 — 4 metrics** (this project) | Single-target, folder-grouped. Manual timer management is fine. 4 NSStatusItems. |
| **v1.1 — add sensors/fans** | Add new reader + widget pair. No architectural change needed. |
| **v2 — many modules + plugins** | Consider SPM module-per-resource (like Stats). Centralized timer manager becomes important for energy efficiency. |
| **v2+ — widget customization** | Widget registry pattern: modules register available widget types declaratively (via plist or code). |

### Scaling Priorities

1. **First bottleneck:** Timer frequency / energy impact. Each module polling at 1s uses ~0.5-1% CPU cumulatively. **Fix:** Centralized timer manager that coalesces reads; allow user to set update interval (1s/2s/5s).
2. **Second bottleneck:** GPU monitoring complexity. `IOReport` APIs are sparsely documented and Apple Silicon GPU monitoring requires different approaches than Intel. **Fix:** Isolate GPU reader behind protocol — fall back gracefully if unavailable.

## Anti-Patterns

### Anti-Pattern 1: Polling on the Main Thread

**What people do:** Call `host_statistics()` or `IOKit` queries directly from a Timer on the main run loop, or dispatch data back to the main thread synchronously.

**Why it's wrong:** Mach/IOKit calls can block for 1-5ms. On a 1-second timer, 5ms of blocked main thread = 0.5% main thread utilization, causing UI jank when other events coincide.

**Do this instead:** Always perform system API calls on a background queue (`DispatchQueue.global(qos: .utility)`). Only dispatch the final value assignment to the main thread for UI updates. The Stats `Reader<T>` base class does this correctly.

### Anti-Pattern 2: Over-Redrawing Widgets

**What people do:** Call `widget.display()` or `widget.setNeedsDisplay()` on every timer tick, even when the value hasn't changed meaningfully.

**Why it's wrong:** AppKit view redraws are expensive (layer compositing, Core Animation). Unnecessary redraws waste GPU/energy on a status bar app that runs 24/7.

**Do this instead:** Compare the new value to the last displayed value (with a tolerance, e.g., 0.5% for CPU). Skip the redraw if the change is below threshold. Stats uses `shadowSize` tracking in `WidgetWrapper` to avoid resizing.

### Anti-Pattern 3: Not Handling Mach API Errors

**What people do:** Assume `host_processor_info()` always succeeds with `KERN_SUCCESS`.

**Why it's wrong:** Mach calls can fail after system sleep/wake, when SIP interferes, or under extreme load. Uncaught failures can crash the app or corrupt display with NaN values.

**Do this instead:** Check `kern_return_t` on every call. On failure, log the error and keep the previous reading (stale data is better than crash or NaN). Use a retry counter — if failures persist for 30s, disable the module and show "N/A". The Stats `Reader<T>.read()` pattern handles this well.

### Anti-Pattern 4: SwiftUI MenuBarExtra for Complex Menu Bar Widgets

**What people do:** Use `MenuBarExtra` (macOS 13+) as the sole menu bar mechanism, expecting to render custom AppKit-level views inside it.

**Why it's wrong:** `MenuBarExtra` only supports SwiftUI `View` primitives (Text, Image, basic shapes). You cannot embed `NSView` subclasses, custom `CALayer` hierarchies, or use AppKit drawing inside a `MenuBarExtra`. For live-updating graphs, bar charts, and text with custom fonts/alignment, you need `NSStatusItem`.

**Do this instead:** Use `NSStatusBar.system.statusItem(withLength:)` + `NSStatusItem.button` + custom `NSView` subclasses for the menu bar content. You can optionally use `NSHostingView` to wrap a SwiftUI view inside the NSStatusItem, but be aware of SwiftUI's overhead for frequently updating content (redrawing 4x SwiftUI views at 1Hz can be noticeably slower than AppKit drawing).

### Anti-Pattern 5: One Giant Reader Doing Everything

**What people do:** Create a single "SystemMonitorReader" that gathers all metrics (CPU + memory + network + GPU) in one big `read()` method.

**Why it's wrong:** Different metrics need different polling frequencies (CPU: 1s, network: 1-2s, memory: 2-5s, GPU: variable). A monolithic reader forces the fastest polling rate on all metrics. Also fails the single-responsibility principle — harder to test, harder to add new metrics.

**Do this instead:** One `Reader` subclass per resource type, each with its own polling interval. This is the approach Stats takes and it's proven robust.

## Integration Points

### System APIs

| API | Used For | Access Pattern | Notes |
|-----|----------|----------------|-------|
| `host_processor_info()` | CPU per-core usage | Mach call, needs `processor_info_array_t` + delta calc | Returns ticks per state; must diff against previous sample |
| `host_statistics()` / `host_statistics64()` | CPU overall load, memory stats | Mach call, `host_cpu_load_info` or `vm_statistics64_data_t` | `HOST_CPU_LOAD_INFO` for system/user/idle ticks; `HOST_VM_INFO64` for memory |
| `getifaddrs()` | Network interface byte counters | POSIX system call | Lists all interfaces; filter for active (AF_LINK, IFF_UP, not loopback) |
| `IOReport` (IOKit) | GPU usage, CPU frequency (Apple Silicon) | `IOReportCreateSubscription` + `IOReportCreateSamples` + delta | Sparsely documented; Apple Silicon GPU stats require this. Intel GPU uses different IOKit paths. |
| `SCNetworkInterfaceCopyAll()` / SystemConfiguration | Network interface names, types (WiFi/Ethernet) | Core Foundation C API | For display names and connection type classification |
| `host_info()` with `HOST_BASIC_INFO` | CPU core count, memory size | Mach call | Static info, poll once at startup |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Reader → Module | Callback closure (weak self) | Reader fires `onUpdate?(typedValue)` on main thread |
| Module → Widget | Direct method call (`widget.setValue(...)`) on main thread | Module iterates active widgets and fans out data |
| Module → Popup | Direct method call (popup.view.callback(...)) | Popup shows richer data (top processes, history) |
| Widget ↔ StatusBarManager | Widget added to/removed from `NSStatusItem.button` | Managed by StatusBarManager; widget doesn't know about NSStatusBar |
| SettingsManager ↔ All Components | `Store` (UserDefaults wrapper) | Settings changes propagate via NotificationCenter or KVO |
| AppDelegate ↔ Modules | Direct instantiation + lifecycle calls | `modules.forEach { $0.mount() }` at start, `.terminate()` at shutdown |

## Suggested Build Order

Based on dependency analysis, recommended implementation sequence:

```
Phase 1: Foundation
├── AppDelegate + LSUIElement setup       (no Dock icon, menu bar app skeleton)
├── SettingsManager + Store               (UserDefaults wrapper)
└── StatusBarManager                      (NSStatusItem creation/removal)

Phase 2: First Metric (CPU)
├── ReaderProtocol + TimerReader base     (reusable timer infrastructure)
├── CPUReader                             (host_processor_info)
├── TextWidget                            (simple "CPU 45%" display)
└── Wire: CPUReader → TextWidget → StatusBar

Phase 3: Remaining Metrics
├── MemoryReader                          (host_statistics64)
├── NetworkReader                         (getifaddrs + delta calc)
├── GPUReader                             (IOKit — complex, may be Phase 4)
└── Wire each reader to its TextWidget

Phase 4: Display Polish
├── SpeedWidget (network ↑↓ arrows)
├── BarWidget (CPU/GPU micro bars)
├── Data formatting (GB, MB/s, %)
└── Popup on left-click

Phase 5: Quality of Life
├── Auto-launch at login (SMAppService)
├── Right-click menu (Preferences, Quit)
├── Settings window (update interval, colors)
└── Pause on system sleep (NSWorkspace.willSleepNotification)
```

**Build order rationale:**
- Phase 1 is the hard prerequisite — nothing displays without StatusBarManager.
- CPU is the simplest and most reliable metric (mach APIs are well-documented, work on both Intel and Apple Silicon). It validates the Reader→Widget pipeline end-to-end.
- Network is the most user-visible differentiator (people love seeing download/upload speeds in the menu bar). It should come early.
- GPU is the riskiest (IOReport APIs are poorly documented, Apple may change them). Consider deferring to a later phase or making it gracefully degrade.
- Auto-launch and settings are polish items that don't block core functionality.

## Sources

- **Stats (exelban/stats)**: Primary reference architecture — production macOS menu bar system monitor with 38k+ GitHub stars. Source code analyzed directly from GitHub (AppDelegate, Module base class, Reader base class, CPU module, Network module). [https://github.com/exelban/stats](https://github.com/exelban/stats) — HIGH confidence
- **Apple Developer Documentation — NSStatusBar**: Official reference for menu bar item creation. [https://developer.apple.com/documentation/appkit/nsstatusbar](https://developer.apple.com/documentation/appkit/nsstatusbar) — HIGH confidence
- **Apple Developer Documentation — MenuBarExtra**: SwiftUI menu bar API (macOS 13+), noted for limitations with custom views. [https://developer.apple.com/documentation/swiftui/menubarextra](https://developer.apple.com/documentation/swiftui/menubarextra) — HIGH confidence
- **Mach Kernel APIs**: `host_processor_info`, `host_statistics`, `host_statistics64` — used directly in Stats' CPU and Memory readers. Proven stable across macOS versions. — HIGH confidence
- **IOReport Framework**: Apple Silicon GPU/CPU frequency monitoring. Sparsely documented — Stats' implementation is the best open-source reference. — MEDIUM confidence (API may change with macOS updates)

---

*Architecture research for: macOS Menu Bar System Monitor*  
*Researched: 2026-05-14*
