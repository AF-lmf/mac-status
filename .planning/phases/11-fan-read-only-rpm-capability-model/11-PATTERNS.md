# Phase 11: Fan Read-Only RPM & Capability Model - Pattern Map

**Mapped:** 2026-06-24
**Files analyzed:** 7
**Analogs found:** 7 / 7

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `MacStatus/MacStatus/Readers/FanReader.swift` | service/model | request-response, hardware read, transform | `MacStatus/MacStatus/Readers/ThermalReader.swift` | exact |
| `MacStatus/MacStatus/Readers/SMCReader.swift` | service/utility | request-response, hardware read, transform | `MacStatus/MacStatus/Readers/SMCReader.swift` | exact |
| `MacStatus/MacStatus/Collectors/MetricCollector.swift` | service/controller | event-driven polling, request-response | `MacStatus/MacStatus/Collectors/MetricCollector.swift` | exact |
| `MacStatus/MacStatus/UI/Views/DashboardView.swift` | component/store | request-response UI state render | `MacStatus/MacStatus/UI/Views/DashboardView.swift` | exact |
| `MacStatus/MacStatus/Utils/SettingsManager.swift` | store/config | event-driven settings persistence | `MacStatus/MacStatus/Utils/SettingsManager.swift` | exact |
| `MacStatus/MacStatus/UI/Views/SettingsView.swift` | component | request-response settings UI | `MacStatus/MacStatus/UI/Views/SettingsView.swift` | exact |
| `MacStatus/MacStatus.xcodeproj/project.pbxproj` | config | build graph registration | `MacStatus/MacStatus.xcodeproj/project.pbxproj` | exact |

## Pattern Assignments

### `MacStatus/MacStatus/Readers/FanReader.swift` (service/model, hardware read + transform)

**Analog:** `MacStatus/MacStatus/Readers/ThermalReader.swift`

**Imports pattern** (lines 1-3):
```swift
import Darwin
import Foundation
import IOKit
```

**Snapshot/value model pattern** (lines 28-43):
```swift
struct ThermalSnapshot: Sendable, Equatable {
    let cpuSocTemperatureCelsius: Double?
    let systemState: SystemThermalState
    let gpuTemperatureCelsius: Double?
    let batteryTemperatureCelsius: Double?
    let capturedAt: Date

    static func unavailable(capturedAt: Date = Date()) -> ThermalSnapshot {
        ThermalSnapshot(
            cpuSocTemperatureCelsius: nil,
            systemState: .unknown,
            gpuTemperatureCelsius: nil,
            batteryTemperatureCelsius: nil,
            capturedAt: capturedAt
        )
    }
}
```

Apply this shape to `FanSnapshot`, `FanReading`, and `FanCapabilities`: value types, `Sendable`, `Equatable`, optional read fields, stable unavailable state. Keep `controlPotential` internal-only and do not expose control promises in UI.

**Hardware catalog/model gating pattern** (lines 54-76):
```swift
enum ThermalSensorCatalog {
    static let supportedModel = "Mac15,9"

    static let mac15_9CPUSoCCandidates = [
        "Te05", "Te0L", "Te0P", "Te0S",
        "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
        "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"
    ]

    static func cpuSocCandidates(for model: String?) -> [String] {
        model == supportedModel ? mac15_9CPUSoCCandidates : []
    }
}
```

Use a fan catalog for `Mac15,9` validation expectations, but make runtime support depend on `FNum` and per-fan key readability, not model string alone.

**Reader lifecycle and current snapshot pattern** (lines 78-101):
```swift
final class ThermalReader {

    private let smcReader = SMCReader()

    func setup() {
        smcReader.open()
    }

    func readValue() -> ThermalSnapshot {
        let model = Self.hardwareModel()
        let capturedAt = Date()
        let systemState = SystemThermalState(ProcessInfo.processInfo.thermalState)

        return ThermalSnapshot(
            cpuSocTemperatureCelsius: firstTemperature(
                in: ThermalSensorCatalog.cpuSocCandidates(for: model)
            ),
            systemState: systemState,
            gpuTemperatureCelsius: firstTemperature(
                in: ThermalSensorCatalog.gpuCandidates(for: model)
            ),
            batteryTemperatureCelsius: batteryTemperatureCelsius(),
            capturedAt: capturedAt
        )
    }
}
```

