# Architecture Research: MacStatus v3.0 Fan and Thermal Integration

**Domain:** macOS menu bar system monitor, v3.0 fan RPM, thermal sensors, safe fan control, fixed popover layout
**Researched:** 2026-06-23
**Overall confidence:** MEDIUM-HIGH

Confidence is HIGH for integration points in the existing codebase and MEDIUM for SMC write/control behavior because AppleSMC keys and write semantics are undocumented and vary by hardware/OS. The architecture below intentionally isolates fan control from read-only monitoring so the roadmap can ship low-risk read-only value first and gate write control behind explicit safety checks.

## Summary

MacStatus v3.0 should extend the existing `Reader -> MetricCollector -> DashboardState/StatusBarManager` pipeline for read-only thermal and fan RPM data, but fan control must be a separate lifecycle-managed component. Temperature snapshots and fan RPM snapshots are ordinary value-type data: read on the existing collector tick, stored only as last snapshots, and pushed into the popover. Fan writes are not ordinary metric reads: they need validation, mode tracking, restore-auto guarantees, sleep/quit hooks, and failure rollback.

Do not add more `NSStatusItem`s, do not persist thermal/fan samples to `MetricSample` in v3.0, and do not let SwiftUI views talk directly to SMC. The current v2.0 battery pattern is the right model: `BatterySnapshot` is `Sendable`, `BatteryReader` is synchronous, `MetricCollector` keeps `lastBatterySnapshot`, and `DashboardState` hides unavailable sections. Thermal and fan RPM should mirror that exactly.

The existing `SMCReader` is read-only and explicitly main-actor-confined in practice. v3.0 should either rename/refactor it into an `SMCClient` with read/write primitives or keep `SMCReader` as read-only and add a narrow `SMCWriter` owned only by `FanControlManager`. The safer route is a small `SMCClient` abstraction with: open/close, read key info, read raw bytes, decode numeric values, encode `fp78`, and write raw bytes. All public sensor/control APIs should return `Sendable` structs or typed errors; no IOKit handles, CF types, or mutable SMC structs should cross actor boundaries.

Layout stabilization should be planned separately from SMC sensor/control work. It is lower risk and mostly contained in `DashboardView`, `MetricCardWithSparkline`, and `PopoverManager` sizing. The popover should move from content-intrinsic height/partly flexible card text to fixed row/column dimensions with monospaced trailing value columns, so network value length and added thermal/fan sections cannot resize the panel.

## Existing Patterns

### Metric collection is a single main-actor timer

`MetricCollector` is `@MainActor`, owns one `Timer`, and synchronously calls each reader's `readValue()` on every tick. It already routes samples to `RingBuffer`, `HistoryStore`, `DashboardState`, and `StatusBarManager`. This is the only read-data integration point v3.0 needs to extend.

Evidence:
- `MetricCollector` documents the route `Timer -> RingBuffer/HistoryStore/DashboardState/StatusBarManager` and is `@MainActor` (`MacStatus/MacStatus/Collectors/MetricCollector.swift:5-16`).
- Existing readers are private members and initialized in `start()` (`MetricCollector.swift:28-34`, `MetricCollector.swift:57-71`).
- `tick()` reads CPU, memory, network, GPU, and battery synchronously (`MetricCollector.swift:146-155`).
- `lastBatterySnapshot` is kept outside `MetricSample` and pushed separately to the dashboard (`MetricCollector.swift:45-46`, `MetricCollector.swift:206-209`).

### Battery is the model for new popover-only snapshots

`BatterySnapshot` is immutable, value-type-only, `Sendable`, and optional fields degrade to `"—"` instead of faking values. `BatteryReader` is not a `TimerReader`; it is driven by `MetricCollector`. It also has wake recovery via `NSWorkspace.didWakeNotification`.

Evidence:
- `BatterySnapshot: Sendable, Equatable` with optional probe-and-nil fields (`MacStatus/MacStatus/Readers/BatteryReader.swift:6-50`).
- `BatteryReader` explicitly states it is synchronous and collector-driven (`BatteryReader.swift:63-67`).
- Wake observer uses main queue so wake state and collector reads stay serialized (`BatteryReader.swift:88-98`).
- `DashboardState.updateBattery(_:)` sets snapshot and hardware gate (`MacStatus/MacStatus/UI/Views/DashboardView.swift:371-373`, `DashboardView.swift:457-461`).

