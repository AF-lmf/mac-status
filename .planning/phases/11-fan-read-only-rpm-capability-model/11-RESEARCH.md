# Phase 11: Fan Read-Only RPM & Capability Model - Research

**Researched:** 2026-06-24
**Domain:** macOS read-only fan RPM monitoring, AppleSMC key decoding, SwiftUI popover capability UI
**Confidence:** HIGH for read-only RPM on Mac15,9; MEDIUM for broader hardware behavior because AppleSMC fan keys are undocumented. [VERIFIED: local read-only probe] [CITED: https://github.com/exelban/stats/blob/master/Modules/Sensors/readers.swift]

<user_constraints>
## User Constraints (from CONTEXT.md)

Source: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md` [VERIFIED: codebase grep]

### Locked Decisions

### Popover Placement and Settings
- **D-01:** Merge fan information into the existing thermal/cooling information flow instead of creating a separate top-level visual area.
- **D-02:** Rename the combined popover section to `温度与风扇` so users understand the section includes both temperature and fan signals.
- **D-03:** Add a separate Settings toggle named `风扇区块`. The existing temperature display and new fan display must be independently controllable.
- **D-04:** Keep the existing 320pt popover width constraint for Phase 11. Small local layout adjustments are allowed only when needed to make fan rows readable; full fixed-width stress work stays in Phase 12.

### Fan Row Content
- **D-05:** Prefer human-readable position labels such as `左风扇` / `右风扇` when the implementation can infer them reliably.
- **D-06:** If fan position cannot be confirmed, fall back to stable numbered labels such as `风扇 1` and `风扇 2`.
- **D-07:** Current RPM is the primary per-fan value. Missing RPM must render as `N/A` rather than causing the row to disappear on supported MacBook Pro hardware.
- **D-08:** Show min/max/target or similar boundary data only when readable. Missing optional fields should not reserve blank subrows.
- **D-09:** Do not add a separate fan-count row or badge. The number of rendered fan rows communicates the count.

### Unavailable and Unsupported States
- **D-10:** If a MacBook Pro fan surface is expected but no fan RPM can be read, keep a stable fan row and show `风扇 N/A` or `风扇不可读取`.
- **D-11:** Fanless and non-MacBook-Pro machines should not surface fan information by default. Avoid distracting unsupported-hardware copy in normal use.
- **D-12:** Degrade each field independently: unreadable RPM becomes `N/A`; unreadable min/max/target fields are omitted.
- **D-13:** Read failures must stay quiet: no modal alert, no warning popup, no crash, and no repeated user-visible error surface.

### Capability Model and Copy
- **D-14:** The internal model must distinguish at least: RPM-readable, boundary-readable, and potentially controllable in a future safe-control phase.
- **D-15:** Phase 11 UI should mainly show RPM and readable bounds. It should not show a constant capability label when the data itself is clear.
- **D-16:** If explanatory copy is needed when bounds are readable but control is not implemented, use `边界可读，控制未启用`.
- **D-17:** `控制可用` may exist only as an internal capability-model state for future planning. Phase 11 UI must not display it as a promise.
- **D-18:** Do not show control buttons, disabled controls, Settings placeholders, or other future-control affordances in Phase 11.

### Hardware Validation
- **D-19:** Treat the current validation hardware as first-class: MacBook Pro with Apple M3 Max, model identifier `Mac15,9`.
- **D-20:** Phase 11 can complete on `Mac15,9` if it records read-only probe evidence and stable `N/A` / `不可读取` behavior for optional or missing fan keys. Do not block completion solely because some optional fields are unreadable.
- **D-21:** Record enough read-only evidence to prove behavior: model identifier, read attempts for fan keys, decoded values when available, build result, and no-write guard evidence where useful.
- **D-22:** Fan key exploration may be broader than Phase 10 temperature probing, but only as read-only SMC diagnostics. Do not add a user-facing raw key browser or any write/enumeration control surface.

### the agent's Discretion
- The planner may choose exact type names and file splits, but should keep the read-only snapshot pattern established by Phase 10 and battery snapshots.
- The planner may choose the precise visual grouping inside `温度与风扇`, as long as temperature rows and fan rows remain independently gated and do not pre-solve Phase 12.

### Deferred Ideas (OUT OF SCOPE)

- Manual fan control, SMC writes, `FS!` writes, target RPM writes, helper/XPC work, opt-in control UI, and restore-auto lifecycle logic are deferred to Phase 13+.
- Popover-wide fixed-width stress hardening, deterministic extreme-value screenshots, and network/RPM/temperature column stabilization remain Phase 12.
- Status-bar temperature or fan segments remain out of scope unless a future display phase explicitly opts in.
- Fanless/non-MacBook-Pro explanatory UI copy is not part of normal Phase 11 UI; record unsupported behavior in probe/debug artifacts instead.
- Raw SMC key browser, complete SMC enumeration UI, fan history charts, alerts, and fan curves remain out of scope.
- Broader hardware model catalogs beyond the current `Mac15,9` validation target are deferred unless implementation discovers low-risk reusable mappings naturally.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FAN-01 | 用户能在 MacBook Pro 弹窗中看到风扇数量和每个风扇当前 RPM | Use `FNum` for fan count and `F{i}Ac` for current RPM; local Mac15,9 read-only probe found `FNum` raw byte `02`, `F0Ac=1454.42`, and `F1Ac=1567.96`. [VERIFIED: local read-only probe] [CITED: https://github.com/exelban/stats/blob/master/Modules/Sensors/readers.swift] |
| FAN-02 | 用户能看到每个风扇的 min/max/target 或控制能力状态；不可读字段显示为稳定的 `N/A` | Probe `F{i}Mn`, `F{i}Mx`, `F{i}Tg`, and optional `F{i}Sf`; local Mac15,9 probe found min/max/target for both fans and `F{i}ID` absent. [VERIFIED: local read-only probe] [CITED: https://github.com/exelban/stats/blob/master/Modules/Sensors/readers.swift] |
| FAN-03 | fanless、非 MacBook Pro 或不支持读取的机型优雅降级，不显示误导性的风扇控制入口 | Gate fan rows by hardware capability and settings; hide fan section by default when `FNum` is absent/zero and never render any control affordance in Phase 11. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`] |
| FAN-04 | 风扇能力模型能区分“可读取 RPM”“可读取边界”“可安全控制”，避免把可读误判为可控 | Model `rpmReadable`, `boundsReadable`, and future-only `controlPotential` separately; Phase 11 sets no UI control state and performs no SMC writes. [VERIFIED: `.planning/REQUIREMENTS.md`] [VERIFIED: codebase grep] |
</phase_requirements>

