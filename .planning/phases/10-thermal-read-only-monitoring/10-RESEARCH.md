# Phase 10: Thermal Read-Only Monitoring - Research

**Researched:** 2026-06-24
**Domain:** macOS read-only thermal monitoring via Swift, IOKit AppleSMC, AppleSmartBattery IORegistry, and `ProcessInfo.thermalState`
**Confidence:** MEDIUM-HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

Source: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md` [VERIFIED: codebase grep]

### Locked Decisions

### Temperature Trust Policy
- **D-01:** The primary CPU/SoC temperature must come from an explicitly trusted CPU or SoC sensor. If Phase 10 cannot confirm a sensor's meaning on the target hardware, the UI must show `N/A` rather than relabel an ambiguous package, proximity, die, or hottest value as CPU/SoC.
- **D-02:** `ProcessInfo.thermalState` is required as a separate semantic thermal-pressure field. It supplements temperature values but does not count as a substitute for the primary CPU/SoC temperature.
- **D-03:** Do not fabricate, smooth, cache old successful reads as current, or silently substitute unrelated SMC keys when a temperature key is missing or unreadable.

### Secondary Sensor Scope
- **D-04:** Phase 10 should attempt GPU and battery temperatures after the CPU/SoC primary value and system thermal state. These secondary values must be individually trusted and independently degradable.
- **D-05:** SSD temperature is deferred for Phase 10 unless planning discovers a reliable existing project-local/public macOS path that adds no new dependency and no shell-out. The default plan should not add SMART/NVMe dependency work for SSD temperature.
- **D-06:** A secondary sensor row should not be promoted into the primary CPU/SoC position. Secondary labels must stay honest, e.g. GPU and Battery.

### Degradation and Display Stability
- **D-07:** The thermal section should preserve rows for the Phase 10 fields it owns and display `N/A` or `—` on unsupported hardware, missing keys, or transient read failures. Avoid rows appearing/disappearing every tick.
- **D-08:** Unsupported or failed reads must stay quiet: no crash, no user-facing error popup, and no repeated console-noise loop in normal operation.
- **D-09:** The UI should use stable value formatting suitable for later Phase 12 hardening, including Celsius units, compact labels, and monospaced/right-aligned values where the existing dashboard pattern supports it.

### Popover and Settings Entry
- **D-10:** Add a dedicated popover section named around `散热`/thermal information rather than mixing thermal rows into the existing battery or metric cards.
- **D-11:** The thermal section should default to visible and get a Settings toggle, matching the existing `showBatterySection` / `showProcessSection` pattern.
- **D-12:** Phase 10 may reuse the current roughly 320pt dashboard width unless content truly forces an expansion. It must avoid introducing known jitter, while full fixed-width stress work remains Phase 12.

### Validation Target
- **D-13:** Phase 10 validation targets the user's current MacBook Pro first: Apple M3 Max, model identifier `Mac15,9`.
- **D-14:** Intel/T2 and other Apple Silicon sensor catalogs are not required for Phase 10. Other machines must gracefully degrade rather than crash or show misleading values.

### the agent's Discretion
- The planner may choose the internal type names and exact file split, but should keep the existing read-only snapshot pattern and avoid adding a generic public SMC writer.
- The planner may decide whether the thermal settings toggle lands in the existing General settings section or a new display-related group, as long as it follows the current SettingsManager/UserDefaults style.

### Deferred Ideas (OUT OF SCOPE)

- SSD temperature support is deferred unless a no-dependency, reliable path already exists.
- Intel/T2 and broader multi-model sensor catalogs are deferred beyond Phase 10.
- Fan RPM, fan capability modeling, layout stress hardening, and fan control remain in Phases 11-14.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| THERM-01 | 用户能在弹窗中看到 CPU/SoC 主温度，显示值必须来自可信传感器或明确标为 `N/A` | Use a strict Mac15,9 CPU key allowlist plus local key-probe evidence before rendering the primary value; otherwise render `CPU/SoC N/A`. [VERIFIED: `.planning/REQUIREMENTS.md`] [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/Modules/Sensors/values.swift] |
| THERM-02 | 用户能在弹窗中看到系统 thermal state，用于补充说明当前系统热压力 | Read `ProcessInfo.processInfo.thermalState` each snapshot and map `.nominal/.fair/.serious/.critical/@unknown default` to stable Chinese labels. [CITED: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum] |
| THERM-03 | 用户能看到可信的 GPU、电池、SSD 等次要温度；不可读或不可信时不显示假值 | Attempt GPU from trusted M3 GPU SMC keys and battery from `TB1T`/`TB2T` plus `AppleSmartBattery Temperature`; omit SSD by default. [VERIFIED: local ioreg] [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/Modules/Sensors/values.swift] |
| THERM-04 | 传感器缺失、机型不支持或读取失败时，温度区块优雅降级，不崩溃、不刷错误弹窗 | Preserve stable UI rows and propagate `nil` values through `ThermalSnapshot`, matching existing battery probe-and-nil pattern. [VERIFIED: `MacStatus/MacStatus/Readers/BatteryReader.swift`] [VERIFIED: `MacStatus/MacStatus/UI/Views/DashboardView.swift`] |
</phase_requirements>

## Project Constraints (from AGENTS.md)

- Use Chinese for all user-facing communication. [VERIFIED: `AGENTS.md`]
- Target macOS 14+ with Swift, SwiftUI, and AppKit; menu bar behavior relies on AppKit `NSStatusBar`. [VERIFIED: `AGENTS.md`]
- Keep the app lightweight: avoid visible CPU cost from status updates, use reasonable sampling, and avoid high-frequency polling. [VERIFIED: `AGENTS.md`]
- Keep dependencies absent or minimal; Phase 10 should add no external package. [VERIFIED: `AGENTS.md`] [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`]
- Before file-changing work, use the GSD workflow entry points; this research file is produced by the phase research workflow. [VERIFIED: `AGENTS.md`]