### SMC access exists, but only for reads

`SMCReader` opens `AppleSMC`, validates the 80-byte ABI struct layout, reads key info, reads raw bytes, and decodes `'flt '`, `spXY`, and `fpXY` formats. It has no write command, no raw-byte API, no fan force-mode helper, and no key enumeration.

Evidence:
- It is documented as "Minimal read-only client" (`MacStatus/MacStatus/Readers/SMCReader.swift:4-19`).
- It guards the critical 80-byte `SMCParamStruct` layout (`SMCReader.swift:58-100`).
- It opens and closes `AppleSMC` with IOKit (`SMCReader.swift:91-118`).
- It reads key info and decodes known numeric formats (`SMCReader.swift:122-200`).

### UI is fixed width but not fully fixed layout

`DashboardView` uses `.frame(width: 320)` and a two-column flexible `LazyVGrid`. Network text is forced to two lines, which fixed one class of network layout jitter, but value rows and new sections can still shift height/width if added naively.

Evidence:
- Popover body uses a two-column flexible grid (`MacStatus/MacStatus/UI/Views/DashboardView.swift:21-60`).
- Network text is multiline and trailing aligned in the metric card (`DashboardView.swift:146-151`, `DashboardView.swift:427-437`).
- The whole dashboard has fixed width 320 (`DashboardView.swift:123-125`).
- `PopoverManager` currently lets the hosting controller derive preferred content size from SwiftUI intrinsic content (`MacStatus/MacStatus/UI/PopoverManager.swift`, sizingOptions `.preferredContentSize`).

### App lifecycle currently lacks fan-restore hooks

`AppDelegate` currently wires managers and starts the collector. It does not implement terminate/sleep restore logic. Fan control must add those hooks centrally rather than hiding them in SwiftUI.

Evidence:
- AppDelegate's current role is wiring, collector start, and self-monitoring (`MacStatus/MacStatus/App/AppDelegate.swift:4-14`, `AppDelegate.swift:22-31`).

## Proposed Components

### New: `ThermalReader`

Purpose: read a small curated set of SMC temperature keys and return one `ThermalSnapshot?`.

Recommended shape:

```swift
struct ThermalSensorReading: Sendable, Equatable, Identifiable {
    let id: String          // SMC key, e.g. "TC0P"
    let name: String        // Display label, e.g. "CPU/SoC"
    let celsius: Double?
    let category: ThermalCategory
}

struct ThermalSnapshot: Sendable, Equatable {
    let sensors: [ThermalSensorReading]
    let primaryCelsius: Double?
    let hottestCelsius: Double?
    let capturedAt: Date
}

final class ThermalReader {
    private let smc: SMCClient
    func setup()
    func readValue() -> ThermalSnapshot?
}
```

Integration rules:
- Keep the first version curated, not exhaustive. Probe known CPU/SoC/GPU/battery/SSD key candidates and only display values that decode cleanly.
- No sensor dictionary, CF object, or mutable SMC struct crosses into UI. UI receives only `ThermalSnapshot`.
- `nil` or empty `sensors` means hide the thermal section or show "温度 N/A"; it is not an error state.
- Sampling can follow the global refresh interval initially. If SMC reads prove expensive, add `thermalTickModulo` later rather than another timer.

### New: `FanReader`

Purpose: read fan count and RPM/range metadata without performing writes.

Recommended shape:

```swift
struct FanReading: Sendable, Equatable, Identifiable {
    let id: Int
    let currentRPM: Double?
    let minRPM: Double?
    let maxRPM: Double?
    let safeRPM: Double?
    let targetRPM: Double?
}

struct FanSnapshot: Sendable, Equatable {
    let fans: [FanReading]
    let forceModeMask: UInt16?
    let capturedAt: Date
    var isSupported: Bool { !fans.isEmpty }
}

final class FanReader {
    private let smc: SMCClient
    func setup()
    func readValue() -> FanSnapshot?
}
```

SMC keys to probe:
- `FNum`: fan count.
- `F0Ac`, `F1Ac`, ...: actual RPM.
- `F0Mn`, `F0Mx`, `F0Sf`, `F0Tg`: minimum, maximum, safe, target RPM where available.
- `FS!`: force/manual mode bitmask.

The above keys are confirmed by long-standing SMC tooling, but they remain undocumented. Every key must be probe-and-nil, every fan row must tolerate partial data, and non-fan machines should render as unsupported without errors.

