# Phase 9: Settings Window UI + Customization — Pattern Map

**Mapped:** 2026-06-17
**Files analyzed:** 3 (all modifications to existing files)
**Analogs found:** 3 / 3 (all exact role-match within the same files being modified)

---

## File Classification

| Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------|------|-----------|----------------|---------------|
| `MacStatus/MacStatus/Utils/SettingsManager.swift` | model/singleton | CRUD + event-driven | Same file — existing `showIcons`/`launchAtLogin` bool properties + `customThresholds`/`customColors` dict properties | exact |
| `MacStatus/MacStatus/UI/Views/SettingsView.swift` | view (settings form) | request-response (immediate binding) | Same file — existing `Section("告警阈值")` Slider block + `Section("通用")` Toggle/Picker block | exact |
| `MacStatus/MacStatus/UI/Views/DashboardView.swift` | view (popover content) | event-driven (@Observable) | Same file — existing `if state.hasBattery, let battery = state.battery { BatterySectionView(...) }` pattern (line 62) | exact |

---

## Pattern Assignments

### `SettingsManager.swift` — New bool keys `showBatterySection` / `showProcessSection`

**Analog:** Existing `showIcons` bool property (lines 98, 143–149) and `launchAtLogin` bool property (lines 105, 217–235). For bool keys with a non-false default, the `loadAll()` nil-check pattern on lines 352–374.

**Keys enum addition** (copy from lines 64–82, add two new entries after `launchAtLogin`):
```swift
// In private enum Keys { ... }
static let showBatterySection = "showBatterySection"
static let showProcessSection = "showProcessSection"
```

**Backing storage pattern** (lines 98, 105 — copy shape exactly):
```swift
@ObservationIgnored private var _showIcons: Bool = false        // existing
@ObservationIgnored private var _launchAtLogin: Bool = false    // existing

// New: default true (popover sections shown by default)
@ObservationIgnored private var _showBatterySection: Bool = true
@ObservationIgnored private var _showProcessSection: Bool = true
```

**Computed get/set + postChange pattern** (lines 143–149 — simplest bool setter; no side-effects unlike launchAtLogin):
```swift
var showIcons: Bool {           // existing analog
    get { _showIcons }
    set {
        _showIcons = newValue
        defaults.set(newValue, forKey: Keys.showIcons)
        postChange(keys: [Keys.showIcons])
    }
}

// New properties follow identical shape:
var showBatterySection: Bool {
    get { _showBatterySection }
    set {
        _showBatterySection = newValue
        defaults.set(newValue, forKey: Keys.showBatterySection)
        postChange(keys: [Keys.showBatterySection])
    }
}
```

**loadAll() nil-check for numeric keys** (lines 352–374 — use the same `object(forKey:) == nil` guard, because `UserDefaults.bool(forKey:)` returns `false` when key is absent, but we need default `true`):
```swift
// Existing analog pattern (lines 352–357):
if let raw = defaults.object(forKey: Keys.cpuWarningThreshold) as? Double {
    _cpuWarningThreshold = raw
} else {
    _cpuWarningThreshold = 60.0
}

// New bool keys — same intent but for Bool:
if defaults.object(forKey: Keys.showBatterySection) == nil {
    _showBatterySection = true      // default: show battery section
} else {
    _showBatterySection = defaults.bool(forKey: Keys.showBatterySection)
}

if defaults.object(forKey: Keys.showProcessSection) == nil {
    _showProcessSection = true      // default: show process section
} else {
    _showProcessSection = defaults.bool(forKey: Keys.showProcessSection)
}
```

**No schemaVersion bump.** The existing `migrateToV1()` (lines 294–332) writes defaults only for keys expected to be absent at first launch; new bool keys use the loadAll nil-check pattern instead (same as `customThresholds`/`customColors` which are left nil in `migrateToV1()`, line 331).

---

### `SettingsManager.swift` — "恢复默认" clear pattern for nested dict keys

