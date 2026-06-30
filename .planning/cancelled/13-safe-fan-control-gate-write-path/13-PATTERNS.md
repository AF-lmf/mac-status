# Phase 13: Safe Fan Control Gate & Write Path — Pattern Map

**Mapped:** 2026-06-26
**Files analyzed:** 12 new/modified files
**Analogs found:** 12 / 12 (all have close analogs; new helper target files have partial analogs)

---

## File Classification

| New / Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------------|------|-----------|----------------|---------------|
| `MacStatus/MacStatus/Control/FanControlProtocol.swift` | protocol / interface | request-response | `SettingsManager.swift` (SMAppService pattern) + Research Pattern 2 | partial |
| `MacStatus/MacStatus/Control/FanControlManager.swift` | service / state-machine | event-driven + request-response | `MetricCollector.swift` (@MainActor orchestrator) | role-match |
| `MacStatus/FanControlHelper/main.swift` | helper entry point | event-driven (XPC listener) | `AppDelegate.swift` (app entry / NSApp lifecycle) | partial |
| `MacStatus/FanControlHelper/FanControlHelperImpl.swift` | service (root-side) | request-response | `SMCReader.swift` (IOKit open/call/close pattern) | partial |
| `MacStatus/FanControlHelper/SMCWriter.swift` | utility / IOKit client | request-response | `SMCReader.swift` (SMCParamStruct ABI + IOConnectCallStructMethod) | exact (same ABI) |
| `MacStatus/Resources/LaunchDaemons/com.macstatus.fancontrolhelper.plist` | config | — | `SettingsManager.swift` SMAppService.mainApp precedent | partial |
| `MacStatus/MacStatus/Readers/FanReader.swift` *(modified)* | reader / model | CRUD read | itself | self-analog |
| `MacStatus/MacStatus/UI/Views/DashboardView.swift` *(modified)* | component / view | event-driven | itself — `TemperatureAndFanSectionView` + `fanRow()` | self-analog |
| `MacStatus/MacStatus/UI/Views/StableValueLayout.swift` *(modified)* | utility / design tokens | — | itself — `StableValueWidth.fanRPM = 78` | self-analog |
| `MacStatus/MacStatus/Utils/SettingsManager.swift` *(modified)* | utility / settings | CRUD | itself — `launchAtLogin` + `showFanSection` properties | self-analog |
| `MacStatus/MacStatus/UI/Views/SettingsView.swift` *(modified)* | component / view | event-driven | itself — `Section("弹窗区块")` toggle rows | self-analog |
| `MacStatus/MacStatus/Collectors/MetricCollector.swift` *(modified)* | orchestrator | event-driven | itself — `lastFanSnapshot` pattern | self-analog |

---

## Pattern Assignments

### `MacStatus/MacStatus/Control/FanControlProtocol.swift` (protocol, request-response)

**Analog:** Research Pattern 2 (RESEARCH.md lines 226–247) + `SettingsManager.swift` (Objective-C interop pattern)

**Role:** Shared between main-app target and helper target. Must be `@objc` for NSXPCInterface.

**Imports pattern:**
```swift
import Foundation
```

**Core protocol pattern** (derive from RESEARCH.md lines 503–507):
```swift
@objc protocol FanControlProtocol: NSObjectProtocol {
    /// Set all fans to manual mode at the specified target RPM.
    /// Performs Ftst=1 unlock, F{i}Md=1, F{i}Tg=target, Ftst=0 on the helper side.
    func setManualTarget(rpm: UInt16, reply: @escaping (Bool, Int32) -> Void)

    /// Restore system automatic fan control.
    /// Performs F{i}Md=0, Ftst=0 on the helper side.
    func restoreAutoControl(reply: @escaping (Bool) -> Void)
}
```

**Key constraint:** No raw SMC key passthrough. These two methods are the complete API surface. NSXPCInterface will validate the protocol at runtime — every parameter type must be ObjC-compatible (UInt16, Bool, Int32 are fine; Swift enum or struct are not).

---

### `MacStatus/MacStatus/Control/FanControlManager.swift` (service / state-machine, @MainActor)

**Analog:** `MacStatus/MacStatus/Collectors/MetricCollector.swift`

**Imports pattern** (mirrors MetricCollector lines 1–2):
```swift
import Foundation
import ServiceManagement
```

