# Architecture Research

**Domain:** macOS Menu Bar System Monitor — v2.0 feature integration (Battery, Per-Process Top-N, Settings/Customization)
**Researched:** 2026-06-16
**Confidence:** HIGH (grounded in the actual v1.0/M002 source, not training data)

> **Scope:** This document is an *integration* spec for three new v2.0 features against the **existing** MacStatus codebase. It does NOT re-research the menu-bar-monitor domain (see `v1.0-research/ARCHITECTURE.md` for that). Every recommendation below is keyed to a real class read from `MacStatus/MacStatus/`.

---

## Reality Check: How the Code Actually Wires Together Today

The milestone brief described "Reader → Manager → AppDelegate + per-reader `TimerReader.start()`". The shipped M002 code has **evolved past that** and the new features must integrate with what's really there:

| Brief assumption | Actual M002 reality (verified in source) |
|------------------|------------------------------------------|
| Each reader runs its own `TimerReader` timer + `onUpdate` callback | A single **`MetricCollector`** (`@MainActor`, `Collectors/MetricCollector.swift`) owns one `Timer` and calls each reader's **synchronous `readValue()`** every tick. The `TimerReader.start()`/`onUpdate` path still exists but is **bypassed** in production. |
| AppDelegate instantiates readers + status items | `AppDelegate` is minimal: wires `PopoverManager ↔ StatusBarManager`, calls `MetricCollector.shared.start()`, runs a 5s self-monitor. Readers live inside `MetricCollector`. |
| Popover has in-memory history only | Popover history is fed from a **`RingBuffer`** (300 samples) plus a **`HistoryStore`** (SQLite, batched every 30 ticks). `MetricSample` is the canonical per-tick record. |
| Per-process network is a "reader feeding the popover" | `ProcessNetworkReader` is a **stateless `enum`** with one static `readTopProcesses(...)`. It is invoked **on demand** (popover open) via `Task.detached(.utility)` from `PopoverManager.refreshProcessList()`, never on the collector tick. |
| `SettingsManager` is the single source of settings truth | **Two parallel stores exist today:** `SettingsManager` (used by `StatusBarManager` + `MetricCollector`) **and** `@AppStorage` keys inside `SettingsView`. They share UserDefaults keys by string, so they happen to stay in sync — but this is fragile and is the #1 thing v2.0 settings work must reconcile. |
| Status bar is "segments you add/remove" | The status bar is a **single `NSStatusItem`** whose `attributedTitle` is rebuilt wholesale each tick by `StatusBarManager.updateTitle(cpu:mem:net:gpu:)`. There are **no per-metric status items**; "toggling a metric" means conditionally including its substring, not adding/removing an `NSStatusItem`. |

**Implication for all three features:** the integration seam for live data is `MetricCollector.tick()` → (`MetricSample`, `DashboardState`, `StatusBarManager.updateTitle`). The integration seam for on-demand popover detail is `PopoverManager` + `Task.detached`. The integration seam for config is `SettingsManager`. Plan against these, not against the abstract `TimerReader.onUpdate` pipeline.

---

## Standard Architecture (current, with v2.0 additions marked)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  AppDelegate  (minimal: wiring + self-monitor)                                 │
│     applicationDidFinishLaunching → configure popover, MetricCollector.start() │
└───────────────┬────────────────────────────────────────────────────────────────┘
                │ owns / starts
                ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  MetricCollector  (@MainActor, single Timer)         ← LIVE-DATA HUB           │
│   readers: CPUReader, MemoryReader, NetworkReader, GPUReader                    │
│            [+ BatteryReader]   ◄── NEW (v2.0)                                   │
│   tick(): for each reader → readValue()  (sync, off-main work inside)          │
│     → build MetricSample  [+ battery, +per-proc cpu/mem snapshot]  ◄── NEW     │
│     → RingBuffer.append  → HistoryStore (batched)                              │
│     → DashboardState.update*  (@Published)                                     │
│     → StatusBarManager.updateTitle(...)                                        │
│   [+ reconfigure(): rebuild Timer when interval/toggles change]  ◄── NEW       │
└───────┬──────────────────────────────┬─────────────────────────┬──────────────┘
        │ @MainActor calls             │                         │ reads
        ▼                              ▼                         ▼