## Summary

Phase 10 should implement a read-only `ThermalReader` that returns a value-type `ThermalSnapshot` and flows through the existing `MetricCollector -> DashboardState -> DashboardView` popover path. [VERIFIED: `MacStatus/MacStatus/Collectors/MetricCollector.swift`] [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`] The work should not touch `MetricSample`, SQLite history, status-bar metrics, fan rows, fan controls, SMC writes, notifications, or raw sensor browsing. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-UI-SPEC.md`]

The primary technical risk is sensor trust, not rendering. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`] Stats' current source lists M3 CPU temperature candidates (`Te*` efficiency keys and `Tf*` performance keys) and M3 GPU candidates (`Tf14` through `Tf2A`), but its README warns that Apple changes sensor keys by SoC and that CPU/GPU labels are thermal zones rather than exact core identities. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/Modules/Sensors/values.swift] [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/README.md] Therefore the planner should require a Mac15,9 probe step before accepting any CPU/SoC primary key as trusted; absent that evidence, `CPU/SoC N/A` is the correct result. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`]

**Primary recommendation:** Add `ThermalSnapshot`, `ThermalReader`, and a small read-only SMC decoding extension; use explicit Mac15,9 trusted candidate lists plus local verification to populate `CPU/SoC`, `GPU`, `电池`, and `系统状态`, with stable `N/A` degradation and a default-on `showThermalSection` setting. [VERIFIED: codebase grep] [CITED: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| SMC temperature decoding | Native Reader layer | IOKit AppleSMC user client | Existing `SMCReader` owns AppleSMC ABI and must remain the only AppleSMC struct-call boundary for reads. [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`] |
| Thermal semantic state | Native Reader layer | Foundation `ProcessInfo` | `ProcessInfo.thermalState` is a cheap semantic OS signal and belongs in the snapshot, not in UI inference. [CITED: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property] |
| Battery temperature | Native Reader layer | IOKit Power Sources / AppleSmartBattery IORegistry | Existing battery code already uses IOPS and AppleSmartBattery with probe-and-nil semantics; Phase 10 should reuse the same source family for battery temperature. [VERIFIED: `MacStatus/MacStatus/Readers/BatteryReader.swift`] |
| Snapshot collection | Collector layer | Dashboard state | `MetricCollector` already owns the unified timer and non-persistent battery snapshot cache; thermal should mirror that pattern. [VERIFIED: `MacStatus/MacStatus/Collectors/MetricCollector.swift`] |
| Popover thermal display | SwiftUI UI layer | SettingsManager | `DashboardView` renders settings-gated sections and `SettingsManager` owns default-on section toggles. [VERIFIED: `MacStatus/MacStatus/UI/Views/DashboardView.swift`] [VERIFIED: `MacStatus/MacStatus/Utils/SettingsManager.swift`] |
| Hardware trust evidence | Verification/UAT | Reader diagnostics | Runtime key presence and values must be proven on Mac15,9 before a primary CPU/SoC value is considered trusted. [VERIFIED: local `sysctl -n hw.model`] [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`] |

## Standard Stack

### Core

| Library/API | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| Swift | 6.3.2 on this machine | Implement value snapshots, readers, and SwiftUI views | Project language and installed toolchain. [VERIFIED: local `swift --version`] [VERIFIED: `AGENTS.md`] |
| Xcode | 26.5 on this machine | Build the macOS app target | Current local project build tool. [VERIFIED: local `xcodebuild -version`] |
| Foundation `ProcessInfo.thermalState` | macOS 14+ target | Semantic system thermal pressure row | Apple exposes `.nominal`, `.fair`, `.serious`, and `.critical` thermal states through `ProcessInfo`. [CITED: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum] |
| IOKit `IOServiceOpen` + `IOConnectCallStructMethod` | macOS SDK | AppleSMC read-only key access | Existing `SMCReader` uses this path; Apple documents the IOKit user-client open and struct-call functions, while AppleSMC key protocol remains undocumented. [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`] [CITED: https://developer.apple.com/documentation/iokit/1514515-ioserviceopen] [CITED: https://developer.apple.com/documentation/iokit/1514274-ioconnectcallstructmethod] |
| IOKit `IORegistryEntryCreateCFProperty` | macOS SDK | Read AppleSmartBattery properties and existing IOAccelerator dictionaries | Apple documents this as creating a snapshot of an IORegistry property; existing readers already use it. [CITED: https://developer.apple.com/documentation/iokit/1514293-ioregistryentrycreatecfproperty] [VERIFIED: `MacStatus/MacStatus/Readers/BatteryReader.swift`] |
| UserDefaults via `SettingsManager` | macOS SDK | Store `showThermalSection` default-on toggle | Existing `showBatterySection` and `showProcessSection` follow this exact pattern. [VERIFIED: `MacStatus/MacStatus/Utils/SettingsManager.swift`] |

### Supporting

| API / Pattern | Version | Purpose | When to Use |
|---------------|---------|---------|-------------|
| `sysctlbyname("hw.model")` | Darwin | Determine Mac15,9 during trust probing | Use in reader setup or verification harness to select Mac15,9 candidate lists. [VERIFIED: local `sysctl -n hw.model`] |
| `IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceDescription` | macOS SDK | Confirm internal battery presence | Use if the implementation needs to avoid showing battery temperature on desktop Macs. [CITED: https://developer.apple.com/documentation/iokit/1523839-iopscopypowersourcesinfo] [CITED: https://developer.apple.com/documentation/iokit/1523867-iopsgetpowersourcedescription] |
| Existing `IOAccelerator` reader pattern | Project code | Reuse IOKit iteration style for optional GPU source investigation | Current `IOAccelerator` `PerformanceStatistics` on Mac15,9 exposes utilization keys, not a direct temperature key in observed output. [VERIFIED: local `ioreg -r -c IOAccelerator`] [VERIFIED: `MacStatus/MacStatus/Readers/GPUReader.swift`] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SMC + AppleSmartBattery + ProcessInfo | `powermetrics`, `pmset`, `ioreg` shellouts | Shellouts violate the phase constraint and add parsing/privilege/latency risk. [VERIFIED: `.planning/research/STACK.md`] |
| Curated key catalog | Raw SMC sensor browser | A raw browser is explicitly out of scope and would expose ambiguous labels to users. [VERIFIED: `.planning/REQUIREMENTS.md`] |
| `ProcessInfo.thermalState` as separate row | Use thermal state as temperature substitute | User decision forbids treating semantic thermal state as the primary CPU/SoC temperature. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`] |
| SSD temperature in Phase 10 | SMART/NVMe framework or disk sensor work | No reliable project-local no-dependency path exists in current code; default plan should omit SSD. [VERIFIED: codebase grep] [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`] |

**Installation:**

```bash
# No package installation for Phase 10.
```

**Version verification:** no external package versions are required. [VERIFIED: codebase grep]

## Package Legitimacy Audit

Phase 10 should install no external packages. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`]

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| none | — | — | — | — | not run | Approved: no package install |

**Packages removed due to slopcheck [SLOP] verdict:** none.
**Packages flagged as suspicious [SUS]:** none.

## Architecture Patterns

### System Architecture Diagram

```text
MetricCollector.start()
  -> thermalReader.setup()
       -> SMCReader.open() read-only AppleSMC connection
       -> determine model identifier (Mac15,9 target first)
  -> existing unified Timer

MetricCollector.tick() @MainActor
  -> ThermalReader.readValue()
       -> read trusted CPU/GPU/battery SMC candidates
       -> read AppleSmartBattery Temperature fallback for battery
       -> read ProcessInfo.processInfo.thermalState
       -> filter implausible/currently unreadable values to nil
       -> ThermalSnapshot
  -> cache lastThermalSnapshot outside MetricSample
  -> DashboardState.updateThermal(snapshot)
  -> DashboardView
       -> if SettingsManager.showThermalSection
       -> ThermalSectionView stable rows:
          CPU/SoC, 系统状态, GPU, 电池
```

All flow above is read-only and does not add SMC write commands. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`]

### Recommended Project Structure

```text
MacStatus/MacStatus/
├── Readers/
│   ├── SMCReader.swift          # EDIT: read-only typed decode extensions only
│   ├── ThermalReader.swift      # ADD: ThermalSnapshot + trusted sensor reads
│   └── BatteryReader.swift      # optional reference or battery temp source reuse
├── Collectors/
│   └── MetricCollector.swift    # EDIT: setup/read/cache thermal snapshot
├── UI/Views/
│   ├── DashboardView.swift      # EDIT: DashboardState + ThermalSectionView
│   └── SettingsView.swift       # EDIT: add 散热区块 toggle
└── Utils/
    └── SettingsManager.swift    # EDIT: showThermalSection key/default/get/set
```

New Swift files must be registered in `MacStatus.xcodeproj/project.pbxproj`; prior phase research recorded this as a verification trap. [VERIFIED: `.planning/research/PITFALLS.md`] [VERIFIED: local `rg --files`]

### Pattern 1: Read-Only SMC Boundary Extension

**What:** Extend `SMCReader` to expose read-only typed metadata and raw bytes internally, then keep `readValue(key:) -> Double?` for existing callers. [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`]

