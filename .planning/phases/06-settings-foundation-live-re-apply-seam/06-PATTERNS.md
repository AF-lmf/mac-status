# Phase 6: Settings Foundation + Live Re-apply Seam — Pattern Map

**Mapped:** 2026-06-16
**Files analyzed:** 5 (4 modified + 1 new)
**Analogs found:** 5 / 5

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `MacStatus/MacStatus/Utils/SettingsManager.swift` | service/model | request-response (property getter/setter + broadcast) | `MacStatus/MacStatus/Utils/SettingsManager.swift` itself (self-refactor) | self |
| `MacStatus/MacStatus/UI/Views/SettingsView.swift` | component | request-response (SwiftUI binding) | `MacStatus/MacStatus/UI/Views/SettingsView.swift` itself (self-refactor) | self |
| `MacStatus/MacStatus/Collectors/MetricCollector.swift` | service/orchestrator | event-driven + batch | `MacStatus/MacStatus/Collectors/MetricCollector.swift` itself (self-refactor) | self |
| `MacStatus/MacStatus/UI/StatusBarManager.swift` | controller/renderer | request-response + event-driven | `MacStatus/MacStatus/UI/StatusBarManager.swift` itself (self-refactor) | self |
| `MacStatus/MacStatus/Utils/Metric.swift` (NEW) | model/enum | transform | `MacStatus/MacStatus/Utils/SettingsManager.swift` lines 6–13 (`DisplayMode` enum) | role-match |

---

## Pattern Assignments

### `MacStatus/MacStatus/Utils/SettingsManager.swift` (service, request-response + broadcast)

**Analog:** Existing `SettingsManager.swift` — refactor in place, extending the established singleton + computed-property-over-UserDefaults convention.

**Singleton + class declaration pattern** (existing lines 33–41, to be replaced):
```swift
// CURRENT (to be replaced):
final class SettingsManager: @unchecked Sendable {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard
    private init() {}

// TARGET:
@MainActor @Observable
final class SettingsManager {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard
    private init() {
        runMigrations()   // direct UserDefaults writes, no setter calls
        loadAll()         // populate _backing vars without triggering setters
    }
```

**Keys enum pattern** (existing lines 44–54, extend with new keys):
```swift
// Existing Keys enum — add alongside current keys:
private enum Keys {
    // existing:
    static let refreshInterval        = "refreshInterval"
    static let displayMode            = "displayMode"
    static let displayUnit            = "displayUnit"
    static let showIcons              = "showIcons"
    static let cpuWarningThreshold    = "cpuWarningThreshold"
    static let cpuCriticalThreshold   = "cpuCriticalThreshold"
    static let memoryWarningThreshold = "memoryWarningThreshold"
    static let memoryCriticalThreshold = "memoryCriticalThreshold"
    // new in Phase 6:
    static let schemaVersion    = "schemaVersion"
    static let metricOrder      = "metricOrder"
    static let enabledMetrics   = "enabledMetrics"
    static let customThresholds = "customThresholds"
    static let customColors     = "customColors"
    static let launchAtLogin    = "launchAtLogin"
    static let changedKeysUserInfo = "changedKeys"
}
```

**Core property pattern — computed setter with side effects** (replaces existing lines 59–67 style):
```swift
// Existing pattern (lines 59–67) already uses computed getter/setter — GOOD.
// For @Observable the backing var must be explicit and @ObservationIgnored:
@ObservationIgnored private var _refreshInterval: TimeInterval = 2.0

var refreshInterval: TimeInterval {
    get { _refreshInterval }
    set {
        _refreshInterval = newValue
        defaults.set(newValue, forKey: Keys.refreshInterval)
        postChange(keys: [Keys.refreshInterval])
    }
}

// Shared helper to avoid repeating NotificationCenter call:
private func postChange(keys: Set<String>) {
    NotificationCenter.default.post(
        name: .settingsDidChange,
        object: self,
        userInfo: [Keys.changedKeysUserInfo: keys]
    )
}
```

