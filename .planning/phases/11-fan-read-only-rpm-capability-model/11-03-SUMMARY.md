---
phase: 11-fan-read-only-rpm-capability-model
plan: 03
subsystem: hardware-validation
tags: [swift, smc, fan-rpm, hardware-probe, read-only]

requires:
  - phase: 11-fan-read-only-rpm-capability-model
    provides: FanReader/FanSnapshot model and popover wiring from 11-01/11-02
provides:
  - Mac15,9 read-only fan probe evidence for FNum, current RPM, bounds, target, and missing ID keys
  - Final fail-closed source gates proving no fan write/control/status-bar/history/raw-browser surface
  - Phase 11 close-out evidence for FAN-01 through FAN-04
affects: [phase-12-popover-layout-stability, phase-13-safe-fan-control-gate]

tech-stack:
  added: []
  patterns:
    - Temporary Swift probe compiled against product reader files
    - Source-level fail-closed gates scoped to implementation files

key-files:
  created:
    - .planning/phases/11-fan-read-only-rpm-capability-model/11-HARDWARE-PROBE.md
    - .planning/phases/11-fan-read-only-rpm-capability-model/11-03-SUMMARY.md
  modified: []

key-decisions:
  - "Mac15,9 hardware evidence confirms two readable numbered fan rows; F0ID/F1ID are missing, so no left/right inference is made."
  - "Phase 11 remains read-only and fail-closed: safeControlAvailable is false and no control/helper/write UI or source surface exists."
  - "The broad UI forbidden grep is narrowed for fan-specific verification because existing non-fan threshold sliders predate Phase 11."

patterns-established:
  - "Hardware close-out artifacts record exact probe output plus source gates in the same file for auditability."
  - "Broad no-control greps may be paired with narrower fan-specific gates when pre-existing non-fan controls match generic UI tokens."

requirements-completed: [FAN-01, FAN-02, FAN-03, FAN-04]

duration: 5min
completed: 2026-06-24
---

# Phase 11 Plan 03: Hardware Evidence and Fail-Closed Boundary Summary

**Mac15,9 fan RPM probe evidence plus source gates closing Phase 11 as read-only, current-snapshot-only, popover-only, and control-unavailable.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-06-24T07:25:49Z
- **Completed:** 2026-06-24T07:30:54Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Built MacStatus Debug successfully with `xcodebuild`.
- Compiled and ran a temporary Swift probe against product `SMCReader.swift` and `FanReader.swift`.
- Recorded `Mac15,9`, macOS `26.5.1` build `25F80`, `FanSnapshot.supportState=supported`, two numbered fan rows, and diagnostics for `FNum`, `F{i}Ac/Mn/Mx/Tg/Sf/ID/Md/md`, `FS! `, and `Ftst`.
- Confirmed `F0ID/F1ID` are unavailable on this hardware, so labels remain `风扇 1` and `风扇 2`.
- Appended final source gates proving no SMC write API, helper/XPC, fan-control UI, status-bar fan segment, Metric fan item, fan history/storage field, raw SMC browser, or left/right inference.

## Task Commits

1. **Task 1: Record Mac15,9 fan read-only probe evidence** - `ac5e33c` (docs)
2. **Task 2: Run final fail-closed source gates and append evidence** - `b4279f1` (docs)

## Files Created/Modified

- `.planning/phases/11-fan-read-only-rpm-capability-model/11-HARDWARE-PROBE.md` - Mac15,9 build/probe output, fan diagnostics, source gates, and read-only conclusion.
- `.planning/phases/11-fan-read-only-rpm-capability-model/11-03-SUMMARY.md` - Plan close-out summary and verification record.

## Decisions Made

- Treated missing `F0ID/F1ID` as acceptable Mac15,9 evidence and kept numbered labels.
- Kept `FS! ` and `F{i}Tg` strictly diagnostic/read-only; no write/readback/control command was run.
- Used fan-specific UI/control gates after the broader UI grep matched pre-existing non-fan threshold sliders.

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` - PASS (`BUILD SUCCEEDED`).
- `test -f .planning/phases/11-fan-read-only-rpm-capability-model/11-HARDWARE-PROBE.md` - PASS.
- Required probe grep for `hw.model`, `Mac15,9`, `FNum`, `F0Ac/F1Ac`, bounds/target keys, `F0ID/F1ID`, numbered labels, `BUILD SUCCEEDED`, `read-only`, `no write`, and `ui8` - PASS.
- No SMC write/helper/XPC/target-write source gate over `MacStatus/MacStatus` - PASS.
- Fan-specific no control/raw-key UI gate over `DashboardView.swift` and `SettingsView.swift` - PASS.
- No fan slider/stepper in `DashboardView.swift` - PASS.
- No `左风扇` / `右风扇` in `DashboardView.swift` or `FanReader.swift` - PASS.
- No fan/RPM tokens in `Storage`, `StatusBarManager.swift`, or `Metric.swift` - PASS.
- `rg -n "\.frame\(width: 320\)" MacStatus/MacStatus/UI/Views/DashboardView.swift` - PASS.
- Probe document final evidence grep for `no SMC write`, `no status-bar fan`, `no fan history`, `no helper`, `no raw SMC browser`, and `frame(width: 320)` - PASS.

## Deviations from Plan

### Verification Adjustments

**1. Broad UI forbidden grep narrowed to fan-specific controls**
- **Found during:** Task 2
- **Issue:** The planned whole-file UI command matched pre-existing non-fan threshold sliders in `SettingsView.swift`.
- **Resolution:** Preserved unrelated threshold UI and added narrower gates proving no fan-control strings, raw fan keys, fan buttons, or fan slider/stepper in `DashboardView.swift`; `SettingsView.swift` only exposes the visibility toggle `风扇区块`.
- **Files modified:** `.planning/phases/11-fan-read-only-rpm-capability-model/11-HARDWARE-PROBE.md`
- **Verification:** Fan-specific UI/control/raw-key gates passed and are recorded in the probe document.
- **Committed in:** `b4279f1`

---

**Total deviations:** 1 verification adjustment, 0 functional scope changes.
**Impact on plan:** Acceptance intent is preserved; no product code was changed and Phase 11 remains fail-closed.

## Issues Encountered

- `git diff --cached --check` caught one Markdown trailing-space issue before the Task 1 commit; it was removed and the commit was retried successfully.

## Known Stubs

None. This plan only created/updated planning evidence artifacts and did not introduce UI-rendered placeholders, mock data, or source stubs.

## Authentication Gates

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 12 can proceed with layout stability work using confirmed fan rows (`风扇 1`, `风扇 2`) and RPM/bounds/target examples. Phase 13 must still treat control as unavailable until a separate safe write/readback/control gate is designed and verified.

## Self-Check: PASSED

- Found created files: `.planning/phases/11-fan-read-only-rpm-capability-model/11-HARDWARE-PROBE.md`, `.planning/phases/11-fan-read-only-rpm-capability-model/11-03-SUMMARY.md`.
- Found task commits: `ac5e33c`, `b4279f1`.
- Final Debug build passed.
- Final fail-closed source gates passed with the documented fan-specific UI gate adjustment.

---
*Phase: 11-fan-read-only-rpm-capability-model*
*Completed: 2026-06-24*