For `FanReader`, use the same synchronous `setup()` + `readValue()` shape. Read `FNum`, then `F{i}Ac`, `F{i}Mn`, `F{i}Mx`, `F{i}Tg` using read-only calls. Missing fields become `nil`, not thrown errors.

**Diagnostic read pattern** (lines 104-124):
```swift
func diagnosticReadings() -> [ThermalDiagnosticReading] {
    let model = Self.hardwareModel()
    let candidates = [
        ("cpuSoc", ThermalSensorCatalog.cpuSocCandidates(for: model)),
        ("gpu", ThermalSensorCatalog.gpuCandidates(for: model)),
        ("battery", ThermalSensorCatalog.batterySMCCandidates)
    ]

    return candidates.flatMap { group, keys in
        keys.map { key in
            let value = smcReader.readRawValue(key: key)
            return ThermalDiagnosticReading(
                sensorGroup: group,
                key: key,
                dataType: value?.dataType,
                dataSize: value?.dataSize,
                temperatureCelsius: smcReader.readTemperatureCelsius(key: key)
            )
        }
    }
}
```

Add fan diagnostics only as read-only evidence for planning/verification. Do not build a user-facing raw SMC browser.

**Hardware model helper pattern** (lines 159-172):
```swift
private static func hardwareModel() -> String? {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
        return nil
    }

    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
        return nil
    }

    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}
```

Use for `Mac15,9` evidence and expected fan surface behavior.

---

### `MacStatus/MacStatus/Readers/SMCReader.swift` (service/utility, read-only hardware boundary)

**Analog:** `MacStatus/MacStatus/Readers/SMCReader.swift`

**Read-only boundary and degradation contract** (lines 6-18):
```swift
/// Minimal **read-only** client for the Apple System Management Controller (SMC).
///
/// Opens an `AppleSMC` IOKit user-client connection and reads numeric keys such as
/// `PSTR` (whole-system total power, in Watts).
///
/// Every read degrades to `nil` when the connection is unavailable or the key/type
/// is unknown on this hardware, so callers render "—" rather than a fake value —
/// mirroring the project-wide probe-and-nil convention.
```

Preserve this boundary. Phase 11 may add read-side numeric decoding such as `ui8 `, but must not add write APIs, control selectors, or public mutation surfaces.

**Read raw/value pattern** (lines 129-164):
```swift
func readRawValue(key: String) -> SMCValue? {
    guard isOpen else { return nil }

    var info = SMCParamStruct()
    info.key = Self.fourCharCode(key)
    info.data8 = Self.cmdReadKeyInfo
    guard let infoOut = call(info), infoOut.result == 0 else { return nil }

    let size = infoOut.keyInfo.dataSize
    let type = infoOut.keyInfo.dataType
    guard size > 0, size <= 32 else { return nil }

    var read = SMCParamStruct()
    read.key = Self.fourCharCode(key)
    read.keyInfo.dataSize = size
    read.data8 = Self.cmdReadBytes
    guard let readOut = call(read), readOut.result == 0 else { return nil }

    let raw = withUnsafeBytes(of: readOut.bytes) { Array($0.prefix(Int(size))) }
    return SMCValue(
        key: key,
        dataType: Self.fourCharString(type),
        dataSize: size,
        bytes: raw
    )
}

func readValue(key: String) -> Double? {
    guard let value = readRawValue(key: key) else { return nil }
    return Self.decodeNumeric(value)
}
```

Fan reader should call `readValue`/`readRawValue`; it should not duplicate the AppleSMC ABI.

