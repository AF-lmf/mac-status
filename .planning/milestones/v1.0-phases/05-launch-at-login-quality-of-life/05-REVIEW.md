---
phase: 05
status: clean
depth: standard
files_reviewed: 3
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
reviewed: 2026-05-14
---

# Phase 05 Code Review

## Scope

- `MacStatus/MacStatus/App/AppDelegate.swift`
- `MacStatus/MacStatus/UI/StatusBarManager.swift`
- `MacStatus/MacStatus.xcodeproj/project.pbxproj`

## Result

No open code issues found.

## Notes

- Launch-at-login registration is best-effort and non-fatal, which is appropriate for debug/signing edge cases.
- Sleep/wake uses the existing reader `start()`/`stop()` primitives; `TimerReader.start()` cancels any prior timer before scheduling, so wake recovery does not duplicate timers.
- Right-click menu is attached through `NSStatusBarButton` target/action with `.rightMouseUp`; no `statusItem.menu` is assigned, so left-click behavior remains unchanged by source.

## Verification

- Debug build passed.
- Source assertions passed for launch-at-login, sleep/wake, and right-click quit hooks.
- Debug app relaunched and stayed running.

## Residual Risk

Manual UI/OS behavior still needs human UAT:

- Right-click menu opening on the user's actual menu bar.
- Sleep/wake recovery on real hardware.
- 30+ minute CPU overhead soak.
