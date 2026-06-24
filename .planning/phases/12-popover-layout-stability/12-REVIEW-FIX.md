---
phase: 12-popover-layout-stability
fixed_at: 2026-06-24T17:04:29Z
review_path: .planning/phases/12-popover-layout-stability/12-REVIEW.md
iteration: 1
findings_in_scope: 2
fixed: 2
skipped: 0
status: all_fixed
---

# Phase 12: Code Review Fix Report

**Fixed at:** 2026-06-24T17:04:29Z
**Source review:** .planning/phases/12-popover-layout-stability/12-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 2
- Fixed: 2
- Skipped: 0

## Fixed Issues

### CR-01: Memory metric extreme value is wider than its fixed column

**Files modified:** `MacStatus/MacStatus/UI/Views/StableValueLayout.swift`, `MacStatus/MacStatus/UI/Views/DashboardView.swift`, `MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift`
**Commit:** 9e56f83
**Applied fix:** Added `StableValueWidth.memoryMetricCard = 96`, routed the Memory metric card to that width, and added deterministic AppKit font-fit assertions for metric card value strings including `100% (CRIT)`.

### WR-01: CPU/memory process sections violate the Phase 12 loading and empty-state copy contract

**Files modified:** `MacStatus/MacStatus/UI/Views/DashboardView.swift`
**Commit:** d391459
**Applied fix:** Added explicit CPU and memory empty-state strings to `ProcessResourceSectionView`, changed loading copy to `采样中...`, and rendered empty title/body copy with the same centered bounded layout style used by the network process list.

## Verification

Ran:

```bash
xcodebuild test -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -destination 'platform=macOS' -derivedDataPath build
```

Result: `TEST SUCCEEDED` — 6 tests executed, 0 failures.

---

_Fixed: 2026-06-24T17:04:29Z_
_Fixer: the agent (gsd-code-fixer)_
_Iteration: 1_
