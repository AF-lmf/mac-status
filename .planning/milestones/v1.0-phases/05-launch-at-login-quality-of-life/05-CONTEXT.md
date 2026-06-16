# Phase 5: Launch at Login + Quality of Life - Context

**Gathered:** 2026-05-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 5 completes the v1 quality-of-life layer for the existing menu bar monitor. The app should register itself as a login item, expose a minimal right-click menu with Quit, and keep CPU/network/memory/GPU readers reliable across macOS sleep and wake.

This phase does not add a settings window, launch-at-login toggle, popover, notifications, new metrics, or display-format changes. The existing single combined menu bar item remains the visible surface.

</domain>

<decisions>
## Implementation Decisions

### Launch at Login
- **D-01:** Use `SMAppService.mainApp.register()` because the deployment target is macOS 14+ and no helper app is needed.
- **D-02:** Enable launch at login by default on app launch. Phase 5 does not add a preferences UI or toggle.
- **D-03:** If the service is already enabled, do nothing. If registration fails in a debug/signed runtime edge case, log the error and keep the monitor running.
- **D-04:** Link/import ServiceManagement in the app target rather than adding an external dependency.

### Right-Click Menu
- **D-05:** Right-clicking the existing combined status bar item opens an `NSMenu`.
- **D-06:** The v1 menu contains only `Quit MacStatus`, satisfying the minimum requirement without introducing settings or popovers.
- **D-07:** Left click remains no-op so the current at-a-glance monitoring interaction does not change.
- **D-08:** `Quit MacStatus` calls `NSApp.terminate(nil)`.

### Sleep/Wake Recovery
- **D-09:** Observe `NSWorkspace.willSleepNotification` and `NSWorkspace.didWakeNotification` from `AppDelegate`.
- **D-10:** Stop all existing readers before sleep and restart them after wake.
- **D-11:** Keep the current displayed values until the immediate post-wake reader samples replace them. Do not blank the menu bar during sleep/wake transitions.
- **D-12:** Remove observers and stop readers during termination.

### Performance
- **D-13:** Reuse the existing reader intervals and timer model. Phase 5 must not add high-frequency polling.
- **D-14:** Verify with a Debug build, source assertions, and a smoke launch. The 30+ minute under-1% CPU soak remains a manual UAT item if it cannot be run during the implementation session.

### Agent's Discretion
- Planner may choose exact helper names in `AppDelegate`, but lifecycle code should stay centralized there.
- Planner may decide whether to make `StatusBarManager` inherit from `NSObject` to support target/action cleanly.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project and Requirements
- `.planning/PROJECT.md` — macOS menu bar app constraints, AppKit lifecycle, zero external dependency preference.
- `.planning/REQUIREMENTS.md` — LIFE-02 and LIFE-04 requirements.
- `.planning/ROADMAP.md` — Phase 5 goal and success criteria.

### Prior Phase Decisions
- `.planning/phases/01-foundation-cpu-monitoring/01-CONTEXT.md` — AppKit menu bar lifecycle, `LSUIElement`, `StatusBarManager`.
- `.planning/phases/02-network-memory-monitoring/02-CONTEXT.md` — timer reader wiring and network/memory integration.
- `.planning/phases/03-gpu-monitoring/03-CONTEXT.md` — GPU reader nil fallback and combined status item dependency.
- `.planning/phases/04-combined-display-formatting/04-CONTEXT.md` — single visible combined `NSStatusItem`, fixed width, no display-format changes after Phase 4.

### Existing Code
- `MacStatus/MacStatus/App/AppDelegate.swift` — reader creation, callback wiring, start/stop lifecycle.
- `MacStatus/MacStatus/UI/StatusBarManager.swift` — existing combined status item and AppKit status bar button configuration.
- `MacStatus/MacStatus/Readers/TimerReader.swift` — shared timer start/stop behavior used for post-wake recovery.
- `MacStatus/MacStatus.xcodeproj/project.pbxproj` — framework linking and source file membership.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AppDelegate.applicationDidFinishLaunching(_:)` already owns all reader setup and can be refactored into smaller lifecycle helpers.
- `TimerReader.start()` schedules an immediate `.now()` sample, so restarting readers after wake should refresh visible metrics quickly.
- `TimerReader.stop()` cancels the existing timer, making it the right primitive before sleep and during termination.
- `StatusBarManager.setupNetworkItem()` creates the visible fixed-width combined item and `configureStatusButton(_:)` is the correct place to add right-click target/action wiring.

### Integration Points
- `AppDelegate` should import `ServiceManagement` and call a best-effort launch-at-login registration helper during launch.
- `AppDelegate` should observe sleep/wake via `NSWorkspace.shared.notificationCenter`.
- `StatusBarManager` likely needs `NSObject` inheritance for `@objc` target/action selectors.
- The Xcode project may need `ServiceManagement.framework` added to the Frameworks build phase.

### Constraints
- Do not create a second visible status item.
- Do not change the `C | G | M | network` display format.
- Do not add settings UI or storage keys for launch-at-login in Phase 5.
- Do not introduce polling beyond the existing reader timers.

</code_context>

<specifics>
## Specific Ideas

- Target right-click implementation: `button.sendAction(on: [.rightMouseUp])`, `button.target = self`, and a selector that pops an `NSMenu`.
- Target menu item: title `Quit MacStatus`, key equivalent `q`, action `NSApp.terminate(nil)`.
- Target lifecycle split: `configureReaders()`, `startReaders()`, `stopReaders()`, `registerSleepWakeObservers()`, and `unregisterSleepWakeObservers()`.
- Source verification should assert `SMAppService.mainApp`, `willSleepNotification`, `didWakeNotification`, `Quit MacStatus`, and `.rightMouseUp` are present.

</specifics>

<deferred>
## Deferred Ideas

- Launch-at-login preferences toggle.
- Settings or About menu items.
- Popover with detailed metrics.
- User-facing onboarding for macOS 26 menu bar privacy control unless runtime evidence shows the status item cannot appear.

</deferred>

---

*Phase: 05-launch-at-login-quality-of-life*
*Context gathered: 2026-05-14*
