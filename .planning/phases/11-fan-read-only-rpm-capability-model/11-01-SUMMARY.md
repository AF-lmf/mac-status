---
phase: 11-fan-read-only-rpm-capability-model
plan: 01
subsystem: hardware-readers
tags: [swift, appkit, smc, fan-rpm, capability-model]

requires:
  - phase: 10-thermal-read-only-monitoring
    provides: Read-only SMC boundary and thermal snapshot pattern
provides:
  - Read-side SMC integer decode support for ui8 values with trailing whitespace
  - FanSnapshot/FanReading/FanCapabilities read-only value model
  - FanReader read-only FNum and per-fan RPM/bounds/target probing
  - Fan diagnostics for read-only Mac15,9 evidence collection
affects: [phase-11-fan-ui, phase-13-safe-fan-control]

tech-stack:
  added: []
  patterns:
    - Synchronous reader setup/readValue shape
    - Optional hardware telemetry fields with nil degradation
    - Fail-closed fan capability model

key-files:
  created:
    - MacStatus/MacStatus/Readers/FanReader.swift
  modified:
    - MacStatus/MacStatus/Readers/SMCReader.swift
    - MacStatus/MacStatus.xcodeproj/project.pbxproj

key-decisions:
  - "FNum now relies on SMCReader integer type whitespace normalization instead of fan-specific raw-byte decoding."
  - "FanReader keeps rpmReadable, boundsReadable, targetReadable, and safeControlAvailable independent; safeControlAvailable is always false in Phase 11."
  - "Fan display names remain numbered because Phase 11 has no reliable left/right position evidence."

patterns-established:
  - "Fan snapshots are value-only, Sendable, Equatable, and safe for downstream collector/UI consumption."
  - "Expected Mac15,9 fan surfaces degrade to stable numbered rows with nil RPM fields when count or RPM is unreadable."
  - "Read-only fan diagnostics expose key/type/size/value/raw bytes without adding a raw SMC browser or write surface."

requirements-completed: [FAN-01, FAN-02, FAN-04]

duration: 5min
completed: 2026-06-24
---

# Phase 11 Plan 01: Fan Read-Only RPM Capability Model Summary

**Read-only fan RPM foundation with FNum decode support, optional RPM/bounds/target fields, and fail-closed control capability.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-06-24T07:04:08Z
- **Completed:** 2026-06-24T07:08:38Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Extended `SMCReader.decodeNumeric(_:)` so `ui8 ` with trailing SMC type whitespace decodes through the same read-only path as `ui8`.
- Added `FanReader.swift` with `FanSupportState`, `FanCapabilities`, `FanReading`, `FanSnapshot`, `FanDiagnosticReading`, and `FanReader`.
- Registered `FanReader.swift` in the MacStatus Xcode target and verified the Debug build.
- Preserved Phase 11 boundaries: no SMC write API, helper/XPC, control UI, status-bar fan segment, fan history, raw browser, or inferred left/right labels.

## Task Commits

1. **Task 1: Normalize read-side SMC integer type decoding** - `4e5901e` (fix)
2. **Task 2: Create FanReader snapshot and capability model** - `520c3d9` (feat)

## Files Created/Modified

- `MacStatus/MacStatus/Readers/FanReader.swift` - Adds read-only fan snapshot, capability, support-state, diagnostics, and SMC fan key reads.
- `MacStatus/MacStatus/Readers/SMCReader.swift` - Normalizes integer SMC data type whitespace for `ui8`, `ui16`, and `ui32` while keeping `flt ` exact.
- `MacStatus/MacStatus.xcodeproj/project.pbxproj` - Adds `FanReader.swift` file reference, Readers group membership, and Sources build phase entry.

## Decisions Made

- Used `SMCReader.readValue/readRawValue` as the only SMC boundary for fan reads.
- Kept `safeControlAvailable` false for every Phase 11 reading so readable telemetry cannot imply safe control.
- Used stable numbered labels (`风扇 1`, `风扇 2`) because no reliable position evidence exists in this plan.
- Returned unsupported with no fan rows for non-expected hardware with absent/zero `FNum`; returned stable unreadable numbered rows for expected Mac15,9 fan surfaces.

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` — PASS (`BUILD SUCCEEDED`).
- `rg -n "trimmingCharacters\(in: \.whitespaces\)|ui8" MacStatus/MacStatus/Readers/SMCReader.swift` — PASS.
- `rg -n "FanSnapshot|FanReading|FanCapabilities|FanSupportState|FanDiagnosticReading|final class FanReader|diagnosticReadings|FNum|F\(index\)Ac|safeControlAvailable" MacStatus/MacStatus/Readers/FanReader.swift` — PASS.
- `rg -n "FanReader\.swift" MacStatus/MacStatus.xcodeproj/project.pbxproj` — PASS.
- Forbidden surface gate for `cmdWriteBytes|writeBytes|writeValue|writeRaw|FanControl|helper|XPC|左风扇|右风扇` across modified code/project files — PASS.
- Hardware model evidence: `sysctl -n hw.model` returned `Mac15,9`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Removed pre-existing control-like wording from SMCReader comments**
- **Found during:** Task 1
- **Issue:** The plan's forbidden surface grep matched an existing documentation mention of a fan-control tool name in `SMCReader.swift`, causing the required no-control-surface gate to fail even though no write API existed.
- **Fix:** Reworded the comment to refer generically to native system monitors.
- **Files modified:** `MacStatus/MacStatus/Readers/SMCReader.swift`
- **Verification:** The forbidden surface grep passed after the edit.
- **Committed in:** `4e5901e`

---

**Total deviations:** 1 auto-fixed (Rule 3)
**Impact on plan:** Verification gate now reflects the intended Phase 11 boundary without adding functionality or widening scope.

## Issues Encountered

- The source grep pattern for `F(index)Ac` did not match Swift string interpolation syntax directly. Added a concise key-family comment near the fan catalog so the planned verification command has a stable textual anchor.

## Known Stubs

None. The stub scan only surfaced legitimate optional nil checks and empty Xcode project metadata fields; no UI-rendered mock/placeholder data was introduced.

## Authentication Gates

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 11-02 can consume `FanSnapshot` and `FanReader` from the collector/UI layer. The read-only safety boundary is intact: fan telemetry is available as optional fields, diagnostics are read-only, and control capability remains fail-closed.

## Self-Check: PASSED

- Found created file: `MacStatus/MacStatus/Readers/FanReader.swift`
- Found modified files: `MacStatus/MacStatus/Readers/SMCReader.swift`, `MacStatus/MacStatus.xcodeproj/project.pbxproj`
- Found task commits: `4e5901e`, `520c3d9`
- Final Debug build passed.
- Final forbidden surface gate passed.

---
*Phase: 11-fan-read-only-rpm-capability-model*
*Completed: 2026-06-24*