## Project Constraints (from AGENTS.md)

- All user-facing communication and UI planning notes should be Chinese where applicable. [VERIFIED: `AGENTS.md`]
- The app targets macOS 14+ and uses Swift with SwiftUI + AppKit; menu-bar lifecycle remains AppKit-backed. [VERIFIED: `AGENTS.md`] [VERIFIED: `MacStatus/MacStatus.xcodeproj/project.pbxproj`]
- The app must stay lightweight and avoid high-frequency polling or unnecessary CPU cost. [VERIFIED: `AGENTS.md`]
- External dependencies should remain absent or minimal; Phase 11 does not need package installation. [VERIFIED: `AGENTS.md`] [VERIFIED: codebase grep]
- File-changing work should stay inside a GSD workflow; this research artifact is produced for the GSD phase planner. [VERIFIED: `AGENTS.md`]
- Project-local `.agents/skills` contains generic document, SQL, review, and Git skills; no Swift/macOS project-specific skill rules apply to Phase 11. [VERIFIED: project skill discovery grep]

## Summary

Phase 11 should add a read-only `FanReader` and value-type `FanSnapshot` beside the existing `ThermalReader`, then flow the snapshot through `MetricCollector -> DashboardState -> DashboardView` as popover-only current state. [VERIFIED: `MacStatus/MacStatus/Collectors/MetricCollector.swift`] [VERIFIED: `MacStatus/MacStatus/Readers/ThermalReader.swift`] The planner should not add status-bar fan text, persistence/history fields, helper/XPC code, SMC write selectors, control buttons, disabled future controls, or raw key browsing. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]

