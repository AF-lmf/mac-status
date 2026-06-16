---
phase: 02-network-memory-monitoring
status: clean
depth: standard
files_reviewed: 6
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
reviewed_at: 2026-05-14T12:13:00Z
---

# Phase 2 Code Review

## Scope

Reviewed Phase 2 source files derived from the plan summaries:

- `MacStatus/MacStatus/Readers/NetworkReader.swift`
- `MacStatus/MacStatus/Readers/MemoryReader.swift`
- `MacStatus/MacStatus/Utils/ByteFormatting.swift`
- `MacStatus/MacStatus/UI/StatusBarManager.swift`
- `MacStatus/MacStatus/App/AppDelegate.swift`
- `MacStatus/MacStatus.xcodeproj/project.pbxproj`

## Findings

### WR-001: MemoryReader can publish unusable stats if total memory lookup fails

**Severity:** Warning - resolved  
**File:** `MacStatus/MacStatus/Readers/MemoryReader.swift`  
**Area:** Error handling

`MemoryReader.setup()` sets `totalSize = 0` when `host_info(HOST_BASIC_INFO)` fails, but `read()` can still publish `MemoryStats(usedBytes: used, totalBytes: 0, freeBytes: 0)` when `host_statistics64()` succeeds. That can render misleading text such as `MEM 8.2G/0B`, and `StatusBarManager.updateMemory(_:)` later divides by `stats.totalBytes` in the redraw threshold calculation.

**Resolution:** Fixed in `9c27d7c` by returning `nil` through `onUpdate` when `totalSize <= 0` before computing or publishing stats.

## Clean Checks

- `StatusBarManager` now renders CPU, network, and memory through the visible combined `networkStatusItem`.
- `memoryStatusItem` dependency is removed from the Phase 2 visible display path.
- Network interface detection still uses `SCDynamicStoreCopyValue` instead of hardcoded interface names.
- `getifaddrs()` allocation is still released with `freeifaddrs()` in a `defer` block.
- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` succeeds.

## Recommendation

No open code-review findings remain for Phase 2.
