# Phase 7: Battery & Power — Pattern Map

**Mapped:** 2026-06-17
**Files analyzed:** 3 (1 new, 2 modified)
**Analogs found:** 3 / 3

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `MacStatus/MacStatus/Readers/BatteryReader.swift` | reader | request-response (sync readValue) | `GPUReader.swift` (nil-degradation, Sendable struct, IOKit, readValue) + `NetworkReader.swift` (wake observer) | exact (split across two analogs) |
| `MacStatus/MacStatus/Collectors/MetricCollector.swift` | orchestrator | CRUD (tick-driven) | `MetricCollector.swift` itself — gpuReader lines 32, 59, 65, 147, 194 | exact self-reference |
| `MacStatus/MacStatus/UI/Views/DashboardView.swift` | component + state | request-response (ObservableObject) | `DashboardView.swift` itself — updateGPU/updateMemory pattern + card background style | exact self-reference |

---

## Pattern Assignments

---

### `MacStatus/MacStatus/Readers/BatteryReader.swift` (reader, request-response)

**Primary analog:** `MacStatus/MacStatus/Readers/GPUReader.swift`
**Secondary analog:** `MacStatus/MacStatus/Readers/NetworkReader.swift`

---

#### Sendable snapshot struct pattern
Analog: `GPUReader.swift` lines 7–18

```swift
// GPUReader.swift — copy this struct shape for BatterySnapshot
enum GPUPressureLevel: Sendable, Equatable {
    case normal
    case warning
    case critical
}

struct GPUStats: Sendable, Equatable {
    let utilizationPercent: Double
    let pressureLevel: GPUPressureLevel?
}
```

**Apply to BatteryReader:** Define `BatterySnapshot: Sendable, Equatable` with all-value-type fields (Int, Bool, Double, Optional). No CF types cross the actor boundary. Mirror `GPUStats` naming convention (`BatterySnapshot` not `BatteryStats` — snapshot better reflects one-shot read semantics per CONTEXT.md).

Concrete struct (from RESEARCH.md — verified on device):
```swift
struct BatterySnapshot: Sendable, Equatable {
    let chargePercent: Int
    let isCharging: Bool
    let isOnAC: Bool
    let timeToEmptyMinutes: Int?   // nil = post-wake skip; -1 = calculating
    let timeToFullMinutes: Int?    // nil = post-wake skip; -1 = calculating
    let watts: Double?             // nil = Amperage/Voltage keys missing
    let healthPercent: Double?     // nil = AppleRawMaxCapacity/DesignCapacity missing
    let cycleCount: Int?           // nil = CycleCount key missing
}
```

---

#### IOKit service acquisition + defer release pattern
Analog: `GPUReader.swift` lines 44–56 (IOServiceGetMatchingServices + iterator + defer IOObjectRelease)

```swift
// GPUReader.swift lines 44–56 — defer + guard pattern
guard let matching = IOServiceMatching("IOAccelerator") else {
    onUpdate?(nil)
    return
}
var iterator: io_iterator_t = 0
let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
guard result == KERN_SUCCESS else {
    onUpdate?(nil)
    return
}
defer { IOObjectRelease(iterator) }
```

**Apply to BatteryReader:** Use `IOServiceGetMatchingService` (singular, not iterator) for `AppleSmartBattery`. Place `defer { IOObjectRelease(service) }` immediately after the guard. This is the exact Mach port leak prevention pattern (RESEARCH.md Pitfall 6).

```swift
// BatteryReader — adapt from GPUReader defer pattern
let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                          IOServiceMatching("AppleSmartBattery"))
guard service != IO_OBJECT_NULL else { return nil }
defer { IOObjectRelease(service) }
```

---

#### probe-and-nil IORegistry property read pattern
Analog: `GPUReader.swift` lines 87–98

```swift
// GPUReader.swift lines 87–98
private func performanceStatistics(for service: io_registry_entry_t) -> [String: Any]? {
    guard let property = IORegistryEntryCreateCFProperty(
        service,
        "PerformanceStatistics" as CFString,
        kCFAllocatorDefault,
        0
    ) else {
        return nil
    }
    return property.takeRetainedValue() as? [String: Any]
}
```

**Apply to BatteryReader:** Use `IORegistryEntryCreateCFProperties` (all properties at once) rather than per-key `IORegistryEntryCreateCFProperty`. Pattern is the same — `takeRetainedValue()` on the result, `as? [String: Any]` cast, nil on failure.

```swift
// BatteryReader adaptation
var propsRef: Unmanaged<CFMutableDictionary>?
guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
      let props = propsRef?.takeRetainedValue() as? [String: Any] else {
    return nil
}
// All key reads: props["Amperage"] as? Int — never as!
```

---

#### Synchronous readValue() returning optional Sendable
Analog: `GPUReader.swift` lines 127–155

