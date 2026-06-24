---
phase: 11-fan-read-only-rpm-capability-model
reviewed: 2026-06-24T07:39:03Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - MacStatus/MacStatus/Readers/SMCReader.swift
  - MacStatus/MacStatus/Readers/FanReader.swift
  - MacStatus/MacStatus/Collectors/MetricCollector.swift
  - MacStatus/MacStatus/UI/Views/DashboardView.swift
  - MacStatus/MacStatus/Utils/SettingsManager.swift
  - MacStatus/MacStatus/UI/Views/SettingsView.swift
  - MacStatus/MacStatus.xcodeproj/project.pbxproj
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 11: Code Review Report

**Reviewed:** 2026-06-24T07:39:03Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Reviewed the Phase 11 read-only fan RPM implementation, collector wiring, popover UI, settings toggle, and Xcode project registration. The SMC path remains read-only: no write command, helper/XPC surface, fan control UI, status-bar fan segment, MetricSample fan field, or storage fan field was found. The current build also succeeds.

One capability-model edge case needs correction before shipping: non-expected hardware can still surface unreadable fan rows when `FNum` is readable but per-fan RPM keys are not.

## Warnings

### WR-01: Non-expected hardware can show unreadable fan rows

**File:** `MacStatus/MacStatus/Readers/FanReader.swift:89`

**Issue:** `FanReader.readValue()` uses `expectsFanSurface` only when `FNum` is missing or zero. If a non-`Mac15,9` machine returns a positive `FNum` but the per-fan current RPM keys are unavailable or decode to implausible values, lines 89-93 still return `.expectedButUnreadable` with numbered fan rows. `DashboardView` renders any non-`.unsupported` snapshot, so unsupported/non-target hardware can show stable `N/A` fan rows even though Phase 11's fallback model reserves that state for expected Mac15,9 fan surfaces. This weakens FAN-03's graceful unsupported behavior and makes the capability state less truthful.

**Fix:** Gate the no-readable-RPM fallback by `expectsFanSurface`. Keep readable RPM telemetry supported, but hide unreadable rows on non-expected hardware:

```swift
let fans = (0..<fanCount).map { reading(for: $0) }
let hasReadableRPM = fans.contains { $0.capabilities.rpmReadable }

if hasReadableRPM {
    return FanSnapshot(supportState: .supported, fans: fans, capturedAt: capturedAt)
}

guard expectsFanSurface else {
    return .unavailable(capturedAt: capturedAt)
}

return FanSnapshot(
    supportState: .expectedButUnreadable,
    fans: fans,
    capturedAt: capturedAt
)
```

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` - PASS.
- Targeted source search found no fan SMC write API, helper/XPC surface, fan controls, left/right inference, fan status-bar segment, fan MetricSample field, or fan storage field.

---

_Reviewed: 2026-06-24T07:39:03Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