**When to use:** Use when `ThermalReader` must know SMC data type (`sp78`, `fpe2`, `flt `, `ui16`, etc.) and reject unknown or implausible values without adding write support. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/SMC/smc.swift]

**Example:**

```swift
// Source: project SMCReader + Stats SMC type list.
// Keep this read-only; do not add cmdWriteBytes in Phase 10.
struct SMCValue: Sendable, Equatable {
    let key: String
    let dataType: String
    let dataSize: UInt32
    let bytes: [UInt8]
}

extension SMCReader {
    func readRawValue(key: String) -> SMCValue? {
        // Use existing readKeyInfo (data8 = 9) then readBytes (data8 = 5).
        // Return nil for closed connection, absent key, nonzero SMC result, or invalid size.
    }

    func readTemperatureCelsius(key: String) -> Double? {
        guard let value = readRawValue(key: key),
              let celsius = Self.decodeNumeric(value),
              (0...120).contains(celsius)
        else { return nil }
        return celsius
    }
}
```

### Pattern 2: Strict Trusted Sensor Catalog

**What:** Keep candidate keys in code as explicit groups, not string guesses in the UI. [VERIFIED: `.planning/research/ARCHITECTURE.md`]

**When to use:** Use before every read so `ThermalReader` can decide which values may populate `CPU/SoC`, `GPU`, or `电池`. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`]

**Example:**

```swift
// Source: Stats values.swift at 9a8e6e26; must be validated on Mac15,9 before primary display.
enum ThermalSensorCatalog {
    static let mac15_9M3CPUCandidates = [
        "Te05", "Te0L", "Te0P", "Te0S",
        "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
        "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"
    ]

