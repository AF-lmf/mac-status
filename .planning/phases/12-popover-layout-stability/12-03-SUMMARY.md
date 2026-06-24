---
phase: 12-popover-layout-stability
plan: 03
subsystem: ui
tags: [swiftui, appkit, xctest, popover, layout, verification]

requires:
  - phase: 12-popover-layout-stability
    provides: StableValueLayout helpers and 372pt popover width from Plan 12-01
  - phase: 12-popover-layout-stability
    provides: DEBUG short/extreme dashboard fixtures from Plan 12-02
provides:
  - Hosted MacStatusTests XCTest target and shared scheme
  - Deterministic short/extreme layout stability tests
  - Geometry probe frame assertions for required popover value columns
  - Phase 12 layout verification artifact
affects: [phase-12, popover-layout, dashboard-view, process-list, xctest]

tech-stack:
  added: [XCTest target]
  patterns:
    - Hosted macOS app XCTest bundle using MacStatus.app as TEST_HOST
    - SwiftUI anchorPreference geometry probes captured by NSHostingController tests
    - TestAction-only host isolation via MACSTATUS_LAYOUT_TEST_HOST

key-files:
  created:
    - MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift
    - MacStatus/MacStatus.xcodeproj/xcshareddata/xcschemes/MacStatus.xcscheme
    - .planning/phases/12-popover-layout-stability/12-LAYOUT-VERIFICATION.md
  modified:
    - MacStatus/MacStatus.xcodeproj/project.pbxproj
    - MacStatus/MacStatus/App/main.swift
    - MacStatus/MacStatus/App/AppDelegate.swift
    - MacStatus/MacStatus/UI/Views/StableValueLayout.swift
    - MacStatus/MacStatus/UI/Views/DashboardView.swift
    - MacStatus/MacStatus/UI/Views/ProcessListView.swift

key-decisions:
  - "12-03: Hosted layout tests run with MACSTATUS_LAYOUT_TEST_HOST so the test host does not start duplicate-instance termination, MetricCollector, status-bar wiring, or self-monitor timers."
  - "12-03: LayoutProbeID geometry probes capture deterministic x-position and width frames for required dashboard and process value surfaces."
  - "12-03: The generic Slider forbidden grep is treated as a pre-existing SettingsView threshold-control false positive; Phase 12 scope verification uses fan/SMC/status-bar-specific gates."

patterns-established:
  - "LayoutProbeKey + LayoutProbeFrameStore: internal SwiftUI geometry capture for deterministic tests."
  - "DashboardLayoutStabilityTests: hosted NSHostingController measurement of short/extreme fixtures."

requirements-completed: [LAYOUT-01, LAYOUT-02, LAYOUT-03, LAYOUT-04, UAT-04]

duration: 31min
completed: 2026-06-25
---

# Phase 12 Plan 03: Deterministic Layout Verification Summary

**Hosted XCTest gate proves the 372pt popover, same-height short/extreme fixtures, fixed value widths, and stable x-position/width frames for all required value columns.**

## Performance

- **Duration:** 31 min
- **Started:** 2026-06-24T16:39:00Z
- **Completed:** 2026-06-24T17:10:00Z
- **Tasks:** 2
- **Files modified:** 9 source/project files plus 2 planning artifacts on disk

## Accomplishments

- Added `MacStatusTests` as a hosted XCTest bundle with `MacStatus.app` as `TEST_HOST` and a shared `MacStatus.xcscheme`.
- Implemented deterministic layout tests over `DashboardLayoutFixture.make(.short)` and `.make(.extreme)`.
- Verified both fixtures measure `372pt` width and `834pt` height under the same visible section set.
- Added internal SwiftUI geometry probes for network card value, temperature, fan RPM, battery/system power, and network/CPU/memory process trailing values.
- Recorded frame comparison evidence in `12-LAYOUT-VERIFICATION.md`.

## Task Commits

1. **Task 1: Add XCTest target and shared scheme for layout stability** - `baeabdd` (feat)
2. **Task 2 RED: Add failing deterministic layout tests** - `67a08f6` (test)
3. **Task 2 GREEN: Implement layout stability probes** - `1858daa` (feat)

## Files Created/Modified

- `MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift` - Adds five deterministic layout tests plus measurement helpers.
- `MacStatus/MacStatus.xcodeproj/project.pbxproj` - Adds `MacStatusTests`, XCTest framework, target dependency, product, and hosted test settings.
- `MacStatus/MacStatus.xcodeproj/xcshareddata/xcschemes/MacStatus.xcscheme` - Shared scheme builds and runs the hosted test bundle.
- `MacStatus/MacStatus/App/main.swift` - Skips duplicate-instance termination only for the layout test host.
- `MacStatus/MacStatus/App/AppDelegate.swift` - Skips collector/status-bar/self-monitor startup only for the layout test host.
- `MacStatus/MacStatus/UI/Views/StableValueLayout.swift` - Adds `LayoutProbeID`, `LayoutProbeKey`, `LayoutProbeFrameSnapshot`, and `LayoutProbeFrameStore`.
- `MacStatus/MacStatus/UI/Views/DashboardView.swift` - Attaches required dashboard value-column probes.
- `MacStatus/MacStatus/UI/Views/ProcessListView.swift` - Attaches the network process trailing probe.
- `.planning/phases/12-popover-layout-stability/12-LAYOUT-VERIFICATION.md` - Records command results, frame values, source gates, and scope gates.

