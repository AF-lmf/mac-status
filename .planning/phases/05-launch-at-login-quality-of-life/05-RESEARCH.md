# Phase 5: Launch at Login + Quality of Life - Research

**Date:** 2026-05-14
**Phase:** 05-launch-at-login-quality-of-life
**Question:** How should MacStatus implement launch-at-login, right-click quit, and sleep/wake recovery without expanding v1 scope?

## RESEARCH COMPLETE

## Executive Summary

Phase 5 should stay inside AppKit and existing reader lifecycle primitives. `SMAppService.mainApp.register()` is the correct launch-at-login API for a macOS 14+ app. `NSWorkspace` sleep/wake notifications are the correct app-level recovery hook. The right-click menu can be implemented on the existing `NSStatusBarButton` using target/action and an `NSMenu`.

No new dependency, helper target, settings UI, or polling loop is needed.

## Existing Implementation

### AppDelegate

`MacStatus/MacStatus/App/AppDelegate.swift` currently:

- creates `StatusBarManager`
- creates CPU/network/memory/GPU readers
- wires reader callbacks back to the main queue
- starts each reader once at launch
- stops each reader during termination

The main gap is that start/stop logic is inline, so sleep/wake recovery needs a small refactor:

- `configureReaders()`
- `startReaders()`
- `stopReaders()`
- `registerSleepWakeObservers()`
- `unregisterSleepWakeObservers()`

### TimerReader

`TimerReader.start()` calls `stop()` first, creates a new `DispatchSourceTimer`, and schedules the first read at `.now()`. This makes repeated wake recovery safe: if a reader is already running, `start()` replaces the timer; if the Mac just woke, the first refresh happens immediately.

### StatusBarManager

`StatusBarManager` already owns the only visible combined `NSStatusItem`. Right-click behavior belongs in `configureStatusButton(_:)` so the menu is attached to that same visible button.

Because AppKit target/action selectors are Objective-C based, the simplest implementation is to make `StatusBarManager` inherit `NSObject` and add `@objc` methods for opening the menu and quitting.

## Recommended Technical Approach

### Launch at Login

Use:

```swift
import ServiceManagement

private func configureLaunchAtLogin() {
    let service = SMAppService.mainApp
    guard service.status != .enabled else { return }

    do {
        try service.register()
    } catch {
        print("Launch at login registration failed: \(error)")
    }
}
```

This is best-effort and non-blocking. It satisfies the v1 requirement without a helper app or preferences UI.

### Right-Click Menu

Use:

- `button.target = self`
- `button.action = #selector(showStatusMenu(_:))`
- `button.sendAction(on: [.rightMouseUp])`
- `NSMenuItem(title: "Quit MacStatus", action: #selector(quitMacStatus(_:)), keyEquivalent: "q")`
- `NSApp.terminate(nil)` in the quit selector

Do not assign the menu as a normal `statusItem.menu`; that would change the default click behavior. The phase decision is right-click-only.

### Sleep/Wake Recovery

Use `NSWorkspace.shared.notificationCenter`:

- `NSWorkspace.willSleepNotification` -> `stopReaders()`
- `NSWorkspace.didWakeNotification` -> `startReaders()`

This avoids stale timers and stale interface state across sleep transitions while preserving the last visible menu bar text until fresh samples arrive.

## Risks And Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Login item registration fails in Debug or unsigned contexts | Medium | Catch and log the error; keep monitoring running |
| Left-click starts opening the menu unexpectedly | Medium | Use `sendAction(on: [.rightMouseUp])` and keep left click no-op |
| Readers duplicate timers after wake | High | Reuse `TimerReader.start()`, which calls `stop()` before scheduling |
| Sleep/wake observers outlive AppDelegate | Medium | Remove observers during `applicationWillTerminate` |
| ServiceManagement import fails at link time | Medium | Add `ServiceManagement.framework` to the Xcode Frameworks build phase if needed |

## Recommended Plan Split

One plan is sufficient because this phase is a small lifecycle slice:

- `05-01-PLAN.md`: Implement launch-at-login registration, right-click quit menu, sleep/wake reader recovery, build verification, and smoke launch.

## Validation Strategy

Run:

`xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build`

Source assertions:

- `AppDelegate.swift` contains `SMAppService.mainApp`
- `AppDelegate.swift` contains `willSleepNotification`
- `AppDelegate.swift` contains `didWakeNotification`
- `StatusBarManager.swift` contains `Quit MacStatus`
- `StatusBarManager.swift` contains `.rightMouseUp`

Smoke launch:

- Relaunch the Debug app from `build/Build/Products/Debug/MacStatus.app`.
- Confirm the process stays running.
- Confirm the visible combined status item still renders.

Manual UAT:

- Right-click the status item and confirm `Quit MacStatus` appears.
- Sleep/wake the Mac and confirm all segments resume updating.
- Run a 30+ minute soak and confirm MacStatus remains under 1% CPU.