    static let m3GPUCandidates = [
        "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"
    ]

    static let batterySMCCandidates = ["TB1T", "TB2T"]
}
```

### Pattern 3: Snapshot-Only Collector Integration

**What:** Store the last thermal snapshot beside `lastBatterySnapshot`, outside `MetricSample`, `RingBuffer`, and `HistoryStore`. [VERIFIED: `MacStatus/MacStatus/Collectors/MetricCollector.swift`]

**When to use:** Use for Phase 10 because thermal values are popover-only and should not create history or status-bar metrics. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-UI-SPEC.md`]

**Example:**

```swift
// Source: BatteryReader/MetricCollector pattern.
private let thermalReader = ThermalReader()
private var lastThermalSnapshot: ThermalSnapshot?

func start() {
    thermalReader.setup()
    _ = thermalReader.readValue()
}

private func tick() {
    let thermal = thermalReader.readValue()
    lastThermalSnapshot = thermal
    updateUI(sample: sample)
}

private func updateUI(sample: MetricSample) {
    let dashboard = PopoverManager.shared.dashboardState
    dashboard.updateThermal(lastThermalSnapshot)
}
```

### Pattern 4: Stable SwiftUI Rows

**What:** Render the section even when values are unavailable, using monospaced, trailing values and fixed row labels. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-UI-SPEC.md`]

**When to use:** Always use in `ThermalSectionView`; do not insert/remove Phase 10 rows on transient read failure. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`]

**Example:**

```swift
// Source: DashboardView BatterySectionView row pattern.
private func row(_ label: String, _ value: String, color: Color = .secondary) -> some View {
    HStack {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
        Text(value)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(color)
            .frame(minWidth: 52, alignment: .trailing)
    }
}
```

### Anti-Patterns to Avoid