┌────────────────────┐   ┌──────────────────────────┐   ┌────────────────────────┐
│ StatusBarManager    │   │ PopoverManager           │   │ SettingsManager        │
│ single NSStatusItem │   │  NSPopover + DashboardView│   │  UserDefaults wrapper  │
│ attributedTitle =   │   │  DashboardState (ObsObj) │   │  [+ metricOrder,       │
│  rebuild each tick  │   │  refreshProcessList()    │   │     enabled toggles,   │
│ [+ battery segment] │   │   Task.detached(.utility)│   │     per-metric interval│
│ [+ honor toggles/   │   │   → ProcessNetworkReader │   │     custom colors]◄─NEW│
│    order/colors]◄NEW│   │  [+ ProcessSampler call]◄│   │  [+ change broadcast]  │
└────────────────────┘   │  [+ battery card]   NEW  │   └───────────┬────────────┘
                         └──────────────────────────┘               │ notifies (live re-apply)
                                                                    ▼
                              ┌─────────────────────────────────────────────────┐
                              │ SettingsWindowManager + SettingsView (SwiftUI)   │
                              │  [+ migrate @AppStorage → SettingsManager-backed]│
                              │  [+ toggle/reorder list, per-metric interval,    │
                              │     color pickers, compact/verbose]   ◄── NEW    │
                              └─────────────────────────────────────────────────┘
```

### Component Responsibilities (existing + v2.0 deltas)

| Component | Today's responsibility | v2.0 change | New/Modified |
|-----------|------------------------|-------------|--------------|
| `MetricCollector` | Single-timer orchestration; reads 4 metrics, builds `MetricSample`, fans out to ring/SQLite/dashboard/statusbar | Add `BatteryReader`; add per-process CPU/mem sampling cadence; add `reconfigure()` for live interval/toggle changes | **Modified** |
| `CPUReader`/`MemoryReader`/`NetworkReader`/`GPUReader` | `readValue()` synchronous, off-main C/Mach/IOKit work | Unchanged (template for `BatteryReader`) | Unchanged |
| `BatteryReader` | — | `TimerReader<BatteryStats>` with `readValue()`; IOKit `IOPowerSources` / `IOPSCopyPowerSourcesInfo`; returns `nil` on desktop Macs (GPU nil-pattern) | **New** |
| `ProcessNetworkReader` (enum) | On-demand nettop top-N by network | Sibling `ProcessSampler` for CPU/mem top-N (same on-demand + `Task.detached` pattern) | Unchanged (pattern reused) |
| `ProcessSampler` | — | Stateless source producing top-N CPU & mem snapshots | **New** |
| `MetricSample` | Per-tick record (cpu/mem/net/gpu) persisted | Add optional `batteryPercent`, `batteryWatts`, charging flag (for sparkline + history) | **Modified** |
| `StatusBarManager` | Builds single `attributedTitle` (full/compact/percentage) | Add battery segment; honor enabled-set, order, custom thresholds/colors, compact/verbose | **Modified** |
| `DashboardState` | `@Published` metric values + samples + top processes | Add battery card fields; add `topCPUProcesses` / `topMemProcesses` | **Modified** |
| `DashboardView` / `MetricCard` / `ProcessListView` | Popover UI | Add battery `MetricCard`; add CPU/mem process list section | **Modified** |
| `SettingsManager` | UserDefaults wrapper (singleton, `@unchecked Sendable`) | Add new keys (order, per-metric enabled, per-metric interval, custom colors); add a **change-broadcast** mechanism | **Modified** |
| `SettingsView` / `SettingsWindowManager` | SwiftUI prefs in `NSWindow` via `NSHostingView` | Migrate from raw `@AppStorage` to `SettingsManager`-backed bindings; add toggle/reorder/color/interval UI | **Modified** |

---

## Recommended Project Structure (additions only)

```
MacStatus/MacStatus/
├── Readers/
│   ├── BatteryReader.swift            ◄── NEW  TimerReader<BatteryStats>, IOPowerSources, nil on desktop
│   └── ProcessSampler.swift           ◄── NEW  enum, on-demand top-N CPU/mem (mirror ProcessNetworkReader)
├── Collectors/
│   └── MetricCollector.swift          ── MODIFIED  + batteryReader, + reconfigure(), + battery in MetricSample
├── Storage/
│   └── MetricSample.swift             ── MODIFIED  + battery fields (optional, back-compat)
├── UI/
│   ├── StatusBarManager.swift         ── MODIFIED  + battery segment, + enabled/order/color honoring
│   └── Views/
│       ├── DashboardView.swift        ── MODIFIED  + DashboardState battery + topCPU/topMem fields
│       ├── MetricCard.swift           ── MODIFIED (or reuse) battery card
│       ├── ProcessListView.swift      ── MODIFIED  generalize: drive by (name, pid, value, unit)
│       └── SettingsView.swift         ── MODIFIED  migrate to SettingsManager, + new sections
└── Utils/
    └── SettingsManager.swift          ── MODIFIED  + new keys + change broadcast (NotificationCenter)
