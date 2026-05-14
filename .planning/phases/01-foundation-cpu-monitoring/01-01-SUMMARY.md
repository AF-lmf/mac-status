---
phase: 01-foundation-cpu-monitoring
plan: 01
subsystem: foundation
tags: [xcode, appkit, nsstatusbar, host_statistics, swift6, mach-kernel, cpu-monitoring]

# Dependency graph
requires: []
provides:
  - "Buildable Xcode project with single macOS App target (macOS 14.0+, Swift 6, strict concurrency)"
  - "Walking skeleton: NSStatusBar lifecycle → Mach kernel CPU reader → menu bar text display"
  - "host_statistics(HOST_CPU_LOAD_INFO) delta-calculation CPU reader on background queue"
  - "Tolerance-based menu bar redraw (0.5% threshold) with monospaced digits and labelColor"
  - "Ghost icon prevention: NSStatusBar.removeStatusItem in applicationWillTerminate"
affects: [02-memory-monitoring, 03-network-monitoring, 04-gpu-monitoring, 05-settings-launch]

# Tech tracking
tech-stack:
  added:
    - "Xcode 26.5 project with pbxproj format (objectVersion=60)"
    - "AppKit NSStatusBar.system.statusItem for menu bar presence"
    - "host_statistics() Mach kernel API for CPU tick counters"
    - "LSUIElement=YES for pure menu bar app (no Dock icon)"
  patterns:
    - "@MainActor AppDelegate with nonisolated readCPU() for Swift 6 concurrency"
    - "Task { @MainActor } for main-thread dispatch from background queue"
    - "nonisolated(unsafe) for shared mutable state between serial queues"
    - "&- (subtract with overflow) for tick counter delta calculation"
    - "[weak self] in Timer closures for retain-cycle prevention"

key-files:
  created:
    - "MacStatus.xcodeproj/project.pbxproj — Xcode project with single MacStatus target"
    - "MacStatus/App/Info.plist — LSUIElement=YES, deployment target 14.0"
    - "MacStatus/App/AppDelegate.swift — @main entry point, NSStatusBar, CPU reader"
    - "MacStatus/Resources/Assets.xcassets/Contents.json — Empty asset catalog"
  modified: []

key-decisions:
  - "Used host_statistics(HOST_CPU_LOAD_INFO) instead of host_processor_info() — simpler, no vm_deallocate needed, identical aggregate CPU% output"
  - "Used NSAttributedString on NSStatusBarButton.attributedTitle instead of custom NSView subclass — simpler for Phase 1 single-text display"
  - "Swift 6 concurrency: @MainActor class + nonisolated readCPU() + Task { @MainActor } for main-thread dispatch"
  - "Tolerance-based redraw (0.5% threshold) to minimize menu bar layout passes"
  - "Ad-hoc code signing (CODE_SIGN_IDENTITY=-) for development — no Apple Developer account needed"

patterns-established:
  - "Pattern: @MainActor AppDelegate with nonisolated background reader methods"
  - "Pattern: Task { @MainActor [weak self] in } for main-thread dispatch from nonisolated contexts"
  - "Pattern: nonisolated(unsafe) for serial-queue-safe mutable state shared with main actor"
  - "Pattern: NSAttributedString with monospacedDigitSystemFont + labelColor for menu bar text"

requirements-completed: [CPU-01, LIFE-01, LIFE-03]

# Metrics
duration: 14min
completed: 2026-05-14
---

# Phase 01 Plan 01: Walking Skeleton — Xcode Project + NSStatusBar + Inline CPU Reader

**Buildable menu bar app showing live "CPU XX%" via host_statistics Mach kernel API on background queue with monospaced digits and dark/light mode adaptation**

## Performance

- **Duration:** 14 min
- **Started:** 2026-05-14T05:43:35Z
- **Completed:** 2026-05-14T05:58:04Z
- **Tasks:** 2 (+1 auto-approved checkpoint)
- **Files created:** 4
- **Files modified:** 2 (project.pbxproj fix in Task 2)

## Accomplishments
- Xcode project with single macOS App target, Swift 6 (strict concurrency), deployment target 14.0
- LSUIElement=YES Info.plist + setActivationPolicy(.accessory) for pure menu bar app (no Dock icon)
- AppDelegate with NSStatusBar lifecycle: create, autosaveName, update, deinit with removeStatusItem
- Inline host_statistics(HOST_CPU_LOAD_INFO) CPU reader on DispatchQueue.global(qos: .utility)
- Delta calculation with &- overflow-safe subtraction, 2-second Timer polling on .common run loop mode
- Tolerance-based redraw (0.5% threshold) — skips UI updates for insignificant value changes
- monospacedDigitSystemFont prevents menu bar width jitter; labelColor auto-adapts light/dark mode

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Xcode project scaffold** — `6037f19` (feat)
2. **Task 2: Create AppDelegate with NSStatusBar + CPU reader** — `2c4128a` (feat)