- **Generic SMC writer in `SMCReader`:** Phase 10 is read-only and must not introduce `cmdWriteBytes` or public `writeValue`. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`] [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/SMC/smc.swift]
- **Hottest/average fallback as primary CPU/SoC without key trust:** User explicitly rejected relabeling ambiguous hottest/package/proximity values. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`]
- **Using `ProcessInfo.thermalState` as temperature:** It is semantic pressure only and must be a separate row. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`] [CITED: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum]
- **SSD row by default:** Existing project code has no reliable no-dependency SSD temperature path; omit unless implementation discovers and verifies one. [VERIFIED: codebase grep]
- **Previous-good-value caching:** Failed current reads must render `N/A`, not stale temperatures. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| System thermal pressure | Custom thresholds from ambiguous temperatures | `ProcessInfo.processInfo.thermalState` row | Apple already exposes semantic thermal pressure; Phase 10 should not invent numeric policy. [CITED: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum] |
| Battery presence and battery registry access | Model-name checks | IOPS + `AppleSmartBattery` probe-and-nil | Existing battery code already proves this pattern and avoids desktop/laptop guesses. [VERIFIED: `MacStatus/MacStatus/Readers/BatteryReader.swift`] |
| AppleSMC ABI | Duplicate structs in `ThermalReader` | Existing `SMCReader` with read-only extensions | The 80-byte struct layout is fragile and already guarded in one file. [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`] |
| GPU temperature trust | Derive temperature from GPU utilization or pressure | Trusted SMC GPU keys only, else `N/A` | Current IOAccelerator output on Mac15,9 exposes utilization, not a direct temperature value. [VERIFIED: local `ioreg -r -c IOAccelerator`] |
| SSD temperature | SMART/NVMe subsystem | Omit in Phase 10 | SSD is deferred unless a reliable existing no-dependency path is found. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`] |

**Key insight:** In Phase 10, nil is a valid product state; false certainty is the bug. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`]

## Common Pitfalls

### Pitfall 1: Treating M3 sensor labels as self-evident

**What goes wrong:** A `Tf*` or `Te*` value is shown as `CPU/SoC` without recording why that key is trusted on Mac15,9. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/README.md]
**Why it happens:** AppleSMC keys are undocumented and Stats warns that Apple changes mappings by SoC. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/README.md]
**How to avoid:** Add a verification task that probes Mac15,9 candidate keys, records present keys and plausible values, and only then enables primary CPU/SoC output. [VERIFIED: local `sysctl -n hw.model`]
**Warning signs:** Code falls back to any `T*` key, `Hottest CPU`, `TC0P`, `TCAD`, or a generated average without trust metadata. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`]

### Pitfall 2: Missing SMC data type support

**What goes wrong:** Temperature values decode as `nil` or nonsense because `SMCReader` currently lacks explicit `ui8`, `ui16`, `ui32`, and `fpe2` support. [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`]
**Why it happens:** Existing v2.0 power keys only required `'flt '` and fixed-point support. [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`]
**How to avoid:** Extend decoders before adding `ThermalReader`, and unit/fixture-test raw bytes for `sp78`, `fpe2`, `flt `, `ui16`, and absent/unknown types. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/SMC/smc.swift]
**Warning signs:** CPU/GPU temperatures below ambient, above 120°C, exactly zero, or changing by impossible jumps. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/Modules/Sensors/readers.swift]

### Pitfall 3: Row churn from transient nil reads

**What goes wrong:** GPU or battery rows appear/disappear every tick. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-UI-SPEC.md`]
**Why it happens:** Live value availability is confused with section ownership. [VERIFIED: `.planning/research/PITFALLS.md`]
**How to avoid:** Always render `CPU/SoC`, `系统状态`, `GPU`, and `电池` rows when `showThermalSection` is true; render missing values as `N/A` or `—`. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-UI-SPEC.md`]
**Warning signs:** `if let gpuCelsius` wraps the entire row instead of just formatting its value. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-UI-SPEC.md`]

### Pitfall 4: Accidentally adding fan/control scope

**What goes wrong:** A "thermal" task adds fan RPM, fan mode, `FS! `, `F0Ac`, or SMC writes. [VERIFIED: `.planning/ROADMAP.md`]
**Why it happens:** Stats combines sensors and fans in one module, but this roadmap splits them across phases. [VERIFIED: `.planning/ROADMAP.md`] [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/Modules/Sensors/readers.swift]
**How to avoid:** Limit Phase 10 SMC keys to temperature candidates and battery temperature keys; leave fan keys for Phase 11+. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`]
**Warning signs:** Any new code path references `FNum`, `F0Ac`, `F0Mn`, `F0Mx`, `F0Tg`, `F0Md`, `F0md`, or `FS! `. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/Modules/Sensors/readers.swift]

### Pitfall 5: New Swift files not added to the Xcode target

**What goes wrong:** `ThermalReader.swift` exists on disk but is absent from `project.pbxproj`. [VERIFIED: `.planning/research/PITFALLS.md`]
**Why it happens:** This project uses an Xcode project, not SwiftPM auto-discovery. [VERIFIED: local `xcodebuild -list`]
**How to avoid:** Verification must grep `project.pbxproj` for every new Swift file and run an Xcode build. [VERIFIED: local `MacStatus/MacStatus.xcodeproj/project.pbxproj`]
**Warning signs:** Build tasks mention source files but not target membership. [VERIFIED: `.planning/research/PITFALLS.md`]

## Code Examples

### Thermal Snapshot

```swift
// Source: BatterySnapshot pattern + Phase 10 UI contract.
enum SystemThermalState: Sendable, Equatable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .unknown
        }
    }
}

