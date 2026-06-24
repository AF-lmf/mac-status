# Phase 10: Thermal Read-Only Monitoring - Pattern Map

**Mapped:** 2026-06-24
**Files analyzed:** 7 new/modified files
**Analogs found:** 7 / 7

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `MacStatus/MacStatus/Readers/ThermalReader.swift` | reader/model | request-response | `MacStatus/MacStatus/Readers/BatteryReader.swift` | exact |
| `MacStatus/MacStatus/Readers/SMCReader.swift` | reader/utility | request-response | existing same file | exact |
| `MacStatus/MacStatus/Collectors/MetricCollector.swift` | collector/service | event-driven tick | existing battery integration in same file | exact |
| `MacStatus/MacStatus/UI/Views/DashboardView.swift` | component/state | request-response UI render | `BatterySectionView` + `DashboardState` in same file | exact |
| `MacStatus/MacStatus/Utils/SettingsManager.swift` | config/store | event-driven notification | `showBatterySection` / `showProcessSection` | exact |
| `MacStatus/MacStatus/UI/Views/SettingsView.swift` | component | request-response form binding | existing `弹窗区块` section | exact |
| `MacStatus/MacStatus.xcodeproj/project.pbxproj` | config | build registration | existing `BatteryReader.swift` / `SMCReader.swift` entries | exact |

## Pattern Assignments

### `MacStatus/MacStatus/Readers/ThermalReader.swift` (reader/model, request-response)

**Analog:** `MacStatus/MacStatus/Readers/BatteryReader.swift`

**Imports pattern** (lines 1-4):
```swift
import Foundation
import IOKit
import IOKit.ps
import AppKit
```

Use `Foundation` for `ProcessInfo.thermalState`, `IOKit` for SMC/AppleSmartBattery registry reads, and only add `IOKit.ps`/`AppKit` if reusing power-source or wake patterns. Keep this file dependency-free.

**Snapshot model pattern** (lines 6-14, 32-49):
```swift
/// Immutable, value-type-only battery reading that safely crosses actor boundaries.
struct BatterySnapshot: Sendable, Equatable {
    let chargePercent: Int
    let isCharging: Bool
    let isOnAC: Bool
    let watts: Double?
    let healthPercent: Double?
    let cycleCount: Int?
    let systemPowerWatts: Double?
}
```

Copy this as `ThermalSnapshot: Sendable, Equatable` with optional current readings:
`cpuSocTemperatureCelsius: Double?`, `gpuTemperatureCelsius: Double?`, `batteryTemperatureCelsius: Double?`, and non-optional/optional semantic state such as `thermalState: ProcessInfo.ThermalState`.

**Reader ownership/setup pattern** (lines 67-90):
```swift
final class BatteryReader {
    private let smcReader = SMCReader()

    func setup() {
        smcReader.open()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(...)
    }
}
```

For `ThermalReader`, own an `SMCReader`, call `smcReader.open()` in `setup()`, and read synchronously from `MetricCollector.tick()`. Do not subclass `TimerReader` unless there is a specific reason; battery already establishes the current synchronous snapshot pattern.

**Probe-and-nil degradation pattern** (lines 108-132):
```swift
func readValue() -> BatterySnapshot? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }

    guard let desc = psDict,
          let chargePercent = desc[kIOPSCurrentCapacityKey] as? Int,
          let isChargingPS = desc[kIOPSIsChargingKey] as? Bool,
          let stateStr = desc[kIOPSPowerSourceStateKey] as? String
    else { return nil }
}
```

Thermal differs in one important way: return a `ThermalSnapshot` even when all temperature fields are nil, because `ProcessInfo.thermalState` and stable UI rows should still render. Individual sensor values degrade to `nil`; no crashes, no popups, no repeated logging.

