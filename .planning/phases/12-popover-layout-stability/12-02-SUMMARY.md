---
phase: 12-popover-layout-stability
plan: 02
subsystem: ui
tags: [swiftui, popover, layout, fixtures, process-list]

requires:
  - phase: 12-popover-layout-stability
    provides: StableValueLayout helpers and 372pt DashboardLayout popover width from Plan 12-01
provides:
  - Fixed-width trailing metric blocks for network, CPU, and memory Top-N process rows
  - DEBUG-only short and extreme DashboardState fixtures for deterministic Phase 12 layout verification
  - NetworkTrafficValueBlock using current ByteFormatting upload/download semantics
affects: [phase-12, phase-12-03, popover-layout, process-list, dashboard-fixtures]

tech-stack:
  added: []
  patterns:
    - SwiftUI process rows with left text yielding to fixed trailing value blocks
    - DEBUG-only DashboardState fixture construction for layout tests
    - Xcode project registration for fixture-only Swift source

key-files:
  created:
    - MacStatus/MacStatus/UI/Fixtures/DashboardLayoutFixtures.swift
  modified:
    - MacStatus/MacStatus/UI/Views/ProcessListView.swift
    - MacStatus/MacStatus/UI/Views/DashboardView.swift
    - MacStatus/MacStatus.xcodeproj/project.pbxproj

key-decisions:
  - "Network Top Processes keep existing ByteFormatting plus /s semantics while reserving a fixed 148pt upload/download trailing block."
  - "ProcessMetricRow is the shared text-yields/value-wins row for network, CPU, and memory Top-N sections."
  - "DashboardLayoutFixture remains DEBUG-only and is not referenced from live app, collector, status-bar, popover, or settings paths."

patterns-established:
  - "NetworkTrafficValueBlock: two 68pt monospaced upload/download cells inside a 148pt trailing reservation."
  - "DashboardLayoutFixture.make/apply: creates same-visible-section short/extreme DashboardState fixtures for Plan 12-03 measurement tests."

requirements-completed: [LAYOUT-01, LAYOUT-02, LAYOUT-03, UAT-04]

duration: 4min
completed: 2026-06-25
---

# Phase 12 Plan 02: Process Row Stability and Layout Fixtures Summary

**Fixed Top-N process trailing value regions plus DEBUG-only short/extreme dashboard fixtures for deterministic popover layout measurement.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-06-24T16:32:25Z
- **Completed:** 2026-06-24T16:36:30Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Stabilized network Top Processes rows with `NetworkTrafficValueBlock`, preserving upload/download SF Symbol direction and `ByteFormatting.format(...)+"/s"` strings.
- Hardened `ProcessMetricRow` so process name and PID stay in a truncating left region while trailing metrics keep fixed width and higher layout priority.
- Kept CPU and memory Top-N rows on the same shared fixed-trailing process row contract.
- Added `DashboardLayoutFixture.Kind.short` and `.extreme` with matching visible sections across metric grid, battery, temperature/fan, network, CPU, and memory process sections.
- Registered `DashboardLayoutFixtures.swift` in the app target while guarding all declarations with `#if DEBUG`.

## Task Commits

1. **Task 1: Stabilize process row trailing value blocks** - `11283b4` (feat)
2. **Task 2: Add DEBUG deterministic dashboard layout fixtures** - `0c7a997` (feat)

## Files Created/Modified

- `MacStatus/MacStatus/UI/Views/ProcessListView.swift` - Adds `NetworkTrafficValueBlock`, Chinese inline network process states, and fixed-trailing `ProcessMetricRow`.
- `MacStatus/MacStatus/UI/Views/DashboardView.swift` - Passes CPU/memory process trailing widths into the shared `ProcessMetricRow`.
- `MacStatus/MacStatus/UI/Fixtures/DashboardLayoutFixtures.swift` - Adds DEBUG-only short/extreme `DashboardState` fixtures covering required layout stress values.
- `MacStatus/MacStatus.xcodeproj/project.pbxproj` - Registers the fixture file under `UI/Fixtures` and the MacStatus Sources phase.

## Decisions Made

