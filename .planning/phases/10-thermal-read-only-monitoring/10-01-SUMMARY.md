---
phase: 10-thermal-read-only-monitoring
plan: 01
subsystem: readers
tags: [swift, appkit, iokit, smc, thermal, macos]

requires:
  - phase: 07-battery-power
    provides: BatteryReader optional hardware snapshot and SMC read pattern
provides:
  - Read-only SMC raw value metadata and Celsius decoding
  - ThermalSnapshot and SystemThermalState value types
  - Mac15,9-gated CPU/SoC and GPU temperature candidate catalog
  - AppleSmartBattery and trusted SMC battery temperature reads
  - ThermalReader.swift Xcode target membership
affects: [thermal-read-only-monitoring, fan-read-only-display, popover-layout-stability, fan-control]

tech-stack:
  added: []
  patterns:
    - Read-only AppleSMC key-info/read-bytes helper
    - Optional snapshot reader with nil degradation
    - Explicit model-gated thermal sensor catalog

key-files:
  created:
    - MacStatus/MacStatus/Readers/ThermalReader.swift
  modified:
    - MacStatus/MacStatus/Readers/SMCReader.swift
    - MacStatus/MacStatus.xcodeproj/project.pbxproj

key-decisions:
  - "ThermalReader only populates CPU/SoC and GPU temperatures from explicit Mac15,9 candidate lists; unsupported models return nil for those fields."
  - "ProcessInfo.thermalState is captured as a separate SystemThermalState and never substitutes for a missing CPU/SoC temperature."
  - "Battery temperature is validated from AppleSmartBattery Temperature first, with only TB1T/TB2T as SMC fallback."

patterns-established:
  - "SMCValue: typed read-side metadata keeps SMCReader compatible while enabling trusted thermal decoding."
  - "ThermalSnapshot: value-only optional fields preserve current-read nil degradation for UI N/A rendering."

requirements-completed: [THERM-01, THERM-02, THERM-03, THERM-04]

duration: 3 min
completed: 2026-06-24
---

# Phase 10 Plan 01: Thermal Read-Only Foundation Summary

**Read-only SMC thermal decoding plus a model-gated ThermalReader snapshot foundation for MacStatus.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-06-24T01:12:03Z
- **Completed:** 2026-06-24T01:15:26Z
- **Tasks:** 2 completed
- **Files modified:** 3

## Accomplishments

- Extended `SMCReader` with `SMCValue`, `readRawValue(key:)`, and bounded `readTemperatureCelsius(key:)` without adding SMC write/control paths.
- Added `ThermalReader.swift` with `ThermalSnapshot`, `SystemThermalState`, `ThermalDiagnosticReading`, and `ThermalSensorCatalog`.
- Registered `ThermalReader.swift` in PBXFileReference, Readers group, PBXBuildFile, and PBXSourcesBuildPhase.

## Task Commits

1. **Task 1: Extend SMCReader with read-only raw and temperature decoding** - `fdca1ce` (feat)
2. **Task 2: Create ThermalReader snapshot, strict catalog, and target membership** - `0a6c569` (feat)

## Files Created/Modified

- `MacStatus/MacStatus/Readers/SMCReader.swift` - Adds typed raw SMC reads and shared numeric/Celsius decoding for `sp78`, `fpe2`, `flt `, `ui8`, `ui16`, and `ui32`.
- `MacStatus/MacStatus/Readers/ThermalReader.swift` - Adds current thermal snapshot reads with Mac15,9 CPU/SoC and GPU catalogs, semantic thermal state, battery temperature validation, and diagnostics.
- `MacStatus/MacStatus.xcodeproj/project.pbxproj` - Registers `ThermalReader.swift` in the app target.

## Decisions Made

- CPU/SoC and GPU temperature candidates are model-gated to `Mac15,9`; other models degrade to nil for these fields.
- `ProcessInfo.processInfo.thermalState` is mapped only into `SystemThermalState`, preserving the strict separation between semantic thermal pressure and temperature readings.
- Battery temperature uses `AppleSmartBattery` `Temperature / 100` with `0...100` bounds before trying the trusted SMC battery keys `TB1T` and `TB2T`.

## Deviations from Plan

None - product scope executed exactly as written.

## Auto-fixed Issues

**1. [Rule 1 - Warning cleanup] Replaced deprecated hardware model string decoding**
- **Found during:** Task 2
- **Issue:** The first `ThermalReader` build passed but emitted a Swift warning for deprecated `String(cString:)`.
- **Fix:** Switched to null-trimmed UTF-8 decoding.
- **Files modified:** `MacStatus/MacStatus/Readers/ThermalReader.swift`
- **Verification:** Re-ran the Task 2 Xcode build and grep gates successfully.
- **Committed in:** `0a6c569`

**Total deviations:** 1 auto-fixed warning cleanup.  
**Impact on plan:** No scope change.

## Issues Encountered

- Task metadata marked both tasks as `tdd="true"`, but the project has no test target and the plan supplied build/grep verification gates rather than test files. Execution followed the plan's required macOS build and source gates.

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` - passed.
- `ThermalReader.swift` appears at least four times in `project.pbxproj` - passed.
- Reader-wide SMC write/control grep returned no matches for Phase 10 forbidden tokens - passed.
- Required `ThermalSnapshot`, `ThermalReader`, `ProcessInfo.processInfo.thermalState`, `AppleSmartBattery`, and `Mac15,9` symbols are present - passed.

## Known Stubs

None.

## Threat Flags

None - new trust-boundary surfaces are the reader surfaces already covered by the plan threat model.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for Plan 10-02 to connect the thermal snapshot into collector/dashboard state and render the stable popover rows. No fan RPM/control, SSD, history, notifications, status-bar metric, helper/XPC, or dependency scope was introduced.

## Self-Check: PASSED

- Created/modified files exist on disk.
- Task commits `fdca1ce` and `0a6c569` exist in git history.
- Plan-level verification passed after both task commits.

---
*Phase: 10-thermal-read-only-monitoring*
*Completed: 2026-06-24*