**IORegistry fallback pattern** (lines 185-200, 218-239):
```swift
guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
      let props = propsRef?.takeRetainedValue() as? [String: Any]
else {
    return BatterySnapshot(..., healthPercent: nil, cycleCount: nil, ...)
}

let healthPercent: Double? = {
    guard let rawMax = props["AppleRawMaxCapacity"] as? Int,
          let design = props["DesignCapacity"] as? Int,
          design > 0 else { return nil }
    return min(100.0, Double(rawMax) / Double(design) * 100.0)
}()
```

Use this style for AppleSmartBattery temperature fallback: read properties with `as?`, validate units/range, and set only `batteryTemperatureCelsius` to nil if unavailable.

**Strict trust guardrail:** Context decisions D-01/D-03 forbid “hottest” or ambiguous package fallback as primary CPU/SoC. Candidate SMC keys must be explicit and machine-gated; if Mac15,9 trust evidence is absent, set `cpuSocTemperatureCelsius = nil`.

---

### `MacStatus/MacStatus/Readers/SMCReader.swift` (reader/utility, request-response)

**Analog:** existing `SMCReader.swift`

**Read-only contract** (lines 6-18):
```swift
/// Minimal **read-only** client for the Apple System Management Controller (SMC).
/// Every read degrades to `nil` when the connection is unavailable or the key/type
/// is unknown on this hardware, so callers render "—" rather than a fake value.
final class SMCReader {
```

Preserve the read-only boundary. Phase 10 may add internal typed/raw read helpers, but must not add public SMC write APIs or fan-control commands.

**AppleSMC ABI constants and layout guard** (lines 24-31, 91-100):
```swift
private static let kernelIndexSMC: UInt32 = 2
private static let cmdReadBytes: UInt8 = 5
private static let cmdReadKeyInfo: UInt8 = 9

assert(MemoryLayout<SMCParamStruct>.stride == 80, "SMCParamStruct must be 80 bytes")
guard MemoryLayout<SMCParamStruct>.stride == 80 else { return false }
```

Any new raw helper should reuse `cmdReadKeyInfo` then `cmdReadBytes`; do not change struct layout. Keep the stride guard.

**Current read sequence** (lines 122-145):
```swift
func readValue(key: String) -> Double? {
    guard isOpen else { return nil }

    var info = SMCParamStruct()
    info.key = Self.fourCharCode(key)
    info.data8 = Self.cmdReadKeyInfo
    guard let infoOut = call(info), infoOut.result == 0 else { return nil }

    let size = infoOut.keyInfo.dataSize
    let type = infoOut.keyInfo.dataType
    guard size > 0 else { return nil }

    var read = SMCParamStruct()
    read.key = Self.fourCharCode(key)
    read.keyInfo.dataSize = size
    read.data8 = Self.cmdReadBytes
    guard let readOut = call(read), readOut.result == 0 else { return nil }

    return Self.decode(type: type, size: size, bytes: readOut.bytes)
}
```

If `ThermalReader` needs type-aware trust, extract the same sequence into a read-only `SMCValue` helper containing key/type/size/bytes, then keep `readValue(key:)` implemented on top of that helper for existing callers.

**Decode pattern** (lines 174-200):
```swift
private static func decode(type: UInt32, size: UInt32, bytes: SMCBytes32) -> Double? {
    let raw = withUnsafeBytes(of: bytes) { Array($0.prefix(Int(size))) }
    if type == typeFLT, raw.count >= 4 { ... }
    if raw.count >= 2,
       typeChars[1] == UInt8(ascii: "p"),
       let fracBits = hexDigit(typeChars[3]) {
        ...
    }
    return nil
}
```

For temperature reads, decode through this same numeric path, then range-check Celsius values, e.g. `0...120`. Unknown formats return nil.

---

### `MacStatus/MacStatus/Collectors/MetricCollector.swift` (collector/service, event-driven tick)

**Analog:** existing battery snapshot integration in `MetricCollector.swift`

**Reader property and cached snapshot pattern** (lines 28-46):
```swift
private let gpuReader = GPUReader()
private let batteryReader = BatteryReader()

// Last battery snapshot — kept separately from MetricSample (no persistence, no sparkline)
private var lastBatterySnapshot: BatterySnapshot? = nil
```