```

**Structure rationale:** No new layers. v2.0 adds exactly two new files (`BatteryReader`, `ProcessSampler`) and threads new fields through existing types. This keeps the "zero new architecture" property the v1.0 retrospective credited for fast delivery.

---

## Feature 1: Battery & Power

### Reader shape — yes, `TimerReader<BatteryStats>`

`BatteryReader` follows the `GPUReader` template exactly: subclass `TimerReader<BatteryStats>`, expose a synchronous `readValue() -> BatteryStats?`, and let `MetricCollector` call it each tick. **Do not rely on the `onUpdate` callback** — production reads through `readValue()`.

```swift
struct BatteryStats: Sendable, Equatable {
    let percentage: Double          // 0...100
    let isCharging: Bool
    let isPluggedIn: Bool
    let powerWatts: Double?         // signed: + charging, − discharging; nil if unavailable
    let timeRemainingMinutes: Int?  // nil while "calculating"
    let healthPercent: Double?      // maxCapacity / designCapacity * 100; nil if unreadable
    let cycleCount: Int?
}

final class BatteryReader: TimerReader<BatteryStats> {
    private let hasBattery: Bool
    init() {
        hasBattery = Self.detectBattery()   // false on iMac/Mac mini/Studio/Pro
        super.init(interval: 5.0)            // battery changes slowly; 5s is plenty
    }
    func readValue() -> BatteryStats? {
        guard hasBattery else { return nil }   // ◄── desktop degradation = nil (GPU pattern)
        // IOPSCopyPowerSourcesInfo / IOPSGetPowerSourceDescription for %, charging, time
        // IORegistry AppleSmartBattery for Watts (Amperage×Voltage), CycleCount, capacities
        ...
    }
    private static func detectBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        return !sources.isEmpty
    }
}
```

### Desktop-Mac degradation = the established nil-stats pattern

This is identical to GPU on Intel: `readValue()` returns `nil`, `nil` flows into `MetricSample.batteryPercent = nil`, and every consumer already handles `nil` as "render `--` / N/A". Concretely:
- **Status bar:** in `updateTitle`, battery segment renders `"BAT: --"` / omitted (same as the `GPU: N/A` branch).
- **Popover:** `DashboardState.updateBattery(nil)` sets `batteryText = "N/A"`; the battery `MetricCard` shows a disabled/empty state.
- **Detection is cheap and static** — compute `hasBattery` once at init (like `GPUReader.detectAppleSilicon()`), not every tick.

### Wiring points (exact)

1. `MetricCollector`: add `private let batteryReader = BatteryReader()`; in `start()` call `_ = batteryReader.readValue()` for baseline; in `tick()` call `let bat = batteryReader.readValue()` and put fields into `MetricSample`.
2. `MetricSample`: add `batteryPercent: Double?`, `batteryWatts: Double?`, `batteryCharging: Bool?` (all optional → SQLite schema add columns, back-compatible; reads of old rows yield nil).
3. `DashboardState`: add `@Published batteryText/batteryPercent/batteryCharging/batteryWatts/batteryHealth` + `updateBattery(_:)`; `MetricCollector.updateUI` calls it.
4. `StatusBarManager.updateTitle`: add a `batteryStats:` parameter and a battery segment in each of the three mode builders (`buildFullTitle`/`buildCompactTitle`/`buildPercentageTitle`). Use value-level coloring (the established pattern): low %/critical → `.systemOrange`/`.systemRed`, else `.labelColor` — never parse the rendered string for color.
5. Popover: add a battery `MetricCard` (percentage + charging glyph + W + time remaining) and, optionally, a battery sparkline fed from `RingBuffer` (charge % over time).

**Power (Watts) caveat (MEDIUM confidence):** instantaneous wattage comes from `AppleSmartBattery` IORegistry (`Amperage` × `Voltage`, or `InstantAmperage`). Field availability varies by model and these are private-ish IORegistry keys — treat like the GPU `PerformanceStatistics` multi-key probe: try keys, fall back to `nil` (show "—W") rather than asserting a value. Health (`AppleRawMaxCapacity`/`DesignCapacity`) and `CycleCount` are similarly IORegistry-sourced and should degrade to `nil` gracefully.

---

## Feature 2: Per-Process Top-N CPU & Memory

### Does it fit `TimerReader`? No — reuse the `ProcessNetworkReader` on-demand pattern instead

The per-process **network** feature is NOT a `TimerReader` today; it's a stateless `enum` (`ProcessNetworkReader.readTopProcesses`) invoked **only when the popover opens**, on a detached utility task, with the result marshalled back to `@MainActor`. CPU/mem top-N should mirror this exactly, for the same reasons:
- Top-N process enumeration is **expensive** (proc table walk / `nettop` subprocess) and only meaningful **while the popover is visible** — running it on every collector tick would waste energy 24/7 for data nobody is looking at.
- It must **not block `@MainActor`** — the existing pattern already solves this with `Task.detached(priority: .utility)`.

```swift
struct ProcessResourceUsage: Sendable, Equatable {
    let processName: String
    let pid: Int32
    let cpuPercent: Double
    let memoryBytes: UInt64
}
enum ProcessSamplerResult: Sendable, Equatable {
    case processes([ProcessResourceUsage]); case idle; case unavailable(String)
}
enum ProcessSampler {
    static func readTopProcesses(limit: Int = 5, sortBy: SortKey) -> ProcessSamplerResult { ... }
}
```

### Sampling source — prefer `libproc` over spawning `ps`/`top` (HIGH confidence)

For CPU/mem you do **not** need a subprocess (unlike `nettop`, which is the only per-process network source). Use the in-process `libproc` API: `proc_listpids(PROC_ALL_PIDS, ...)` to enumerate, then `proc_pid_rusage(pid, RUSAGE_INFO_V*, ...)` for CPU time + `proc_pidinfo(... PROC_PIDTASKINFO ...)` (`pti_resident_size`) for RSS. CPU% needs a **delta** between two `proc_pid_rusage` snapshots (same delta pattern as network bytes / `getifaddrs`) — so `ProcessSampler` can either take two quick samples ~0.5s apart inside the detached task, or keep a small previous-snapshot dictionary keyed by pid. Keep it stateless-with-internal-window like `ProcessNetworkReader` does its two-sample `nettop` window. Avoid `host_processor_info`-style global calls; this is per-pid.

> If `libproc` proves fiddly under Swift 6 sandbox/entitlement constraints, the fallback is spawning `/bin/ps -Aceo pid,pcpu,rss,comm` and parsing — same `Process()` + pipe + timeout scaffolding `ProcessNetworkReader` already has. Prefer `libproc` (no subprocess spawn, lower latency, no TTY quirks).

### Wiring points (exact)

1. `PopoverManager.refreshProcessList()`: today it calls `ProcessNetworkReader`. Generalize so popover-open triggers **all** on-demand samplers. Either extend this method or add `refreshResourceProcesses()` that runs `ProcessSampler.readTopProcesses(sortBy: .cpu)` and `.memory` in the same detached task, then updates `dashboardState.topCPUProcesses` / `topMemProcesses` on `@MainActor`.
2. `DashboardState`: add `@Published topCPUProcesses`, `@Published topMemProcesses` (+ loading/error flags), mirroring the existing `topProcesses`/`processesLoading`/`processError` triad.
3. `ProcessListView`: generalize from network-specific to a reusable `(name, pid, primaryValue, secondaryValue)` row so CPU%, mem (MB), and network all reuse it. Add CPU and memory sub-sections to `DashboardView` alongside the existing network process list.
4. Respect the `transient` popover lifetime: cancel in-flight sampling on close (the existing `processRefreshTask?.cancel()` + `Task.isCancelled` guard pattern).

**Energy note:** keep top-N sampling **strictly popover-gated**. Do NOT add it to `MetricCollector.tick()`. This is the single most important integration constraint for this feature.

---

## Feature 3: Settings Window + Live Customization

### SwiftUI, not AppKit — and the window already exists

Keep the existing approach: `SettingsView` (SwiftUI `Form`) hosted in an `NSWindow` via `NSHostingView`, managed by `SettingsWindowManager.shared.showSettings()`. This is already wired to the right-click "偏好设置…" menu item in `StatusBarManager.showPreferences()`. **No new window framework is needed.** SwiftUI `Form` + `List` (with `.onMove` for drag-reorder) covers every v2.0 settings requirement (toggles, reorder, sliders, color wells via `ColorPicker`, pickers for mode/interval). AppKit would be strictly more work for no benefit here.

### The settings-model problem you MUST fix first

Today there are **two sources of truth**: `SettingsView` writes raw `@AppStorage("refreshInterval")` etc., while `StatusBarManager`/`MetricCollector` read `SettingsManager.shared.refreshInterval`. They only agree because both sides hardcode the same UserDefaults key strings. Before adding richer settings, **route all settings through `SettingsManager`** so there's one typed API. Two viable bridges:

- **Option A (recommended):** Make `SettingsManager` `ObservableObject` (or expose an `@Observable` facade) and bind SwiftUI controls to it via a small `@Published`/`Binding` adapter. One typed store, SwiftUI reads/writes it, collector/statusbar read it.
- **Option B (minimal):** Keep `@AppStorage` in the view but treat `SettingsManager` as the *read* API everywhere else, and have the view post a change notification after writes. Less clean (key strings still duplicated) but smallest diff.

Recommend Option A — it removes the duplicated key strings that are a latent bug.

### New settings to model in `SettingsManager`

| Setting | Type | Default | Consumed by |
|---------|------|---------|-------------|
| Per-metric enabled | `Set<MetricKind>` (or per-key Bool) | all on | `StatusBarManager` (include/omit segment), popover (show/hide card) |
| Metric order | `[MetricKind]` (Codable → JSON in UserDefaults) | cpu,mem,net,gpu,bat | `StatusBarManager` segment order, popover card order |
| Per-metric refresh interval | `[MetricKind: TimeInterval]` | 2s (battery 5s) | `MetricCollector` tick scheduling |
| Custom warning/critical thresholds | already partly present (cpu/mem) | 60/80 | `StatusBarManager.colorForUsage` (extend to gpu/battery) |
| Custom colors | per-metric `NSColor`/hex | system label | `StatusBarManager` value-level coloring |
| Compact/verbose mode | `DisplayMode` (exists) | compact | `StatusBarManager.updateTitle` (exists) |

### The live re-apply mechanism (concrete)

There is **no live re-apply today** — `MetricCollector.start()` reads `refreshInterval` once and the `Timer` is never rebuilt; changing it requires relaunch. v2.0 must add a broadcast + reconfigure path. Recommended mechanism:

1. **Broadcast on change.** `SettingsManager` posts `Notification.Name("MacStatusSettingsChanged")` (with an enum payload describing what changed) on every setter, OR, with Option A above, SwiftUI's `@Published` already drives observers. A `NotificationCenter` notification is the lowest-risk fit for the existing singleton + `@MainActor` consumers.

2. **Consumers re-apply on the main actor:**
   - **Interval change → reconfigure the timer.** Add `MetricCollector.reconfigure()` that invalidates and rebuilds its `Timer` from the (now per-metric or global) interval. Because there's one unified timer, the simplest correct model is: tick at the **GCD of enabled per-metric intervals** (or just the minimum), and inside `tick()` skip readers whose individual interval hasn't elapsed (tick-counter modulo, like the existing `tickCount % 1800` cleanup). This honors per-metric intervals without N timers and preserves the single-tick `MetricSample` contract.
   - **Toggle a metric → no status item add/remove.** Because the status bar is one `NSStatusItem` with a rebuilt `attributedTitle`, "toggling" = `StatusBarManager.updateTitle` reads the enabled-set and conditionally appends that metric's segment. The very next tick (or an immediate forced `updateTitle`) reflects it. Likewise the popover reads enabled/order from `DashboardState` (pushed from settings) to show/hide/reorder cards. **Do not** try to create per-metric `NSStatusItem`s for toggling — that would be a larger rearchitecture than v2.0 needs.
   - **Reorder → segment/card order.** `updateTitle` iterates `SettingsManager.metricOrder` instead of a hardcoded sequence; popover `DashboardView` iterates the same order.
   - **Threshold/color change → next `updateTitle`.** `colorForUsage` already reads `SettingsManager` live each call, so these apply on the next tick automatically; just force one immediate `updateTitle` for instant feedback.

3. **Force an immediate refresh** after any change so the user sees it without waiting a tick: have `MetricCollector` expose `applyNow()` that re-runs `updateUI` with the last `MetricSample`, and have the settings notification handler call it on `@MainActor`.

```swift
// SettingsManager (sketch)
func notifyChanged(_ what: SettingsChange) {
    NotificationCenter.default.post(name: .macStatusSettingsChanged, object: what)
}
// MetricCollector.start(): subscribe once
NotificationCenter.default.addObserver(forName: .macStatusSettingsChanged, object: nil, queue: .main) { [weak self] note in
    MainActor.assumeIsolated {
        guard let self else { return }
        if (note.object as? SettingsChange)?.affectsTiming == true { self.reconfigure() }
        self.applyNow()   // re-push last sample to status bar + dashboard
    }
}
```

**Swift 6 note:** the broadcast handler hops to `@MainActor` (all of `MetricCollector`/`StatusBarManager`/`DashboardState` are `@MainActor`). `SettingsManager` stays `@unchecked Sendable`. Keep `BatteryStats`/`ProcessResourceUsage`/`MetricSample` `Sendable` so detached sampling tasks stay clean — consistent with the existing `Sendable` structs.

---

## Data Flow (v2.0)

### Live tick (status bar + popover cards + history) — extends existing path

```
Timer (MetricCollector, unified) every effective interval
  → cpuReader.readValue() | memoryReader | networkReader | gpuReader | batteryReader.readValue()
        (each does its C/Mach/IOKit work synchronously inside readValue; battery=nil on desktop)
  → MetricSample(cpu, mem, net, gpu, battery…)        [+ battery fields]
  → RingBuffer.append + HistoryStore (batched 30 ticks)
  → DashboardState.updateCPU/Memory/Network/GPU/[Battery]   (@Published → SwiftUI cards + sparklines)
  → StatusBarManager.updateTitle(cpu, mem, net, gpu, [battery])  (honors enabled/order/colors/mode)