**Enum-typed property pattern** (existing lines 70–78 `displayMode` — same shape applies to new `Metric`-typed props):
```swift
// Existing lines 70–78:
var displayMode: DisplayMode {
    get {
        let raw = defaults.string(forKey: Keys.displayMode) ?? ""
        return DisplayMode(rawValue: raw) ?? .compact
    }
    set {
        defaults.set(newValue.rawValue, forKey: Keys.displayMode)
    }
}
// For @Observable version, back with @ObservationIgnored private var _displayMode and
// put UserDefaults write + postChange in the set block. Same rawValue round-trip.
```

**Collection-typed property pattern** (`metricOrder` as `[Metric]` stored as `[String]`):
```swift
@ObservationIgnored private var _metricOrder: [Metric] = [.cpu, .gpu, .memory, .network]

var metricOrder: [Metric] {
    get { _metricOrder }
    set {
        _metricOrder = newValue
        defaults.set(newValue.map(\.rawValue), forKey: Keys.metricOrder)
        postChange(keys: [Keys.metricOrder])
    }
}
```

**JSON-encoded dictionary property pattern** (`customThresholds` as `[String: [String: Double]]`):
```swift
@ObservationIgnored private var _customThresholds: [String: [String: Double]] = [:]

var customThresholds: [String: [String: Double]] {
    get { _customThresholds }
    set {
        _customThresholds = newValue
        if let data = try? JSONEncoder().encode(newValue) {
            defaults.set(data, forKey: Keys.customThresholds)
        }
        postChange(keys: [Keys.customThresholds])
    }
}
// Same shape for customColors: [String: [String: String]]
```

**`launchAtLogin` setter with side-effect** (mirrors existing `setLaunchAtLogin` in SettingsView lines 110–120):
```swift
@ObservationIgnored private var _launchAtLogin: Bool = false

var launchAtLogin: Bool {
    get { _launchAtLogin }
    set {
        _launchAtLogin = newValue
        defaults.set(newValue, forKey: Keys.launchAtLogin)
        // Side effect — SMAppService registration (migrated from SettingsView):
        do {
            if newValue { try SMAppService.mainApp.register() }
            else        { try SMAppService.mainApp.unregister() }
        } catch {
            print("[Settings] launchAtLogin toggle failed: \(error)")
        }
        postChange(keys: [Keys.launchAtLogin])
    }
}
```

**Migration ladder pattern** (init called before `loadAll`):
```swift
private func runMigrations() {
    let current = defaults.integer(forKey: Keys.schemaVersion)
    // integer(forKey:) returns 0 when key absent — "fresh install"
    if current < 1 { migrateToV1() }
    defaults.set(1, forKey: Keys.schemaVersion)
}

private func migrateToV1() {
    // Write directly to UserDefaults — NOT through property setters.
    // This avoids triggering .settingsDidChange during init.
    if defaults.object(forKey: Keys.metricOrder) == nil {
        defaults.set([Metric.cpu, .gpu, .memory, .network].map(\.rawValue),
                     forKey: Keys.metricOrder)
    }
    if defaults.object(forKey: Keys.enabledMetrics) == nil {
        defaults.set([Metric.cpu, .gpu, .memory, .network].map(\.rawValue),
                     forKey: Keys.enabledMetrics)
    }
    // Existing scalar keys: write defaults so sentinel (> 0) check can be simplified later:
    if defaults.object(forKey: Keys.refreshInterval) == nil {
        defaults.set(2.0, forKey: Keys.refreshInterval)
    }
    // customThresholds / customColors: leave nil (code defaults apply)
}
```

**`loadAll()` pattern** (populates `_backing` vars without triggering setters):
```swift
private func loadAll() {
    _refreshInterval = {
        let v = defaults.double(forKey: Keys.refreshInterval)
        return v > 0 ? v : 2.0
    }()
    _displayMode = {
        let raw = defaults.string(forKey: Keys.displayMode) ?? ""
        return DisplayMode(rawValue: raw) ?? .compact
    }()
    // ... repeat for all properties ...
    _metricOrder = {
        let raws = defaults.stringArray(forKey: Keys.metricOrder) ?? []
        let metrics = raws.compactMap(Metric.init(rawValue:))
        return metrics.isEmpty ? [.cpu, .gpu, .memory, .network] : metrics
    }()
}
```