**Numeric decode extension point** (lines 207-250):
```swift
private static func decodeNumeric(_ value: SMCValue) -> Double? {
    let raw = value.bytes

    if value.dataType == "flt ", raw.count >= 4 {
        let bits = UInt32(raw[0]) | (UInt32(raw[1]) << 8)
                 | (UInt32(raw[2]) << 16) | (UInt32(raw[3]) << 24)
        return Double(Float(bitPattern: bits))
    }

    if value.dataType == "ui8", raw.count >= 1 {
        return Double(raw[0])
    }

    if value.dataType == "ui16", raw.count >= 2 {
        return Double(UInt16(raw[0]) << 8 | UInt16(raw[1]))
    }

    if value.dataType == "ui32", raw.count >= 4 {
        let integer = UInt32(raw[0]) << 24
                    | UInt32(raw[1]) << 16
                    | UInt32(raw[2]) << 8
                    | UInt32(raw[3])
        return Double(integer)
    }

    let typeChars = Array(value.dataType.utf8)
    if raw.count >= 2,
       typeChars.count == 4,
       typeChars[1] == UInt8(ascii: "p"),
       let fracBits = hexDigit(typeChars[3]) {
        let rawValue = UInt16(raw[0]) << 8 | UInt16(raw[1])
        let divisor = Double(1 << fracBits)
        if typeChars[0] == UInt8(ascii: "s") {
            return Double(Int16(bitPattern: rawValue)) / divisor
        } else if typeChars[0] == UInt8(ascii: "f") {
            return Double(rawValue) / divisor
        }
    }

    return nil
}
```

Research identified `FNum` as `ui8 ` with a trailing space on local `Mac15,9`; planner should include a read-side codec fix or fan-specific raw-byte decode without changing write behavior.

---

### `MacStatus/MacStatus/Collectors/MetricCollector.swift` (service/controller, event-driven polling)

**Analog:** `MacStatus/MacStatus/Collectors/MetricCollector.swift`

**Reader ownership and popover-only cache pattern** (lines 28-52):
```swift
private let batteryReader = BatteryReader()

// Last battery snapshot — kept separately from MetricSample (no persistence, no sparkline)
private var lastBatterySnapshot: BatterySnapshot? = nil

private let thermalReader = ThermalReader()

// Last thermal snapshot — popover-only current read, outside history/status bar schemas
private var lastThermalSnapshot: ThermalSnapshot = .unavailable()
```

Add `private let fanReader = FanReader()` and `lastFanSnapshot` beside thermal. Keep fan outside `MetricSample`, SQLite, ring buffer, sparklines, and status-bar title.

**Setup and initial read pattern** (lines 62-79):
```swift
func start() {
    cpuReader.setup()
    memoryReader.setup()
    networkReader.setup()
    gpuReader.setup()
    batteryReader.setup()
    thermalReader.setup()

    _ = cpuReader.readValue()
    _ = memoryReader.readValue()
    _ = networkReader.readValue()
    _ = gpuReader.readValue()
    _ = batteryReader.readValue()
    lastThermalSnapshot = thermalReader.readValue()
}
```

Call `fanReader.setup()` and initialize `lastFanSnapshot = fanReader.readValue()` here.

**Settings live repaint pattern** (lines 128-149):
```swift
settingsObserver = NotificationCenter.default.addObserver(
    forName: .settingsDidChange,
    object: nil,
    queue: .main
) { [weak self] event in
    guard let self,
          let changedKeys = event.userInfo?[SettingsManager.changedKeysUserInfoKey] as? Set<String>
    else { return }
    Task { @MainActor [weak self] in
        guard let self else { return }
        if changedKeys.contains("refreshInterval") {
            self.reconfigure()
        } else {
            self.applyNow()
        }
    }
}
```

`showFanSection` should use the existing `.settingsDidChange` path. No separate fan timer or manual refresh.

**Tick and current-only snapshot pattern** (lines 153-189):
```swift
private func tick() {
    tickCount += 1

    let cpu = cpuReader.readValue()
    let mem = memoryReader.readValue()
    let net = networkReader.readValue()
    let gpu = gpuReader.readValue()
    let battery = batteryReader.readValue()
    lastBatterySnapshot = battery

    let sample = MetricSample(
        cpuUsage: cpu,
        memoryUsage: mem?.usedPercent,
        networkUploadBps: net?.uploadBytesPerSec,
        networkDownloadBps: net?.downloadBytesPerSec,
        gpuUsage: gpu?.utilizationPercent
    )

    let thermal = thermalReader.readValue()
    lastThermalSnapshot = thermal

    lastSample = sample
    ringBuffer.append(sample)
    pendingSamples.append(sample)

    updateUI(sample: sample)
}
```