```

### On-demand (popover open) — extends existing process path

```
StatusBar click → PopoverManager.toggle → popover.show
  → refreshProcessList() + [refreshResourceProcesses()]
      → Task.detached(.utility):
            ProcessNetworkReader.readTopProcesses()      (network, nettop subprocess)
            ProcessSampler.readTopProcesses(.cpu/.memory)  [NEW] (libproc, in-process)
      → await MainActor: dashboardState.topProcesses / topCPUProcesses / topMemProcesses
  popover close → processRefreshTask.cancel()  (no sampling while hidden)
```

### Settings change (NEW live re-apply path)

```
SettingsView control changes value
  → SettingsManager setter (single source of truth)
  → NotificationCenter .macStatusSettingsChanged  (or @Published)
      → MetricCollector: reconfigure() if timing changed; applyNow() always
      → StatusBarManager.updateTitle re-runs (enabled/order/colors/mode honored immediately)
      → DashboardState enabled/order pushed → popover cards show/hide/reorder
```

---

## Anti-Patterns (specific to this integration)

### Anti-Pattern 1: Making per-process CPU/mem a `TimerReader` on the collector tick
**Why wrong:** runs expensive proc-table walks 24/7 for data only visible when the popover is open; defeats the energy budget the project explicitly constrains. **Instead:** on-demand `ProcessSampler` gated by popover visibility, exactly like `ProcessNetworkReader`.

### Anti-Pattern 2: Creating per-metric `NSStatusItem`s to implement toggling/reorder
**Why wrong:** the app is intentionally a *single combined* status item (fixed-width, single attributed title, the v1.0 "四合一" decision). Splitting into N items contradicts a shipped product decision and is far more work. **Instead:** toggle = conditionally append a segment; reorder = iterate `metricOrder` in `updateTitle`.

### Anti-Pattern 3: Adding new settings via raw `@AppStorage` in `SettingsView`
**Why wrong:** doubles down on the existing two-sources-of-truth fragility (string keys duplicated between the view and `SettingsManager`). **Instead:** route everything through `SettingsManager` (Option A) before adding new keys.

### Anti-Pattern 4: Asserting battery Watts/health as always-available
**Why wrong:** `AppleSmartBattery` IORegistry keys vary by model and are semi-private — assuming them yields wrong/zero readings on some Macs. **Instead:** probe-and-nil like the GPU `PerformanceStatistics` multi-key approach; show "—" when absent.

### Anti-Pattern 5: Rebuilding the timer per metric for per-metric intervals
**Why wrong:** N concurrent timers reintroduce the energy/skew problems the unified `MetricCollector` was built to avoid. **Instead:** keep one timer at min/GCD interval and gate each reader with a per-metric tick-counter modulo.

---

## Integration Points

### System APIs (new for v2.0)

| API | Used for | Pattern | Notes / confidence |
|-----|----------|---------|--------------------|
| `IOPSCopyPowerSourcesInfo` / `IOPSCopyPowerSourcesList` / `IOPSGetPowerSourceDescription` (IOKit.ps) | Battery %, charging, time-to-full/empty, present? | CF dictionary read; empty list ⇒ desktop ⇒ `nil` | HIGH — public IOKit Power Sources API |
| `AppleSmartBattery` IORegistry (`IORegistryEntryCreateCFProperties`) | Watts (Amperage×Voltage), CycleCount, MaxCapacity/DesignCapacity (health) | Multi-key probe → nil fallback (GPU pattern) | MEDIUM — keys vary by model, semi-private |
| `proc_listpids` + `proc_pid_rusage` + `proc_pidinfo(PROC_PIDTASKINFO)` (`<libproc.h>`) | Per-process CPU time (delta) + RSS | In-process, off-main inside detached task; delta for CPU% | HIGH — standard libproc, no subprocess |
| `/bin/ps` (fallback only) | Per-process cpu/rss | `Process()`+pipe+timeout (reuse `ProcessNetworkReader` scaffolding) | HIGH — fallback if libproc constrained |
| SwiftUI `List{}.onMove`, `ColorPicker`, `Slider`, `Picker` | Settings reorder/colors/intervals/mode | Bound to `SettingsManager` | HIGH — standard SwiftUI |

### Internal boundaries (new/changed)

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `BatteryReader → MetricCollector` | synchronous `readValue()` each tick | Same contract as CPU/GPU readers; `nil` on desktop |
| `ProcessSampler → PopoverManager` | `Task.detached(.utility)` → `await MainActor` | Mirror `ProcessNetworkReader`; cancel on popover close |
| `SettingsManager → MetricCollector/StatusBarManager/DashboardState` | `NotificationCenter` broadcast (or `@Published`) | The new live re-apply seam; handlers hop to `@MainActor` |
| `SettingsView ↔ SettingsManager` | typed bindings (Option A) | Replaces raw `@AppStorage` to kill duplicate key strings |
| `MetricCollector.reconfigure()` | invalidate+rebuild unified `Timer`; per-metric modulo gating | Single timer preserved |

---

## Suggested Build Order (dependency-aware)

The settings **persistence + live-apply model is a prerequisite** for per-metric intervals and toggles, so it lands before the features that depend on runtime reconfiguration. Battery is independent and low-risk; per-process is independent and self-contained. Recommended sequence:

```
Phase A — Settings foundation (UNBLOCKS everything customizable)
  A1. Consolidate settings on SettingsManager (kill @AppStorage duplication; Option A)
  A2. Add new keys: metricOrder, per-metric enabled, per-metric interval, custom colors
  A3. Add live re-apply: SettingsManager change broadcast + MetricCollector.reconfigure()/applyNow()
      + StatusBarManager honoring enabled/order in updateTitle
  Rationale: per-metric intervals (needs reconfigure) and metric toggles (needs broadcast)
             cannot be wired until this model exists.