```swift
// GPUReader.swift lines 127–155 — the readValue() pattern MetricCollector calls
func readValue() -> GPUStats? {
    guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
    guard result == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iterator) }

    var bestUtilization: Double?
    var service = IOIteratorNext(iterator)
    while service != 0 {
        defer {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        guard let statistics = performanceStatistics(for: service),
              let utilization = utilizationPercent(from: statistics) else {
            continue
        }
        bestUtilization = max(bestUtilization ?? utilization, utilization)
    }

    guard let utilization = bestUtilization else { return nil }
    let pressure = isAppleSilicon ? pressureLevel(for: utilization) : nil
    return GPUStats(utilizationPercent: utilization, pressureLevel: pressure)
}
```

**Apply to BatteryReader:** `readValue() -> BatterySnapshot?` follows identical shape — guard IOKit calls, defer release, probe-and-nil all keys, return nil for no-battery. `BatteryReader` does NOT subclass `TimerReader` (per RESEARCH.md recommendation — MetricCollector drives the tick).

---

#### Wake observer + deinit cleanup pattern
Analog: `NetworkReader.swift` lines 44–66, 107–111

```swift
// NetworkReader.swift lines 44–66 — wakeObserver declaration + setup()
private var wakeObserver: NSObjectProtocol?

override func setup() {
    previousBytes = nil
    previousTime = nil

    wakeObserver = NSWorkspace.shared.notificationCenter
        .addObserver(forName: NSWorkspace.didWakeNotification,
                     object: nil,
                     queue: nil) { [weak self] _ in
            self?.previousBytes = nil
            self?.previousTime = nil
        }
}

// NetworkReader.swift lines 107–111 — deinit removes observer
deinit {
    if let observer = wakeObserver {
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
}
```

**Apply to BatteryReader:** Identical structure. Instead of resetting `previousBytes`, set `postWakeSkipCount = postWakeSkipTotal` (3). In `readValue()`, check the counter before including time fields:

```swift
// BatteryReader — wake grace period (mirrors NetworkReader.wakeObserver)
private var wakeObserver: NSObjectProtocol?
private var postWakeSkipCount: Int = 0
private let postWakeSkipTotal = 3   // 3 ticks × 2s = 6s grace period

func setup() {
    wakeObserver = NSWorkspace.shared.notificationCenter
        .addObserver(forName: NSWorkspace.didWakeNotification,
                     object: nil,
                     queue: nil) { [weak self] _ in
            self?.postWakeSkipCount = self?.postWakeSkipTotal ?? 3
        }
}

deinit {
    if let observer = wakeObserver {
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
}

// In readValue(), after time keys are read from IOPS:
var timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int
var timeToFull  = desc[kIOPSTimeToFullChargeKey] as? Int
if postWakeSkipCount > 0 {
    postWakeSkipCount -= 1
    timeToEmpty = nil   // forces "计算中" in UI
    timeToFull  = nil
}
```

---

#### Import block
Analog: `GPUReader.swift` lines 1–3 + `NetworkReader.swift` line 1

```swift
// GPUReader.swift
import Darwin
import Foundation
import IOKit

// NetworkReader.swift
import Cocoa
import SystemConfiguration
```