Add `private let thermalReader = ThermalReader()` and `private var lastThermalSnapshot: ThermalSnapshot? = nil`. Keep thermal out of `MetricSample`, `RingBuffer`, `HistoryStore`, status-bar metric order, and sparklines.

**Setup and baseline read pattern** (lines 57-72):
```swift
cpuReader.setup()
memoryReader.setup()
networkReader.setup()
gpuReader.setup()
batteryReader.setup()

_ = cpuReader.readValue()
_ = memoryReader.readValue()
_ = networkReader.readValue()
_ = gpuReader.readValue()
_ = batteryReader.readValue()
```

Insert `thermalReader.setup()` and a first `_ = thermalReader.readValue()` alongside battery. Do not create a second timer.

**Tick pattern** (lines 146-156):
```swift
private func tick() {
    let cpu = cpuReader.readValue()
    let mem = memoryReader.readValue()
    let net = networkReader.readValue()
    let gpu = gpuReader.readValue()
    let battery = batteryReader.readValue()
    lastBatterySnapshot = battery
```

Read `let thermal = thermalReader.readValue()` on the same `@MainActor` tick and set `lastThermalSnapshot = thermal`.

**UI update pattern** (lines 206-210):
```swift
// Battery — pushed from the separately-cached snapshot (not part of MetricSample,
// no persistence, no sparkline). nil on desktop → DashboardState hides the section.
// Reached from both tick() and applyNow(), so a settings-driven repaint keeps it live.
dashboard.updateBattery(lastBatterySnapshot)
```

Add `dashboard.updateThermal(lastThermalSnapshot)` next to battery. `applyNow()` must repaint the cached thermal snapshot without forcing a fresh SMC read.

---

### `MacStatus/MacStatus/UI/Views/DashboardView.swift` (component/state, request-response UI render)

**Analog:** `BatterySectionView` and `DashboardState` in same file.

**Settings-gated section placement** (lines 62-70):
```swift
if settings.showBatterySection && state.hasBattery, let battery = state.battery {
    BatterySectionView(snapshot: battery)
}

if settings.showProcessSection {
    ProcessListView(...)
}
```

Add `ThermalSectionView` after battery and before process sections. Gate only by `settings.showThermalSection`; do not hide the section just because values are `nil`.

**Card/header/row style** (lines 193-228):
```swift
VStack(alignment: .leading, spacing: 6) {
    HStack {
        Text("电池")
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
        Text("\(snapshot.chargePercent)% · \(chargeStateText)")
            .font(.system(.body, design: .monospaced))
            .fontWeight(.medium)
            .foregroundStyle(.primary)
    }

    row(timeLabel, timeText)
}
.padding(10)
.background(
    RoundedRectangle(cornerRadius: 8)
        .fill(Color.primary.opacity(0.04))
)

private func row(_ label: String, _ value: String) -> some View {
    HStack {
        Text(label).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Text(value).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
    }
}
```

For Phase 10, prefer UI-SPEC spacing `.padding(8)` / row spacing `8` unless direct reuse of legacy card padding is chosen. Values must be monospaced and right aligned with a fixed/min trailing width.

**Value formatting pattern** (lines 279-293):
```swift
private var systemPowerText: String {
    guard let p = snapshot.systemPowerWatts else { return "—" }
    return "\(String(format: "%.1f", p))W"
}
```

Thermal formatting should use integer Celsius: `58°C`; unavailable temperatures use `N/A`; non-temperature unknown state can use `—` or `未知` per UI-SPEC. Do not display raw SMC keys.

**DashboardState storage/update pattern** (lines 371-373, 457-461):
```swift
@Published var battery: BatterySnapshot? = nil
@Published var hasBattery: Bool = false

func updateBattery(_ snapshot: BatterySnapshot?) {
    battery = snapshot
    hasBattery = snapshot != nil
}
```

Add `@Published var thermal: ThermalSnapshot? = nil` and `func updateThermal(_ snapshot: ThermalSnapshot?) { thermal = snapshot }`. Avoid a `hasThermal` hardware gate unless it remains true for stable empty snapshots; settings toggle controls visibility.