Phase B — Battery & Power (independent; low risk; nil-pattern proven)
  B1. BatteryReader (TimerReader<BatteryStats>, IOPowerSources, desktop ⇒ nil)
  B2. MetricSample + storage columns; MetricCollector wires batteryReader into tick()
  B3. StatusBarManager battery segment (value-level coloring, honors Phase A enabled/order)
  B4. DashboardState + popover battery MetricCard (+ optional charge sparkline)
  Rationale: B3/B4 are cleaner once Phase A's enabled/order/color plumbing exists,
             but B1/B2 (reader + data) can start in parallel with Phase A.

Phase C — Per-Process Top-N CPU & Memory (independent; popover-gated)
  C1. ProcessSampler (libproc top-N CPU/mem, delta for CPU%, Sendable result)
  C2. Generalize ProcessListView + DashboardState (topCPUProcesses/topMemProcesses)
  C3. PopoverManager.refresh* triggers CPU/mem sampling on open (detached, cancel on close)
  Rationale: fully self-contained; depends only on the existing ProcessNetworkReader
             pattern, not on Phase A. Can run in parallel with B if capacity allows.

Phase D — Settings UI polish for the new features
  D1. SettingsView sections: enable/reorder list (.onMove), per-metric interval pickers,
      color wells (ColorPicker), battery & process toggles
  D2. Wire those controls to the Phase A SettingsManager + broadcast
  Rationale: must come AFTER A (model) and AFTER B/C exist (so there's something to toggle/order).
```

**Critical path:** A → D. B and C are parallelizable branches that only need A's enabled/order plumbing for their *display* polish (B3/B4, C2), not for their core reader/sampler work (B1/B2, C1). If sequencing single-threaded, do **A, then B, then C, then D**.

**Dependency callouts:**
- Per-metric refresh intervals **require** `MetricCollector.reconfigure()` (Phase A3) — do not attempt before it.
- Metric toggle/reorder in the status bar **require** the enabled-set/order read in `updateTitle` (Phase A) — without it, toggling has nowhere to take effect.
- Battery and per-process have **no inter-dependency** and don't block each other.
- Settings UI (D) is last because it's the control surface for A/B/C; building it first would have nothing concrete to drive.

---

## Sources

- **MacStatus M002 source** (read directly, 2026-06-16): `Collectors/MetricCollector.swift`, `Readers/{TimerReader,GPUReader,ProcessNetworkReader,ReaderProtocol}.swift`, `UI/{StatusBarManager,PopoverManager}.swift`, `UI/Views/{DashboardView,SettingsView,ProcessListView}.swift`, `Utils/SettingsManager.swift`, `Storage/MetricSample.swift`, `App/AppDelegate.swift` — HIGH confidence (ground truth).
- **`.planning/milestones/v1.0-research/ARCHITECTURE.md`** — domain architecture baseline; Reader/Manager/StatusItem patterns and anti-patterns (main-thread polling, over-redraw, nil degradation) — HIGH confidence.
- **`.planning/RETROSPECTIVE.md`** — established patterns: `TimerReader<T>` lifecycle, value-level coloring, `freeifaddrs()`-in-`defer`, multi-key IOKit probe + nil degradation — HIGH confidence.
- **`.planning/PROJECT.md`** — v2.0 scope, constraints (energy budget, zero/min dependencies, macOS 14+), out-of-scope (no GPU-per-process, no full Activity Monitor) — HIGH confidence.
- **Apple IOKit Power Sources** (`IOPSCopyPowerSourcesInfo`, `IOPSGetPowerSourceDescription`) — public API for battery presence/%/charging/time — HIGH confidence (training + consistent with Stats' battery module).
- **`AppleSmartBattery` IORegistry keys** (Amperage, Voltage, CycleCount, MaxCapacity, DesignCapacity) — model-dependent, semi-private; probe-and-nil — MEDIUM confidence.
- **`libproc`** (`proc_listpids`, `proc_pid_rusage`, `proc_pidinfo`) — in-process per-process CPU/mem; standard BSD/Darwin API — HIGH confidence.

---
*Architecture research for: macOS Menu Bar System Monitor — v2.0 feature integration*
*Researched: 2026-06-16*