**Apply to BatteryReader:**
```swift
import Foundation
import IOKit
import IOKit.ps   // Power Sources API (IOPSCopyPowerSourcesInfo, IOPSGetPowerSourceDescription)
```
`AppKit`/`Cocoa` not needed — `NSWorkspace` is available via `Foundation` when imported alongside `AppKit` transitively through the app target. Use `Foundation` only (matches GPUReader's minimal imports).

---

### `MacStatus/MacStatus/Collectors/MetricCollector.swift` (MODIFY)

**Analog:** `MetricCollector.swift` itself — gpuReader declaration + integration lines

---

#### Reader property declaration pattern
Analog: `MetricCollector.swift` lines 29–32

```swift
// MetricCollector.swift lines 29–32 — individual reader declarations
private let cpuReader = CPUReader()
private let memoryReader = MemoryReader()
private let networkReader = NetworkReader()
private let gpuReader = GPUReader()
```

**Apply:** Add `private let batteryReader = BatteryReader()` on line 33 (after gpuReader). Same `private let` + inline init pattern.

---

#### setup() + first read pattern
Analog: `MetricCollector.swift` lines 54–65

```swift
// MetricCollector.swift lines 54–65 — setup then first read for each reader
func start() {
    cpuReader.setup()
    memoryReader.setup()
    networkReader.setup()
    gpuReader.setup()

    _ = cpuReader.readValue()
    _ = memoryReader.readValue()
    _ = networkReader.readValue()
    _ = gpuReader.readValue()
    // ...
}
```

**Apply:** Add `batteryReader.setup()` in the setup block and `_ = batteryReader.readValue()` in the first-read block. The `setup()` call registers the wake observer. The discarded first read establishes no baseline (unlike NetworkReader — BatteryReader has no delta state), but mirrors the pattern for consistency.

---

#### tick() read pattern
Analog: `MetricCollector.swift` lines 143–147

```swift
// MetricCollector.swift lines 143–147 — synchronous reads in tick()
let cpu = cpuReader.readValue()
let mem = memoryReader.readValue()
let net = networkReader.readValue()
let gpu = gpuReader.readValue()
```

**Apply:** Add `let battery = batteryReader.readValue()` after line 147. Battery data does NOT enter `MetricSample` (no history, no sparkline). The variable is used only in `updateUI`.

---

#### updateUI() push pattern
Analog: `MetricCollector.swift` lines 194–196

```swift
// MetricCollector.swift lines 194–196 — updateGPU as the closest analog
dashboard.updateGPU(sample.gpuUsage.map {
    GPUStats(utilizationPercent: $0, pressureLevel: nil)
})
```

**Apply:** Battery is simpler — pass the snapshot directly (no reconstruction from sample):

```swift
// In updateUI(sample:) — add after updateGPU call
dashboard.updateBattery(battery)
// battery is captured from tick() scope; nil on desktop → section hidden
```

Note: `battery` must be captured from `tick()` scope, not from `sample` (battery is not in MetricSample). The `updateUI` signature stays `updateUI(sample:)` — `battery` is a separate local captured by the enclosing `tick()` closure. The cleanest approach is to store it as a private var `lastBatterySnapshot` alongside `lastSample`, or pass it as a second parameter. Prefer a `private var lastBatterySnapshot: BatterySnapshot?` instance property updated in `tick()`, read in `updateUI()`.

---

#### reconfigure() — do NOT touch batteryReader
Analog: `MetricCollector.swift` lines 97–106

```swift
// MetricCollector.swift lines 97–106 — reconfigure() only resets the timer
func reconfigure() {
    timer?.invalidate()
    timer = nil
    let interval = SettingsManager.shared.refreshInterval
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
            self?.tick()
        }
    }
}
```

**Apply:** `reconfigure()` must not call `batteryReader.setup()` or `batteryReader.readValue()`. The wake observer registered in `setup()` must survive timer reconfiguration. No change to this method.

---

### `MacStatus/MacStatus/UI/Views/DashboardView.swift` (MODIFY)

**Analog:** `DashboardView.swift` itself — DashboardState @Published fields + updateGPU + card background + DashboardView body layout

---

#### @Published field declaration pattern
Analog: `DashboardView.swift` lines 156–186 (DashboardState @Published block)

```swift
// DashboardView.swift lines 173–175 — GPU block as the closest analog (no sparkline samples)
@Published var gpuUsage: Double = 0
@Published var gpuText: String = "--"
@Published var gpuSamples: [Double] = []
```

**Apply:** Battery has no sparkline samples (CONTEXT.md: no sparkline in Phase 7). Add to DashboardState after the GPU block:

```swift
// Battery — add after GPU block
@Published var hasBattery: Bool = false        // false on desktop → section hidden
@Published var battery: BatterySnapshot? = nil // full snapshot for multi-field rendering
```

Using a single `BatterySnapshot?` @Published field (rather than separate per-field @Published vars) is appropriate because: (a) all fields update atomically each tick, (b) the view reads multiple fields from one source of truth, (c) it mirrors the established pattern where the state holds the full struct (NetworkStats, GPUStats, MemoryStats) rather than individual fields.

---

#### updateGPU nil-degradation update method pattern
Analog: `DashboardView.swift` lines 240–249

```swift
// DashboardView.swift lines 240–249 — updateGPU guard-nil pattern
func updateGPU(_ stats: GPUStats?) {
    guard let stats else {
        gpuText = "N/A"
        gpuUsage = 0
        return
    }
    gpuUsage = stats.utilizationPercent
    gpuText = "\(Int(stats.utilizationPercent))%"
    appendSample(&gpuSamples, value: stats.utilizationPercent)
}
```

**Apply:** `updateBattery` follows the same guard-let structure. No `appendSample` call (no sparkline):

```swift
func updateBattery(_ snapshot: BatterySnapshot?) {
    battery = snapshot
    hasBattery = snapshot != nil
}
```

This is deliberately minimal — the view derives all display strings from `battery` directly (or via computed helper functions). DashboardState does not pre-format battery strings (unlike CPU/Memory which format to `cpuText`). This is appropriate because battery has 5+ display strings with complex formatting rules (charging state text, time remaining with sentinel handling, signed watts, health + cycle count). Putting all format logic in the view (or a helper) keeps DashboardState clean and avoids re-publishing individual strings. The planner may choose to add formatted @Published strings instead — either approach is consistent with the codebase; prefer the `battery: BatterySnapshot?` single-field approach for minimal DashboardState surface.

---

#### Card background style pattern
Analog: `DashboardView.swift` lines 144–149 (MetricCardWithSparkline background)

```swift
// DashboardView.swift lines 144–149 — card background style used by all metric cards
.padding(10)
.background(
    RoundedRectangle(cornerRadius: 8)
        .fill(Color.primary.opacity(0.04))
)
```

**Apply to battery section:** The battery section is a full-width section (not a grid card). Use the same background style — `RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04))` — to visually match the 2×2 grid cards. The section uses `.padding(10)` inside the background.

---

#### DashboardView body layout insertion point
Analog: `DashboardView.swift` lines 10–95 (VStack body)

```swift
// DashboardView.swift lines 11–66 — VStack structure
VStack(spacing: 8) {
    // Header (lines 13–19)

    // LazyVGrid 2x2 (lines 21–59)
    LazyVGrid(...) { ... }

    // ← BATTERY SECTION INSERTED HERE (between grid and ProcessListView)

    // Process list (lines 62–66)
    ProcessListView(...)

    // Footer (lines 69–91)
    HStack { ... }
}
.padding(12)
.frame(width: 320)
```

**Apply:** Insert battery section as a conditional view between the `LazyVGrid` closing brace (line 59) and `ProcessListView` (line 62):

```swift
// Battery section — full-width, conditional on hasBattery
if state.hasBattery {
    BatterySectionView(snapshot: state.battery)
}
```

`BatterySectionView` is a private struct defined in the same file (following `MetricCardWithSparkline` as a precedent for companion view structs in DashboardView.swift).

---

#### Footer HStack row style (for battery section internal rows)
Analog: `DashboardView.swift` lines 69–91 (footer HStack)

```swift
// DashboardView.swift lines 69–91 — two-column HStack row style
HStack {
    Label("Self: ...", systemImage: "exclamationmark.triangle.fill")
        .font(.system(size: 9))
        .foregroundStyle(.orange)
    Spacer()
    Text("RAM: ...")
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(.tertiary)
    Spacer()
    Button("Quit MacStatus") { ... }
        .font(.caption2)
}
```

**Apply to BatterySectionView rows:** Each battery row (charge/state, time, watts, health) follows `HStack { Text(label).foregroundStyle(.secondary) Spacer() Text(value).font(.system(.body, design: .monospaced)) }`. The `.caption` / `.secondary` label style and `.monospaced` value style match the metric card header pattern (lines 111–118 of MetricCardWithSparkline).

Metric card header row pattern (lines 111–118):
```swift
// DashboardView.swift lines 111–118 — label/value HStack inside card
HStack {
    Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    Spacer()
    Text(value)
        .font(.system(.body, design: .monospaced))
        .fontWeight(.medium)
        .foregroundStyle(color)
}
```

---

## Shared Patterns

### nil-degradation: reader returns nil → UI hides section
**Source:** `GPUReader.swift` `readValue() -> GPUStats?` + `DashboardView.swift` `updateGPU` lines 240–244
**Apply to:** `BatteryReader.readValue() -> BatterySnapshot?` (nil = no battery) and `DashboardState.updateBattery` + `DashboardView` `if state.hasBattery { ... }` guard.

```swift
// Established pattern — guard let in update method; guard check in view
func updateGPU(_ stats: GPUStats?) {
    guard let stats else {
        gpuText = "N/A"   // graceful placeholder
        gpuUsage = 0
        return
    }
    // ... update published fields
}
```

### IOObjectRelease in defer
**Source:** `GPUReader.swift` lines 55, 60–62
**Apply to:** Every `IOServiceGetMatchingService` and `IOServiceGetMatchingServices` call in BatteryReader. The `defer { IOObjectRelease(...) }` goes immediately after the `guard service != IO_OBJECT_NULL` check.

### @MainActor ObservableObject @Published update methods
**Source:** `DashboardView.swift` lines 154–263 (entire DashboardState class)
**Apply to:** New `updateBattery(_:)` method follows `updateGPU` shape — single guard-let, set all published fields, no appendSample for battery.

### weak self in observer closures
**Source:** `NetworkReader.swift` line 63 (`[weak self]`), `MetricCollector.swift` line 70 (`[weak self]`)
**Apply to:** `BatteryReader.setup()` wake observer closure must capture `[weak self]` to avoid retain cycle.

---

## No Analog Found

None. All three files have strong codebase analogs.

---

## Metadata

**Analog search scope:** `MacStatus/MacStatus/Readers/`, `MacStatus/MacStatus/Collectors/`, `MacStatus/MacStatus/UI/Views/`
**Files read:** GPUReader.swift, NetworkReader.swift, MetricCollector.swift, DashboardView.swift
**Pattern extraction date:** 2026-06-17

---

## PATTERN MAPPING COMPLETE