---

### `MacStatus/MacStatus/Utils/SettingsManager.swift` (config/store, event-driven notification)

**Analog:** `showBatterySection` / `showProcessSection`

**Key declaration pattern** (lines 83-86):
```swift
// Phase 9 new keys
static let showBatterySection = "showBatterySection"
static let showProcessSection = "showProcessSection"
```

Add `static let showThermalSection = "showThermalSection"` near the section visibility keys.

**Backing storage pattern** (lines 112-114):
```swift
@ObservationIgnored private var _showBatterySection: Bool = true
@ObservationIgnored private var _showProcessSection: Bool = true
```

Add `_showThermalSection: Bool = true`. Default is `true`.

**Public property pattern** (lines 280-306):
```swift
var showBatterySection: Bool {
    get {
        access(keyPath: \.showBatterySection)
        return _showBatterySection
    }
    set {
        withMutation(keyPath: \.showBatterySection) { _showBatterySection = newValue }
        defaults.set(newValue, forKey: Keys.showBatterySection)
        postChange(keys: [Keys.showBatterySection])
    }
}
```

Copy exactly for `showThermalSection`, changing key path/backing/key name. This ensures SwiftUI observation and `.settingsDidChange` repaint behavior work.

**Default-on load pattern** (lines 463-473):
```swift
if defaults.object(forKey: Keys.showBatterySection) == nil {
    _showBatterySection = true
} else {
    _showBatterySection = defaults.bool(forKey: Keys.showBatterySection)
}
```

Add the same branch for `showThermalSection`. Do not use plain `defaults.bool(forKey:)` without the `object(forKey:) == nil` check, or first-run default becomes false.

---

### `MacStatus/MacStatus/UI/Views/SettingsView.swift` (component, request-response form binding)

**Analog:** existing `弹窗区块` section.

**Bindable settings pattern** (lines 7-9):
```swift
struct SettingsView: View {
    @Bindable var settings = SettingsManager.shared
```

Use the existing shared settings binding. No local state is needed.

**Toggle placement pattern** (lines 43-47):
```swift
Section("弹窗区块") {
    Toggle("电池区块", isOn: $settings.showBatterySection)
    Toggle("进程区块", isOn: $settings.showProcessSection)
}
```

Add `Toggle("散热区块", isOn: $settings.showThermalSection)` in this section. Do not add thermal threshold controls, alert controls, fan controls, or status-bar metric toggles.

---

### `MacStatus/MacStatus.xcodeproj/project.pbxproj` (config, build registration)

**Analog:** existing `BatteryReader.swift` / `SMCReader.swift` entries.

**PBXBuildFile entry pattern** (lines 25-27):
```text
F70000000000000000000002 /* BatteryReader.swift in Sources */ = {isa = PBXBuildFile; fileRef = F70000000000000000000001 /* BatteryReader.swift */; };
5C0000000000000000000002 /* SMCReader.swift in Sources */ = {isa = PBXBuildFile; fileRef = 5C0000000000000000000001 /* SMCReader.swift */; };
```

Add a new `PBXBuildFile` for `ThermalReader.swift in Sources` with a unique ID and fileRef.

**PBXFileReference entry pattern** (lines 60-63):
```text
C30000000000000000000001 /* GPUReader.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GPUReader.swift; sourceTree = "<group>"; };
F70000000000000000000001 /* BatteryReader.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BatteryReader.swift; sourceTree = "<group>"; };
5C0000000000000000000001 /* SMCReader.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SMCReader.swift; sourceTree = "<group>"; };
```

Add a `PBXFileReference` for `ThermalReader.swift`.

**Readers group registration pattern** (lines 125-138):
```text
08FB7793FE84155DC02AAC0B /* Readers */ = {
    isa = PBXGroup;
    children = (
        ...
        C30000000000000000000001 /* GPUReader.swift */,
        F70000000000000000000001 /* BatteryReader.swift */,
        A80000000000000000000001 /* ProcessResourceReader.swift */,
        5C0000000000000000000001 /* SMCReader.swift */,
    );
    path = Readers;
    sourceTree = "<group>";
};
```