**Notification name extension** (new, place at file top or in separate extension file):
```swift
extension Notification.Name {
    static let settingsDidChange = Notification.Name("com.macstatus.settingsDidChange")
}
```

---

### `MacStatus/MacStatus/UI/Views/SettingsView.swift` (component, request-response)

**Analog:** Existing `SettingsView.swift` — refactor `@AppStorage` → `@Bindable`.

**Current `@AppStorage` block** (lines 9–17 — to be fully deleted):
```swift
// DELETE all of these:
@AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
@AppStorage("displayMode") private var displayModeRaw: String = DisplayMode.full.rawValue
@AppStorage("displayUnit") private var displayUnitRaw: String = DisplayUnit.auto.rawValue
@AppStorage("showIcons") private var showIcons: Bool = false
@AppStorage("cpuWarningThreshold") private var cpuWarning: Double = 60.0
@AppStorage("cpuCriticalThreshold") private var cpuCritical: Double = 80.0
@AppStorage("memoryWarningThreshold") private var memWarning: Double = 60.0
@AppStorage("memoryCriticalThreshold") private var memCritical: Double = 80.0
@AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
```

**Replacement `@Bindable` declaration** (single property replaces all 9 `@AppStorage` lines):
```swift
struct SettingsView: View {
    @Bindable var settings = SettingsManager.shared
    // No other stored properties needed for settings binding.
```

**Picker binding pattern** (replaces `$refreshInterval` style, existing lines 26–33):
```swift
// Before (line 26): Picker("", selection: $refreshInterval)
// After:
Picker("", selection: $settings.refreshInterval) {
    Text("1s").tag(1.0)
    Text("2s").tag(2.0)
    Text("5s").tag(5.0)
    Text("10s").tag(10.0)
}
```

**Enum picker binding** (replaces `$displayModeRaw` String binding, existing lines 38–43):
```swift
// Before (line 38): Picker("", selection: $displayModeRaw) with .tag(DisplayMode.full.rawValue)
// After — bind directly to the typed enum property:
Picker("", selection: $settings.displayMode) {
    Text("完整").tag(DisplayMode.full)
    Text("紧凑").tag(DisplayMode.compact)
    Text("百分比").tag(DisplayMode.percentage)
}
```

**Toggle without onChange** (existing lines 46–49 — `onChange` no longer needed):
```swift
// Before:
Toggle("登录时启动", isOn: $launchAtLogin)
    .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
// After — SettingsManager.launchAtLogin setter handles SMAppService side-effect:
Toggle("登录时启动", isOn: $settings.launchAtLogin)
// Delete the private func setLaunchAtLogin(_:) entirely from SettingsView.
```

**SettingsWindowManager.showSettings()** (existing lines 136–152 — no change needed):
```swift
// showSettings() creates SettingsView() with no arguments.
// @Bindable var settings = SettingsManager.shared resolves the singleton at init time.
// No parameter passing required. Keep as-is.
let settingsView = SettingsView()
```

---

### `MacStatus/MacStatus/Collectors/MetricCollector.swift` (service/orchestrator, event-driven + batch)

**Analog:** Existing `MetricCollector.swift` — extend in place.

**Existing singleton + timer pattern** (lines 15–43) — the `reconfigure()` and `applyNow()` additions slot into this class without structural change:
```swift
// Existing structure to keep intact:
@MainActor
final class MetricCollector {
    static let shared = MetricCollector()
    private var timer: Timer?
    private init() {}
```

**New `lastSample` cache property** (add alongside existing `pendingSamples` at lines 35–36):
```swift
// Add after line 36 (tickCount):
private var lastSample: MetricSample?
private var settingsObserver: NSObjectProtocol?
```

**Cache population in `tick()`** (add one line after existing `MetricSample(...)` construction at line 95):
```swift
// Existing tick() lines 86–121, add lastSample = sample before updateUI call:
let sample = MetricSample(...)
lastSample = sample        // cache for applyNow()
ringBuffer.append(sample)
// ... rest of tick unchanged
updateUI(sample: sample)
```