**@MainActor singleton pattern** (MetricCollector lines 15–22):
```swift
@MainActor
final class FanControlManager {
    static let shared = FanControlManager()
    private init() {}
    // ...
}
```

**NSXPCConnection helper-call pattern** (derive from RESEARCH.md lines 255–280):
```swift
private func makeConnection() -> NSXPCConnection {
    let c = NSXPCConnection(
        machServiceName: "com.macstatus.fancontrolhelper",
        options: .privileged
    )
    c.remoteObjectInterface = NSXPCInterface(with: FanControlProtocol.self)
    c.resume()
    return c
}

func setManualTarget(rpm: Double, snapshot: FanSnapshot) async -> FanControlResult {
    let clamped = clampRPM(rpm, snapshot: snapshot)
    let conn = makeConnection()
    defer { conn.invalidate() }

    return await withCheckedContinuation { continuation in
        let proxy = conn.remoteObjectProxyWithErrorHandler { err in
            continuation.resume(returning: .helperError(err))
        } as? FanControlProtocol

        proxy?.setManualTarget(rpm: UInt16(clamped)) { success, code in
            continuation.resume(returning: success ? .writeSucceeded : .writeFailed(code: code))
        }
    }
}
```

**SMAppService daemon status check** (mirrors SettingsManager.swift lines 265–281 `launchAtLogin` setter, adapted for daemon):
```swift
// From SettingsManager.swift launchAtLogin setter (lines 265–281):
// Pattern: call SMAppService API, only persist/proceed on success.
// For daemon: check status before use; never assume .enabled after register().
func registerHelperIfNeeded() {
    let service = SMAppService.daemon(plistName: "com.macstatus.fancontrolhelper.plist")
    do {
        try service.register()
    } catch {
        // Registration failed; keep safeControlAvailable = false
    }
    // status may be .requiresApproval even after register()
}
```

**settingsDidChange observer pattern** (MetricCollector lines 137–156):
```swift
// From MetricCollector.swift setupSettingsObserver() (lines 137–156):
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
        // React to manualFanControlEnabled key change
    }
}
```

**Fan control state enum** (new; pattern: optional/nil = unavailable, matching FanCapabilities style):
```swift
// Mirrors FanReader.swift nil-is-normal pattern (lines 151–174):
// Optional/nil is not an exception — it is the normal "not available" state.
enum FanControlState: Sendable, Equatable {
    case systemAuto          // baseline, no manual mode
    case pending             // write sent, read-back not yet confirmed
    case manualVerified      // read-back confirmed mode=1 + target matches
    case failClosed(message: String)  // write failed or read-back disagreed; auto-restore attempted
    case helperPendingApproval       // SMAppService status == .requiresApproval
    case unavailable         // safeControlAvailable == false
}
```

**Read-back verification pattern** (derive from RESEARCH.md Pattern 4, lines 333–348; uses FanReader diagnosticReadings):
```swift
// After XPC reply, wait 500ms for mode to settle, then verify via FanReader
private func verifyManualMode(targetRPM: Double) async -> Bool {
    try? await Task.sleep(nanoseconds: 500_000_000)
    let diag = fanReader.diagnosticReadings()
    // Mode must be exactly 1; target within ±1 RPM; current RPM is advisory
    for i in 0..<expectedFanCount {
        guard let modeReading = diag.first(where: { $0.key == "F\(i)Md" }),
              let mode = modeReading.numericValue,
              Int(mode) == 1
        else { return false }
        guard let tgReading = diag.first(where: { $0.key == "F\(i)Tg" }),
              let tg = tgReading.numericValue,
              abs(tg - targetRPM) <= 1.0
        else { return false }
    }
    return true
}
```

**RPM clamp pattern** (new logic; pattern matches FanReader.swift plausibleRPM, line 196):
```swift
// From FanReader.swift (line 196):
// private func plausibleRPM(_ value: Double?) -> Double? {
//     guard let value, (0...20_000).contains(value) else { return nil }
//     return value
// }
// Clamp follows the same guard-and-range idiom:
private func clampRPM(_ rpm: Double, snapshot: FanSnapshot) -> Double {
    let globalMin = snapshot.fans.compactMap(\.minRPM).max() ?? rpm
    let globalMax = snapshot.fans.compactMap(\.maxRPM).min() ?? rpm
    return max(globalMin, min(globalMax, rpm))
}
```

---

### `MacStatus/FanControlHelper/main.swift` (helper entry point, NSXPCListener)