### New or refactored: `SMCClient`

Purpose: centralize the fragile AppleSMC ABI and prevent each feature from inventing its own `IOConnectCallStructMethod` handling.

Recommended implementation:
- Move the existing `SMCReader` ABI structs and open/close/read logic into `SMCClient`.
- Keep `SMCReader` as a compatibility wrapper only if it reduces diff size.
- Add raw read/write primitives:
  - `readKeyInfo(_ key: String) -> SMCKeyInfo?`
  - `readRaw(_ key: String) -> SMCValue?`
  - `readDouble(_ key: String) -> Double?`
  - `writeRaw(_ key: String, type: UInt32, bytes: [UInt8]) throws`
  - `encodeFP78(rpm:) -> [UInt8]`
- Keep it actor-confined by ownership, not globally `Sendable`. For v3.0, owning it from `@MainActor` readers/managers is acceptable because existing SMC reads already run on the main collector tick and are small.

Do not make SMC calls from SwiftUI views. Do not expose `io_connect_t`. Do not duplicate the 80-byte struct in fan code.

### New: `FanControlManager`

Purpose: own manual fan-control state, validation, write sequencing, and restore-auto lifecycle.

Recommended shape:

```swift
@MainActor
final class FanControlManager {
    static let shared = FanControlManager()

    private let smc: SMCClient
    private(set) var state: FanControlState

    func setup()
    func enableManual(fanID: Int, targetRPM: Int, latest: FanSnapshot) async
    func updateManualTarget(fanID: Int, targetRPM: Int, latest: FanSnapshot) async
    func restoreAutomatic(reason: FanRestoreReason) async
    func handleWillSleep()
    func handleWillTerminate()
}
```

Safety contract:
- Default state is automatic. Never persist "manual on" as a desired startup state.
- Manual control is only enabled when `FanSnapshot.isSupported`, current RPM, min/max RPM, and `FS!` are readable.
- Clamp requested RPM to hardware range and product policy. For v3.0, use "boost only" semantics: never allow a target below the current automatic RPM at enable time or below the reported minimum/safe RPM. This avoids building a UI that can intentionally reduce cooling.
- Write sequence must be all-or-restore:
  1. Capture previous `FS!` and target values.
  2. Write target key (`F0Tg`/`F1Tg`) using proper `fp78` encoding.
  3. Write `FS!` bitmask to enable manual for selected fan(s).
  4. Re-read `FanSnapshot` and verify mode/target changed.
  5. If any step fails, call `restoreAutomatic(reason: .writeFailed)`.
- `restoreAutomatic` writes `FS! = 0` for MacStatus-owned control, clears "session active" state, re-reads fan snapshot, and updates UI state.
- On quit, sleep, and app relaunch after a previous unclean manual session, restore automatic before doing anything else.
- If temperature snapshot becomes unavailable while manual mode is active, restore automatic. If primary/hottest temperature crosses a hard guard threshold, restore automatic. v3.0 should not try to be a full fan-curve daemon.

Why this is separate from `FanReader`: reads can fail harmlessly; writes can leave hardware in a bad state. Keeping control in `FanControlManager` makes restore paths auditably central.

### Modified: `MetricCollector`

Add:
- `private let thermalReader = ThermalReader(...)`
- `private let fanReader = FanReader(...)`
- `private var lastThermalSnapshot: ThermalSnapshot?`
- `private var lastFanSnapshot: FanSnapshot?`

In `start()`:
- call `thermalReader.setup()` and `fanReader.setup()`.
- perform first read as baseline only.

In `tick()`:
- read thermal and fan snapshots after battery.
- keep them out of `MetricSample`.
- update `DashboardState` through `dashboard.updateThermal(lastThermalSnapshot)` and `dashboard.updateFans(lastFanSnapshot, controlState: FanControlManager.shared.state)`.
- optionally call a lightweight `FanControlManager.shared.validateRuntimeSafety(thermal:fans:)` if manual mode is active.

Do not persist these snapshots in SQLite for v3.0. Persistent thermal history and charts are a different milestone.

### Modified: `DashboardState` and `DashboardView`

Add state:
- `@Published var thermal: ThermalSnapshot?`
- `@Published var hasThermalSensors: Bool`
- `@Published var fans: FanSnapshot?`
- `@Published var hasFans: Bool`
- `@Published var fanControlState: FanControlState`