**`reconfigure()` — timer-only replacement** (add as new method after `stop()` at line 82):
```swift
/// Reschedule the tick timer to the new refreshInterval.
/// Does NOT touch any reader baseline — preserves NetworkReader.previousBytes.
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

**`applyNow()` — re-push last frame** (add after `reconfigure()`):
```swift
/// Re-push the last cached sample through updateUI without waiting for next tick.
/// Called on appearance-only setting changes (order, enabled-set, thresholds, colors).
func applyNow() {
    guard let sample = lastSample else { return }
    updateUI(sample: sample)
}
```

**NotificationCenter observer registration pattern** (closure form, `queue: .main`; copy this exact shape — do NOT use `@objc #selector` form):
```swift
// Register in start() after timer setup, or in a new setupSettingsObserver() called from start():
settingsObserver = NotificationCenter.default.addObserver(
    forName: .settingsDidChange,
    object: nil,
    queue: .main
) { [weak self] notification in
    guard let self,
          let changedKeys = notification.userInfo?[SettingsManager.changedKeysUserInfoKey] as? Set<String>
    else { return }

    if changedKeys.contains(SettingsManager.Keys.refreshInterval) {
        self.reconfigure()
    } else {
        self.applyNow()
    }
}

// In deinit (MetricCollector is a singleton so deinit is theoretical, but add for completeness):
// NotificationCenter.default.removeObserver(settingsObserver as Any)
```

**Existing Timer construction pattern** (lines 63–67 — `reconfigure()` replicates this exactly):
```swift
// Source pattern in start() (lines 62–67):
let interval = SettingsManager.shared.refreshInterval
timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
    Task { @MainActor [weak self] in
        self?.tick()
    }
}
```

---

### `MacStatus/MacStatus/UI/StatusBarManager.swift` (controller/renderer, event-driven)

**Analog:** Existing `StatusBarManager.swift` — extend in place.

**Existing singleton + `@MainActor` class declaration** (lines 11–17) — keep unchanged:
```swift
@MainActor
final class StatusBarManager {
    static let shared = StatusBarManager()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
```

**New observer storage property** (add alongside `rightClickMenu` at line 22):
```swift
private var settingsObserver: NSObjectProtocol?
```

**NotificationCenter observer in `init`** (add to `private init()` after existing setup calls):
```swift
// After setupRightClickMenu() call:
settingsObserver = NotificationCenter.default.addObserver(
    forName: .settingsDidChange,
    object: nil,
    queue: .main
) { [weak self] _ in
    // Any setting change that reaches StatusBarManager means appearance changed;
    // MetricCollector.applyNow() will re-call updateTitle shortly.
    // StatusBarManager itself has no reconfigure() — it is stateless per-frame.
    // No explicit action needed here; updateTitle will pick up new SM values on
    // next call from MetricCollector.applyNow() or tick().
    _ = self  // satisfy capture warning
}
```

**`updateTitle` refactor — enabled-set + order conditional composition** (replaces existing lines 73–103):
```swift
// Existing updateTitle (lines 73–103) unconditionally builds one of three mode strings.
// Phase 6 refactor: switch on metricOrder + enabledMetrics to filter segments.
func updateTitle(
    cpuUsage: Double?,
    memoryStats: MemoryStats?,
    networkStats: NetworkStats?,
    gpuStats: GPUStats?
) {
    guard let button = statusItem.button else { return }
    let settings = SettingsManager.shared
    let order   = settings.metricOrder           // [Metric]
    let enabled = Set(settings.enabledMetrics)   // Set<Metric>
    let mode    = settings.displayMode

    let active = order.filter { enabled.contains($0) }
    if active.isEmpty {
        button.title = "◆"   // minimal placeholder — never empty status bar
        return
    }

    let result = NSMutableAttributedString()
    for (index, metric) in active.enumerated() {
        if index > 0 { result.append(separator()) }
        switch metric {
        case .cpu:
            result.append(cpuSegment(cpuUsage, mode: mode))
        case .memory:
            result.append(memSegment(memoryStats, mode: mode))
        case .network:
            result.append(netSegment(networkStats, mode: mode))
        case .gpu:
            result.append(gpuSegment(gpuStats, mode: mode))
        case .battery:
            break   // Phase 7 activates this case
        }
    }
    button.attributedTitle = result
}
```