**Analog:** `MacStatus/MacStatus/App/AppDelegate.swift` (lifecycle wiring pattern)

**Pattern:** The helper runs as a root LaunchDaemon. `main.swift` sets up the NSXPCListener and runs the RunLoop — equivalent to AppDelegate's `applicationDidFinishLaunching` wiring role.

**Core pattern** (derive from RESEARCH.md architecture + Apple NSXPCListener docs):
```swift
import Foundation

// Mirror AppDelegate.swift lifecycle structure (lines 22–35):
// Wire listener → start event loop. No UI, no MetricCollector.
final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: FanControlProtocol.self)
        newConnection.exportedObject = FanControlHelperImpl()
        newConnection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener(machServiceName: "com.macstatus.fancontrolhelper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
```

---

### `MacStatus/FanControlHelper/FanControlHelperImpl.swift` (service, root-side XPC implementation)

**Analog:** `MacStatus/MacStatus/Readers/SMCReader.swift` (IOKit user-client open/close lifecycle)

**Imports pattern** (mirrors SMCReader.swift lines 1–2):
```swift
import Foundation
import IOKit
```

**Core pattern:** Implements `FanControlProtocol`. Owns an `SMCWriter` instance (mirrors FanReader owning SMCReader, line 65). Executes the Ftst unlock sequence from RESEARCH.md Pattern 3.

**IOKit lifecycle** (mirrors SMCReader.swift open/close/deinit, lines 100–125):
```swift
// The helper impl opens SMCWriter (which owns the IOKit connection)
// exactly as FanReader owns SMCReader (FanReader.swift line 65):
// private let smcReader = SMCReader()
// func setup() { smcReader.open() }
final class FanControlHelperImpl: NSObject, FanControlProtocol {
    private let writer = SMCWriter()

    override init() {
        super.init()
        writer.open()
    }

    deinit { writer.close() }
    // ...
}
```

**output.result check pattern** (RESEARCH.md Pitfall 3 / Anti-Pattern; SMCReader.swift line 137 shows the existing convention):
```swift
// From SMCReader.swift (line 137): guard let infoOut = call(info), infoOut.result == 0 else { return nil }
// EVERY write call must check BOTH kIOReturnSuccess AND output.result == 0.
// IOKit success alone does not mean firmware accepted the write.
```

**Ftst unlock sequence** (RESEARCH.md Pattern 3, lines 293–318):
```swift
func setManualTarget(rpm: UInt16, reply: @escaping (Bool, Int32) -> Void) {
    do {
        // STEP 1 — Unlock thermalmonitord reclaim
        try writer.writeUI8(key: "Ftst", value: 1)

        // STEP 2 — Wait for thermalmonitord to yield (poll F{i}Md != 3)
        var unlocked = false
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let mode = writer.readUI8(key: "F0Md"), mode != 3 {
                unlocked = true; break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard unlocked else { throw FanControlError.unlockTimeout }

        // STEP 3 — Write mode=1 (manual) + target RPM
        try writer.writeUI8(key: "F0Md", value: 1)
        try writer.writeUI8(key: "F1Md", value: 1)
        try writer.writeFloatRPM(key: "F0Tg", rpm: Double(rpm))
        try writer.writeFloatRPM(key: "F1Tg", rpm: Double(rpm))

        // STEP 4 — Release unlock (Ftst=0 lets thermalmonitord resume oversight)
        try writer.writeUI8(key: "Ftst", value: 0)

        reply(true, 0)
    } catch let err as FanControlError {
        reply(false, err.rawCode)
    } catch {
        reply(false, -1)
    }
}
```

---

### `MacStatus/FanControlHelper/SMCWriter.swift` (utility / IOKit client, root-side)

**Analog:** `MacStatus/MacStatus/Readers/SMCReader.swift` — EXACT same 80-byte `SMCParamStruct` ABI

**Critical:** SMCWriter reuses the same struct layout and `IOConnectCallStructMethod` selector 2. Only difference: `data8 = cmdWriteKey` (6 instead of 5), and `bytes` field is populated with the value to write.

**Imports pattern** (same as SMCReader.swift lines 1–2):
```swift
import Foundation
import IOKit
```

**SMCParamStruct reuse** (SMCReader.swift lines 41–94): The writer must declare an identical `SMCParamStruct`. Copy the struct verbatim — deviation from the 80-byte layout causes silent kernel rejection.