**Analog:** Existing `customThresholds` setter (lines 241–254) and `customColors` setter (lines 257–278) — both write the full dict to UserDefaults via JSONEncoder. The "恢复默认" action is a removeValue then reassign to trigger the setter.

**Nested dict setter pattern** (lines 241–254):
```swift
var customThresholds: [String: [String: Double]] {
    get { _customThresholds }
    set {
        var clamped: [String: [String: Double]] = [:]
        for (metric, levels) in newValue {
            clamped[metric] = levels.mapValues { max(0.0, min(100.0, $0)) }
        }
        _customThresholds = clamped
        if let data = try? JSONEncoder().encode(clamped) {
            defaults.set(data, forKey: Keys.customThresholds)
        }
        postChange(keys: [Keys.customThresholds])
    }
}
```

**"恢复默认" clear pattern** (remove key from dict, reassign to trigger setter + postChange + applyNow):
```swift
// ThresholdSubsection.resetThresholds() — copy this exact pattern:
var updated = settings.customThresholds
updated.removeValue(forKey: metric.rawValue)
settings.customThresholds = updated    // triggers setter: clamp + JSONEncode + postChange

// ColorSubsection.resetColors() — same shape for customColors:
var updated = settings.customColors
updated.removeValue(forKey: metric.rawValue)
settings.customColors = updated
```

---

### `SettingsView.swift` — New and modified sections

**Analog:** Existing sections in SettingsView.swift (lines 11–95). The whole view is the analog.

**Top-level view structure** (lines 7–95 — keep identical @Bindable binding, Form, formStyle):
```swift
struct SettingsView: View {
    @Bindable var settings = SettingsManager.shared   // line 8 — DO NOT CHANGE

    var body: some View {
        Form {
            // sections...
        }
        .formStyle(.grouped)           // line 91
        .frame(width: 380, height: 440) // line 92 — change to .frame(width: 420) + .frame(minHeight: 400)
        .padding()                     // line 93
    }
}
```

**Existing Section("通用") Toggle pattern** (lines 37 — direct @Bindable binding to bool property):
```swift
Toggle("登录时启动", isOn: $settings.launchAtLogin)
// New toggles follow same shape:
Toggle("电池区块", isOn: $settings.showBatterySection)
Toggle("进程区块", isOn: $settings.showProcessSection)
```

**Existing Section("通用") Picker pattern** (lines 26–35 — $settings.displayMode binding):
```swift
HStack {
    Text("显示模式")
    Spacer()
    Picker("", selection: $settings.displayMode) {
        Text("完整").tag(DisplayMode.full)
        Text("紧凑").tag(DisplayMode.compact)
        Text("百分比").tag(DisplayMode.percentage)
    }
    .frame(width: 120)
}
// Section 4 moves/relabels this Picker; change to .pickerStyle(.segmented), relabel tags
```

**Existing Section("告警阈值") VStack+Slider pattern** (lines 41–57 — the pattern ThresholdSubsection generalizes):
```swift
Section("告警阈值") {
    VStack(alignment: .leading, spacing: 8) {
        Text("CPU 警告：\(Int(settings.cpuWarningThreshold))%")
        Slider(value: $settings.cpuWarningThreshold, in: 30...90, step: 5)

        Text("CPU 严重：\(Int(settings.cpuCriticalThreshold))%")
        Slider(value: $settings.cpuCriticalThreshold, in: 50...95, step: 5)

        Divider()
        // ... memory sliders ...
    }
}
// Phase 9 REPLACES this entire section with per-metric ThresholdSubsection structs
// The VStack(alignment: .leading, spacing: 8) + Text label + Slider shape is preserved
// inside each ThresholdSubsection
```

**Section("数据") + Section("关于") pattern** (lines 59–94 — preserve exactly, move to positions 7+8):
```swift
Section("数据") { ... }    // lines 59–73 — no change
Section("关于") { ... }    // lines 75–90 — bump version to v2.0
```

**New sub-struct binding pattern** (computed Binding as struct computed property — NOT body-local):