**Segment helper extraction** (refactor the existing `buildFullTitle`/`buildCompactTitle`/`buildPercentageTitle` inline code into per-metric helpers that accept a `mode` parameter):
```swift
// Existing segment() helper (lines 272–290) — keep as-is.
// Existing separator() helper (lines 272–280) — keep as-is.

// New per-metric segment helpers (extract from existing build*Title methods):
private func cpuSegment(_ cpu: Double?, mode: DisplayMode) -> NSAttributedString {
    switch mode {
    case .full:
        let text = cpu.map { "CPU: \(Int($0))%" } ?? "CPU: --"
        let color = cpu.map { colorForUsage($0, metric: .cpu) } ?? .secondaryLabelColor
        return segment(text, color: color)
    case .compact:
        let text = cpu.map { "C:\(Int($0))%" } ?? "C:--"
        let color = cpu.map { colorForUsage($0, metric: .cpu) } ?? .secondaryLabelColor
        return segment(text, color: color)
    case .percentage:
        let text = cpu.map { "\(Int($0))%" } ?? "--"
        let color = cpu.map { colorForUsage($0, metric: .cpu) } ?? .secondaryLabelColor
        return segment(text, color: color)
    }
}
// Similar helpers for memSegment, netSegment, gpuSegment.
```

**`colorForUsage` refactor — accepts `Metric` enum, reads custom thresholds/colors** (replaces existing lines 298–311):
```swift
// Existing (lines 292–311) — private MetricType enum is replaced by the new Metric enum:
private func colorForUsage(_ percent: Double, metric: Metric) -> NSColor {
    let settings = SettingsManager.shared

    // Custom thresholds (fall back to hard-coded defaults):
    let warning  = settings.customThresholds[metric.rawValue]?["warning"]
                   ?? defaultWarning(for: metric)
    let critical = settings.customThresholds[metric.rawValue]?["critical"]
                   ?? defaultCritical(for: metric)

    // Custom colors (fall back to semantic system colors):
    if percent >= critical {
        if let hex = settings.customColors[metric.rawValue]?["critical"],
           let color = NSColor(hex: hex) { return color }
        return .systemRed
    } else if percent >= warning {
        if let hex = settings.customColors[metric.rawValue]?["warning"],
           let color = NSColor(hex: hex) { return color }
        return .systemOrange
    }
    return .labelColor   // semantic; adapts to dark/light mode
}

private func defaultWarning(for metric: Metric) -> Double {
    switch metric {
    case .cpu:    return SettingsManager.shared.cpuWarningThreshold
    case .memory: return SettingsManager.shared.memoryWarningThreshold
    case .gpu:    return 80.0
    default:      return 80.0
    }
}

private func defaultCritical(for metric: Metric) -> Double {
    switch metric {
    case .cpu:    return SettingsManager.shared.cpuCriticalThreshold
    case .memory: return SettingsManager.shared.memoryCriticalThreshold
    case .gpu:    return 90.0
    default:      return 90.0
    }
}
```

---

### `MacStatus/MacStatus/Utils/Metric.swift` (NEW — model enum)

**Analog:** `DisplayMode` enum in `SettingsManager.swift` lines 6–13 — exact same structure (String rawValue, CaseIterable, Sendable).

**`DisplayMode` as template** (existing lines 6–13):
```swift
// Existing DisplayMode — copy this exact declaration shape:
enum DisplayMode: String, CaseIterable, Sendable {
    case full
    case compact
    case percentage
}
```

**`Metric` enum — copy shape, adapt cases**:
```swift
// MacStatus/MacStatus/Utils/Metric.swift
// New file — mirrors DisplayMode declaration shape exactly.

/// Stable identifier for each monitored metric.
/// rawValue is the UserDefaults key component for metricOrder, enabledMetrics,
/// customThresholds, and customColors.
enum Metric: String, CaseIterable, Sendable {
    case cpu     = "cpu"
    case memory  = "memory"
    case network = "network"
    case gpu     = "gpu"
    case battery = "battery"  // reserved; Phase 7 activates
}
```