Read fan after thermal or adjacent to it, update `lastFanSnapshot`, and leave persistence untouched.

**Dashboard update pattern** (lines 216-224):
```swift
// Battery — pushed from the separately-cached snapshot (not part of MetricSample,
// no persistence, no sparkline). nil on desktop → DashboardState hides the section.
dashboard.updateBattery(lastBatterySnapshot)

// Thermal — current snapshot only. Kept out of MetricSample/history/status bar and
// reused by applyNow() so appearance/settings repaint does not force a fresh SMC read.
dashboard.updateThermal(lastThermalSnapshot)
```

Add `dashboard.updateFans(lastFanSnapshot)` here. Do not add fan to `StatusBarManager.shared.updateTitle(...)` (lines 241-246).

---

### `MacStatus/MacStatus/UI/Views/DashboardView.swift` (component/store, SwiftUI render)

**Analog:** `MacStatus/MacStatus/UI/Views/DashboardView.swift`

**Settings-gated section pattern** (lines 62-71):
```swift
if settings.showBatterySection && state.hasBattery, let battery = state.battery {
    BatterySectionView(snapshot: battery)
}

if settings.showThermalSection {
    ThermalSectionView(snapshot: state.thermal)
}
```

Replace the standalone thermal gate with a combined `温度与风扇` section gate. Hide the combined card only when both `showThermalSection` and `showFanSection` are false, or when the fan group is unsupported and thermal is disabled.

**Thermal card visual pattern** (lines 135-166):
```swift
struct ThermalSectionView: View {
    let snapshot: ThermalSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("散热")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("CPU/SoC \(temperatureText(snapshot.cpuSocTemperatureCelsius))")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
            }

            row("CPU/SoC", temperatureText(snapshot.cpuSocTemperatureCelsius))
            row("系统状态", thermalStateText, color: thermalStateColor)
            row("GPU", temperatureText(snapshot.gpuTemperatureCelsius))
            row("电池", temperatureText(snapshot.batteryTemperatureCelsius))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("散热信息")
    }
}
```

Rename title to `温度与风扇`, accessibility label to `温度与风扇信息`, render temperature rows first and fan rows second. Keep 320pt outer frame from lines 128-129.

**Row layout pattern** (lines 168-181):
```swift
private func row(_ label: String, _ value: String, color: Color = .secondary) -> some View {
    HStack(spacing: 8) {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
        Text(value)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .frame(minWidth: 52, alignment: .trailing)
            .accessibilityLabel(accessibilityText(label: label, value: value))
    }
}
```

Fan rows should use this `HStack + Spacer + monospaced trailing value` shape. UI spec recommends `minWidth: 72` for RPM values (`9999 RPM` / `N/A`).

**Optional field formatting pattern** (lines 183-186 and 374-383):
```swift
private func temperatureText(_ value: Double?) -> String {
    guard let value else { return "N/A" }
    return "\(Int(value.rounded()))°C"
}

private var systemPowerText: String {
    guard let p = snapshot.systemPowerWatts else { return "—" }
    return "\(String(format: "%.1f", p))W"
}
```

For fans: current RPM nil becomes `N/A`; optional min/max/target detail rows are omitted unless readable. Do not reserve blank subrows.

**Dashboard state pattern** (lines 472-478, 561-570):
```swift
// Battery (popover-only; nil = no battery = desktop → section hidden)
@Published var battery: BatterySnapshot? = nil
@Published var hasBattery: Bool = false

// Thermal (popover-only current snapshot; stable unavailable values render inline)
@Published var thermal: ThermalSnapshot = .unavailable()

func updateBattery(_ snapshot: BatterySnapshot?) {
    battery = snapshot
    hasBattery = snapshot != nil
}

func updateThermal(_ snapshot: ThermalSnapshot) {
    thermal = snapshot
}
```

Add fan state as popover-only current state. Use `nil`/support state to hide fanless machines by default, while keeping stable fan rows with `N/A` on expected MacBook Pro surfaces.

---

### `MacStatus/MacStatus/Utils/SettingsManager.swift` (store/config, settings persistence)

**Analog:** `MacStatus/MacStatus/Utils/SettingsManager.swift`