**Connection open/close/deinit** (SMCReader.swift lines 99–125 — copy exactly):
```swift
// From SMCReader.swift (lines 100–125):
@discardableResult
func open() -> Bool {
    guard !isOpen else { return true }
    assert(MemoryLayout<SMCParamStruct>.stride == 80, "SMCParamStruct must be 80 bytes")
    guard MemoryLayout<SMCParamStruct>.stride == 80 else { return false }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
    guard service != IO_OBJECT_NULL else { return false }
    defer { IOObjectRelease(service) }
    let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
    isOpen = (result == kIOReturnSuccess)
    return isOpen
}
func close() {
    if isOpen { IOServiceClose(connection); connection = 0; isOpen = false }
}
deinit { close() }
```

**Write command constant** (SMCReader.swift line 34 shows read=5, info=9; write=6):
```swift
private static let cmdWriteKey: UInt8 = 6   // kSMCWriteKey (read=5, info=9 in SMCReader)
private static let cmdReadKeyInfo: UInt8 = 9 // same as SMCReader
```

**writeUI8 implementation** (RESEARCH.md Code Examples lines 471–497):
```swift
func writeUI8(key: String, value: UInt8) throws {
    guard isOpen else { throw SMCWriteError.notOpen }

    // Step 1: get key info (exact same two-step as readRawValue in SMCReader lines 133–156)
    var info = SMCParamStruct()
    info.key = Self.fourCharCode(key)
    info.data8 = Self.cmdReadKeyInfo
    guard let infoOut = call(info), infoOut.result == 0 else {
        throw SMCWriteError.keyInfoFailed(key: key)
    }

    // Step 2: write — populate bytes field, use cmd=6
    var write = SMCParamStruct()
    write.key = Self.fourCharCode(key)
    write.keyInfo.dataSize = infoOut.keyInfo.dataSize
    write.keyInfo.dataType = infoOut.keyInfo.dataType
    write.data8 = Self.cmdWriteKey
    withUnsafeMutableBytes(of: &write.bytes) { ptr in ptr[0] = value }

    // CRITICAL: check BOTH kIOReturnSuccess AND output.result == 0 (RESEARCH Pitfall 3)
    guard let writeOut = call(write), writeOut.result == 0 else {
        throw SMCWriteError.writeFailed(key: key)
    }
}
```

**writeFloatRPM — flt encoding** (RESEARCH.md Pitfall 5, lines 431–440; mirrors SMCReader.swift `decodeNumeric` flt path, lines 213–216):
```swift
// From SMCReader.swift (lines 213–216) — decode flt (little-endian):
// let bits = UInt32(raw[0]) | (UInt32(raw[1]) << 8) | (UInt32(raw[2]) << 16) | (UInt32(raw[3]) << 24)
// Encode is the exact inverse:
func writeFloatRPM(key: String, rpm: Double) throws {
    let bits = Float(rpm).bitPattern  // IEEE-754 32-bit
    let bytes: [UInt8] = [
        UInt8(bits & 0xFF),
        UInt8((bits >> 8) & 0xFF),
        UInt8((bits >> 16) & 0xFF),
        UInt8((bits >> 24) & 0xFF)
    ]
    try writeBytes(key: key, bytes: bytes, expectedSize: 4)
}
```

**call() helper** (mirrors SMCReader.swift lines 177–191 — copy exactly):
```swift
// From SMCReader.swift (lines 177–191):
private func call(_ input: SMCParamStruct) -> SMCParamStruct? {
    var inputCopy = input
    var output = SMCParamStruct()
    let structSize = MemoryLayout<SMCParamStruct>.stride
    var outputSize = structSize
    let result = IOConnectCallStructMethod(
        connection, Self.kernelIndexSMC,
        &inputCopy, structSize,
        &output, &outputSize
    )
    return result == kIOReturnSuccess ? output : nil
}
```

**fourCharCode / fourCharString helpers** (SMCReader.swift lines 193–205 — copy exactly):
```swift
// From SMCReader.swift (lines 193–205) — pack/unpack FourCharCode:
private static func fourCharCode(_ s: String) -> UInt32 {
    var code: UInt32 = 0
    for byte in s.utf8.prefix(4) { code = (code << 8) | UInt32(byte) }
    return code
}
```

---

### `MacStatus/MacStatus/Readers/FanReader.swift` *(modified)*

