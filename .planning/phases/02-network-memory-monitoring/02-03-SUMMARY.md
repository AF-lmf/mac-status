---
phase: 02-network-memory-monitoring
plan: 03
subsystem: Menu bar presentation
tags: [gap-closure, status-bar, memory, combined-display, UAT]
requires:
  - 02-01
  - 02-02
provides:
  - Visible CPU/network/memory combined status item
affects: [StatusBarManager, Phase 2 UAT, Phase 4 combined display]
tech-stack:
  added: []
  patterns: [single visible NSStatusItem, cached latest metric text, fixed-width clipping]
key-files:
  created: []
  modified:
    - MacStatus/MacStatus/UI/StatusBarManager.swift
key-decisions:
  - "Memory text now renders through the already-visible networkStatusItem, matching the CPU visibility fix from quick task 260514-rj1."
  - "setupMemoryItem() remains as an AppDelegate integration point but no longer creates a separate NSStatusItem."
  - "The visible combined item width increased to 280pt to fit CPU, network, and memory on one clipped line."
requirements-completed: []
metrics:
  duration: "2 min"
  completed: 2026-05-14T12:07:17Z
  files_changed: 1
  commits: 1
---

# Phase 2 Plan 3: Gap Closure Summary

**Visible menu bar display now renders CPU, network, and memory together through the same combined status item.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-05-14T12:05:38Z
- **Completed:** 2026-05-14T12:07:17Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Added cached `latestMemoryText` state beside the existing CPU and network text.
- Changed memory nil and success updates to refresh the combined visible status item.
- Removed the separate `memoryStatusItem` dependency from the visible Phase 2 display.
- Increased the fixed `networkStatusItem` width from 160pt to 280pt so CPU, network, and memory remain on one clipped line.

## Task Commits

Each task was committed atomically:

1. **Task 1: Fold memory text into the visible combined status item** - `8fff0b2` (fix)

## Files Created/Modified

- `MacStatus/MacStatus/UI/StatusBarManager.swift` - combines `latestCPUText`, `latestNetworkText`, and `latestMemoryText` into `networkStatusItem`; keeps `setupMemoryItem()` as initialization only.

## Decisions Made

- Memory should follow the same visible-display path as CPU: update cached text and redraw the combined status item.
- The independent memory status item was removed because this user's menu bar does not reliably show separate CPU/memory items.
- The Phase 4 "combined display" direction is now partially pulled forward for Phase 2 UAT correctness, but only within the existing status bar manager.

## Deviations from Plan

None - plan executed exactly as written.

**Total deviations:** 0 auto-fixed.
**Impact on plan:** No scope expansion beyond the UAT gap closure.

## Issues Encountered

None.

## Verification

- **Static wiring:** `rg -n "latestMemoryText|updateCombinedStatus|memoryStatusItem|statusItem\\(withLength" MacStatus/MacStatus/UI/StatusBarManager.swift` confirmed memory now participates in combined status rendering and `memoryStatusItem` is gone.
- **Build:** `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` -> BUILD SUCCEEDED.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 2 now satisfies the UAT gap that memory must be visible in the same menu bar item the user can already see. Phase-level review and verification can re-check the updated combined display before moving to Phase 3 GPU monitoring.

---
*Phase: 02-network-memory-monitoring*
*Completed: 2026-05-14*
