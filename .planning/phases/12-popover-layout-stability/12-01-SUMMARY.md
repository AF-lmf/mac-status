---
phase: 12-popover-layout-stability
plan: 01
subsystem: ui
tags: [swiftui, appkit, popover, layout, dashboard]

requires:
  - phase: 10-thermal-read-only-monitoring
    provides: read-only thermal snapshots rendered in the dashboard popover
  - phase: 11-fan-read-only-rpm-capability-model
    provides: read-only fan RPM/capability snapshots rendered in the dashboard popover
provides:
  - Stable dashboard value layout primitives with named 372pt popover width
  - Fixed-width, right-aligned, monospaced value cells for dashboard-owned high-jitter rows
  - Dashboard metric, battery, temperature, fan, and CPU/memory process trailing values wired to stable helpers
affects: [phase-12, phase-12-02, phase-12-03, popover-layout, dashboard-view]

tech-stack:
  added: []
  patterns:
    - SwiftUI fixed-width value cells via StableValueText
    - Text-yields/value-wins rows via StableValueRow
    - Full-width explanatory captions via StableCaptionText

key-files:
  created:
    - MacStatus/MacStatus/UI/Views/StableValueLayout.swift
  modified:
    - MacStatus/MacStatus/UI/Views/DashboardView.swift
    - MacStatus/MacStatus.xcodeproj/project.pbxproj

key-decisions:
  - "Dashboard popover root width is fixed through DashboardLayout.popoverWidth at exactly 372pt."
  - "Dashboard-owned high-jitter values use fixed-width SwiftUI frames instead of local minWidth or Spacer-only negotiation."
  - "Fan range/target/status explanatory copy remains full-width caption text and does not participate in RPM row width negotiation."

patterns-established:
  - "StableValueText: right-aligned, fixed-width, monospaced-digit values with higher layout priority."
  - "StableValueRow: one-line truncating labels yield before caller-supplied fixed-width values."
  - "StableCaptionText: secondary caption copy uses a stable two-line full-width policy below paired value rows."

requirements-completed: [LAYOUT-01, LAYOUT-02, LAYOUT-03, LAYOUT-04]

duration: 4min
completed: 2026-06-25
---

# Phase 12 Plan 01: Stable Dashboard Value Columns Summary

**372pt popover root plus shared fixed-width SwiftUI value helpers applied to dashboard metric, battery, thermal, fan, and CPU/memory process value hotspots.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-06-24T16:23:50Z
- **Completed:** 2026-06-24T16:27:42Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Created `StableValueLayout.swift` with `DashboardLayout.popoverWidth = 372`, all required `StableValueWidth` constants, `StableValueText`, `StableValueRow`, and `StableCaptionText`.
- Registered the new SwiftUI helper file in the MacStatus app target.
- Replaced DashboardView's root `320pt` width with the named 372pt constant.
- Applied fixed-width stable values to metric cards, temperature rows, fan RPM rows, fan captions, battery/power rows, and CPU/memory Top-N trailing values.
- Preserved compact network up/down display semantics and left `PopoverManager` unchanged.

## Task Commits

1. **Task 1: Define shared stable value layout primitives** - `97e5346` (feat)
2. **Task 2: Apply fixed width and stable dashboard-owned value columns** - `a7be51e` (feat)

## Files Created/Modified

- `MacStatus/MacStatus/UI/Views/StableValueLayout.swift` - Adds the named dashboard width, stable value widths, fixed-width value text, label/value row, and caption helpers.
- `MacStatus/MacStatus/UI/Views/DashboardView.swift` - Uses the stable helpers for dashboard-owned layout hotspots and fixes the root popover width through `DashboardLayout.popoverWidth`.
- `MacStatus/MacStatus.xcodeproj/project.pbxproj` - Adds `StableValueLayout.swift` to the Views group and MacStatus Sources build phase.

## Decisions Made

- Used `372pt` as the single dashboard popover width constant, matching the approved 360-380pt range and the plan's exact source assertion.
- Kept `PopoverManager` host sizing unchanged so AppKit continues to size from SwiftUI preferred content size.
- Scoped process-row work to CPU/memory trailing values inside `DashboardView`; network process rows remain for Plan 12-02.

## Deviations from Plan

None - plan executed exactly as written.

**Total deviations:** 0 auto-fixed.
**Impact on plan:** No scope expansion; no hardware, status-bar, fan-control, SMC write, helper/XPC, alert, chart, or raw sensor browsing surface was added.

## Issues Encountered

- Task 1's first constant spelling used explicit `CGFloat` type annotations, which built correctly but did not satisfy the plan's grep for `popoverWidth = 372`. The constants were rewritten as `372 as CGFloat` / `64 as CGFloat` forms, then the build and grep gates passed.

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` - PASS (`BUILD SUCCEEDED`)
- `rg -n "enum DashboardLayout|popoverWidth = 372|enum StableValueWidth|struct StableValueText|struct StableValueRow|struct StableCaptionText|monospacedDigit|layoutPriority" MacStatus/MacStatus/UI/Views/StableValueLayout.swift` - PASS
- `rg -n "StableValueLayout.swift" MacStatus/MacStatus.xcodeproj/project.pbxproj` - PASS
- `rg -n "DashboardLayout\\.popoverWidth|StableValueText|StableValueRow|StableCaptionText|StableValueWidth\\.(percentage|networkCard|temperature|fanRPM|batteryPower|batteryHealthTime|processCPU|processMemory)" MacStatus/MacStatus/UI/Views/DashboardView.swift` - PASS
- `bash -lc 'if rg -n "\\.frame\\(width: 320\\)|frame\\(minWidth: (52|72)" MacStatus/MacStatus/UI/Views/DashboardView.swift; then exit 1; fi'` - PASS
- `bash -lc 'if rg -n "StatusBarManager|Slider\\(|Stepper\\(|Button\\(\".*风扇|raw SMC|传感器浏览|history chart|Chart\\(|Alert\\(" MacStatus/MacStatus/UI/Views/DashboardView.swift MacStatus/MacStatus/UI/Views/StableValueLayout.swift; then exit 1; fi'` - PASS
- Plan-level `rg -n "StableValueLayout.swift|DashboardLayout\\.popoverWidth|StableValueWidth" MacStatus/MacStatus.xcodeproj/project.pbxproj MacStatus/MacStatus/UI/Views` - PASS

## Known Stubs

None. Stub scan only matched pre-existing `DashboardState` empty collection defaults for live samples and process lists; these are runtime initial states, not placeholder UI introduced by this plan.

## Threat Flags

None. Touched files introduced no new network endpoints, auth paths, file access, SMC write/control boundary, helper/XPC path, status-bar surface, alerts, charts, or raw sensor browser.

## Authentication Gates

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 12-02 can reuse `StableValueText`, `StableValueRow`, and `StableValueWidth.processNetworkRate/processNetworkPair` to stabilize network Top-N process rows and build deterministic short/extreme fixtures. Plan 12-03 can assert the named 372pt root and fixed value-column contracts.

## Self-Check: PASSED

- `MacStatus/MacStatus/UI/Views/StableValueLayout.swift` exists.
- Commits `97e5346` and `a7be51e` exist in git history.
- Final Debug build and plan-level grep gates passed after both task commits.

---
*Phase: 12-popover-layout-stability*
*Completed: 2026-06-25*