Add views:
- `ThermalSectionView(snapshot:)`: compact full-width section with primary temperature, hottest temperature, and 3-5 important rows.
- `FanSectionView(snapshot:controlState:onRestore:onSetTarget:)`: RPM rows plus a clearly separated manual-control area.

Control UI rules:
- Restore Auto button is always visible when `controlState.isManualActive`.
- Manual target control is disabled unless fan support and safety metadata are present.
- Slider/stepper range comes from `FanReading.minRPM/maxRPM`, further clamped by boost-only policy.
- Show "不可用" or "N/A" for unsupported hardware; do not show scary errors for missing SMC keys.

### Modified: `SettingsManager` and `SettingsView`

Add simple visibility settings only:
- `showThermalSection: Bool = true`
- `showFanSection: Bool = true`
- optionally `enableFanControlUI: Bool = false` if the roadmap wants an explicit advanced safety gate.

Do not store target RPM as a normal preference in v3.0. A persisted target invites accidental manual mode restoration after reboot. If a target is needed for UI convenience, persist it as "last used target" only and never auto-apply it.

### Modified: `AppDelegate`

Add lifecycle hooks:
- `applicationWillTerminate(_:)` calls `FanControlManager.shared.handleWillTerminate()`.
- register `NSWorkspace.willSleepNotification` and restore automatic before sleep.
- optionally register wake notification to refresh fan snapshot and ensure UI state is automatic.

This belongs in `AppDelegate` because it is application lifecycle, not view lifecycle.

### Modified: `PopoverManager`

Use a fixed content size strategy once thermal/fan sections are added:
- Keep width fixed, likely increase from `320` to `360` or `380` if fan controls need labels and steppers.
- Set bounded min/max height and allow internal scrolling if all sections are visible.
- Avoid relying solely on `.preferredContentSize` if section visibility or network strings cause height churn while the popover is open.

## Data Flow

### Read-only sensor flow

```text
MetricCollector.start()
  -> thermalReader.setup()
  -> fanReader.setup()
  -> existing Timer

MetricCollector.tick() @MainActor
  -> ThermalReader.readValue() -> ThermalSnapshot?
  -> FanReader.readValue() -> FanSnapshot?
  -> cache lastThermalSnapshot / lastFanSnapshot
  -> DashboardState.updateThermal(...)
  -> DashboardState.updateFans(...)
  -> StatusBarManager unchanged for v3.0 unless roadmap explicitly wants menu-bar fan/temp segments
```

Recommendation: keep fan/thermal off the status bar in the first v3.0 slice. The current status bar already has CPU/GPU/memory/network ordering and customization. Fan/thermal data is richer and better suited to the popover. A later phase can add optional `.thermal` and `.fan` `Metric` cases after the popover proves stable.

### Fan control flow

```text
FanSectionView user action
  -> FanControlManager.enableManual(...) @MainActor
      -> validate latest FanSnapshot
      -> clamp target RPM
      -> SMCClient.writeRaw(FxTg)
      -> SMCClient.writeRaw(FS!)
      -> FanReader.readValue()
      -> update DashboardState fanControlState

Failure / quit / sleep / over-temp / sensor unavailable
  -> FanControlManager.restoreAutomatic(reason:)
      -> SMCClient.writeRaw(FS! = 0)
      -> clear MacStatus-owned manual session flag
      -> re-read FanSnapshot
      -> update UI
```

`FanControlManager` should treat writes as a critical section. While a write/restore is in progress, disable controls and ignore duplicate UI commands.

### Fixed popover layout flow

```text
DashboardState updates values
  -> DashboardView renders stable sections
      -> fixed width
      -> fixed metric card min heights
      -> monospaced trailing value columns
      -> ScrollView for optional sections
  -> PopoverManager uses stable content size
```

The key is that value text changes should not change grid geometry. Network rows, fan RPM rows, and temperature rows should all use fixed label/value column widths.

## Build Order

1. **Popover layout stabilization**
   - Scope: `DashboardView`, `MetricCardWithSparkline`, `PopoverManager`.
   - Rationale: independent of SMC risk and prevents new fan/thermal sections from compounding existing layout jitter.
   - Deliverable: stable fixed-width/fixed-row layout under long network values and all existing v2.0 sections.