Insert `ThermalReader.swift` in the Readers group near `BatteryReader.swift` / `SMCReader.swift`.

**Sources build phase pattern** (lines 274-306):
```text
08FB7793FE84155DC02AAC18 /* Sources */ = {
    isa = PBXSourcesBuildPhase;
    files = (
        ...
        F70000000000000000000002 /* BatteryReader.swift in Sources */,
        A80000000000000000000002 /* ProcessResourceReader.swift in Sources */,
        5C0000000000000000000002 /* SMCReader.swift in Sources */,
        ...
    );
};
```

Add `ThermalReader.swift in Sources`. This is a known trap: a Swift file present on disk but absent from `PBXSourcesBuildPhase` will not compile into the app.

## Shared Patterns

### Read-Only Thermal Guardrails

**Source:** `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`; `SMCReader.swift` lines 6-18, 24-31, 122-145

**Apply to:** `ThermalReader.swift`, `SMCReader.swift`

Rules to carry into implementation:
- SMC boundary remains read-only; no fan writes or generic write methods.
- Missing/untrusted/unreadable keys return nil and render as `N/A`/`—`.
- Primary CPU/SoC must come only from explicitly trusted CPU/SoC keys. No hottest/package/proximity fallback masquerading as CPU/SoC.
- `ProcessInfo.thermalState` is a separate semantic row, not a temperature substitute.

### Optional Hardware Snapshot

**Source:** `BatteryReader.swift` lines 8-14, 58-65, 108-110, 185-200

**Apply to:** `ThermalReader.swift`, `MetricCollector.swift`, `DashboardView.swift`

Use `Sendable, Equatable` value snapshots with optional fields. Absence of a sensor is normal. Avoid user-facing errors and avoid console noise loops.

### Collector Non-Persistence Path

**Source:** `MetricCollector.swift` lines 45-46, 146-156, 206-210

**Apply to:** `MetricCollector.swift`

Thermal is popover-only in Phase 10. Store `lastThermalSnapshot` beside `lastBatterySnapshot`; do not extend `MetricSample`, SQLite history, metric order, enabled metrics, or status-bar rendering.

### Stable UI Rows

**Source:** `DashboardView.swift` lines 62-67, 193-228, 457-461

**Apply to:** `DashboardView.swift`

Render a dedicated `散热` card with stable rows:
- Header: `散热` and `CPU/SoC 58°C` or `CPU/SoC N/A`
- Rows: `系统状态`, `GPU`, `电池`
- Values are monospaced/right-aligned and degrade inline.

### Default-On Settings Toggle

**Source:** `SettingsManager.swift` lines 83-86, 112-114, 280-306, 463-473; `SettingsView.swift` lines 43-47

**Apply to:** `SettingsManager.swift`, `SettingsView.swift`, `DashboardView.swift`, `MetricCollector.swift`

Add `showThermalSection` defaulting to true. Setter posts `.settingsDidChange`, and collector `applyNow()` repaints cached data without a fresh read.

### Xcode Project Registration

**Source:** `project.pbxproj` lines 9-40, 43-76, 125-138, 274-306

**Apply to:** any new Swift file, specifically `ThermalReader.swift`

New Swift file registration requires all three:
1. `PBXFileReference`
2. group child under `Readers`
3. `PBXBuildFile` plus entry in `PBXSourcesBuildPhase.files`

## No Analog Found

All planned Phase 10 source changes have close in-repo analogs. No external pattern is required.

## Metadata

**Analog search scope:** `MacStatus/MacStatus/**/*.swift`, `MacStatus/MacStatus.xcodeproj/project.pbxproj`, phase context/research/UI spec  
**Files scanned:** 10 required files plus `GPUReader.swift` and `CPUReader.swift` as supplementary reader analogs  
**Pattern extraction date:** 2026-06-24