**Analog:** itself

**Modifications required:**

1. **Add `modeValue: Int?` to `FanReading`** (to expose `F{i}Md` for read-back verification):
```swift
// Current FanReading (lines 17–27) — add one property:
struct FanReading: Sendable, Equatable, Identifiable {
    // ... existing properties ...
    let modeValue: Int?   // F{i}Md: 0=auto, 1=manual, 3=thermalmonitord system
}
```

2. **Read `F{i}Md` in `reading(for:)`** (mirror the pattern at lines 151–154 — add after targetRPM read):
```swift
// From FanReader.swift reading(for:) (lines 150–175) — add mode read:
let modeRaw = smcReader.readValue(key: "F\(index)Md")
let modeValue: Int? = modeRaw.map { Int($0.rounded()) }
```

3. **Add `diagnosticSuffixes` entry for `"Md"`** — already present as `"Md"` in `FanSensorCatalog.diagnosticSuffixes` (line 56); confirm this covers `F{i}Md` for diagnosticReadings() calls.

4. **Flip `safeControlAvailable`** in `reading(for:)` (line 173 — currently hardcoded `false`):
```swift
// Replace line 173:
//   safeControlAvailable: false
// With a computed gate (RESEARCH.md Pattern safeControlAvailable, lines 515–524):
let modeReadable = smcReader.readRawValue(key: "F\(index)Md") != nil
let helperEnabled = (SMAppService.daemon(
    plistName: "com.macstatus.fancontrolhelper.plist"
).status == .enabled)
// safeControlAvailable requires: rpmReadable + boundsReadable + modeReadable + helperEnabled
safeControlAvailable: current != nil && boundsReadable && modeReadable && helperEnabled
```

---

### `MacStatus/MacStatus/UI/Views/DashboardView.swift` *(modified)*

**Analog:** itself — `TemperatureAndFanSectionView` (lines 148–336) + `fanRow()` (lines 220–246)

**Modification:** Extend `TemperatureAndFanSectionView` or add a `FanControlAffordanceView` child inside the existing `温度与风扇` card VStack. The control affordance attaches **after** the existing `fanRow()` calls — no new card, no popover-width change.

**Card attachment pattern** (existing card structure lines 154–200):
```swift
// From DashboardView.swift TemperatureAndFanSectionView.body (lines 154–200):
// New control affordance appended inside the same VStack, after ForEach(visibleFans):
VStack(alignment: .leading, spacing: 8) {
    // ... existing temperature rows, divider, fan rows ...
    ForEach(visibleFans) { fan in fanRow(fan) }

    // NEW: fan control affordance (only when enabled + safeControlAvailable + helper .enabled)
    if showsManualControl {
        Divider()
        FanControlAffordanceView(controlManager: FanControlManager.shared)
    }
}
.padding(8)
.background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
```

**Inline status / calm-degradation pattern** (existing `StableCaptionText` at line 243):
```swift
// From DashboardView.swift fanRow() (line 243):
// "边界可读，控制未启用" — calm .caption2 .secondary inline note
// Phase 13 reuses the same StableCaptionText pattern for all control state copy:
StableCaptionText(text: "控制未生效，已恢复自动")   // fail-closed message
StableCaptionText(text: "正在应用…")               // pending state
```

**StableValueRow + StableValueText for target RPM** (existing fanRow lines 222–229):
```swift
// From DashboardView.swift fanRow() (lines 222–229):
StableValueRow(label: "目标转速") {
    StableValueText(
        text: targetRPMText,           // "{rpm} RPM"
        width: StableValueWidth.fanRPM, // 78pt — reused as fanTargetRPM per UI-SPEC
        color: .primary,
        font: .system(.body, design: .monospaced),
        fontWeight: .medium
    )
}
```

**Slider contract** (new; no existing analog — use system Slider bounded to live min/max):
```swift
// Slider commits on drag-end only (avoid write storm):
Slider(value: $pendingTarget, in: fanMin...fanMax, step: 50)
    .onSubmit { Task { await FanControlManager.shared.setManualTarget(rpm: pendingTarget, ...) } }
// Or use .onChange(of:) with debounce / onEditingChanged: true = drag-end
```