## Decisions Made

- Kept the XCTest target app-hosted to satisfy the plan contract, but isolated hosted test launch through `MACSTATUS_LAYOUT_TEST_HOST=1`.
- Used SwiftUI `anchorPreference` and an internal `NSViewRepresentable` updater to capture concrete `CGRect` values without adding user-facing UI.
- Kept geometry probe symbols internal and runtime-inert for normal app use; they only become meaningful when tests install a `LayoutProbeFrameStore`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Isolated hosted test startup from normal app lifecycle**
- **Found during:** Task 2 RED
- **Issue:** `xcodebuild test` initially failed before bootstrapping because the hosted `MacStatus.app` could exit under duplicate-instance protection when an installed MacStatus was already running.
- **Fix:** Added the `MACSTATUS_LAYOUT_TEST_HOST` TestAction environment variable and skipped duplicate-instance termination, `MetricCollector`, status-bar wiring, and self-monitor timers only under that test host.
- **Files modified:** `MacStatus/MacStatus/App/main.swift`, `MacStatus/MacStatus/App/AppDelegate.swift`, `MacStatus/MacStatus.xcodeproj/xcshareddata/xcschemes/MacStatus.xcscheme`
- **Committed in:** `67a08f6`

**2. [Rule 3 - Blocking] Made LayoutProbeKey compatible with Swift 6 strict concurrency**
- **Found during:** Task 2 GREEN
- **Issue:** Swift 6 rejected `PreferenceKey.defaultValue` as a mutable static var.
- **Fix:** Used immutable `static let defaultValue`, preserving the `PreferenceKey` contract and passing strict concurrency checks.
- **Files modified:** `MacStatus/MacStatus/UI/Views/StableValueLayout.swift`
- **Committed in:** `1858daa`

### Verification Adjustment

The exact broad forbidden grep from the plan matches pre-existing CPU/memory threshold sliders in `SettingsView.swift` lines 203 and 213. Those controls are unrelated to fan control and predate Phase 12. Following the established Phase 11/12 scope-gate precedent, final verification used a fan/SMC/status-bar/raw-sensor/alert/chart-specific forbidden gate and documented the broad false positive in `12-LAYOUT-VERIFICATION.md`.

**Total deviations:** 2 auto-fixed blocking issues plus 1 documented verification adjustment.

## Verification

- `xcodebuild -list -project MacStatus/MacStatus.xcodeproj` - PASS; lists `MacStatus` and `MacStatusTests`.
- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -destination 'platform=macOS' build-for-testing` - PASS (`TEST BUILD SUCCEEDED`).
- `xcodebuild test -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -destination 'platform=macOS' -derivedDataPath build` - PASS (`TEST SUCCEEDED`, 5 tests, 0 failures).
- Required test/source grep gates for width, height, constants, process trailing reservation, probe IDs, `origin.x`, and `.width` - PASS.
- `frame(width: 320)` and hotspot `frame(minWidth: 52|72)` absence gate - PASS.
- Narrowed forbidden fan/SMC/status-bar/raw-sensor/alert/chart scope gate - PASS.
- `12-LAYOUT-VERIFICATION.md` artifact grep gate - PASS.

## Known Stubs

None. Stub scan found only intentional fixture unavailable values such as `N/A` and existing default empty runtime collections; no placeholder UI or unwired data source was introduced.

## Threat Flags

None. The changes add test infrastructure and internal geometry probes only; no network endpoint, auth path, file access boundary, SMC write/control path, helper/XPC path, status-bar feature, alert, chart, or raw sensor browser was introduced.

## Authentication Gates

None.

## TDD Gate Compliance

- RED commit exists: `67a08f6` (`test(12-03): add failing layout stability tests`).
- GREEN commit exists after RED: `1858daa` (`feat(12-03): implement layout stability probes`).
- No separate refactor commit was needed.

## User Setup Required

None. The deterministic gate runs through `xcodebuild test`; no external packages or credentials are required.

## Next Phase Readiness

Phase 13 can proceed with fan-control planning knowing Phase 12 layout requirements are covered by automated tests and that the popover layout gate will catch width/height/value-column regressions.

## Self-Check: PASSED

- `MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift` exists.
- `.planning/phases/12-popover-layout-stability/12-LAYOUT-VERIFICATION.md` exists on disk and passed artifact grep gates.
- Commits `baeabdd`, `67a08f6`, and `1858daa` exist in git history.
- Final `xcodebuild test` passed after the GREEN commit.

---
*Phase: 12-popover-layout-stability*
*Completed: 2026-06-25*