struct ThermalSnapshot: Sendable, Equatable {
    let primaryCPUSoCCelsius: Double?
    let systemState: SystemThermalState
    let gpuCelsius: Double?
    let batteryCelsius: Double?
    let capturedAt: Date
}
```

### Temperature Formatting

```swift
// Source: UI-SPEC value strings.
private func temperatureText(_ value: Double?) -> String {
    guard let value else { return "N/A" }
    return "\(Int(value.rounded()))°C"
}
```

### Battery Temperature Candidate Read

```swift
// Source: local ioreg showed AppleSmartBattery Temperature = 3036 on Mac15,9.
private func appleSmartBatteryTemperatureCelsius() -> Double? {
    let service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("AppleSmartBattery")
    )
    guard service != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(service) }

    var propsRef: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let props = propsRef?.takeRetainedValue() as? [String: Any],
          let raw = props["Temperature"] as? Int
    else { return nil }

    let celsius = Double(raw) / 100.0
    return (0...100).contains(celsius) ? celsius : nil
}
```

## State of the Art

| Old Approach | Current Approach | When Changed / Evidence | Impact |
|--------------|------------------|--------------------------|--------|
| One hard-coded Intel CPU key such as `TC0D` | Probe curated model/generation lists and degrade to nil | Stats source carries separate M1/M2/M3/M4/M5 key groups. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/Modules/Sensors/values.swift] | Planner must not assume Intel keys work on Mac15,9. |
| Treat thermal state as exact temperature | Show `ProcessInfo.thermalState` as semantic row | Apple exposes thermal states through Foundation. [CITED: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum] | Meets THERM-02 without violating THERM-01. |
| Show any available SMC `T*` key | Show only trusted category keys; unknown keys stay hidden | User locked strict trust policy. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`] | Prevents misleading labels. |
| Use IOAccelerator utilization as proxy for GPU heat | Use GPU temperature only if trusted SMC key reads; else `N/A` | Current Mac15,9 IOAccelerator `PerformanceStatistics` shows utilization keys but no direct temperature key in observed output. [VERIFIED: local `ioreg -r -c IOAccelerator`] | Prevents derived/fake GPU temperature. |

**Deprecated/outdated:**
- Single-key CPU temperature assumptions are not acceptable for Phase 10 on Apple Silicon. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/README.md]
- Fan control concepts belong to later phases and must not leak into this plan. [VERIFIED: `.planning/ROADMAP.md`]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| macOS | App runtime and hardware probes | ✓ | 26.5.1 on this machine | Target remains macOS 14+; probe-and-nil on API/hardware gaps. [VERIFIED: local `sw_vers`] |
| Xcode | Build verification | ✓ | 26.5 | None needed. [VERIFIED: local `xcodebuild -version`] |
| Swift | Implementation | ✓ | 6.3.2 | None needed. [VERIFIED: local `swift --version`] |
| Mac15,9 hardware | Primary UAT target | ✓ | Apple M3 Max model identifier | If unavailable in CI, mark hardware verification as manual/local. [VERIFIED: local `sysctl -n hw.model`] |
| AppleSmartBattery | Battery temperature | ✓ on current machine | `Temperature` raw value observed as `3036` | Use `N/A` on desktops or unreadable registry. [VERIFIED: local `ioreg -r -c AppleSmartBattery`] |
| IOAccelerator | Existing GPU utilization / possible registry investigation | ✓ | AGX / Apple M3 Max observed | Use SMC GPU keys for temperature; render GPU `N/A` if no trusted temperature. [VERIFIED: local `ioreg -r -c IOAccelerator`] |
| Context7 CLI | Docs fallback | ✗ | `ctx7` not found | Official Apple docs and source fetches used instead. [VERIFIED: local `command -v ctx7`] |

**Missing dependencies with no fallback:** none for Phase 10. [VERIFIED: local environment probes]
**Missing dependencies with fallback:** Context7 CLI is missing; official docs and project/source evidence are sufficient for this phase. [VERIFIED: local `command -v ctx7`]

## Verification Strategy