**confirmationDialog pattern** (new; no existing analog in this codebase — use SwiftUI standard):
```swift
// Standard SwiftUI confirmationDialog for one-time risk consent (D-02):
.confirmationDialog("开启手动风扇控制？", isPresented: $showingRiskDialog, titleVisibility: .visible) {
    Button("开启手动控制", role: .destructive) { confirmManualControl() }
    Button("取消", role: .cancel) { revertToggle() }
} message: {
    Text("手动控制会直接调整风扇转速。设置过低可能导致设备过热。\n\nMacStatus 会把目标转速限制在硬件安全范围内，不能低于系统默认下限，也不能让风扇停转。\n\n写入失败或退出应用时，MacStatus 会自动恢复系统自动控制。")
}
```

---

### `MacStatus/MacStatus/UI/Views/StableValueLayout.swift` *(modified)*

**Analog:** itself

**Modification:** Add `fanTargetRPM` token to `StableValueWidth` (UI-SPEC line 186). Reuse `fanRPM = 78` value:

```swift
// From StableValueLayout.swift (lines 10–22) — add one line after fanRPM:
enum StableValueWidth {
    // ... existing tokens ...
    static let fanRPM = 78 as CGFloat
    static let fanTargetRPM = 78 as CGFloat  // NEW — same width; reuse proven fanRPM column
    // ...
}
```

Also add `fanTargetRPMValueColumn` to `LayoutProbeID` if layout test coverage is required:
```swift
// From StableValueLayout.swift (lines 92–101) — add to enum:
enum LayoutProbeID: String, Hashable, CaseIterable {
    // ... existing cases ...
    case fanTargetRPMValueColumn  // NEW
}
```

---

### `MacStatus/MacStatus/Utils/SettingsManager.swift` *(modified)*

**Analog:** itself — `launchAtLogin` property (lines 258–282) and `showFanSection` property (lines 325–337)

**Modifications:** Add two new `Keys` entries and two new backing vars + computed properties.

**Keys enum addition** (mirrors Keys enum structure lines 64–88):
```swift
// Add to private enum Keys:
static let manualFanControlEnabled = "manualFanControlEnabled"
static let hasConfirmedFanControlRisk = "hasConfirmedFanControlRisk"
```

**Bool toggle property pattern** (copy from `showFanSection` lines 325–337):
```swift
// From SettingsManager.swift showFanSection (lines 325–337):
var manualFanControlEnabled: Bool {
    get {
        access(keyPath: \.manualFanControlEnabled)
        return _manualFanControlEnabled
    }
    set {
        withMutation(keyPath: \.manualFanControlEnabled) { _manualFanControlEnabled = newValue }
        defaults.set(newValue, forKey: Keys.manualFanControlEnabled)
        postChange(keys: [Keys.manualFanControlEnabled])
    }
}

var hasConfirmedFanControlRisk: Bool {
    get {
        access(keyPath: \.hasConfirmedFanControlRisk)
        return _hasConfirmedFanControlRisk
    }
    set {
        withMutation(keyPath: \.hasConfirmedFanControlRisk) { _hasConfirmedFanControlRisk = newValue }
        defaults.set(newValue, forKey: Keys.hasConfirmedFanControlRisk)
        postChange(keys: [Keys.hasConfirmedFanControlRisk])
    }
}
```

**Backing var declarations** (mirrors lines 101–117 pattern):
```swift
@ObservationIgnored private var _manualFanControlEnabled: Bool = false   // default OFF (D-01)
@ObservationIgnored private var _hasConfirmedFanControlRisk: Bool = false
```

**Migration + loadAll additions** (mirror `showFanSection` migration pattern in `migrateToV1` and `loadAll`):
```swift
// In migrateToV1() — write defaults only if key absent:
if defaults.object(forKey: Keys.manualFanControlEnabled) == nil {
    defaults.set(false, forKey: Keys.manualFanControlEnabled)
}
if defaults.object(forKey: Keys.hasConfirmedFanControlRisk) == nil {
    defaults.set(false, forKey: Keys.hasConfirmedFanControlRisk)
}

// In loadAll() — same guard pattern as showFanSection (lines 511–515):
if defaults.object(forKey: Keys.manualFanControlEnabled) == nil {
    _manualFanControlEnabled = false
} else {
    _manualFanControlEnabled = defaults.bool(forKey: Keys.manualFanControlEnabled)
}
```