2. **SMC client refactor without behavior change**
   - Scope: extract `SMCClient` from `SMCReader` while preserving `PSTR`/`PPBR` behavior.
   - Rationale: fan/thermal work depends on the fragile 80-byte SMC ABI. Refactor before adding more keys or writes.
   - Verification: battery power still reads/degrades exactly as before.

3. **Read-only fan RPM snapshots**
   - Scope: `FanReader`, `FanSnapshot`, `DashboardState.updateFans`, `FanSectionView` read-only UI.
   - Rationale: validates fan count/RPM/range keys safely before any write path exists.
   - Risk gate: unsupported machines must show no fan controls and no crashes.

4. **Read-only thermal snapshots**
   - Scope: `ThermalReader`, `ThermalSnapshot`, `ThermalSectionView`.
   - Rationale: temperature visibility is useful by itself and becomes a safety input for control.
   - Risk gate: curated key set only; all unknown keys degrade to nil.

5. **Fan control safety manager, restore-auto only**
   - Scope: `FanControlManager`, AppDelegate terminate/sleep hooks, Dashboard control state.
   - Rationale: implement lifecycle restore before manual write UI. This phase should include a "Restore Auto" action and startup cleanup of stale MacStatus-owned sessions.
   - Risk gate: forced mode can always be cleared in test conditions.

6. **Manual fan boost UI and write path**
   - Scope: manual target controls in `FanSectionView`, SMC write support, validation, rollback.
   - Rationale: highest-risk feature comes last after reads, layout, and restore hooks are in place.
   - Risk gate: every failed write restores auto; quit/sleep restore verified; UI never allows target below safe lower bound.

7. **Settings toggles and final polish**
   - Scope: `SettingsManager`, `SettingsView`, optional advanced fan-control gate.
   - Rationale: visibility toggles are simple, but should follow actual sections to avoid adding settings for unavailable UI.

## File Impact

### New files

| File | Purpose |
|------|---------|
| `MacStatus/MacStatus/Readers/SMCClient.swift` | Refactored AppleSMC open/read/write/raw encoding layer; may replace or wrap current `SMCReader`. |
| `MacStatus/MacStatus/Readers/ThermalReader.swift` | Curated SMC temperature probes and `ThermalSnapshot` value types. |
| `MacStatus/MacStatus/Readers/FanReader.swift` | Read-only fan count/RPM/range/force-mode snapshot. |
| `MacStatus/MacStatus/Control/FanControlManager.swift` | Manual fan boost state machine, SMC writes, restore-auto lifecycle. Create `Control/` group or place under `Utils/` if avoiding a new group. |
| `MacStatus/MacStatus/UI/Views/ThermalSectionView.swift` | Optional; can be nested in `DashboardView.swift` initially to avoid pbxproj churn. |
| `MacStatus/MacStatus/UI/Views/FanSectionView.swift` | Optional; can be nested first, split after behavior stabilizes. |

### Modified files

| File | Change |
|------|--------|
| `MacStatus/MacStatus/Readers/SMCReader.swift` | Refactor to `SMCClient` or delegate to it. Add write/raw support only in the shared SMC layer. Preserve 80-byte layout guard. |
| `MacStatus/MacStatus/Readers/BatteryReader.swift` | Update to use `SMCClient` for `PSTR`/`PPBR`; behavior should remain unchanged. |
| `MacStatus/MacStatus/Collectors/MetricCollector.swift` | Add thermal/fan readers, last snapshots, dashboard updates, and optional manual-mode safety validation. |
| `MacStatus/MacStatus/UI/Views/DashboardView.swift` | Add thermal/fan sections and fixed layout rules; avoid further growth of flexible value text. |
| `MacStatus/MacStatus/UI/PopoverManager.swift` | Stabilize popover content size and optional scroll behavior. |
| `MacStatus/MacStatus/Utils/SettingsManager.swift` | Add section visibility keys and migrations. Do not persist active manual fan mode. |
| `MacStatus/MacStatus/UI/Views/SettingsView.swift` | Add thermal/fan visibility toggles and optional advanced fan-control UI gate. |
| `MacStatus/MacStatus/App/AppDelegate.swift` | Add terminate/sleep hooks that call `FanControlManager.restoreAutomatic`. |
| `MacStatus/MacStatus.xcodeproj/project.pbxproj` | Add any new Swift files to the target sources. |

### Files that should not change for v3.0 unless scope expands

