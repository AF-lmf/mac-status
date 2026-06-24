---
phase: 10-thermal-read-only-monitoring
plan: 03
subsystem: settings-verification
tags: [swift, swiftui, settings, thermal, hardware-probe, macos]

requires:
  - phase: 10-02
    provides: ThermalReader collector wiring, DashboardState.thermal, and ThermalSectionView
provides:
  - Default-on showThermalSection setting
  - Settings toggle labeled 散热区块
  - Live DashboardView gate for the thermal section
  - Mac15,9 hardware probe and final anti-scope verification record
affects: [thermal-read-only-monitoring, fan-read-only-display, popover-layout-stability]

tech-stack:
  added: []
  patterns:
    - UserDefaults-backed section visibility setting with @Observable access/mutation
    - SettingsManager.shared read inside DashboardView body for live SwiftUI observation
    - Temporary local Swift probe compiled against product read-only reader files

key-files:
  created:
    - .planning/phases/10-thermal-read-only-monitoring/10-HARDWARE-PROBE.md
  modified:
    - MacStatus/MacStatus/Utils/SettingsManager.swift
    - MacStatus/MacStatus/UI/Views/SettingsView.swift
    - MacStatus/MacStatus/UI/Views/DashboardView.swift

key-decisions:
  - "The thermal popover section defaults visible and is hidden only by showThermalSection."
  - "Mac15,9 probe confirmed trusted CPU/SoC and GPU catalog candidates; unsupported or untrusted reads still render N/A."
  - "Phase 10 remains read-only and popover-only: no fan, SMC write, status-bar, persistence, SSD, helper/XPC, notification, or alert scope."

patterns-established:
  - "Thermal visibility follows the existing battery/process section setting pattern without schema migration churn."
  - "Hardware probe evidence is recorded in phase docs with exact command output and source gates."

requirements-completed: [THERM-01, THERM-02, THERM-03, THERM-04]

duration: 3min
completed: 2026-06-24
---

# Phase 10 Plan 03: Thermal Settings and Hardware Probe Summary

**Default-on `散热区块` visibility setting plus a committed Mac15,9 probe proving trusted read-only thermal behavior and no scope expansion.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-06-24T01:27:27Z
- **Completed:** 2026-06-24T01:30:09Z
- **Tasks:** 2 completed
- **Files modified:** 4

## Accomplishments

- Added `SettingsManager.showThermalSection` with default-on nil-check loading, `withMutation`, UserDefaults persistence, and `.settingsDidChange`.
- Added `Toggle("散热区块", isOn: $settings.showThermalSection)` under the existing `弹窗区块` settings section.
- Gated the existing `ThermalSectionView(snapshot: state.thermal)` live by `settings.showThermalSection`, without adding a hardware availability gate.
- Recorded Mac15,9 probe output, trusted CPU/SoC/GPU/battery outcomes, and final no-scope-regression gates in `10-HARDWARE-PROBE.md`.

## Task Commits

1. **Task 1: Add default-on thermal section setting and live dashboard gate** - `fe63177` (feat)
2. **Task 2: Record Mac15,9 hardware probe and final no-scope-regression gates** - `84ca011` (docs)

## Files Created/Modified

- `MacStatus/MacStatus/Utils/SettingsManager.swift` - Adds `showThermalSection` key, backing storage, property, persistence, notification, and default-on `loadAll()` nil-check.
- `MacStatus/MacStatus/UI/Views/SettingsView.swift` - Adds the `散热区块` toggle inside `弹窗区块`.
- `MacStatus/MacStatus/UI/Views/DashboardView.swift` - Hides or shows the entire thermal section from the setting while keeping stable N/A rows when visible.
- `.planning/phases/10-thermal-read-only-monitoring/10-HARDWARE-PROBE.md` - Records model/OS/build/probe/source-gate evidence.

## Decisions Made