The current Mac15,9 hardware strongly supports the read-only path: `AppleSMC` opened successfully, `FNum` was present with raw byte `02`, and both fans exposed readable current/min/max/target RPM through `flt ` keys. [VERIFIED: local read-only probe] One implementation trap is already visible: current `SMCReader.decodeNumeric` handles `ui8` but not `ui8 ` with a trailing space, so `FNum`, `F0Md`, and `F1Md` raw reads succeeded while `readValue` returned `nil`. [VERIFIED: local read-only probe] [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`] The plan should therefore include a tiny read-side codec fix or a fan-specific raw-byte decode for `ui8 ` before relying on `FNum`.

**Primary recommendation:** Use existing zero-dependency IOKit/AppleSMC reads, extend only read-side decoding, add `FanSnapshot` with independent capability flags, render fan rows inside the renamed `温度与风扇` section behind a separate `风扇区块` toggle, and record a Mac15,9 read-only probe plus no-write grep gate before signoff. [VERIFIED: local read-only probe] [CITED: https://developer.apple.com/documentation/iokit/1514274-ioconnectcallstructmethod] [CITED: https://github.com/exelban/stats/blob/master/SMC/smc.swift]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| AppleSMC fan key reads | Native Reader layer | IOKit AppleSMC user client | Existing `SMCReader` owns the 80-byte AppleSMC ABI and read-only IOKit calls; duplicating it in UI or collector code would widen the fragile boundary. [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`] |
| Fan count and per-fan RPM | Native Reader layer | Dashboard state | `FNum` and `F{i}Ac` are hardware telemetry and should be decoded before UI receives value snapshots. [VERIFIED: local read-only probe] |
| Capability model | Native Reader/model layer | SwiftUI rendering | UI must consume booleans/enum states such as RPM-readable and bounds-readable; UI must not infer controllability from RPM presence. [VERIFIED: `.planning/REQUIREMENTS.md`] |
| Snapshot collection | Collector layer | Dashboard state | `MetricCollector` already owns the unified timer and separate current-only thermal snapshot; fan should follow the same non-persistent route. [VERIFIED: `MacStatus/MacStatus/Collectors/MetricCollector.swift`] |
| Fan row display | SwiftUI popover layer | SettingsManager | `DashboardView` owns section rendering, and `SettingsManager` owns live section toggles. [VERIFIED: `MacStatus/MacStatus/UI/Views/DashboardView.swift`] [VERIFIED: `MacStatus/MacStatus/Utils/SettingsManager.swift`] |
| Fan control safety | Out of scope for Phase 11 | Future control manager/helper | Phase 11 can model future control potential internally but must not expose write APIs or control UI. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`] |

## Standard Stack

### Core

| Library/API | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| Swift | 6.3.2 installed locally; project `SWIFT_VERSION = 6.0` | Implement value snapshots, reader, collector updates, and SwiftUI rows | Project language and current local compiler. [VERIFIED: local `swift --version`] [VERIFIED: `MacStatus/MacStatus.xcodeproj/project.pbxproj`] |
| Xcode | 26.5 installed locally | Build and sign the macOS app target | Current local build tool for the Xcode project. [VERIFIED: local `xcodebuild -version`] |
| IOKit `IOServiceOpen` / `IOConnectCallStructMethod` | macOS SDK 26.5, deployment target macOS 14.0 | Open AppleSMC user client and submit read-only struct calls | Existing `SMCReader` already uses these APIs; Apple documents the generic IOKit user-client functions, while AppleSMC key meanings remain undocumented. [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`] [CITED: https://developer.apple.com/documentation/iokit/1514515-ioserviceopen] [CITED: https://developer.apple.com/documentation/iokit/1514274-ioconnectcallstructmethod] |
| Existing `SMCReader` | Project-local | Read fan SMC keys and decode numeric values | It already has open/close, key info, raw bytes, `flt `, `ui16`, `ui32`, and fixed-point decode; Phase 11 needs only read-side additions for `ui8 ` and fan diagnostics. [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`] |
| SwiftUI + `SettingsManager` | Project-local | Render `温度与风扇`, add `风扇区块` toggle | Existing `散热` section and settings toggles provide the exact integration pattern. [VERIFIED: `MacStatus/MacStatus/UI/Views/DashboardView.swift`] [VERIFIED: `MacStatus/MacStatus/UI/Views/SettingsView.swift`] |

### Supporting

| Library/API | Version | Purpose | When to Use |
|-------------|---------|---------|-------------|
| `sysctlbyname("hw.model")` | Darwin | Identify `Mac15,9` for expected fan surface and probe evidence | Use for diagnostics and capability policy, not as the sole fan-availability gate. [VERIFIED: local `sysctl -n hw.model`] |
| Stats source fan reader | master branch inspected 2026-06-24 | Cross-check fan key names and open-source ecosystem behavior | Use as implementation evidence for `FNum`, `F{i}Ac`, `F{i}Mn`, `F{i}Mx`, `F{i}Tg`, `F{i}ID`, mode keys, and `fpe2`/`flt ` handling. [CITED: https://github.com/exelban/stats/blob/master/Modules/Sensors/readers.swift] [CITED: https://github.com/exelban/stats/blob/master/SMC/smc.swift] |
| SMCKit source | master branch inspected 2026-06-24 | Historical Intel-era fan key and `fpe2` decode reference | Use only as corroboration, not as a dependency. [CITED: https://github.com/beltex/SMCKit/blob/master/SMCKit/SMC.swift] |
| Asahi SMC docs | web docs inspected 2026-06-24 | Apple Silicon SMC domain background | Use only as supporting context that SMC covers fan status/control classes; Phase 11 stays read-only. [CITED: https://asahilinux.org/docs/hw/soc/smc/] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Direct AppleSMC reads through `SMCReader` | `powermetrics`, `ioreg`, `pmset`, or shelling out to `smc` tools | Shellouts add process cost, parsing fragility, and external dependency risk; Phase 11 can use existing in-process IOKit. [VERIFIED: `AGENTS.md`] [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`] |
| Project-local read-only model | Third-party fan libraries | The project already has the AppleSMC read boundary; adding a package is unnecessary and increases maintenance risk. [VERIFIED: codebase grep] |
| Hide unsupported machines silently | Show unsupported hardware copy in normal UI | User decision says fanless/non-MacBook-Pro machines should not surface fan info by default. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`] |
| Use MacBook Pro model name alone | Probe `FNum` and actual fan keys | Model name is insufficient; capability must come from SMC key presence and sane decoded values. [VERIFIED: `.planning/research/PITFALLS.md`] |

**Installation:**

```bash
# No external packages for Phase 11.
```

**Version verification:** no npm/PyPI/crates package versions are needed because Phase 11 should install no external packages. [VERIFIED: codebase grep]

## Package Legitimacy Audit

Phase 11 installs no external packages. [VERIFIED: `AGENTS.md`] [VERIFIED: codebase grep]

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| none | — | — | — | — | not run | Approved: no package install |

**Packages removed due to slopcheck [SLOP] verdict:** none.
**Packages flagged as suspicious [SUS]:** none.

## Architecture Patterns

### System Architecture Diagram

```text
MetricCollector.start()
  -> fanReader.setup()
       -> SMCReader.open() read-only AppleSMC connection
       -> optional first fan capability probe

MetricCollector.tick() @MainActor
  -> FanReader.readValue()
       -> read FNum raw/numeric fan count
       -> for each fan index:
            read F{i}Ac current RPM
            read optional F{i}Mn / F{i}Mx / F{i}Tg / F{i}Sf
            read optional F{i}ID / F{i}Md / F{i}md / FS! / Ftst for capability metadata only
            validate values and degrade missing fields independently
       -> FanSnapshot(capturedAt, support state, [FanReading])
  -> cache lastFanSnapshot outside MetricSample/history/status bar
  -> DashboardState.updateFans(snapshot)
  -> DashboardView
       -> section title renamed 温度与风扇
       -> temperature rows gated by showThermalSection
       -> fan rows gated by showFanSection and fan support/capability
       -> no control buttons, no disabled future controls
```

The data flow is read-only from AppleSMC to Swift value snapshots to SwiftUI rows. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]

### Recommended Project Structure

```text
MacStatus/MacStatus/
├── Readers/
│   ├── SMCReader.swift        # EDIT: read-side codec/diagnostic support only
│   ├── ThermalReader.swift    # KEEP: Phase 10 thermal snapshot pattern
│   └── FanReader.swift        # ADD: FanSnapshot + FanReading + capability model
├── Collectors/
│   └── MetricCollector.swift  # EDIT: setup/read/cache/update fan snapshot
├── UI/Views/
│   ├── DashboardView.swift    # EDIT: 温度与风扇 section + FanSectionView + state
│   └── SettingsView.swift     # EDIT: 风扇区块 toggle
└── Utils/
    └── SettingsManager.swift  # EDIT: showFanSection UserDefaults key/default
```

New Swift files must be registered in the Xcode project, as `ThermalReader.swift` is already present in `project.pbxproj`. [VERIFIED: `MacStatus/MacStatus.xcodeproj/project.pbxproj`]

### Pattern 1: Read-Only Fan Snapshot

**What:** Return a stable current fan snapshot even when optional fields are missing; only fan rows backed by expected support should stay visible with `N/A`. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]

**When to use:** Use on every collector tick after `FanReader.setup()` succeeds or gracefully degrades. [VERIFIED: `MacStatus/MacStatus/Collectors/MetricCollector.swift`]

**Example:**

```swift
// Source: project ThermalSnapshot pattern + local Fan SMC probe.
enum FanSupportState: Sendable, Equatable {
    case supported
    case unsupported
    case unreadable
}

struct FanReading: Sendable, Equatable, Identifiable {
    let id: Int
    let displayName: String
    let currentRPM: Double?
    let minRPM: Double?
    let maxRPM: Double?
    let targetRPM: Double?
    let capabilities: FanCapabilities
}

struct FanCapabilities: Sendable, Equatable {
    let rpmReadable: Bool
    let boundsReadable: Bool
    let targetReadable: Bool
    let controlPotential: Bool   // internal only; Phase 11 UI must not promise control
}
```

### Pattern 2: Decode Capability Separately From Values

**What:** Track whether RPM, bounds, and target are readable independently instead of deriving one global fan state. [VERIFIED: `.planning/REQUIREMENTS.md`]

**When to use:** Use when `F0Ac` is readable but `F0Mn/F0Mx/F0Tg` or mode keys are missing; this must render RPM without implying control. [VERIFIED: local read-only probe]

**Example:**

```swift
// Source: local Mac15,9 probe and Stats fan key usage.
let current = smc.readValue(key: "F\(index)Ac")
let min = smc.readValue(key: "F\(index)Mn")
let max = smc.readValue(key: "F\(index)Mx")
let target = smc.readValue(key: "F\(index)Tg")

let boundsReadable = min != nil && max != nil
let capability = FanCapabilities(
    rpmReadable: current != nil,
    boundsReadable: boundsReadable,
    targetReadable: target != nil,
    controlPotential: false
)
```

### Pattern 3: Stable UI Rows With Optional Detail

**What:** Render one row per fan; current RPM is primary, optional bounds render only when readable. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]

**When to use:** Use inside the renamed `温度与风扇` section and gate with `showFanSection`. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]

**Example:**

```swift
// Source: existing ThermalSectionView row style.
FanRowView(fan: fan) {
    Text(fan.displayName)
    Spacer()
    Text(rpmText(fan.currentRPM)) // "1454 RPM" or "N/A"
        .font(.system(.caption, design: .monospaced))
        .frame(minWidth: 72, alignment: .trailing)
}

if fan.capabilities.boundsReadable {
    Text("范围 \(rpmText(fan.minRPM)) - \(rpmText(fan.maxRPM))")
}
```

### Anti-Patterns to Avoid

- **Adding `cmdWriteBytes` or generic SMC write APIs:** Phase 11 is read-only and must not introduce write selectors or public write helpers. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`] [CITED: https://github.com/exelban/stats/blob/master/SMC/smc.swift]
- **Showing disabled fan controls:** User explicitly rejected control buttons, disabled controls, Settings placeholders, and future-control affordances. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]
- **Treating readable RPM as control support:** `F{i}Ac` telemetry does not prove `F{i}Tg`, mode keys, `FS!`, or write/readback behavior. [VERIFIED: `.planning/REQUIREMENTS.md`] [CITED: https://github.com/exelban/stats/blob/master/SMC/smc.swift]
- **Using model name as the only support gate:** Use `FNum`/key reads as the primary capability signal; model identifier is validation context and expected-surface context. [VERIFIED: `.planning/research/PITFALLS.md`]
- **Reserving blank optional subrows:** Missing min/max/target fields should be omitted; only current RPM degrades to `N/A` on expected fan hardware. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| AppleSMC ABI access | Duplicate `SMCParamStruct` or `IOConnectCallStructMethod` code in `FanReader` | Existing `SMCReader` read boundary | The 80-byte struct layout is already guarded and fragile. [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`] |
| Fan support detection | Marketing-model-only MacBook Pro check | `FNum` + per-key probe + model context | Fanless/read-failed systems must degrade quietly and not show misleading rows. [VERIFIED: `.planning/REQUIREMENTS.md`] |
| Capability inference | One `isControllable` flag inferred from RPM | Separate `rpmReadable`, `boundsReadable`, future-only `controlPotential` | FAN-04 requires not confusing readable telemetry with safe control. [VERIFIED: `.planning/REQUIREMENTS.md`] |
| Fan control UI | Disabled sliders/buttons/placeholders | No Phase 11 control UI | Control belongs to Phase 13+ and needs write/readback/lifecycle safety. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`] |
| Raw diagnostics UX | User-facing SMC key browser | Private probe/debug artifact | Raw key browsing is out of scope and can mislead users with undocumented labels. [VERIFIED: `.planning/REQUIREMENTS.md`] |
| External fan package | Add SMCKit or another library | Project-local `SMCReader` read extensions | Existing code already has the read path; no package is needed. [VERIFIED: codebase grep] |

**Key insight:** Phase 11 is a capability modeling phase, not a fan-control phase; read telemetry is useful only if the model preserves uncertainty and keeps write/control affordances absent. [VERIFIED: `.planning/REQUIREMENTS.md`]

## Common Pitfalls

### Pitfall 1: `ui8 ` Data Type Is Not Decoded

**What goes wrong:** `FNum`, `F0Md`, and `F1Md` raw reads succeed but `readValue(key:)` returns `nil`, so the implementation may think no fans exist. [VERIFIED: local read-only probe]
**Why it happens:** Current `SMCReader` checks `"ui8"` while local AppleSMC reports `"ui8 "` with a trailing space. [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`]
**How to avoid:** Normalize data type strings or accept both `"ui8"` and `"ui8 "` in read-side decode. [VERIFIED: local read-only probe]
**Warning signs:** Probe output shows `type=ui8  size=1 value=nil bytes=02` for `FNum`. [VERIFIED: local read-only probe]

### Pitfall 2: Showing 0 RPM for Unreadable Values

**What goes wrong:** Missing `F{i}Ac` becomes `0 RPM`, which suggests a stopped fan rather than unreadable telemetry. [VERIFIED: `.planning/research/PITFALLS.md`]
**Why it happens:** Some open-source examples default missing values to `0` for display convenience. [CITED: https://github.com/exelban/stats/blob/master/Modules/Sensors/readers.swift]
**How to avoid:** Keep `currentRPM: Double?` and render nil as `N/A`; only show numeric zero if the key decoded successfully as zero. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]
**Warning signs:** `FanReading.currentRPM` is non-optional or fallback uses `?? 0`. [VERIFIED: codebase grep pattern]

### Pitfall 3: Position Labels Without Evidence

**What goes wrong:** UI labels `左风扇` and `右风扇` but the hardware did not provide `F{i}ID`, so index-to-position may be wrong. [VERIFIED: local read-only probe]
**Why it happens:** Stats falls back to left/right names for two fans when ID is missing; that is an ecosystem convention, not hardware proof. [CITED: https://github.com/exelban/stats/blob/master/Modules/Sensors/readers.swift]
**How to avoid:** Use `F{i}ID` if readable; otherwise use `风扇 1` / `风扇 2` unless planner records reliable Mac15,9 index mapping evidence. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]
**Warning signs:** Code maps `F0` to `左风扇` without a probe note or source. [VERIFIED: local read-only probe]

### Pitfall 4: Accidentally Importing Fan Control Scope

**What goes wrong:** Planner adds `FS!`, `F{i}Tg` writes, helper/XPC, control sliders, restore-auto lifecycle, or mode toggles. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]
**Why it happens:** Open-source fan implementations put read and write paths close together. [CITED: https://github.com/exelban/stats/blob/master/SMC/smc.swift]
**How to avoid:** Phase 11 may read mode/target keys for diagnostics and capability modeling but must grep-gate out write selectors and user-visible controls. [VERIFIED: `.planning/REQUIREMENTS.md`]
**Warning signs:** New code contains `cmdWriteBytes`, `writeBytes`, `writeRaw`, `FanControlManager`, `helper`, `XPC`, or UI controls mentioning manual fan behavior. [VERIFIED: codebase grep]

### Pitfall 5: Layout Drift From Optional Bounds

**What goes wrong:** Popover height jumps every tick as optional min/max/target rows appear/disappear on transient read failures. [VERIFIED: `.planning/research/PITFALLS.md`]
**Why it happens:** Capability and live values are not separated. [VERIFIED: `.planning/research/PITFALLS.md`]
**How to avoid:** Let support/capability change only after setup/wake/probe decisions; render current RPM rows stably and optional details only when capability says readable. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]
**Warning signs:** Rows are inserted/removed based directly on a single tick's nil values. [VERIFIED: codebase grep pattern]

## Code Examples

Verified patterns from current code and sources:

### Fan Reader Skeleton

```swift
// Source: MacStatus ThermalReader pattern + Stats fan key usage.
final class FanReader {
    private let smcReader = SMCReader()

    func setup() {
        smcReader.open()
    }

    func readValue() -> FanSnapshot {
        let count = fanCount()
        guard count > 0 else {
            return FanSnapshot(state: .unsupported, fans: [], capturedAt: Date())
        }

        let fans = (0..<count).map { index in
            readFan(index)
        }
        return FanSnapshot(state: .supported, fans: fans, capturedAt: Date())
    }
}
```

### Read-Side Data Type Normalization

```swift
// Source: local probe showed `ui8 `, while existing code checks `ui8`.
private static func normalizedSMCType(_ type: String) -> String {
    type.trimmingCharacters(in: .whitespaces)
}

if normalizedSMCType(value.dataType) == "ui8", raw.count >= 1 {
    return Double(raw[0])
}
```

### Fan RPM Validation

```swift
// Source: local Mac15,9 probe found flt current/min/max/target values.
private func plausibleRPM(_ rpm: Double?, min: Double?, max: Double?) -> Double? {
    guard let rpm, rpm >= 0 else { return nil }
    if let max, max > 0, rpm > max + 500 { return nil }
    if let min, let max, min > max { return nil }
    return rpm
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Intel-era fan mode via `FS!` bitmask and `F{i}Md` | Apple Silicon implementations also probe lower-case `F{i}md`, `Ftst`, and retry/write behavior | Observed in current Stats source inspected 2026-06-24 | Treat control as future, risky, and separate from read-only RPM. [CITED: https://github.com/exelban/stats/blob/master/SMC/smc.swift] |
| Read fan availability from product family | Read `FNum` and each fan key at runtime | Reinforced by project v3 research and local Mac15,9 probe | Capability comes from hardware probe, not marketing name. [VERIFIED: `.planning/research/PITFALLS.md`] |
| Show raw SMC values directly | Curated snapshot with optional fields and stable `N/A` | Established by Phase 10 thermal implementation | UI stays honest when undocumented keys are absent or ambiguous. [VERIFIED: `MacStatus/MacStatus/Readers/ThermalReader.swift`] |

**Deprecated/outdated:**
- Generic fan control in the same phase as read-only fan RPM is out of scope and should be treated as a future hardware-safety phase. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]
- Assuming `ui8` has no trailing space is invalid on the local Mac15,9 fan keys; normalize SMC data types before decode. [VERIFIED: local read-only probe]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | If planner labels `F0`/`F1` as left/right without `F{i}ID`, that index-to-position mapping is only an ecosystem convention, not verified for this Mac15,9 session. [ASSUMED] | Common Pitfalls | User may see swapped fan labels; prefer numbered labels unless verified. |

## Open Questions

1. **Can `F0`/`F1` be confidently labeled left/right on Mac15,9?**
   - What we know: local probe found `F0ID` and `F1ID` absent, and Stats uses left/right fallback for two fans. [VERIFIED: local read-only probe] [CITED: https://github.com/exelban/stats/blob/master/Modules/Sensors/readers.swift]
   - What's unclear: physical index-to-position mapping was not verified in this session. [ASSUMED]
   - Recommendation: default to `风扇 1` / `风扇 2` unless implementation records a reliable mapping source. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]

2. **Should mode keys be read in Phase 11 UI?**
   - What we know: local probe reads `F0Md/F1Md` raw `ui8 ` zero, while `FS!` is absent and `Ftst` is present as `ui8 ` zero. [VERIFIED: local read-only probe]
   - What's unclear: displaying mode/control state risks implying control support. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]
   - Recommendation: record mode/`Ftst` in probe evidence and internal capability only; do not show constant capability copy unless needed. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| macOS hardware `Mac15,9` | Hardware validation | yes | macOS 26.5.1 build 25F80, arm64 | None needed for primary validation target. [VERIFIED: local `sysctl`/`sw_vers`] |
| Xcode | Build gate | yes | 26.5 | None. [VERIFIED: local `xcodebuild -version`] |
| Swift compiler | Local probes and build | yes | Swift 6.3.2 | None. [VERIFIED: local `swift --version`] |
| IOKit.framework | SMC reads | yes | SDK macOS 26.5, linked in project | None. [VERIFIED: `MacStatus/MacStatus.xcodeproj/project.pbxproj`] |
| Context7 CLI | Documentation lookup | no | — | Official Apple docs and source inspection were used. [VERIFIED: local `command -v ctx7`] |
| SwiftLint | Optional style lint | no | — | Use `xcodebuild` and source grep gates. [VERIFIED: local `command -v swiftlint`] |
| XCTest target | Automated unit tests | no | — | Use build, read-only probe, and grep gates unless planner adds tests. [VERIFIED: local test discovery] |

**Missing dependencies with no fallback:**
- None for Phase 11 planning and implementation. [VERIFIED: environment audit]

**Missing dependencies with fallback:**
- Context7 CLI is missing; official docs and direct source inspection provide enough research for this phase. [VERIFIED: local `command -v ctx7`]
- SwiftLint is missing; build and grep gates remain available. [VERIFIED: local `command -v swiftlint`]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | Local menu-bar app has no authentication surface in Phase 11. [VERIFIED: `.planning/REQUIREMENTS.md`] |
| V3 Session Management | no | No sessions or remote users are introduced. [VERIFIED: `.planning/REQUIREMENTS.md`] |
| V4 Access Control | yes | Keep AppleSMC access inside reader layer; SwiftUI must not access raw SMC keys directly. [VERIFIED: `MacStatus/MacStatus/Readers/SMCReader.swift`] |
| V5 Input Validation | yes | Validate decoded fan count, RPM, min/max, and target values; reject malformed/implausible data to nil. [VERIFIED: local read-only probe] |
| V6 Cryptography | no | No cryptographic storage or network protocol is introduced. [VERIFIED: `.planning/REQUIREMENTS.md`] |

### Known Threat Patterns for Swift/macOS AppleSMC Read Path

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Misleading fan capability from partial reads | Tampering / Information Integrity | Separate telemetry readability from future control potential and avoid control UI. [VERIFIED: `.planning/REQUIREMENTS.md`] |
| Hardware unavailable or malformed SMC response | Denial of Service | Probe-and-nil, optional fields, stable `N/A`, no modal alert. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`] |
| Accidental SMC writes | Elevation of Privilege / Tampering | No `cmdWriteBytes`, no write APIs, no helper/XPC, grep gate before signoff. [VERIFIED: codebase grep] |
| UI making unsupported hardware look broken | Information Integrity | Hide fan section by default on fanless/non-MacBook-Pro/unsupported reads. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`] |

## Validation Architecture

Skipped because `.planning/config.json` has `workflow.nyquist_validation` explicitly set to `false`. [VERIFIED: `.planning/config.json`]

Recommended manual/command gates for planner:

| Gate | Command / Evidence | Purpose |
|------|--------------------|---------|
| Build | `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` | Confirms new `FanReader.swift` is in target and app builds. [VERIFIED: existing project build settings] |
| Fan probe | Compile a temporary Swift harness using `SMCReader.swift` and read `FNum`, `F{i}Ac/Mn/Mx/Tg/Sf/ID/Md/md`, `FS! `, `Ftst` | Records Mac15,9 read-only evidence. [VERIFIED: local read-only probe] |
| No-write guard | `rg "cmdWriteBytes|writeBytes|writeValue|writeRaw|FanControl|helper|XPC|FS!.*write|F[0-9]Tg.*write" MacStatus/MacStatus` | Ensures Phase 11 remains read-only. [VERIFIED: codebase grep] |
| No status/history surface | `rg "fan|Fan|RPM|风扇" MacStatus/MacStatus/Storage MacStatus/MacStatus/UI/StatusBarManager.swift MacStatus/MacStatus/Utils/Metric.swift` | Ensures fan stays popover-only. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`] |
| Settings/UI gate | Verify `风扇区块`, `showFanSection`, `温度与风扇`, and independent temperature/fan gating in source | Satisfies D-01..D-04. [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`] |

## Local Read-Only Probe Evidence

Captured on 2026-06-24 with a temporary Swift harness compiling `MacStatus/MacStatus/Readers/SMCReader.swift`; no write selector was called. [VERIFIED: local read-only probe]

```text
hw.model=Mac15,9
opened=true
FNum type=ui8  size=1 value=nil bytes=02
FS!  absent
Ftst type=ui8  size=1 value=nil bytes=00
F0Ac type=flt  value=1454.42
F0Mn type=flt  value=1350.00
F0Mx type=flt  value=5349.00
F0Tg type=flt  value=1446.00
F0Sf type=ui16 value=0.00
F0Md type=ui8  value=nil bytes=00
F0ID absent
F1Ac type=flt  value=1567.96
F1Mn type=flt  value=1458.00
F1Mx type=flt  value=5777.00
F1Tg type=flt  value=1561.00
F1Sf type=ui16 value=0.00
F1Md type=ui8  value=nil bytes=00
F1ID absent
```

Planner implication: implement `ui8 ` decode or raw-byte fan count decode before `FNum` is consumed, and use numbered fan labels unless position evidence is added. [VERIFIED: local read-only probe]

## Sources

### Primary (HIGH confidence)
- `MacStatus/MacStatus/Readers/SMCReader.swift` — existing read-only AppleSMC boundary, data type decode, 80-byte ABI guard. [VERIFIED: codebase grep]
- `MacStatus/MacStatus/Readers/ThermalReader.swift` — Phase 10 snapshot/degradation pattern. [VERIFIED: codebase grep]
- `MacStatus/MacStatus/Collectors/MetricCollector.swift` — current non-persistent thermal snapshot flow. [VERIFIED: codebase grep]
- `MacStatus/MacStatus/UI/Views/DashboardView.swift` — existing section layout and dashboard state. [VERIFIED: codebase grep]
- `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md` — locked user decisions and phase boundaries. [VERIFIED: codebase grep]
- Local Mac15,9 read-only fan probe — exact key/type/value behavior for validation hardware. [VERIFIED: local read-only probe]
- Apple Developer Documentation: `IOServiceOpen`, `IOConnectCallStructMethod`, `ProcessInfo.ThermalState`. [CITED: https://developer.apple.com/documentation/iokit/1514515-ioserviceopen] [CITED: https://developer.apple.com/documentation/iokit/1514274-ioconnectcallstructmethod] [CITED: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum]

### Secondary (MEDIUM confidence)
- exelban/stats `Modules/Sensors/readers.swift` — fan loading via `FNum` and `F{i}` keys. [CITED: https://github.com/exelban/stats/blob/master/Modules/Sensors/readers.swift]
- exelban/stats `SMC/smc.swift` — SMC data types, fan mode keys, write complexity, and SMC-level write rejection checks. [CITED: https://github.com/exelban/stats/blob/master/SMC/smc.swift]
- SMCKit `SMC.swift` — historical `FNum`, `F{i}Ac/Mn/Mx/ID`, and `fpe2` handling. [CITED: https://github.com/beltex/SMCKit/blob/master/SMCKit/SMC.swift]
- Asahi Linux SMC documentation — Apple Silicon SMC background and fan-status/control domain context. [CITED: https://asahilinux.org/docs/hw/soc/smc/]

### Tertiary (LOW confidence)
- None used as an implementation source. [VERIFIED: source audit]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — project and local toolchain are verified; no external packages are needed. [VERIFIED: local environment audit]
- Architecture: HIGH — Phase 10 already implemented the same snapshot path and Phase 11 boundaries are locked. [VERIFIED: `MacStatus/MacStatus/Collectors/MetricCollector.swift`] [VERIFIED: `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md`]
- Fan key behavior on Mac15,9: HIGH — local read-only probe produced fan count, RPM, min/max, target, and mode raw evidence. [VERIFIED: local read-only probe]
- Broader model behavior: MEDIUM — fan SMC keys are undocumented and verified mainly through open-source implementations and project research. [CITED: https://github.com/exelban/stats/blob/master/Modules/Sensors/readers.swift] [CITED: https://github.com/beltex/SMCKit/blob/master/SMCKit/SMC.swift]
- Pitfalls: HIGH for scope/control risks and `ui8 ` decode; MEDIUM for left/right position mapping. [VERIFIED: local read-only probe] [ASSUMED]

**Research date:** 2026-06-24
**Valid until:** 2026-07-24 for read-only Mac15,9 planning; re-probe before broader hardware claims. [ASSUMED]