- Preserved network process display semantics by continuing to build values from `ByteFormatting.format(rate) + "/s"` rather than changing formatter output.
- Used the Plan 12-01 `StableValueWidth.processNetworkRate` and `processNetworkPair` constants directly for process-network width reservation.
- Kept fixture construction isolated to source-level DEBUG gates; no runtime setting, preview hook, live collector path, or app entry point references the fixture type.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated existing CPU/memory process row call site for the new shared row API**
- **Found during:** Task 1 (Stabilize process row trailing value blocks)
- **Issue:** Adding required `trailingWidth` to `ProcessMetricRow` would otherwise leave the existing CPU/memory process section call site without the new argument.
- **Fix:** Passed the existing `ProcessResourceSectionView.trailingWidth` through to `ProcessMetricRow` in `DashboardView`.
- **Files modified:** `MacStatus/MacStatus/UI/Views/DashboardView.swift`
- **Verification:** Debug `xcodebuild` and Task 1 source gates passed.
- **Committed in:** `11283b4`

---

**Total deviations:** 1 auto-fixed (1 blocking integration fix).
**Impact on plan:** No scope expansion. The fix kept the planned shared process-row contract compiling and did not add monitoring, status-bar, fan-control, alert, chart, helper/XPC, SMC write, or raw sensor browsing surface.

## Issues Encountered

None beyond the documented call-site integration fix.

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` - PASS (`BUILD SUCCEEDED`)
- `rg -n "NetworkTrafficValueBlock|trailingWidth|StableValueWidth\.(processNetworkRate|processNetworkPair)|lineLimit\(1\)|truncationMode\(\.tail\)|layoutPriority" MacStatus/MacStatus/UI/Views/ProcessListView.swift` - PASS
- `bash -lc 'if rg -n "No active network processes|Sampling\.\.\." MacStatus/MacStatus/UI/Views/ProcessListView.swift; then exit 1; fi'` - PASS
- `bash -lc 'if git diff -- MacStatus/MacStatus/Utils/ByteFormatting.swift | rg -n "."; then exit 1; fi'` - PASS
- `rg -n "DashboardLayoutFixture|enum Kind|case short|case extreme|make\(|apply\(|9999|100°C|999T|999\.9W|99小时59分|100%（999 次循环）|N/A|ProcessNetworkUsage|ProcessResourceUsage|BatterySnapshot|ThermalSnapshot|FanSnapshot" MacStatus/MacStatus/UI/Fixtures/DashboardLayoutFixtures.swift` - PASS
- `rg -n "DashboardLayoutFixtures.swift" MacStatus/MacStatus.xcodeproj/project.pbxproj` - PASS
- `bash -lc 'if rg -n "DashboardLayoutFixture" MacStatus/MacStatus/App MacStatus/MacStatus/Collectors MacStatus/MacStatus/UI/StatusBarManager.swift MacStatus/MacStatus/UI/PopoverManager.swift MacStatus/MacStatus/UI/Views/SettingsView.swift; then exit 1; fi'` - PASS
- Plan-level `rg -n "NetworkTrafficValueBlock|DashboardLayoutFixture|9999|100°C|999T" MacStatus/MacStatus/UI` - PASS
- Layout-scope guard for fan-control/status-bar/helper/chart/alert terms in touched Swift files - PASS

## Known Stubs

None. Stub scan matches only intentional unavailable/default states already used by the app (`N/A`, `nil`, empty sample arrays) and the new DEBUG fixture's required unavailable cases. No placeholder UI or unwired live data source was introduced.

## Threat Flags

None. Touched files introduced no new network endpoint, auth path, file-access boundary, SMC write/control path, helper/XPC path, status-bar surface, alert, chart, or raw sensor browser.

## Authentication Gates

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 12-03 can use `DashboardLayoutFixture.make(.short)` and `.make(.extreme)` to measure root width, height stability, and fixed value-column positions without relying on live hardware readings.

## Self-Check: PASSED

- `MacStatus/MacStatus/UI/Fixtures/DashboardLayoutFixtures.swift` exists.
- Commits `11283b4` and `0c7a997` exist in git history.
- Final Debug build and plan-level grep/live-path gates passed.

---
*Phase: 12-popover-layout-stability*
*Completed: 2026-06-25*