- Followed the existing `showBatterySection` / `showProcessSection` setting shape rather than adding schema migration or a new settings group.
- Treated the settings toggle as visibility-only; it does not force a fresh SMC read, change hardware semantics, or affect status-bar metrics.
- Accepted Mac15,9 CPU/SoC display because the probe read `Te05` from the explicit Mac15,9 CPU/SoC catalog; the fallback rule remains `CPU/SoC N/A` when trust is absent.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Committed ignored phase probe file precisely**
- **Found during:** Task 2 commit
- **Issue:** `.planning/` is ignored by `.gitignore`, so normal `git add` and `gsd-tools query commit` refused the new `10-HARDWARE-PROBE.md` file even though the plan explicitly required it to be committed.
- **Fix:** Used a precise `git add -f .planning/phases/10-thermal-read-only-monitoring/10-HARDWARE-PROBE.md` for that one required artifact only; did not stage the ignored `.planning/` tree broadly.
- **Files modified:** `.planning/phases/10-thermal-read-only-monitoring/10-HARDWARE-PROBE.md`
- **Verification:** Commit `84ca011` exists and contains only the probe document.
- **Committed in:** `84ca011`

**Total deviations:** 1 auto-fixed blocking process issue.  
**Impact on plan:** No product scope change; required artifact was committed atomically.

## Issues Encountered

- Task 1 carried `tdd="true"`, but the project has no test target and global `workflow.tdd_mode` is false. Execution followed the plan's macOS build and source grep gates without adding a new Xcode test target for a visibility toggle.
- `xcodebuild` still emits an existing Swift 6 actor-isolation warning in `MetricCollector.swift` for `SettingsManager.changedKeysUserInfoKey`; the build succeeds and this warning predates this task's changed surface.

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` - passed with `BUILD SUCCEEDED`.
- `rg -n "showThermalSection|_showThermalSection|散热区块" ...` - passed.
- `rg -n "object\(forKey: Keys\.showThermalSection\)" MacStatus/MacStatus/Utils/SettingsManager.swift` - passed.
- Task 1 forbidden settings/UI scope grep for thermal thresholds, status-bar thermal, fan, RPM, alerts, and notifications - passed with no matches.
- `test -f .planning/phases/10-thermal-read-only-monitoring/10-HARDWARE-PROBE.md` - passed.
- Probe document keyword gate for `hw.model`, `Mac15,9`, `CPU/SoC`, `ProcessInfo`, `diagnostic`, `N/A`, `xcodebuild`, `BUILD SUCCEEDED`, `no SMC write`, `no fan`, and `no status-bar thermal` - passed.
- Final SMC write/fan/control/helper/XPC source gate - passed with no matches.
- Final storage/status-bar/Metric thermal source gate - passed with no matches.
- `rg -n "\.frame\(width: 320\)" MacStatus/MacStatus/UI/Views/DashboardView.swift` - passed.

## Known Stubs

None introduced by this plan. Stub-pattern scan found the pre-existing disabled clear-history TODO in `SettingsView.swift` and live state arrays in `DashboardState`; neither is part of Phase 10 thermal behavior or blocks this plan goal.

## Threat Flags

None. The plan touched only local UserDefaults visibility and read-only verification documentation. It introduced no network endpoint, auth path, file-access runtime surface, schema, SMC write path, helper/XPC, notification path, or status-bar metric surface.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 10 is ready to close. The popover thermal section is visible by default, can be hidden live from settings, records real Mac15,9 trusted-read evidence, and remains read-only/current-snapshot-only. Phase 11 can build fan read-only RPM and capability modeling without inheriting any write/control UI from Phase 10.

## Self-Check: PASSED

- Created file exists: `.planning/phases/10-thermal-read-only-monitoring/10-HARDWARE-PROBE.md`.
- Summary file exists: `.planning/phases/10-thermal-read-only-monitoring/10-03-SUMMARY.md`.
- Task commits `fe63177` and `84ca011` exist in git history.
- Plan-level build and grep verification passed on final task HEAD.

---
*Phase: 10-thermal-read-only-monitoring*
*Completed: 2026-06-24*