`workflow.nyquist_validation` is explicitly `false`, so this research omits the GSD Validation Architecture section. [VERIFIED: `.planning/config.json`] The planner should still require these Phase 10 checks. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`]

| Area | Verification | Command / Method |
|------|--------------|------------------|
| Build and target membership | Ensure new Swift files compile and are in the Xcode project | `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug build`; `rg "ThermalReader.swift|ThermalSectionView|showThermalSection" MacStatus/MacStatus.xcodeproj/project.pbxproj MacStatus/MacStatus` [VERIFIED: local `xcodebuild -list`] |
| Read-only SMC boundary | Ensure no write command/API added in Phase 10 | `rg "cmdWriteBytes|writeBytes|writeValue|writeRaw|FS!|F[0-9](Ac|Mn|Mx|Tg|Md|md)|FNum" MacStatus/MacStatus` should not show new Phase 10 fan/control paths. [VERIFIED: `.planning/ROADMAP.md`] |
| Mac15,9 CPU key trust | Probe exact M3 CPU candidate keys and record present key/type/value evidence | Temporary local probe using `SMCReader.readRawValue` over `Te05/Te0L/Te0P/Te0S/Tf04...Tf4E`; primary stays `N/A` until evidence is recorded. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/Modules/Sensors/values.swift] |
| Missing key degradation | Inject fake reader or test catalog with absent keys | Snapshot returns `primaryCPUSoCCelsius == nil`, `gpuCelsius == nil`, and UI shows `N/A`; no alert or console loop. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-UI-SPEC.md`] |
| Thermal state mapping | Exercise `.nominal/.fair/.serious/.critical/@unknown default` mapping | Pure Swift unit-style function test or preview values; current machine observed `nominal`. [VERIFIED: local Swift execution] |
| Battery temperature | Validate AppleSmartBattery raw temperature handling | Current Mac15,9 `ioreg` exposes `Temperature => 3036`; implementation must cast probe-and-nil and bounds-check. [VERIFIED: local `ioreg -r -c AppleSmartBattery`] |
| Stable UI rows | Preview with all nil, all present, and mixed nil snapshots | Confirm rows remain `CPU/SoC`, `系统状态`, `GPU`, `电池` with `N/A`/labels and no row churn. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-UI-SPEC.md`] |
| Settings toggle | Toggle `散热区块` live | Follows `showBatterySection`/`showProcessSection`; setting hides/shows the whole thermal section without forcing a fresh SMC read. [VERIFIED: `MacStatus/MacStatus/Utils/SettingsManager.swift`] |

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | No auth surface is added. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-UI-SPEC.md`] |
| V3 Session Management | no | No session surface is added. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-UI-SPEC.md`] |
| V4 Access Control | no | No privileged helper, SMC write, or user role boundary is added. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`] |
| V5 Input Validation | yes | Validate decoded sensor values with bounds and optional casts; reject unknown keys/types to nil. [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`] [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/Modules/Sensors/readers.swift] |
| V6 Cryptography | no | No cryptography is added. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-UI-SPEC.md`] |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Misleading hardware state from ambiguous key | Tampering / Integrity | Explicit allowlist plus Mac15,9 probe evidence; otherwise `N/A`. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`] |
| Hardware control accidentally introduced | Elevation of Privilege / Tampering | No SMC write constants, no fan keys, no helper, no control UI in Phase 10. [VERIFIED: `.planning/ROADMAP.md`] |
| Crash from absent IORegistry/SMC properties | Denial of Service | Probe-and-nil optional casts; never force unwrap CF dictionaries. [VERIFIED: `MacStatus/MacStatus/Readers/BatteryReader.swift`] |
| UI alarm fatigue from normal unsupported state | Reliability | Inline `N/A`/`—`, no modal or alert. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-UI-SPEC.md`] |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The Stats M3 `Te*`/`Tf*` candidate groups are good starting points for Mac15,9 CPU/GPU thermal probing, but not sufficient alone for final trust. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/Modules/Sensors/values.swift] | Standard Stack / Verification Strategy | Primary CPU/SoC may remain `N/A` until local probe confirms candidates. |
| A2 | AppleSmartBattery `Temperature` raw value can be converted by `/100` for Celsius after type/bounds validation. [VERIFIED: local ioreg] | Code Examples | Battery temperature may show `N/A` if raw units differ on another model. |

## Open Questions (RESOLVED)

1. **RESOLVED — Which exact Mac15,9 SMC key should be accepted as the Phase 10 primary CPU/SoC source?**
   - What we know: Stats maps M3 CPU thermal-zone candidates to `Te05`, `Te0L`, `Te0P`, `Te0S`, and `Tf04` through `Tf4E`. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/Modules/Sensors/values.swift]
   - Resolution: Phase 10 does not pre-accept any single Mac15,9 SMC key at planning time. The primary `CPU/SoC` value must remain `N/A` until the implementation's read-only Mac15,9 probe records candidate key/type/value evidence and the executor can justify a specific key as explicitly trusted. If no candidate can be justified during execution, shipping `CPU/SoC N/A` still satisfies the locked trust policy. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`]

