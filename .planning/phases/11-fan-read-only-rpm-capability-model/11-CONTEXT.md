# Phase 11: Fan Read-Only RPM & Capability Model - Context

**Gathered:** 2026-06-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 11 delivers read-only fan monitoring and a conservative fan capability model in the MacStatus popover. It must let MacBook Pro users see current fan RPM, readable fan bounds or target fields when available, and a clear internal distinction between "RPM can be read", "hardware bounds can be read", and "control may be safe in a later phase".

This phase extends the Phase 10 thermal surface into a combined `温度与风扇` information flow. It must not introduce SMC writes, manual fan control, disabled/future control UI, helper/XPC components, fan status-bar metrics, raw SMC sensor browsers, or persistent fan history. Fan control starts no earlier than Phase 13, and popover-wide layout hardening remains Phase 12.

</domain>

<decisions>
## Implementation Decisions

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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Scope
- `.planning/PROJECT.md` — v3.0 scope, lightweight menu-bar monitor identity, safety posture, and platform constraints.
- `.planning/REQUIREMENTS.md` — FAN-01 through FAN-04 plus Future/Out-of-Scope items that prevent fan-control scope creep.
- `.planning/ROADMAP.md` — Phase 11 goal, success criteria, dependencies, and boundaries between Phases 10-14.

### Prior Phase 10
- `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md` — established read-only thermal section decisions, validation target, degradation style, and Settings toggle pattern.
- `.planning/phases/10-thermal-read-only-monitoring/10-VERIFICATION.md` — current implementation verification and hardware probe summary for the thermal surface.
- `.planning/phases/10-thermal-read-only-monitoring/10-SECURITY.md` — no-write security gate and threat verification from the preceding thermal phase.
- `.planning/phases/10-thermal-read-only-monitoring/10-HARDWARE-PROBE.md` — local `Mac15,9` read-only SMC probing evidence and format expectations.

### v3.0 Research
- `.planning/research/STACK.md` — zero-dependency macOS monitoring stack and fan/SMC read path constraints.
- `.planning/research/FEATURES.md` — user-visible cooling and fan UX, unavailable states, and fan-control anti-features.
- `.planning/research/ARCHITECTURE.md` — proposed `FanReader`, read-only snapshot integration, and separation from future `FanControlManager`.
- `.planning/research/PITFALLS.md` — SMC trust, degradation, and safety pitfalls for fan/thermal work.

### Existing Code
- `MacStatus/MacStatus/Readers/SMCReader.swift` — read-only AppleSMC client and numeric decode boundary.
- `MacStatus/MacStatus/Readers/ThermalReader.swift` — Phase 10 thermal snapshot pattern to extend.
- `MacStatus/MacStatus/Readers/BatteryReader.swift` — optional hardware snapshot and nil-degradation precedent.
- `MacStatus/MacStatus/Collectors/MetricCollector.swift` — single collector tick, last snapshot state, and DashboardState update flow.
- `MacStatus/MacStatus/UI/Views/DashboardView.swift` — existing 320pt popover, thermal section, row styling, and dashboard state model.
- `MacStatus/MacStatus/Utils/SettingsManager.swift` — UserDefaults-backed section visibility toggles and settings notification pattern.
- `MacStatus/MacStatus/UI/Views/SettingsView.swift` — Settings UI placement for popover section toggles.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SMCReader` is still the hard hardware boundary. Phase 11 can extend read coverage or add a read-only wrapper, but it must not add public SMC write APIs as part of the fan read implementation.
- `ThermalReader` and `ThermalSnapshot` provide the closest Phase 11 template: curated SMC reads, optional values, `Sendable` value snapshots, and quiet `N/A` degradation.
- `BatteryReader` remains useful as a non-persistent hardware snapshot precedent, especially for independently missing fields and UI formatting.
- `MetricCollector` already keeps popover-only data out of `MetricSample` history. Fan snapshots should follow this non-persistent path.
- `DashboardView` already has a thermal section and stable rows. Phase 11 should extend that surface into `温度与风扇` rather than inventing a new panel.
- `SettingsManager` / `SettingsView` already support default-on visibility toggles, live `.settingsDidChange`, and re-applying the last sample without a full restart.

### Established Patterns
- Readers are synchronous and lightweight on the `@MainActor` collector tick.
- Hardware values are represented as optional fields; nil means a normal unavailable state, not an exception path.
- Popover-only snapshots are not written to SQLite or long-term history for v3.0.
- UI rows should use calm degradation (`N/A` / `—`) instead of transient row churn, modal warnings, or stale value reuse.
- Settings changes should apply live and preserve the current data model as the source of truth.

### Integration Points
- Add a read-only fan snapshot type and reader near the existing reader layer.
- Probe fan count and per-fan SMC keys such as `FNum`, `F{i}Ac`, `F{i}Mn`, `F{i}Mx`, `F{i}Tg`, and identification keys only through read calls.
- Add collector-owned `lastFanSnapshot` state and push it to `DashboardState` alongside the thermal snapshot.
- Add dashboard state for fan snapshot and fan section availability without adding fan values to status-bar rendering or history persistence.
- Rename or refactor the thermal section display to `温度与风扇` while preserving the independent temperature and fan section toggles.
- Add `showFanSection` or equivalent default-on SettingsManager/UserDefaults state and a `风扇区块` toggle in Settings.
- Add verification artifacts for read-only fan probes and no-write guards.

</code_context>

<specifics>
## Specific Ideas

- User selected a combined `温度与风扇` section, not a separate `风扇` top-level block.
- User selected a separate `风扇区块` toggle so temperature and fan rows can be shown/hidden independently.
- User selected left/right names when reliable, falling back to numbered fans when not.
- User selected stable fan rows on supported MacBook Pro hardware, with RPM `N/A` when current RPM is unreadable.
- User selected omission of optional min/max/target details when those fields are missing.
- User selected quiet inline degradation only; no fan read alert or modal.
- User selected an internal capability model but no Phase 11 control affordance.
- Current validation hardware is MacBook Pro `Mac15,9` with Apple M3 Max.

</specifics>

<deferred>
## Deferred Ideas

- Manual fan control, SMC writes, `FS!` writes, target RPM writes, helper/XPC work, opt-in control UI, and restore-auto lifecycle logic are deferred to Phase 13+.
- Popover-wide fixed-width stress hardening, deterministic extreme-value screenshots, and network/RPM/temperature column stabilization remain Phase 12.
- Status-bar temperature or fan segments remain out of scope unless a future display phase explicitly opts in.
- Fanless/non-MacBook-Pro explanatory UI copy is not part of normal Phase 11 UI; record unsupported behavior in probe/debug artifacts instead.
- Raw SMC key browser, complete SMC enumeration UI, fan history charts, alerts, and fan curves remain out of scope.
- Broader hardware model catalogs beyond the current `Mac15,9` validation target are deferred unless implementation discovers low-risk reusable mappings naturally.

</deferred>

---

*Phase: 11-Fan Read-Only RPM & Capability Model*
*Context gathered: 2026-06-24*
