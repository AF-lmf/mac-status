# MacStatus v3.0 Research Summary

**Project:** MacStatus
**Milestone:** v3.0 风扇与热状态
**Researched:** 2026-06-23
**Confidence:** MEDIUM-HIGH

## Executive Summary

MacStatus v3.0 should remain a lightweight native macOS menu-bar monitor: Swift 6, AppKit/SwiftUI, IOKit/Mach/SystemConfiguration, and zero/minimal dependencies. The research consensus is clear: fan RPM and key temperature monitoring fit naturally into the existing read-only `Reader -> MetricCollector -> DashboardState/UI` path, while fan control must be isolated as a separate, safety-critical capability.

The recommended approach is read-only first. Extend the existing AppleSMC path into a typed SMC boundary, add curated thermal and fan snapshots, and render a stable `散热` / `温度与风扇` popover section with graceful `N/A` behavior. Only after capability detection, bounds, readback verification, lifecycle restore, and real MacBook Pro UAT are in place should any fan write UI ship.

The main risk is not showing temperatures or RPM; it is writing fan mode/target values incorrectly or leaving the machine in manual control. Mitigation should be structural: no generic public SMC writer, no UI-owned writes, no persisted manual startup state, no below-min targets, verified restore-to-auto on quit/sleep/failure, and disabled controls whenever hardware capability or write verification is inconclusive.

## Stack Additions

- Keep the current native stack: Swift 6, AppKit `NSStatusBar`, SwiftUI settings/popover UI, IOKit/Mach APIs, and `UserDefaults`.
- Extend existing `SMCReader`/SMC access into a typed boundary that can decode `ui8`, `ui16`, `ui32`, `flt `, `fpe2`, `sp78`/fixed-point formats, and string/byte keys such as fan IDs.
- Add read-only SMC support for fan and thermal keys: `FNum`, `F{i}Ac`, `F{i}Mn`, `F{i}Mx`, `F{i}Sf`, `F{i}Tg`, `F{i}ID`, `F{i}Md`/`F{i}md`, `FS! `, and curated temperature key families.
- Use `ProcessInfo.thermalState` as a low-cost system thermal state supplement, not as a replacement for exact sensor values.
- Use `SMAppService.daemon(plistName:)` plus XPC only if fan control requires a privileged helper; do not add legacy `SMJobBless` or a helper for read-only monitoring.
- Do not add SMCKit/SystemKit, shell out to `top`/`nettop`/`smc`, add SMART/NVMe dependencies for SSD temperature, or introduce layout libraries.

## Feature Scope

Table stakes for v3.0:

- A single popover cooling section showing primary CPU/SoC temperature, system thermal state, fan RPM, fan availability, and calm unavailable states.
- Curated secondary temperatures for GPU, battery, and SSD only when values are trustworthy; raw sensor explorer and historical charts are out of scope.
- Fan RPM monitoring with fan count and per-fan rows on MacBook Pro, with fanless/unsupported hardware treated as normal.
- Auto/manual visibility if control exists; users must always know whether MacStatus has changed fan behavior.
- One-click `恢复自动` whenever manual mode is active.
- Stable popover layout under changing network, temperature, fan RPM, process, and control-state values.
- Settings toggles for thermal/fan sections, and a separate explicit opt-in if fan control UI is exposed.

Recommended deferrals:

- Full automatic fan curves.
- Quiet/silent modes that reduce cooling below Apple defaults.
- Alerts/notification rules.
- Long-term thermal history and persistent charts.
- Raw SMC sensor browser.
- SSD temperature unless a project-local public disk sensor path already exists.
- Apple Silicon protected fan unlock/write paths unless validated on target hardware and explicitly accepted as a product risk.

## Architecture Direction

Read-only thermal and fan data should mirror the existing battery pattern: immutable `Sendable` snapshots, synchronous cheap reads on the collector tick, optional fields, and UI degradation through `N/A` or hidden secondary rows. Do not store thermal/fan samples in `MetricSample` or SQLite for v3.0.

Recommended components:

1. `SMCClient` or refactored `SMCReader` — owns AppleSMC ABI, open/close, key info, raw reads, typed decoding, and tightly restricted raw write primitives if control phase needs them.
2. `SensorCatalog` — static curated key lists by sensor group/model family, separated from reader logic and UI labels.
3. `ThermalReader` — produces `ThermalSnapshot` with primary CPU/SoC, hottest/average, optional GPU/battery/SSD, source metadata, and timestamp.
4. `FanReader` — produces `FanSnapshot` with fan count, current RPM, min/max/safe/target RPM, display names, and mode hints.
5. `FanControlManager` / optional helper client — owns manual-control state, bounds, writes, readback verification, restore-auto, sleep/wake/quit hooks, and failure rollback.
6. `ThermalSectionView` and `FanSectionView` — fixed-width, monospaced, capability-stable rows inside the existing dashboard.

UI and SMC boundaries should stay strict: SwiftUI views render snapshots and call high-level actions only; they never read/write raw SMC keys. Capability should be distinct from live values so transient nil reads do not insert/remove rows every tick.

## Safety Guardrails