**CRITICAL — do NOT persist "manual mode active" runtime state** (RESEARCH.md Anti-Pattern line 361):
> Never write a "manual mode active" or "last manual RPM target" flag to UserDefaults. Only `manualFanControlEnabled` (the opt-in preference) and `hasConfirmedFanControlRisk` (one-time consent flag) are persisted.

---

### `MacStatus/MacStatus/UI/Views/SettingsView.swift` *(modified)*

**Analog:** itself — `Section("弹窗区块")` (lines 43–49)

**Modification:** Add a `Toggle` for `manualFanControlEnabled` inside the existing `弹窗区块` Section, after the `风扇区块` row. Gated by `FanCapabilities.safeControlAvailable` (hidden, not disabled, per D-04).

**Toggle placement pattern** (mirrors existing toggles lines 44–49):
```swift
// From SettingsView.swift Section("弹窗区块") (lines 43–49):
Section("弹窗区块") {
    Toggle("电池区块", isOn: $settings.showBatterySection)
    Toggle("散热区块", isOn: $settings.showThermalSection)
    Toggle("风扇区块", isOn: $settings.showFanSection)
    // NEW — conditional: only when hardware passes capability gate (D-04)
    if isSafeControlAvailable {
        Toggle("风扇手动控制", isOn: $settings.manualFanControlEnabled)
        // Optional: .caption2 help text below the toggle
    }
    Toggle("进程区块", isOn: $settings.showProcessSection)
}
```

**`$settings.manualFanControlEnabled` binding with side-effect** (mirrors `launchAtLogin` pattern):
```swift
// From SettingsManager.swift launchAtLogin setter (lines 265–282):
// The toggle setter handles SMAppService side-effect. For manualFanControlEnabled,
// the setter posts .settingsDidChange; FanControlManager observes and acts.
// If first enable: show confirmationDialog before writing to settings.
```

---

### `MacStatus/MacStatus/Collectors/MetricCollector.swift` *(modified)*

**Analog:** itself — `lastFanSnapshot` pattern (lines 53–56, 85, 181–182, 234–236)

**Modifications:** Add `FanControlManager` integration for control state updates in `updateUI`.

**Non-persistent runtime state pattern** (MetricCollector.swift lines 46–56):
```swift
// From MetricCollector.swift (lines 50–56):
// lastBatterySnapshot and lastFanSnapshot are runtime-only (no SQLite/history writes).
// Fan control state follows the same pattern — it MUST NOT enter MetricSample or HistoryStore.
private var lastFanSnapshot: FanSnapshot = .unavailable()   // existing
// No new var needed for control state — FanControlManager.shared owns it @MainActor
```

**updateUI fan control integration** (mirrors updateFans call at lines 234–236):
```swift
// From MetricCollector.swift updateUI (lines 234–236):
dashboard.updateFans(lastFanSnapshot)
// After Phase 13 modification, also push control state to DashboardState:
dashboard.updateFanControlState(FanControlManager.shared.currentState)
// DashboardState then exposes fanControlState for DashboardView to read.
```

---

## Shared Patterns

### SMCParamStruct 80-byte ABI Guard
**Source:** `MacStatus/MacStatus/Readers/SMCReader.swift` lines 41–94 and lines 105–107
**Apply to:** `FanControlHelper/SMCWriter.swift`
```swift
// From SMCReader.swift (lines 105–107):
assert(MemoryLayout<SMCParamStruct>.stride == 80, "SMCParamStruct must be 80 bytes")
guard MemoryLayout<SMCParamStruct>.stride == 80 else { return false }
```
Copy the full `SMCParamStruct` definition verbatim (including the 3 explicit pad bytes in `SMCKeyInfoData`, lines 69–78). Any deviation collapses the struct to 76 bytes and all kernel calls fail silently.

### output.result Double-Check
**Source:** `MacStatus/MacStatus/Readers/SMCReader.swift` line 137
**Apply to:** `FanControlHelper/SMCWriter.swift` — every write call
```swift
// From SMCReader.swift (line 137):
guard let infoOut = call(info), infoOut.result == 0 else { return nil }
// SMCWriter must apply the same double-check after write calls.
// kIOReturnSuccess alone does not mean firmware accepted the write (RESEARCH Pitfall 3).
```