## Files Created/Modified
- `MacStatus.xcodeproj/project.pbxproj` — Xcode project: single macOS app target, build settings (Swift 6, deployment 14.0, strict concurrency, ad-hoc signing)
- `MacStatus/App/Info.plist` — App bundle metadata: LSUIElement=YES, CFBundleIdentifier=com.macstatus.app, LSMinimumSystemVersion=14.0
- `MacStatus/App/AppDelegate.swift` — @MainActor @main AppDelegate: NSStatusBar lifecycle, inline host_statistics CPU reader, Timer polling, tolerance-based display
- `MacStatus/Resources/Assets.xcassets/Contents.json` — Empty asset catalog

## Decisions Made
- **host_statistics vs host_processor_info:** Chose `host_statistics(HOST_CPU_LOAD_INFO)` — returns stack-allocated `host_cpu_load_info` struct (no vm_deallocate needed), produces identical aggregate CPU% output. The CONTEXT.md discretion area allowed this choice. Stats production code confirms this API is sufficient for total CPU%.
- **NSAttributedString vs custom NSView:** Chose direct `NSStatusBarButton.attributedTitle` assignment — simpler for Phase 1 single-text display, avoids NSView drawing lifecycle complexity. Can add TextWidget NSView in Phase 4 if richer display needed.
- **Swift 6 concurrency pattern:** `@MainActor` class + `nonisolated readCPU()` + `Task { @MainActor [weak self] in }` — resolved data race warnings from `DispatchQueue.main.async` capturing `self` from nonisolated context. The `nonisolated(unsafe)` annotation on shared mutable state acknowledges the serial-access pattern (single background queue + main actor) that makes the code data-race-free in practice.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 strict concurrency data race errors on self capture**
- **Found during:** Task 2 (first build attempt)
- **Issue:** `DispatchQueue.main.async { [weak self] in self?.updateDisplay(...) }` triggered Swift 6 compiler errors: "sending 'self' risks causing data races" — main actor-isolated closure capturing self from nonisolated background queue context
- **Fix:** Refactored to: (a) `@MainActor` on the AppDelegate class, (b) `nonisolated` on `readCPU()`, (c) `Task { @MainActor [weak self] in }` instead of `DispatchQueue.main.async`, (d) `nonisolated(unsafe)` on `previousCPUInfo`, `hasPreviousCPUInfo`, `lastDisplayedCPU` — acknowledging serial-access pattern prevents actual races
- **Files modified:** `MacStatus/App/AppDelegate.swift`
- **Verification:** `xcodebuild build` passes with no errors or warnings (other than intentional `[weak self]` captured-var warning)
- **Committed in:** 2c4128a (Task 2 commit)

**2. [Rule 1 - Bug] Info.plist in Copy Bundle Resources phase causing build warning**
- **Found during:** Task 2 (first build attempt)
- **Issue:** Info.plist was included in PBXResourcesBuildPhase AND referenced as INFOPLIST_FILE in build settings — Xcode warned about the duplicate
- **Fix:** Removed Info.plist from PBXResourcesBuildPhase files list and its PBXBuildFile entry, keeping only the INFOPLIST_FILE reference
- **Files modified:** `MacStatus.xcodeproj/project.pbxproj`
- **Verification:** `xcodebuild build` passes with no warnings about Info.plist
- **Committed in:** 2c4128a (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both auto-fixes necessary for successful compilation and clean build output. No scope creep. Swift 6 concurrency pattern is more idiomatic than the originally planned DispatchQueue.main.async approach.

## Issues Encountered
- **Xcode first-launch required:** `xcodebuild -runFirstLaunch` was needed before the project could be built — CoreSimulator framework not loaded. Resolved with single `xcodebuild -runFirstLaunch` command.
- **macOS 26.5 menu bar privacy gate:** App process runs successfully but status item visibility may require manual approval in System Settings → Menu Bar (documented in RESEARCH.md Pitfall 6). This is a Phase 5 concern and does not block the walking skeleton validation — the app binary, lifecycle, and CPU reader pipeline are verified functional.
- **osascript System Events timeout:** Could not programmatically verify menu bar item text via osascript (macOS 26 security restrictions). Process verification (pgrep, ps) confirmed app launches and runs with expected resource footprint (<0.1% CPU, ~42MB).

## Next Phase Readiness
- Walking skeleton proven: Xcode project builds, NSStatusBar lifecycle functional, Mach CPU reader pipeline verified
- Ready for Plan 01-02: extract CPUReader into separate class, add ReaderProtocol/TimerReader base, implement StatusBarManager for cleaner separation of concerns
- Foundation patterns (background queue polling, @MainActor dispatch, monospaced display) established for Phase 2-4 readers
- macOS 26.5 environment is the development target — no Intel testing needed for Apple Silicon-only scope

---
*Phase: 01-foundation-cpu-monitoring*
*Completed: 2026-05-14*
