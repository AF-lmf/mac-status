---
phase: 04-combined-display-formatting
plan: 01
subsystem: ui
tags: [appkit, nsstatusitem, attributed-string, menu-bar]
requires:
  - phase: 03-gpu-monitoring
    provides: "C | G | M | network combined status item and GPU utilization state"
provides:
  - "Value-level CPU/GPU/MEM warning and critical colors in the combined menu bar text"
  - "Default-colored labels, separators, network text, and normal GPU state"
  - "Fixed-width fallback-safe combined display behavior"
affects: [phase-05-launch-at-login, status-bar-display, menu-bar-ui]
tech-stack:
  added: []
  patterns:
    - "Raw metric state drives attributed value coloring instead of parsing displayed text"
    - "Metric attributed text is appended as label + value so only values receive warning/critical colors"
key-files:
  created: []
  modified:
    - MacStatus/MacStatus/UI/StatusBarManager.swift
key-decisions:
  - "CPU/GPU threshold colors are computed from raw usage values: default under 60%, yellow from 60 to 84%, red at 85% and above."
  - "Memory color is computed from `MemoryPressureLevel`, with OK/default uncolored, WARN yellow, and CRIT red."
  - "GPU normal/default no longer uses green; only warning and critical states add color."
patterns-established:
  - "Value-level status bar coloring: append label with base attributes, then append value/status with optional foreground override."
requirements-completed: [DISP-01, DISP-02, DISP-03, DISP-04]
duration: 2 min
completed: 2026-05-14
---

# Phase 04 Plan 01: Combined Display Formatting Summary

**Value-level menu bar coloring for CPU, GPU, and memory while preserving one fixed-width combined status item**

## Performance

- **Duration:** 2 min
- **Started:** 2026-05-14T13:48:30Z
- **Completed:** 2026-05-14T13:50:00Z
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments

- Added raw CPU, GPU, and memory state in `StatusBarManager` so colors are derived from source values rather than string parsing.
- Rebuilt the combined attributed title as label + value segments, keeping labels/separators/network default-colored while coloring only CPU/GPU values and memory status words.
- Removed the Phase 3 green GPU normal behavior from `StatusBarManager`; GPU now follows default/yellow/red thresholds.
- Preserved fixed width `300`, single-line clipping, and all fallback strings.

## Task Commits

1. **Tasks 1-3: Raw state, value-level attributed text, and verification** - `94c88f7` (feat)

**Plan metadata:** committed with this summary.

## Files Created/Modified

- `MacStatus/MacStatus/UI/StatusBarManager.swift` - Stores raw metric state and applies value-level attributed colors for CPU, GPU, and memory in the combined menu bar item.

## Decisions Made

- Used raw state properties (`latestCPUUsage`, `latestGPUUsage`, `latestMemoryPressure`) to avoid fragile string parsing and stale colors after fallback.
- Kept all color decisions inside `StatusBarManager`, preserving reader and formatter boundaries.
- Continued using system colors only for light/dark mode safety.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Verification

- `grep -n "latestCPUUsage" MacStatus/MacStatus/UI/StatusBarManager.swift` passed.
- `grep -n "latestGPUUsage" MacStatus/MacStatus/UI/StatusBarManager.swift` passed.
- `grep -n "latestMemoryPressure" MacStatus/MacStatus/UI/StatusBarManager.swift` passed.
- `grep -n "usageColor(for" MacStatus/MacStatus/UI/StatusBarManager.swift` passed.
- `grep -n "memoryColor(for" MacStatus/MacStatus/UI/StatusBarManager.swift` passed.
- `grep -n "systemGreen" MacStatus/MacStatus/UI/StatusBarManager.swift` returned no matches.
- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` passed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 4 display polish is code-complete. Phase 5 can build on the existing single combined status item for right-click menu and lifecycle behavior without changing the metric formatting contract.

---
*Phase: 04-combined-display-formatting*
*Completed: 2026-05-14*
