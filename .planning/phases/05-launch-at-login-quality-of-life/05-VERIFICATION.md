---
phase: 05-launch-at-login-quality-of-life
status: human_needed
score: 6/9
verified: 2026-05-14
requirements_verified: [LIFE-02, LIFE-04]
human_verification:
  - "Right-click the menu bar item and confirm `Quit MacStatus` appears and quits the app."
  - "Sleep and wake the Mac, then confirm CPU, network, memory, and GPU resume updating."
  - "Run a 30+ minute soak and confirm sustained MacStatus CPU overhead remains under 1%."
gaps:
  - "Manual right-click UAT not performed in this terminal-only verification."
  - "Real sleep/wake UAT not performed."
  - "30+ minute CPU overhead soak not performed."
---

# Phase 05 Verification

## Verification Status

Phase 05 is code-complete and automated verification passed, but full phase verification still needs human UAT for right-click interaction, real sleep/wake behavior, and the 30+ minute CPU overhead soak.

## Requirement Results

| Requirement | Status | Evidence |
|-------------|--------|----------|
| LIFE-02 | PASS | `AppDelegate.configureLaunchAtLogin()` uses `SMAppService.mainApp` and calls `register()` when the service is not already enabled. |
| LIFE-04 | PASS-SOURCE | `StatusBarManager` creates a native `NSMenu` containing `Quit MacStatus`, triggers it on `.rightMouseUp`, and calls `NSApp.terminate(nil)`. Human right-click UAT remains pending. |

## Success Criteria Results

| Success Criterion | Status | Evidence |
|------------------|--------|----------|
| App automatically launches when user logs in | PASS-SOURCE | `SMAppService.mainApp.register()` is called during app launch and `ServiceManagement.framework` is linked. |
| Right-clicking status bar item shows Quit | HUMAN NEEDED | Source and build verify the hook; actual menu-bar right-click needs human confirmation. |
| Readings resume after wake | HUMAN NEEDED | Source verifies `willSleepNotification` -> `stopReaders()` and `didWakeNotification` -> `startReaders()`; real hardware sleep/wake needs human confirmation. |
| Under 1% CPU for 30+ minutes | HUMAN NEEDED | No new polling was added and existing intervals are reused, but the 30+ minute soak was not run. |

## Must-Have Results

| Must-have | Status | Evidence |
|-----------|--------|----------|
| Launch-at-login registration uses `SMAppService.mainApp.register()` | PASS | `AppDelegate.swift` contains `SMAppService.mainApp` and `try service.register()`. |
| Registration failures are non-fatal | PASS | Registration errors are caught and logged with `print(...)`. |
| ServiceManagement is available to the target | PASS | `ServiceManagement.framework` is linked in the Frameworks build phase. |
| Right-click menu contains only Quit | PASS-SOURCE | `statusMenu` adds only `Quit MacStatus`. |
| Left click remains no-op | PASS-SOURCE | The button sends the action only on `.rightMouseUp`; `statusItem.menu` is not assigned. |
| Quit terminates app | PASS-SOURCE | `quitMacStatus(_:)` calls `NSApp.terminate(nil)`. |
| Sleep stops readers | PASS-SOURCE | `NSWorkspace.willSleepNotification` is wired to `applicationWillSleep(_:)`, which calls `stopReaders()`. |
| Wake restarts readers | PASS-SOURCE | `NSWorkspace.didWakeNotification` is wired to `applicationDidWake(_:)`, which calls `startReaders()`. |
| Termination cleanup removes observers and stops readers | PASS | `applicationWillTerminate(_:)` calls `unregisterSleepWakeObservers()` and `stopReaders()`. |

## Commands Run

```bash
xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build
grep -n "SMAppService.mainApp" MacStatus/MacStatus/App/AppDelegate.swift
grep -n "willSleepNotification" MacStatus/MacStatus/App/AppDelegate.swift
grep -n "didWakeNotification" MacStatus/MacStatus/App/AppDelegate.swift
grep -n "Quit MacStatus" MacStatus/MacStatus/UI/StatusBarManager.swift
grep -n "rightMouseUp" MacStatus/MacStatus/UI/StatusBarManager.swift
grep -n "NSApp.terminate" MacStatus/MacStatus/UI/StatusBarManager.swift
open build/Build/Products/Debug/MacStatus.app
pgrep -fl "MacStatus.app/Contents/MacOS/MacStatus"
```

## Runtime Smoke

- Debug app relaunched successfully from `build/Build/Products/Debug/MacStatus.app`.
- Running process observed: PID `33625`.
- Short CPU sampling was run after launch, but results were not treated as pass/fail for the 30+ minute requirement because Debug startup sampling is noisy and not equivalent to sustained release-operation overhead.

## Result

`human_needed` — implementation and automated checks passed; human UAT remains for OS/UI behaviors.