**Key/backing storage pattern** (lines 83-116):
```swift
// Phase 9 new keys
static let showBatterySection = "showBatterySection"
static let showProcessSection = "showProcessSection"
static let showThermalSection = "showThermalSection"

@ObservationIgnored private var _showBatterySection: Bool = true
@ObservationIgnored private var _showProcessSection: Bool = true
@ObservationIgnored private var _showThermalSection: Bool = true
```

Add `showFanSection` as a new UserDefaults key and backing var, defaulting to `true`.

**Popover section property pattern** (lines 284-321):
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

var showThermalSection: Bool {
    get {
        access(keyPath: \.showThermalSection)
        return _showThermalSection
    }
    set {
        withMutation(keyPath: \.showThermalSection) { _showThermalSection = newValue }
        defaults.set(newValue, forKey: Keys.showThermalSection)
        postChange(keys: [Keys.showThermalSection])
    }
}
```

Copy this exactly for `showFanSection`. It should post `.settingsDidChange` so collector `applyNow()` refreshes without a new SMC read.

**Load default pattern** (lines 478-494):
```swift
if defaults.object(forKey: Keys.showBatterySection) == nil {
    _showBatterySection = true
} else {
    _showBatterySection = defaults.bool(forKey: Keys.showBatterySection)
}

if defaults.object(forKey: Keys.showThermalSection) == nil {
    _showThermalSection = true
} else {
    _showThermalSection = defaults.bool(forKey: Keys.showThermalSection)
}
```

Use `object(forKey:) == nil` so an explicit user `false` is preserved.

**Notification helper pattern** (lines 520-527):
```swift
private func postChange(keys: Set<String>) {
    NotificationCenter.default.post(
        name: .settingsDidChange,
        object: self,
        userInfo: [SettingsManager.changedKeysUserInfoKey: keys]
    )
}
```

No custom notification type is needed.

---

### `MacStatus/MacStatus/UI/Views/SettingsView.swift` (component, settings UI)

**Analog:** `MacStatus/MacStatus/UI/Views/SettingsView.swift`

**Binding and form pattern** (lines 7-11):
```swift
struct SettingsView: View {
    @Bindable var settings = SettingsManager.shared