**File placement:** `MacStatus/MacStatus/Utils/Metric.swift` — alongside `SettingsManager.swift` and `ByteFormatting.swift`. This keeps all model/utility types in `Utils/`.

---

## Shared Patterns

### `@MainActor` Singleton Declaration
**Source:** `MetricCollector.swift` lines 15–21, `StatusBarManager.swift` lines 11–17, `PopoverManager.swift` lines 11–17
**Apply to:** All managers. The pattern is:
```swift
@MainActor
final class FooManager {
    static let shared = FooManager()
    private init() {}
}
```
For `SettingsManager`, add `@Observable` before `@MainActor` and remove `@unchecked Sendable`.

### Timer Construction + Task Hop
**Source:** `MetricCollector.swift` lines 63–67
**Apply to:** `MetricCollector.reconfigure()` — copy exactly:
```swift
timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
    Task { @MainActor [weak self] in
        self?.tick()
    }
}
```

### NotificationCenter Observer (Closure Form)
**Source:** Specified in RESEARCH.md Pattern 3 — no existing codebase usage yet (this is a new pattern for Phase 6).
**Apply to:** Both `MetricCollector.swift` and `StatusBarManager.swift`.
**Critical constraint:** Always use `addObserver(forName:object:queue:.main)` closure form. Never use `@objc #selector` form (swift#74037 crash with `@MainActor`).

### `NSAttributedString` Segment Composition
**Source:** `StatusBarManager.swift` lines 114–167 (`buildFullTitle`) and lines 272–290 (`segment()`, `separator()`)
**Apply to:** Refactored `updateTitle` in `StatusBarManager.swift`.
```swift
// Existing segment() helper — keep unchanged:
private func segment(_ text: String, color: NSColor) -> NSAttributedString {
    NSAttributedString(
        string: text,
        attributes: [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        ]
    )
}
// Separator — keep unchanged (lines 272–280).
```

### UserDefaults Computed Property (Getter + Setter)
**Source:** `SettingsManager.swift` lines 59–67 (`refreshInterval`), lines 70–78 (`displayMode`)
**Apply to:** All new properties in the refactored `SettingsManager`. The pattern of `get { defaults.X(forKey:) }` / `set { defaults.set(...); postChange(...) }` is already established — extend it for all new keys.

### Error Handling for System API Side-Effects
**Source:** `SettingsView.swift` lines 110–120 (`setLaunchAtLogin`)
**Apply to:** `SettingsManager.launchAtLogin` setter — same `do { try SMAppService... } catch { print(...) }` pattern, migrated from SettingsView into SettingsManager.
```swift
// Existing (SettingsView lines 110–120) — migrate verbatim into SM setter:
do {
    if enabled { try SMAppService.mainApp.register() }
    else       { try SMAppService.mainApp.unregister() }
} catch {
    print("[Settings] Failed to \(enabled ? "register" : "unregister") login item: \(error)")
}
```

---

## No Analog Found

No files in this phase lack an analog. All five files either self-refactor from a strong existing base, or map directly to the `DisplayMode` enum pattern (`Metric.swift`).

---

## Compact Mode Order Note (Pitfall 6 Resolution)

The existing `buildCompactTitle` (lines 173–218) appends segments in this order:
1. CPU (`C:xx%`) — line 183
2. GPU (`G:xx%`) — line 188
3. Memory (`M:xx%`) — line 195
4. Network (`N:↑↓`) — line 207

Default `metricOrder` MUST be `[.cpu, .gpu, .memory, .network]` to preserve v1.0 behavior under the compact display mode (which is the current default `displayMode`). Using full-mode order `[.cpu, .memory, .network, .gpu]` would violate the "upgrade zero behavior change" constraint.

---

## Metadata

**Analog search scope:** `MacStatus/MacStatus/` — all 21 Swift files
**Files scanned:** 6 files read in full (SettingsManager, MetricCollector, StatusBarManager, SettingsView, PopoverManager, ReaderProtocol)
**Pattern extraction date:** 2026-06-16