### Optional/nil = Normal Unavailable State
**Source:** `MacStatus/MacStatus/Readers/FanReader.swift` lines 195–198
**Apply to:** `FanControlManager.swift`, `FanControlHelperImpl.swift`
```swift
// From FanReader.swift (lines 195–198):
private func plausibleRPM(_ value: Double?) -> Double? {
    guard let value, (0...20_000).contains(value) else { return nil }
    return value
}
// Pattern: nil return is the normal "not available" path, not an error path.
// FanControlManager: unavailable control state is normal, not exceptional.
```

### Calm-Degradation Inline Copy (No Modals, No Spam)
**Source:** `MacStatus/MacStatus/UI/Views/DashboardView.swift` line 243
**Apply to:** All new control state messages in `TemperatureAndFanSectionView` / `FanControlAffordanceView`
```swift
// From DashboardView.swift fanRow() (line 243):
StableCaptionText(text: "边界可读，控制未启用")
// All Phase 13 status copy uses the same StableCaptionText component.
// Color is always .secondary (calm). Never .red for fail-closed states (UI-SPEC).
```

### @Observable Backing Var + postChange Pattern
**Source:** `MacStatus/MacStatus/Utils/SettingsManager.swift` lines 100–130
**Apply to:** New `manualFanControlEnabled` and `hasConfirmedFanControlRisk` properties
```swift
// From SettingsManager.swift (lines 101, 122–130):
@ObservationIgnored private var _showBatterySection: Bool = true
var showBatterySection: Bool {
    get { access(keyPath: \.showBatterySection); return _showBatterySection }
    set {
        withMutation(keyPath: \.showBatterySection) { _showBatterySection = newValue }
        defaults.set(newValue, forKey: Keys.showBatterySection)
        postChange(keys: [Keys.showBatterySection])
    }
}
```

### SMAppService Side-Effect in Setter
**Source:** `MacStatus/MacStatus/Utils/SettingsManager.swift` lines 258–282
**Apply to:** `manualFanControlEnabled` setter (triggers daemon registration on first enable)
```swift
// From SettingsManager.swift launchAtLogin setter (lines 265–281):
// Pattern: attempt the system call first; only persist on success; let UI rebound on failure.
// For manualFanControlEnabled: trigger FanControlManager.registerHelperIfNeeded() on true;
// only write UserDefaults after confirming the intent (post risk dialog).
```

### settingsDidChange Observer (live reapply)
**Source:** `MacStatus/MacStatus/Collectors/MetricCollector.swift` lines 137–156
**Apply to:** `FanControlManager.swift` — react to `manualFanControlEnabled` key change
```swift
// From MetricCollector.swift setupSettingsObserver() (lines 137–156):
// Copy the observer registration pattern verbatim; react to "manualFanControlEnabled" key.
```

### @MainActor Task Hop (Timer / Observer closures)
**Source:** `MacStatus/MacStatus/Collectors/MetricCollector.swift` lines 89–92 and 147–150
**Apply to:** `FanControlManager.swift` — any async callbacks from XPC or timers
```swift
// From MetricCollector.swift (lines 89–92):
timer = Timer.scheduledTimer(...) { [weak self] _ in
    Task { @MainActor [weak self] in
        self?.tick()
    }
}
// XPC reply closures arrive on an unspecified queue — always hop back to @MainActor:
proxy?.setManualTarget(rpm: clamped) { success, code in
    Task { @MainActor [weak self] in
        self?.handleWriteReply(success: success, code: code)
    }
}
```

---

## No Analog Found

All files have at least a partial analog. The following have no in-codebase analog and should use RESEARCH.md patterns directly:

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `MacStatus/FanControlHelper/main.swift` | helper entry point | XPC event loop | No existing helper binary target in the project; pattern from RESEARCH.md + Apple NSXPCListener docs |
| `MacStatus/Resources/LaunchDaemons/com.macstatus.fancontrolhelper.plist` | config (plist) | — | No existing LaunchDaemon plist; use standard SMAppService daemon plist schema from Apple docs (requires `MachServices` dict + `BundleProgram` pointing to helper binary in `Contents/Library/HelperTools/`) |

---

## Metadata

**Analog search scope:** `MacStatus/MacStatus/Readers/`, `MacStatus/MacStatus/Collectors/`, `MacStatus/MacStatus/UI/Views/`, `MacStatus/MacStatus/Utils/`, `MacStatus/MacStatus/App/`
**Files read:** 8 source files (SMCReader, FanReader, MetricCollector, SettingsManager, DashboardView, SettingsView, StableValueLayout, AppDelegate)
**Pattern extraction date:** 2026-06-26
