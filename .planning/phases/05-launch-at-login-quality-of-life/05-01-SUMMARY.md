---
phase: 05-launch-at-login-quality-of-life
plan: 01
subsystem: lifecycle
tags: [appkit, service-management, sleep-wake, nsstatusitem]
requires:
  - phase: 04-combined-display-formatting
    provides: "single visible combined menu bar status item"
provides:
  - "Default launch-at-login registration through SMAppService"
  - "Right-click Quit menu on the existing combined status item"
  - "Sleep/wake reader stop/start recovery"
affects: [app-lifecycle, status-bar-menu, reader-timers]
tech-stack:
  added:
    - ServiceManagement.framework
  patterns:
    - "AppDelegate owns lifecycle hooks and delegates metric rendering to StatusBarManager"
    - "TimerReader.start() is reused for launch and wake refresh"
key-files:
  created: []
  modified:
    - MacStatus/MacStatus/App/AppDelegate.swift
    - MacStatus/MacStatus/UI/StatusBarManager.swift
    - MacStatus/MacStatus.xcodeproj/project.pbxproj
key-decisions:
  - "Launch at login is enabled by default using SMAppService.mainApp.register(), with failures logged but not fatal."
  - "Reader start/stop is centralized so launch, sleep, wake, and terminate paths share the same lifecycle primitives."
  - "Right-click menu is attached to the existing status item only; left click remains a no-op."
requirements-completed: [LIFE-02, LIFE-04]
duration: 6 min
completed: 2026-05-14
---

# Phase 05 Plan 01: Launch at Login + Quality of Life Summary

**Lifecycle polish for v1: login item registration, right-click Quit, and sleep/wake reader recovery**

## Performance

- **Duration:** 6 min
- **Started:** 2026-05-14T14:03:00Z
- **Completed:** 2026-05-14T14:09:00Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Added `ServiceManagement` and best-effort `SMAppService.mainApp.register()` at startup.
- Refactored reader setup into `configureReaders()`, `startReaders()`, and `stopReaders()`.
- Added `NSWorkspace.willSleepNotification` and `NSWorkspace.didWakeNotification` handlers to stop and restart CPU/network/memory/GPU readers.
- Added a native right-click `NSMenu` with only `Quit MacStatus` on the existing combined status bar item.
- Preserved the Phase 4 combined metric display format, fixed width, and color behavior.

## Task Commits

1. **Tasks 1-3: Launch-at-login, right-click menu, sleep/wake recovery, build and smoke launch** - `5322457` (feat)

**Plan metadata:** committed separately before execution.

## Files Created/Modified

- `MacStatus/MacStatus/App/AppDelegate.swift` - Registers launch at login, centralizes reader lifecycle, and observes sleep/wake.
- `MacStatus/MacStatus/UI/StatusBarManager.swift` - Adds right-click Quit menu target/action while preserving status button display settings.
- `MacStatus/MacStatus.xcodeproj/project.pbxproj` - Links `ServiceManagement.framework`.

## Decisions Made

- Used best-effort login item registration because debug/signing contexts can throw; monitoring should still start.
- Kept right-click menu minimal to satisfy LIFE-04 without expanding v1 UI scope.
- Reused `TimerReader.start()` for wake recovery because it already cancels any existing timer before scheduling an immediate sample.

## Deviations from Plan

### Auto-fixed Issues

**1. [Swift 6 actor isolation] `configureReaders()` needed `@MainActor`**
- **Found during:** Debug build
- **Issue:** `configureReaders()` called `StatusBarManager.setupNetworkItem()` and `setupMemoryItem()`, which are main actor-isolated.
- **Fix:** Marked `configureReaders()` as `@MainActor`.
- **Files modified:** `MacStatus/MacStatus/App/AppDelegate.swift`
- **Verification:** Debug build passed after the fix.

---

**Total deviations:** 1 auto-fixed compile issue
**Impact on plan:** No scope change.

## Issues Encountered

None open.

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` passed.
- Source assertions for `SMAppService.mainApp`, sleep/wake notifications, `Quit MacStatus`, `.rightMouseUp`, and `NSApp.terminate` passed.
- Debug app relaunched from `build/Build/Products/Debug/MacStatus.app` and stayed running as PID `33625`.
- Short debug CPU smoke sampling was run, but it is not a substitute for the planned 30+ minute soak.

## User Setup Required

Manual UAT remains for:

- Right-click the menu bar item and confirm `Quit MacStatus` appears and quits the app.
- Sleep/wake the Mac and confirm CPU/network/memory/GPU resume updating.
- Run a 30+ minute soak and confirm sustained CPU overhead is under 1%.

## Next Phase Readiness

All planned code is implemented and automated verification passed. Phase 5 still needs the manual UAT items above before claiming full human verification.

---
*Phase: 05-launch-at-login-quality-of-life*
*Completed: 2026-05-14*
