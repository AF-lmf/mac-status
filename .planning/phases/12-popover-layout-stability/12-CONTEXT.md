# Phase 12: Popover Layout Stability - Context

**Gathered:** 2026-06-24T23:32:48+08:00
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 12 delivers stable MacStatus popover layout under rapidly changing and extreme values. When network rates, temperatures, fan RPM, power values, and process text change length, the popover must keep a fixed width, stable rows, stable numeric columns, and predictable truncation/wrapping.

This phase is layout hardening only. It may introduce reusable SwiftUI row/value helpers and deterministic fixture data for the popover, but it must not add new monitoring capabilities, fan controls, status-bar temperature/fan segments, history charts, alerts, or raw sensor browsing.

</domain>

<decisions>
## Implementation Decisions

### Stable Numeric Rows
- **D-01:** Use a reusable stable value-row/value-column abstraction for Phase 12 high-jitter popover rows, instead of patching every row independently.
- **D-02:** Scope that abstraction to the known Phase 12 hotspots: network metric values, temperature rows, fan RPM rows, power/battery values, and Top-N process trailing values. Do not rewrite the entire dashboard UI just to introduce the helper.
- **D-03:** Key numeric values must be right-aligned and use monospaced digits. Widths should be explicit per value kind and sized for worst-case fixtures such as `9999 RPM`, `100°C`, `N/A`, large network rates, and large wattage values.

### Popover Width
- **D-04:** Do not keep `320pt` as a hard constraint. Phase 12 may fixed-expand the popover to a value in the `360-380pt` range.
- **D-05:** The selected popover width must be fixed once and must not change on refresh, data availability, network spikes, longer fan labels, or process list changes.
- **D-06:** Keep the current compact popover identity; expansion is for stable readability, not a new large dashboard redesign.

### Long Text Behavior
- **D-07:** When labels or process names compete with values, the text side yields. Long process names, long sensor labels, PID text, and capability/status copy must truncate or move to a separate line before they squeeze the numeric value column.
- **D-08:** Numeric columns remain stable even when explanatory copy such as fan boundary/control status is shown. Full-width captions are acceptable when they do not affect the paired value-column width.
- **D-09:** Network display can keep the current compact up/down presentation; stabilization should come from a fixed value block and row/card sizing, not from changing the meaning of the network metric.

### Deterministic Verification
- **D-10:** Phase 12 must include deterministic extreme test data or preview fixtures. It is not enough to rely on normal live readings or visual inspection during one run.
- **D-11:** Fixtures must cover at least: short and large network rates, `9999 RPM`, `100°C`, `N/A`, large power values, long process names, long sensor labels, and mixed availability across battery, thermal, fan, and process sections.
- **D-12:** Verification must explicitly check that popover width is fixed and that rows/value columns do not jump across short-value and long-value states.

### the agent's Discretion
- The planner may choose exact helper names and file splits, but should prefer small SwiftUI components or modifiers that match the existing `DashboardView` style.
- The planner may choose the precise width inside `360-380pt`, as long as it is fixed and justified by the deterministic fixture.
- The planner may choose whether verification is implemented as SwiftUI previews, XCTest/view-size tests, snapshot-style fixtures, or a lightweight debug fixture, as long as UAT-04 is satisfied deterministically.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Scope
- `.planning/PROJECT.md` — v3.0 scope, active milestone goal, and current milestone item for stable popover/dropdown layout.
- `.planning/REQUIREMENTS.md` — LAYOUT-01 through LAYOUT-04 and UAT-04 define the required fixed columns, long-text handling, width stability, and deterministic verification.
- `.planning/ROADMAP.md` — Phase 12 goal, dependencies on Phases 10/11, success criteria, and Phase 13+ fan-control boundary.

### Prior Phase Context
- `.planning/phases/10-thermal-read-only-monitoring/10-CONTEXT.md` — established stable thermal rows, `N/A` degradation, and deferred full layout hardening to Phase 12.
- `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md` — established `温度与风扇`, fan RPM/bounds rows, capability copy, and explicit deferral of popover-wide fixed-width stress work to Phase 12.

### Existing Code
- `MacStatus/MacStatus/UI/Views/DashboardView.swift` — current popover root width, metric cards, battery section, `TemperatureAndFanSectionView`, and process resource sections.
- `MacStatus/MacStatus/UI/Views/ProcessListView.swift` — `ProcessMetricRow` name/PID/trailing layout used by network, CPU, and memory process rows.
- `MacStatus/MacStatus/Utils/ByteFormatting.swift` — compact byte/rate formatting used by menu bar and popover network/process values.
- `MacStatus/MacStatus/UI/StatusBarManager.swift` — status-bar formatting reference; Phase 12 should not expand status-bar scope unless a shared formatting helper must remain compatible.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DashboardView` currently applies `.frame(width: 320)` to the whole popover; this is the primary fixed-width integration point for D-04/D-05.
- `MetricCardWithSparkline` already uses monospaced text and right alignment for values, including multi-line network text, but it does not reserve a fixed value width.
- `TemperatureAndFanSectionView.temperatureRow` and `fanRow` already use monospaced values and minimum widths (`52` and `72`), which are good starting points but not yet a shared worst-case-width system.
- `BatterySectionView.row` and `ProcessResourceSectionView` already use simple label/spacer/value rows that can adopt a stable value-column helper.
- `ProcessMetricRow` already truncates the process name, which matches D-07; it still needs stronger layout priority/fixed trailing width so PID/name text cannot compress the trailing metrics.
- `ByteFormatting` keeps network and process rates compact, but short-to-long changes still need layout-level stabilization.

### Established Patterns
- The popover uses small full-width sections and compact cards with `8px`-style corner radius and calm secondary labels. Phase 12 should preserve this visual language.
- Hardware and process values degrade inline to `N/A`, `—`, or quiet empty states rather than creating modal/error UI.
- Recent Phase 10/11 work intentionally deferred popover-wide fixed-width stress handling to this phase.
- Menu-bar text already has its own status-bar formatting path; Phase 12 should center the popover/dropdown jitter problem and avoid new status-bar feature work.

### Integration Points
- Root width: `DashboardView.body` fixed frame.
- Metric values: `MetricCardWithSparkline`.
- Thermal/fan rows and captions: `TemperatureAndFanSectionView`.
- Battery/power rows: `BatterySectionView`.
- Network/CPU/memory process rows: `ProcessListView.ProcessMetricRow` and `ProcessResourceSectionView`.
- Fixture or test construction should exercise `DashboardState`-compatible values for all visible sections.

</code_context>

<specifics>
## Specific Ideas

- User explicitly approved a reusable stable row/value-column helper for high-jitter rows.
- User explicitly allowed fixed expansion to `360-380pt`; `320pt` is not a hard requirement for this phase.
- User confirmed that long text should truncate or wrap separately before it affects numeric values.
- User confirmed deterministic extreme fixture/test-data verification as the acceptance posture.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 12 layout-stability scope.

</deferred>

---

*Phase: 12-Popover Layout Stability*
*Context gathered: 2026-06-24T23:32:48+08:00*