The key pitfall: do NOT write `let binding = Binding { ... }` inside `var body`. Instead:

```swift
// WRONG — causes infinite re-render:
var body: some View {
    let enabledBinding = Binding { settings.enabledMetrics.contains(metric) } set: { ... }
    Toggle("", isOn: enabledBinding)
}

// CORRECT — computed property on the struct:
private var enabledBinding: Binding<Bool> {
    Binding {
        settings.enabledMetrics.contains(metric)
    } set: { enabled in
        if enabled {
            if !settings.enabledMetrics.contains(metric) {
                settings.enabledMetrics.append(metric)
            }
        } else {
            settings.enabledMetrics.removeAll { $0 == metric }
        }
    }
}
```

**MetricOrderRow sub-struct shape** — no existing analog in codebase; use RESEARCH.md Q1 pattern verbatim. Key points:
- `private struct MetricOrderRow: View` with `@Bindable var settings: SettingsManager`
- `@State private var isHoveringHandle = false` for `.moveDisabled(!isHoveringHandle)`
- No `EditMode` — macOS SDK marks it `@available(macOS, unavailable)`
- `.frame(height: CGFloat(settings.metricOrder.count) * 36)` on the `List`
- `.listStyle(.plain)` inside `Form` to avoid double-grouped appearance

**ThresholdSubsection sub-struct shape** — partial analog from existing `告警阈值` VStack (lines 42–56). Generalizes it per-metric with computed Bindings. Key additions vs. existing code:
- `@Bindable var settings: SettingsManager` (same as MetricOrderRow)
- `thresholdBinding(for:default:)` computed property returns `Binding<Double>` reading `settings.customThresholds[metric.rawValue]?[level] ?? defaultValue`
- `.onChange(of: warningBinding.wrappedValue) { _, newWarning in ... }` for warning < critical enforcement (Swift 6 two-argument signature)
- `Button("恢复默认")` with `.buttonStyle(.borderless).foregroundStyle(.accentColor)`

**ColorSubsection sub-struct shape** — no existing analog (ColorPicker is new). Use RESEARCH.md Q2 pattern. Key points:
- `colorBinding(for:defaultHex:)` computed property: read hex → `NSColor(hex:)` → `Color(nsColor:)`; write `NSColor(newColor).hexString` → update `settings.customColors`
- `ColorPicker("警告色", selection: warningColorBinding, supportsOpacity: false)` with `.labelsHidden().frame(width: 44)`
- `HStack { Text("警告色"); Spacer(); ColorPicker(...) }` layout

---

### `DashboardView.swift` — Visibility gating for battery and process sections

**Analog:** Existing `if state.hasBattery, let battery = state.battery { BatterySectionView(...) }` (lines 62–64) — the hardware gate. Phase 9 adds a settings gate on top.

**Existing hardware gate pattern** (lines 62–64):
```swift
// Battery section (laptops only; entire section hidden on desktop Macs)
if state.hasBattery, let battery = state.battery {
    BatterySectionView(snapshot: battery)
}
```

**New combined gate pattern** (settings gate wraps hardware gate):
```swift
// Battery: settings gate (outer) + hardware gate (inner, preserved)
if settings.showBatterySection && state.hasBattery, let battery = state.battery {
    BatterySectionView(snapshot: battery)
}

// Process sections: settings gate only (no hardware condition)
if settings.showProcessSection {
    ProcessListView(
        processes: state.topProcesses,
        isLoading: state.processesLoading,
        errorMessage: state.processError
    )
    ProcessResourceSectionView(title: "CPU 占用 Top 5", ...)
    ProcessResourceSectionView(title: "内存占用 Top 5", ...)
}
```

**@Observable access pattern** — DashboardView.body already has `@EnvironmentObject private var state: DashboardState` (line 8). Add `SettingsManager.shared` access in `body` to establish Observation tracking:
```swift
var body: some View {
    let settings = SettingsManager.shared   // body-local let; @Observable auto-tracks reads
    VStack(spacing: 8) {
        // ... existing content ...
        if settings.showBatterySection && state.hasBattery, let battery = state.battery {
```