- Read-only first: initial phases must not introduce SMC write methods or fan control UI.
- Narrow writer: only the fan-control component may write, and only allowlisted fan keys may be writable.
- Capability-gated controls: controls appear only after fan count, current RPM, min/max, target key, mode key, and restore-auto path are verified.
- Bounded target: clamp every manual RPM to live hardware min/max; never expose `0`, below-min, or "silent" control.
- Actual-state source of truth: UI manual/auto state comes from SMC readback, not `UserDefaults`.
- Verified writes: IOKit success alone is insufficient; validate SMC-level result, mode/target readback, and actual RPM response over a short window.
- Restore automatic: provide one-click restore and attempt restore on quit, before sleep, after failed write, when disabling control, and during wake reconciliation.
- Fail closed: if write, unlock, retry, or verification fails, restore automatic and mark control unavailable.
- Main actor protection: no full SMC enumeration or multi-second fan-control retry loops on `@MainActor`.
- Hardware UAT is mandatory before marking fan control complete; simulator or build success is not enough.

## Recommended Roadmap Shape

1. **Thermal Read-Only Foundation** — Extend SMC decoding and sensor catalog, add `ThermalReader`, show CPU/SoC primary temperature and `ProcessInfo.thermalState`, with strict plausibility filtering and `N/A` states. This unlocks visible value without hardware writes.

2. **Fan Read-Only and Capability Model** — Add `FanReader`, detect `FNum`, RPM, min/max, names, mode hints, unsupported/fanless states, and control eligibility. Still no writes. This prevents "MacBook Pro == controllable fans" assumptions.

3. **Popover Layout Stability** — Harden dashboard rows before adding controls: fixed width, monospaced value columns, reserved space for `9999 RPM`, `100°C`, `N/A`, large network values, long process names, and stable section capability. This is lower risk and can be verified with deterministic preview/test snapshots.

4. **Safe Fan Control Design and Implementation** — Add opt-in bounded manual control only after phases 1-2 prove capability. Implement narrow write APIs, target clamping, mode/target readback, actual RPM verification, failure rollback, and possibly an optional privileged helper if required by distribution/hardware behavior.

5. **Lifecycle Recovery and Hardware UAT** — Add quit/sleep/wake restore hooks, SMC reopen/reprobe after wake, stale manual-state cleanup, unsupported-machine tests, and real MacBook Pro control tests. Fan control should not be considered shipped before this phase is green.

Research flags:

- Phase 1 needs targeted sensor-key validation for the user's target MacBook Pro generation, especially CPU/SoC naming on Apple Silicon.
- Phase 4 needs deeper research if Apple Silicon fan writes require `Ftst`, `thermalmonitord` coordination, privileged helper signing, or Developer ID distribution.
- Phase 5 needs real-device validation; automated tests can cover layout and codec behavior but not safe hardware behavior.
- Phase 3 uses standard SwiftUI/AppKit layout patterns and likely does not need separate external research.

## Open Questions

- Which exact MacBook Pro models are v3.0 validation targets: Intel/T2, M1/M2, M3/M4/M5, or only the user's current machine?
- Is a meaningful SoC temperature available through plain SMC on the target hardware, or should v3.0 label CPU hottest/average as the primary thermal signal?
- Should fan control be required in v3.0, or can v3.0 ship read-only fan/thermal plus a fully researched control plan?
- If control ships, is Developer ID signing available for a privileged helper and LaunchDaemon approval flow?
- Is the project willing to use undocumented Apple Silicon `Ftst`/protected-mode behavior, or should such hardware remain read-only until a safer public path exists?
- Should SSD temperature be omitted unless an existing public disk sensor implementation is added later?
- What is the acceptable fixed popover width after adding thermal/fan rows: keep 320pt, or intentionally move to 360-380pt with bounded scrolling?

## Sources

Primary project sources:

- `.planning/PROJECT.md` — v3.0 scope, constraints, active requirements, and safety posture.
- `.planning/research/STACK.md` — stack/API additions, SMC keys, helper/security notes, and source confidence.
- `.planning/research/FEATURES.md` — table-stakes UX, differentiators, anti-features, and UAT acceptance notes.
- `.planning/research/ARCHITECTURE.md` — existing code patterns, proposed components, data flow, and lifecycle integration.
- `.planning/research/PITFALLS.md` — high-risk failure modes, guardrails, verification traps, and phase warnings.

External evidence aggregated by research:

- Apple Developer documentation for IOKit, `IOServiceOpen`, `IOConnectCallStructMethod`, `SMAppService`, Authorization Services, `ProcessInfo.thermalState`, `NSPopover`, and `NSHostingController` sizing APIs.
- exelban/stats source and issues — current ecosystem reference for SMC data types, fan keys, temperature key catalogs, helper/XPC control architecture, Apple Silicon write caveats, and lifecycle failures.
- hholtmann/smcFanControl — historical fan-control safety principle: never set below Apple's defaults.
- Linux `applesmc` driver and Asahi SMC notes — corroborating SMC fan key names and read/write concepts.
- Macs Fan Control and SMCKit documentation — UX and safety patterns, with lower confidence for direct implementation details.

---
*Research completed: 2026-06-23*
*Ready for requirements and roadmap: yes*