| File | Reason |
|------|--------|
| `MacStatus/MacStatus/Storage/MetricSample.swift` | Thermal/fan history is out of scope; keep snapshots popover-only like battery power details. |
| `MacStatus/MacStatus/Storage/HistoryStore.swift` | No schema migration needed if thermal/fan are not persisted. |
| `MacStatus/MacStatus/UI/StatusBarManager.swift` | Keep status bar unchanged initially. Add optional fan/thermal segments only in a later phase with explicit settings. |

## Sources/Evidence

### Local code evidence

- `.planning/PROJECT.md`: v3.0 active requirements require important temperature monitoring, MacBook Pro fan RPM monitoring, safe fan control with restore-auto, and fixed popover layout.
- `.planning/STATE.md`: v2.0 constraints require `Sendable` snapshots, one combined `NSStatusItem`, main-actor settings, and careful sleep/wake recovery.
- `MacStatus/MacStatus/Collectors/MetricCollector.swift:5-16`: existing collector is the central read/data fanout.
- `MacStatus/MacStatus/Collectors/MetricCollector.swift:146-155`: readers are synchronous on the collector tick.
- `MacStatus/MacStatus/Collectors/MetricCollector.swift:206-209`: battery snapshot is popover-only and outside `MetricSample`.
- `MacStatus/MacStatus/Readers/BatteryReader.swift:6-67`: snapshot/read pattern to mirror for thermal and fan RPM.
- `MacStatus/MacStatus/Readers/SMCReader.swift:4-19`: current SMC layer is read-only and not a fan-control abstraction.
- `MacStatus/MacStatus/Readers/SMCReader.swift:58-100`: SMC ABI layout is fragile; refactor must preserve the 80-byte guard.
- `MacStatus/MacStatus/UI/Views/DashboardView.swift:21-60`: current flexible grid where added sections must be layout-stabilized.
- `MacStatus/MacStatus/UI/Views/DashboardView.swift:427-437`: existing network jitter mitigation uses forced two-line value text.
- `MacStatus/MacStatus/App/AppDelegate.swift:22-31`: lifecycle entry point where fan restore hooks belong.

### External ecosystem evidence

- Stats README lists "Fan's control (not maintained)" and sensors/fan features, showing fan control is a known but fragile part of the current macOS monitor ecosystem: https://github.com/exelban/stats
- Stats release notes show recent SMC architecture moved from `SMJobBless` to `SMAppService.daemon`, evidence that privileged/SMC control architecture is still changing and should not be casually embedded in UI code: https://github.com/exelban/stats/releases
- Stats issue #2104 documents sleep/wake fan-control mode regressions where auto/manual state changed after wake, supporting the requirement to make restore-on-sleep/wake central: https://github.com/exelban/stats/issues/2104
- Stats issue #2094 documents newer Apple Silicon fan behavior where manual setting may not resume when the system turns fans off, supporting conservative UI state and re-read verification after writes: https://github.com/exelban/stats/issues/2094
- `jcsalterego/smc` documents common SMC fan keys `FNum`, `F0Ac`, `F0Mn`, `F0Mx`, `F0Sf`, `F0Tg`, and `FS!`, plus force-mode bit behavior. Confidence MEDIUM because this is community tooling over undocumented AppleSMC: https://github.com/jcsalterego/smc
- Linux `applesmc.c` describes Apple SMC as handling temperature sensors and fan control, and notes fan control was based on smcFanControl. Confidence MEDIUM for conceptual validation, not macOS API guarantees: https://chromium.googlesource.com/chromiumos/third_party/kernel/+/0.12.362.B/drivers/hwmon/applesmc.c
- SMCKit documentation states fan speed setting is hardware-sensitive and requires care, and notes setting fan speed requires root privileges in that tool. Treat MacStatus write feasibility as a phase-specific validation item: https://beltex.github.io/SMCKit/

## Roadmap Implications

- Phase thermal/fan RPM before fan control. Read-only SMC work validates key availability without risking hardware state.
- Put restore-auto infrastructure before any manual write UI. A fan-control feature is not ready when it can write; it is ready when every exit/failure path restores automatic mode.
- Keep layout work independent and early. It has low coupling and reduces UI churn before sensor sections are added.
- Mark fan-control write feasibility as a research flag for the control phase. If writes fail from the main app due to privilege or OS changes, the roadmap should either defer control or introduce a privileged `SMAppService` helper/daemon explicitly.