    var body: some View {
        Form {
```

Use the existing `@Bindable` settings singleton. Do not introduce view-local settings state.

**Popover section toggle pattern** (lines 43-48):
```swift
// ── Section 3: 弹窗区块（电池 + 散热 + 进程区块开关）
Section("弹窗区块") {
    Toggle("电池区块", isOn: $settings.showBatterySection)
    Toggle("散热区块", isOn: $settings.showThermalSection)
    Toggle("进程区块", isOn: $settings.showProcessSection)
}
```

Add `Toggle("风扇区块", isOn: $settings.showFanSection)` directly after `散热区块`. Do not add fan control toggles, disabled future controls, mode toggles, sliders, or placeholders.

---

### `MacStatus/MacStatus.xcodeproj/project.pbxproj` (config, build graph registration)

**Analog:** `MacStatus/MacStatus.xcodeproj/project.pbxproj`

**Build file + file reference pattern** (lines 25-28, 62-65):
```text
F70000000000000000000002 /* BatteryReader.swift in Sources */ = {isa = PBXBuildFile; fileRef = F70000000000000000000001 /* BatteryReader.swift */; };
A80000000000000000000002 /* ProcessResourceReader.swift in Sources */ = {isa = PBXBuildFile; fileRef = A80000000000000000000001 /* ProcessResourceReader.swift */; };
5C0000000000000000000002 /* SMCReader.swift in Sources */ = {isa = PBXBuildFile; fileRef = 5C0000000000000000000001 /* SMCReader.swift */; };
E20000000000000000000002 /* ThermalReader.swift in Sources */ = {isa = PBXBuildFile; fileRef = E20000000000000000000001 /* ThermalReader.swift */; };

F70000000000000000000001 /* BatteryReader.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BatteryReader.swift; sourceTree = "<group>"; };
A80000000000000000000001 /* ProcessResourceReader.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProcessResourceReader.swift; sourceTree = "<group>"; };
5C0000000000000000000001 /* SMCReader.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SMCReader.swift; sourceTree = "<group>"; };
E20000000000000000000001 /* ThermalReader.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ThermalReader.swift; sourceTree = "<group>"; };
```

Register `FanReader.swift` with one PBXBuildFile id and one PBXFileReference id.

**Readers group pattern** (lines 127-141):
```text
08FB7793FE84155DC02AAC0B /* Readers */ = {
    isa = PBXGroup;
    children = (
        A00000000000000000000005 /* ReaderProtocol.swift */,
        A00000000000000000000007 /* TimerReader.swift */,
        A00000000000000000000001 /* CPUReader.swift */,
        DD9388B0-76C5-4944-98B4-990FB09BC512 /* NetworkReader.swift */,
        E10000000000000000000001 /* ProcessNetworkReader.swift */,
        BB26C8CE-7E94-423C-A253-BC1FCE810BC5 /* MemoryReader.swift */,
        C30000000000000000000001 /* GPUReader.swift */,
        F70000000000000000000001 /* BatteryReader.swift */,
        A80000000000000000000001 /* ProcessResourceReader.swift */,
        5C0000000000000000000001 /* SMCReader.swift */,
        E20000000000000000000001 /* ThermalReader.swift */,
    );
    path = Readers;
    sourceTree = "<group>";
};
```

Add `FanReader.swift` near `ThermalReader.swift`.

**Sources build phase pattern** (lines 296-300):
```text
F70000000000000000000002 /* BatteryReader.swift in Sources */,
A80000000000000000000002 /* ProcessResourceReader.swift in Sources */,
5C0000000000000000000002 /* SMCReader.swift in Sources */,
E20000000000000000000002 /* ThermalReader.swift in Sources */,
B10000000000000000000002 /* PopoverManager.swift in Sources */,
```

Add `FanReader.swift in Sources` next to thermal/SMC readers.

## Shared Patterns

### Read-Only SMC Safety
**Source:** `MacStatus/MacStatus/Readers/SMCReader.swift` lines 6-18, 129-164, 177-190
**Apply to:** `FanReader.swift`, `SMCReader.swift`, verification/no-write guard

Use only `readRawValue` / `readValue` and `IOConnectCallStructMethod` through the existing read path. Do not add SMC writes, helper/XPC, privileged prompts, fan mode changes, `FS!` writes, or target RPM writes.

### Probe-And-Nil Degradation
**Source:** `MacStatus/MacStatus/Readers/BatteryReader.swift` lines 8-13, 58-61, 168-181, 185-200
**Apply to:** fan snapshot fields, UI display, diagnostics

Missing hardware keys are normal optional values. A missing fan RPM renders `N/A`; missing bounds/target omit detail rows; read failures remain quiet.

### Popover-Only Current State
**Source:** `MacStatus/MacStatus/Collectors/MetricCollector.swift` lines 45-52, 216-224
**Apply to:** fan collector integration and `DashboardState`

Fan snapshots must not enter `MetricSample`, SQLite history, ring buffer, sparkline arrays, status bar metric order, or enabled status-bar metrics.

### Settings Change Flow
**Source:** `MacStatus/MacStatus/Utils/SettingsManager.swift` lines 284-321, 520-527 and `MetricCollector.swift` lines 128-149
**Apply to:** `showFanSection`

Settings setters write `UserDefaults`, post `.settingsDidChange`, and collector `applyNow()` re-pushes cached UI state.

### Compact Card UI
**Source:** `MacStatus/MacStatus/UI/Views/DashboardView.swift` lines 135-166, 168-181
**Apply to:** combined `温度与风扇` section

Keep `VStack(spacing: 8)`, `.padding(8)`, `RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04))`, caption labels, monospaced trailing values, and 320pt popover width.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| none | — | — | Existing thermal, battery, settings, and collector files provide direct analogs for every Phase 11 file. |

## Metadata

**Analog search scope:** `MacStatus/MacStatus/**`, `MacStatus/MacStatus.xcodeproj/project.pbxproj`, project `.agents/skills/**/SKILL.md`
**Files scanned:** 19 source/config files plus 11 project skill indexes
**Pattern extraction date:** 2026-06-24
**Phase constraints applied:** read-only fan monitoring only; no SMC writes; no fan controls; no status-bar fan segment; no history persistence; keep popover width at 320pt.
