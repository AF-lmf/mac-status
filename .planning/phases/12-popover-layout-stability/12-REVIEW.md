---
phase: 12-popover-layout-stability
reviewed: 2026-06-24T16:59:39Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - MacStatus/MacStatus.xcodeproj/project.pbxproj
  - MacStatus/MacStatus.xcodeproj/xcshareddata/xcschemes/MacStatus.xcscheme
  - MacStatus/MacStatus/App/AppDelegate.swift
  - MacStatus/MacStatus/App/main.swift
  - MacStatus/MacStatus/UI/Fixtures/DashboardLayoutFixtures.swift
  - MacStatus/MacStatus/UI/Views/DashboardView.swift
  - MacStatus/MacStatus/UI/Views/ProcessListView.swift
  - MacStatus/MacStatus/UI/Views/StableValueLayout.swift
  - MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift
findings:
  critical: 1
  warning: 1
  info: 0
  total: 2
status: issues_found
---

# Phase 12: Code Review Report

**Reviewed:** 2026-06-24T16:59:39Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Reviewed the listed app, Xcode project/scheme, SwiftUI layout helpers, fixtures, and layout stability tests against the Phase 12 context and UI contract. The project builds and the current XCTest suite passes with:

```bash
xcodebuild test -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -destination 'platform=macOS' -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO
```

Passing tests are not sufficient here: the suite verifies stable frame positions and widths, but misses at least one value that cannot fit inside the reserved column. There is also a copy/state contract mismatch in the touched process sections.

## Narrative Findings (AI reviewer)

### Critical Issues

#### CR-01: Memory metric extreme value is wider than its fixed column

**Severity:** BLOCKER

**File:** `MacStatus/MacStatus/UI/Views/DashboardView.swift:351`

**Issue:** `MetricCardWithSparkline` uses `StableValueWidth.percentage` for every non-network metric value. That width is `64pt` in `StableValueLayout.swift:11`, but the actual memory card value includes the pressure suffix, and the extreme fixture sets `state.memoryText = "100% (CRIT)"` in `DashboardLayoutFixtures.swift:129`. On the system font used by `.system(.body, design: .monospaced)`, `"100% (CRIT)"` measures about `88.4pt`; even with the current `minimumScaleFactor(0.9)`, a `64pt` frame only permits roughly `71.1pt` of unscaled text. The Phase 12 tests still pass because they only assert frame width/x-position, not whether the rendered text fits, so the implementation can ship a visibly clipped/truncated memory value while reporting layout stability success.

**Fix:**

Give memory its own fixed card width sized for the real pressure-bearing value, and add a deterministic fit assertion so this cannot regress silently.

```swift
enum StableValueWidth {
    static let percentage = 64 as CGFloat
    static let memoryMetricCard = 96 as CGFloat
    static let networkCard = 76 as CGFloat
    // ...
}

private var valueWidth: CGFloat {
    switch title {
    case "Network":
        return StableValueWidth.networkCard
    case "Memory":
        return StableValueWidth.memoryMetricCard
    default:
        return StableValueWidth.percentage
    }
}
```

Then extend `DashboardLayoutStabilityTests` to assert representative value strings fit their contracted columns, including `"100% (CRIT)"` at the body monospaced medium font used by the metric cards.

### Warnings

#### WR-01: CPU/memory process sections violate the Phase 12 loading and empty-state copy contract

**Severity:** WARNING

**File:** `MacStatus/MacStatus/UI/Views/DashboardView.swift:526`

**Issue:** `ProcessResourceSectionView` still renders the English loading label `"Sampling..."` and a generic empty label `"无数据"` for both CPU and memory sections. Phase 12's UI contract requires touched process loading labels to use `采样中...`, and requires distinct CPU/memory empty states: `暂无 CPU 进程采样` / `等待 CPU 采样更新` and `暂无内存进程采样` / `等待内存采样更新`. Because Phase 12 modified this section for stable trailing columns, leaving the generic copy in place is a scope compliance defect and makes CPU/memory empty states less actionable than the network process section.

**Fix:**

Pass explicit empty-state strings into `ProcessResourceSectionView` or model the section kind directly.

```swift
ProcessResourceSectionView(
    title: "CPU 占用 Top 5",
    items: state.topCPUProcesses,
    isLoading: state.resourceLoading,
    trailingWidth: StableValueWidth.processCPU,
    emptyTitle: "暂无 CPU 进程采样",
    emptyBody: "等待 CPU 采样更新",
    trailingText: { proc in
        proc.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—"
    }
)
```

Inside the view, replace `"Sampling..."` with `采样中...` and render the supplied empty title/body with the same centered, bounded layout used by the network process list.

---

_Reviewed: 2026-06-24T16:59:39Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
