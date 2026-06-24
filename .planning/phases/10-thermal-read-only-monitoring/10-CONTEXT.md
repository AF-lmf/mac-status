# Phase 10: Thermal Read-Only Monitoring - Context

**Gathered:** 2026-06-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 10 delivers a read-only thermal section in the MacStatus popover. It must show a trusted CPU/SoC primary temperature when an explicitly identifiable CPU/SoC sensor is available, show macOS system thermal state, show trustworthy GPU and battery temperatures where available, and degrade stable fields to `N/A`/`—` when data is missing or untrusted.

This phase must not introduce fan RPM display, fan controls, SMC writes, raw sensor browsing, temperature history, alerting, or SSD temperature work unless a reliable existing public disk sensor path is already present. Fan RPM starts in Phase 11, layout hardening is Phase 12, and fan control starts no earlier than Phase 13.

</domain>

<decisions>
## Implementation Decisions

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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Scope
- `.planning/PROJECT.md` — v3.0 milestone scope, safety posture, active requirements, and out-of-scope boundaries.
- `.planning/REQUIREMENTS.md` — THERM-01 through THERM-04 and Future/Out-of-Scope items that prevent scope creep.
- `.planning/ROADMAP.md` — Phase 10 goal, success criteria, dependencies, and boundaries between Phases 10-14.

### v3.0 Research
- `.planning/research/SUMMARY.md` — read-only-first strategy, architecture direction, sensor-scope warnings, and open questions resolved by this discussion.
- `.planning/research/STACK.md` — SMC, ProcessInfo thermal state, and no-dependency constraints relevant to thermal monitoring.
- `.planning/research/FEATURES.md` — user-visible cooling section behavior and anti-features.
- `.planning/research/ARCHITECTURE.md` — Reader -> MetricCollector -> DashboardState/UI data-flow direction and proposed ThermalReader/SensorCatalog concepts.
- `.planning/research/PITFALLS.md` — trust, degradation, and safety pitfalls for thermal/fan work.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MacStatus/MacStatus/Readers/SMCReader.swift`: existing read-only AppleSMC client. It currently returns `Double?` for recognized numeric formats and degrades unknown/unavailable keys to nil. Phase 10 can extend or wrap this boundary for additional trusted thermal data types, but must keep it read-only.
- `MacStatus/MacStatus/Readers/BatteryReader.swift`: best local pattern for optional hardware snapshots. It owns an `SMCReader`, performs synchronous cheap reads on the collector tick, returns optional fields, and lets UI render unavailable values as `—`.
- `MacStatus/MacStatus/Collectors/MetricCollector.swift`: owns all readers, runs the unified tick, keeps battery snapshot separate from persisted `MetricSample`, and pushes non-history dashboard data through `DashboardState`. Thermal snapshots should follow the same non-persistent path for v3.0.
- `MacStatus/MacStatus/UI/Views/DashboardView.swift`: existing popover section and row style. Battery rows already use label/spacer/value with monospaced digits and nil-to-`—` formatting; ThermalSectionView should align with this style.
- `MacStatus/MacStatus/Utils/SettingsManager.swift` and `MacStatus/MacStatus/UI/Views/SettingsView.swift`: existing section visibility toggles (`showBatterySection`, `showProcessSection`) provide the pattern for a default-on thermal section toggle.

### Established Patterns
- Readers are synchronous and lightweight on the `@MainActor` collector tick; Phase 10 should avoid shelling out, long enumeration loops, or background complexity unless planning proves it necessary.
- Hardware data uses optional value fields and UI degradation instead of strong unwraps or user-facing errors.
- Ephemeral dashboard-only data does not need `MetricSample`/SQLite persistence in v3.0.
- Settings changes notify through `.settingsDidChange`, and appearance/visibility changes can re-apply the last sample without forcing a fresh read.

### Integration Points
- Add a thermal snapshot type and reader near the existing reader layer.
- Initialize/read the thermal reader from `MetricCollector.start()` / `tick()` alongside the battery reader.
- Add thermal state storage and update method to `DashboardState`.
- Add a dedicated thermal section to `DashboardView`, gated by a new default-on setting and by stable degraded values.
- Add a Settings toggle using the existing UserDefaults-backed SettingsManager pattern.

</code_context>

<specifics>
## Specific Ideas

- User selected the strict primary-temperature policy: explicit CPU/SoC sensor or `N/A`; no best-effort hottest/package fallback masquerading as CPU/SoC.
- User selected GPU and battery as Phase 10 secondary temperature targets; SSD is intentionally not part of the normal Phase 10 plan.
- User selected stable visible rows with `N/A`/`—` for unavailable values.
- User selected a dedicated `散热` section with a default-on visibility setting.
- Current validation hardware is MacBook Pro `Mac15,9` with Apple M3 Max.

</specifics>

<deferred>
## Deferred Ideas

- SSD temperature support is deferred unless a no-dependency, reliable path already exists.
- Intel/T2 and broader multi-model sensor catalogs are deferred beyond Phase 10.
- Fan RPM, fan capability modeling, layout stress hardening, and fan control remain in Phases 11-14.

</deferred>

---

*Phase: 10-Thermal Read-Only Monitoring*
*Context gathered: 2026-06-24*