No `@State` needed — `SettingsManager.shared` is `@Observable @MainActor` singleton; reading it in `body` establishes the Observation dependency automatically (RESEARCH.md Q5, confirmed by Swift Observation framework semantics).

---

## Shared Patterns

### @Bindable binding — all new SettingsView sub-structs
**Source:** `SettingsView.swift` line 8
```swift
@Bindable var settings = SettingsManager.shared
```
**Apply to:** `MetricOrderRow`, `ThresholdSubsection`, `ColorSubsection` — each receives `settings` as an init parameter with `@Bindable var settings: SettingsManager`.

### postChange + .settingsDidChange propagation
**Source:** `SettingsManager.swift` lines 411–417
```swift
private func postChange(keys: Set<String>) {
    NotificationCenter.default.post(
        name: .settingsDidChange,
        object: self,
        userInfo: [SettingsManager.changedKeysUserInfoKey: keys]
    )
}
```
**Apply to:** Both new bool keys (`showBatterySection`, `showProcessSection`) call `postChange` in their setters. This triggers MetricCollector's `settingsObserver` → `applyNow()`, which is harmless for popover-only keys (DashboardView responds via @Observable directly).

### Button "恢复默认" style
**Source:** RESEARCH.md Q2/Q3 (no existing analog in codebase — ColorPicker and reset buttons are new)
```swift
Button("恢复默认") { resetThresholds() }   // or resetColors()
    .buttonStyle(.borderless)
    .foregroundStyle(.accentColor)
```
**Apply to:** Both `ThresholdSubsection` and `ColorSubsection` — identical button style.

### Section label + Divider cadence
**Source:** `SettingsView.swift` lines 41–57 (existing `告警阈值` section)
```swift
Section("告警阈值") {
    VStack(alignment: .leading, spacing: 8) {
        // per-metric content
        Divider()   // between metrics
        // next metric
    }
}
```
**Apply to:** Section 5 (`告警阈值`) and Section 6 (`配色`) — use `Divider()` between metric groups. Per RESEARCH.md Code Examples: `if metric != .gpu { Divider() }` (skip trailing divider after last metric).

---

## No Analog Found

| Pattern | Role | Data Flow | Reason |
|---------|------|-----------|--------|
| `ColorPicker` row + `Binding<Color>` ↔ hex | view sub-struct | request-response | `ColorPicker` is new in this codebase; no prior usage. Use RESEARCH.md Q2 `colorBinding(for:defaultHex:)` pattern. |
| `List { ForEach.onMove }` drag reorder | view sub-struct | event-driven | No existing reorderable List in codebase. Use RESEARCH.md Q1 pattern. `EditMode` is `@available(macOS, unavailable)` — do not use. |
| `MetricOrderRow` with `moveDisabled/onHover` | view sub-struct | event-driven | No existing drag-handle row. Use RESEARCH.md Q1 `isHoveringHandle` + `.moveDisabled(!isHoveringHandle)` pattern. |

---

## pbxproj Registration Note

All new structs (`MetricOrderRow`, `ThresholdSubsection`, `ColorSubsection`) are to be defined as **private structs within `SettingsView.swift`**. No new `.swift` files are created, so no `project.pbxproj` change is required. If executor splits any struct into a new file, it **must** register it in `MacStatus.xcodeproj/project.pbxproj` (Phase 7/8 lesson — build will silently succeed in Xcode but CI will fail).

---

## Metadata

**Analog search scope:** `MacStatus/MacStatus/Utils/SettingsManager.swift`, `MacStatus/MacStatus/UI/Views/SettingsView.swift`, `MacStatus/MacStatus/UI/Views/DashboardView.swift`
**Files scanned:** 3 (the three files being modified; no new files)
**Pattern extraction date:** 2026-06-17

---

## PATTERN MAPPING COMPLETE
