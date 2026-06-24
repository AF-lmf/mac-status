# Phase 12 Layout Verification

**Plan:** 12-03
**Date:** 2026-06-25
**Purpose:** deterministic verification for fixed popover width, stable same-visibility height, fixed value widths, value-column x-position/width stability, and Phase 12 layout-only scope.

## Test Command

```bash
xcodebuild test -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -destination 'platform=macOS' -derivedDataPath build
```

Result: **TEST SUCCEEDED**. The suite executed 5 tests with 0 failures.

Task 1 also verified the hosted XCTest target with:

```bash
xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -destination 'platform=macOS' build-for-testing
```

Result: **TEST BUILD SUCCEEDED**.

## Fixture Coverage

The deterministic fixtures are `DashboardLayoutFixture.Kind.short` and `.extreme`.

Required D-11 extreme values are present in source and exercised by tests:

- `9999 RPM` fan value via `currentRPM: 9_999`
- `100°C` CPU/SoC and battery temperature values
- `999T` network/process byte-rate stress values
- `N/A` unavailable GPU/fan/temperature cases
- `999.9W` battery and system power values

## Fixed Size Results

`DashboardLayout.popoverWidth` is `372pt`.

Observed from the passing test run:

| Fixture | Width | Height |
|---------|-------|--------|
| short | 372.0 | 834.0 |
| extreme | 372.0 | 834.0 |

The tests assert both widths equal `DashboardLayout.popoverWidth` with `accuracy: 0.5`, and same-visible-section heights are equal with `accuracy: 0.5`.

## Value-Column Frame Results

The tests compare each required `LayoutProbeID` between short and extreme fixtures, asserting both x-position and width with `accuracy: 0.5`.

| Probe | short x-position | extreme x-position | short width | extreme width |
|-------|------------------|--------------------|-------------|---------------|
| `networkMetricCardValue` | 96.0 | 96.0 | 76.0 | 76.0 |
| `temperatureValueColumn` | 296.0 | 296.0 | 56.0 | 56.0 |
| `fanRPMValueColumn` | 274.0 | 274.0 | 78.0 | 78.0 |
| `batteryPowerValueColumn` | 246.0 | 246.0 | 104.0 | 104.0 |
| `systemPowerValueColumn` | 246.0 | 246.0 | 104.0 | 104.0 |
| `networkProcessTrailingValue` | 202.0 | 202.0 | 148.0 | 148.0 |
| `cpuProcessTrailingValue` | 298.0 | 298.0 | 52.0 | 52.0 |
| `memoryProcessTrailingValue` | 282.0 | 282.0 | 68.0 | 68.0 |

Process row direct check:

| Case | x-position | width |
|------|------------|-------|
| short process name | 224.0 | 148.0 |
| long process name | 224.0 | 148.0 |

## Source Gates

Passed:

- `rg` confirmed `DashboardLayoutStabilityTests` includes `testPopoverWidthIsFixedForShortAndExtremeFixtures`, `testSameVisibilityFixturesKeepStableHeight`, `testStableValueWidthContractMatchesUISpec`, `testProcessRowsReserveTrailingValueColumns`, `testDashboardValueColumnFramesStayStableAcrossFixtures`, `measuredDashboardSize`, `valueColumnFrameSnapshot`, `assertStableValueColumnFrames`, `withAllPopoverSectionsVisible`, `DashboardLayout.popoverWidth`, and `accuracy: 0.5`.
- `rg` confirmed `LayoutProbeKey`, `LayoutProbeID`, `LayoutProbeFrameSnapshot`, `networkMetricCardValue`, `temperatureValueColumn`, `fanRPMValueColumn`, `batteryPowerValueColumn`, `systemPowerValueColumn`, `networkProcessTrailingValue`, `cpuProcessTrailingValue`, and `memoryProcessTrailingValue`.
- no `frame(width: 320)` remains in `DashboardView.swift` or `ProcessListView.swift`.
- no hotspot `frame(minWidth: 52)` or `frame(minWidth: 72)` remains in `DashboardView.swift` or `ProcessListView.swift`.
- no fan control, no SMC write, no helper/XPC, no status-bar fan, no status-bar thermal, no raw sensor browsing, no alerts, and no charts were added by Phase 12.

Broad forbidden grep note:

- The literal broad pattern `Slider\(` matches pre-existing threshold sliders in `SettingsView.swift` lines 203 and 213.
- These are CPU/memory threshold settings from earlier phases, not fan controls.
- The Phase 12 scope gate was therefore narrowed to fan/SMC/status-bar/alert/chart/raw-sensor terms, matching the prior Phase 11/12 decision that generic pre-existing non-fan controls should not fail fan-control scope checks.

## Scope Statement

This verification is layout-only. It adds deterministic tests and DEBUG/runtime-inert geometry probes only. It adds no fan control, no SMC write path, no helper, no XPC, no status-bar fan or thermal feature, no network/API surface, no secrets, no raw sensor browsing, no chart, and no alert surface.
