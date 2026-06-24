---
phase: 11-fan-read-only-rpm-capability-model
reviewed: 2026-06-24T07:41:34Z
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
  warning: 0
  info: 0
  total: 0
status: clean
---

# Phase 11: Code Review Report

**Reviewed:** 2026-06-24T07:41:34Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** clean

## Summary

Reviewed the Phase 11 read-only fan RPM implementation, collector wiring, popover UI, settings toggle, and Xcode project registration. The previous WR-01 finding has been resolved by `46c0e83 fix(11): hide unreadable fan rows on non-target hardware`.

Current `FanReader.readValue()` now returns `.unavailable` for non-target hardware when `FNum > 0` but no fan has readable current RPM. Only the expected `Mac15,9` fan surface keeps `.expectedButUnreadable` with stable numbered `N/A` rows.

All reviewed files meet the Phase 11 quality and safety requirements. No remaining actionable issues were found.

## Resolved Findings

### WR-01: Non-expected hardware can show unreadable fan rows

**Status:** Resolved by `46c0e83`

**Resolution:** The no-readable-RPM branch is now gated by `expectsFanSurface`: expected `Mac15,9` hardware returns `.expectedButUnreadable`; non-target hardware returns `.unavailable(capturedAt:)`, preventing unsupported machines from rendering misleading `N/A` fan rows.

## Verification

- Re-read `MacStatus/MacStatus/Readers/FanReader.swift` and confirmed the WR-01 branch behavior at `readValue()`.
- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` - PASS.
- Source review remains consistent with Phase 11 boundaries: no fan SMC write API, helper/XPC surface, fan controls, left/right inference, fan status-bar segment, fan MetricSample field, or fan storage field.

---

_Reviewed: 2026-06-24T07:41:34Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