2. **RESOLVED — Should Phase 10 include Apple Silicon HID/IOReport temperature sensors?**
   - What we know: Stats can read Apple Silicon HID temperature sensors such as `SOC MTR Temp Sensor%`, but this project has no HID sensor bridge today. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/Modules/Sensors/readers.swift] [VERIFIED: codebase grep]
   - Resolution: HID/IOReport temperature discovery is excluded from Phase 10. This phase stays on the existing SMC/AppleSmartBattery/`ProcessInfo.thermalState` path; adding HID/IOReport requires explicit re-planning or a later phase. If SMC candidates fail, the primary remains `N/A` and `ProcessInfo.thermalState` still provides the semantic heat-pressure row. [VERIFIED: `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md`] [CITED: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum]

## Sources

### Primary (HIGH confidence)

- `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md` — locked decisions, scope, degradation rules, and Mac15,9 target. [VERIFIED: codebase grep]
- `.planning/phases/10-thermal-read-only-monitoring/10-UI-SPEC.md` — required UI rows, copy, settings toggle, and no-control constraints. [VERIFIED: codebase grep]
- `.planning/REQUIREMENTS.md` — THERM-01 through THERM-04. [VERIFIED: codebase grep]
- `MacStatus/MacStatus/Readers/SMCReader.swift` — existing read-only AppleSMC boundary and 80-byte ABI guard. [VERIFIED: codebase grep]
- `MacStatus/MacStatus/Readers/BatteryReader.swift` — optional snapshot, IOPS/AppleSmartBattery pattern, and SMC-owned read-only access. [VERIFIED: codebase grep]
- `MacStatus/MacStatus/Collectors/MetricCollector.swift` — unified timer, `lastBatterySnapshot`, and non-persistent UI update path. [VERIFIED: codebase grep]
- `MacStatus/MacStatus/UI/Views/DashboardView.swift` — current 320pt dashboard, battery section row style, and `DashboardState`. [VERIFIED: codebase grep]
- `MacStatus/MacStatus/Utils/SettingsManager.swift` — `showBatterySection`/`showProcessSection` default-on settings pattern. [VERIFIED: codebase grep]
- Apple Developer `ProcessInfo.ThermalState` and `thermalState` docs — official semantic thermal state API. [CITED: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum] [CITED: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property]
- Apple Developer IOKit docs for `IOServiceOpen`, `IOConnectCallStructMethod`, `IORegistryEntryCreateCFProperty`, and Power Sources. [CITED: https://developer.apple.com/documentation/iokit/1514515-ioserviceopen] [CITED: https://developer.apple.com/documentation/iokit/1514274-ioconnectcallstructmethod] [CITED: https://developer.apple.com/documentation/iokit/1514293-ioregistryentrycreatecfproperty] [CITED: https://developer.apple.com/documentation/iokit/1523839-iopscopypowersourcesinfo]

### Secondary (MEDIUM confidence)

- exelban/stats at `9a8e6e26cc0c779194fd4a2accdf0e37edf30178` — SMC data types, sensor key catalog, filtering behavior, and Apple Silicon sensor caveats. [CITED: https://github.com/exelban/stats/tree/9a8e6e26cc0c779194fd4a2accdf0e37edf30178]
- Local hardware probes on 2026-06-24 — `hw.model=Mac15,9`, `hw.optional.arm64=1`, `ProcessInfo.thermalState=nominal`, `AppleSmartBattery Temperature=3036`, IOAccelerator PerformanceStatistics utilization keys but no direct temperature key. [VERIFIED: local shell]

### Tertiary (LOW confidence)

- None used for implementation recommendations. [VERIFIED: source review]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are local project patterns or Apple public APIs; no external packages. [VERIFIED: codebase grep] [CITED: https://developer.apple.com/documentation/iokit]
- Architecture: HIGH — mirrors existing battery snapshot and collector/UI path. [VERIFIED: `MacStatus/MacStatus/Readers/BatteryReader.swift`] [VERIFIED: `MacStatus/MacStatus/Collectors/MetricCollector.swift`]
- Sensor key trust: MEDIUM — Stats provides current M3 candidate lists, but Mac15,9 local SMC key evidence still needs an implementation probe. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/Modules/Sensors/values.swift]
- Pitfalls: HIGH — directly derived from locked phase constraints, existing code, and v3.0 research. [VERIFIED: `.planning/research/PITFALLS.md`]

**Research date:** 2026-06-24
**Valid until:** 2026-07-24 for architecture and project constraints; re-check Stats key catalog before expanding beyond Mac15,9. [CITED: https://github.com/exelban/stats/blob/9a8e6e26cc0c779194fd4a2accdf0e37edf30178/README.md]
