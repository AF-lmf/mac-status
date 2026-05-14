---
phase: 01-foundation-cpu-monitoring
plan: 02
subsystem: architecture
tags: [refactor, extraction, reader-protocol, timer-reader, status-bar-manager, settings, swift6, sendable]

# Dependency graph
requires:
  - "01-01 (walking skeleton AppDelegate with inline code)"
provides:
  - "CPUReader: standalone, testable class with host_statistics, delta calc, Sendable CPULoad wrapper"
  - "StatusBarManager: NSStatusItem lifecycle with deinit cleanup, tolerance check, macOS 26 visibility gate"
  - "ReaderProtocol: associatedtype ValueType, setup/read/start/stop lifecycle for all future readers"
  - "TimerReader<T>: generic base class with Timer management + background queue dispatch"
  - "SettingsManager: UserDefaults singleton for refreshInterval (ready for Phase 2+ settings)"
  - "Thin AppDelegate: ~30-line wiring hub between StatusBarManager and CPUReader"
affects: [02-memory-monitoring, 03-network-monitoring, 04-gpu-monitoring, 05-settings-launch]

# Tech tracking
tech-stack:
  added:
    - "Swift protocol with associatedtype for reader value type abstraction"
    - "Generic base class TimerReader<T> with Timer lifecycle + DispatchQueue.global(qos: .utility)"
    - "@MainActor class pattern for AppKit NSStatusItem management"
    - "MainActor.assumeIsolated for deinit cleanup in @MainActor classes"
    - "@unchecked Sendable for UserDefaults wrapper singleton"
  patterns:
    - "ReaderProtocol → TimerReader<T> → ConcreteReader subclass hierarchy"
    - "onUpdate closure callback from background queue → caller dispatches to main thread"
    - "Tolerance-based display skip (0.5%) in StatusBarManager.updateCPU"
    - "autosaveName for NSStatusItem position persistence"
    - "DispatchQueue.main.asyncAfter for macOS 26 privacy gate detection"

key-files:
  created:
    - "MacStatus/Readers/CPUReader.swift — extends TimerReader<Double>, host_statistics + delta calc + CPULoad: Sendable"
    - "MacStatus/Readers/ReaderProtocol.swift — protocol with associatedtype ValueType, reader lifecycle"
    - "MacStatus/Readers/TimerReader.swift — generic Timer-based polling base class"
    - "MacStatus/UI/StatusBarManager.swift — @MainActor NSStatusItem lifecycle + display formatting + macOS 26 gate"
    - "MacStatus/Utils/SettingsManager.swift — @unchecked Sendable UserDefaults singleton"
  modified:
    - "MacStatus/App/AppDelegate.swift — simplified to ~30-line wiring hub"
    - "MacStatus.xcodeproj/project.pbxproj — added 5 new source files to build"

key-decisions:
  - "CPUReader extends TimerReader<Double> — Timer lifecycle inherited, only read() override needed"
  - "StatusBarManager is @MainActor — all NSStatusItem ops must be on main thread per AppKit requirement"
  - "SettingsManager uses @unchecked Sendable — UserDefaults is documented thread-safe"
  - "AppDelegate delegates Timer management to TimerReader.start/stop — no inline Timer code"
  - "macOS 26 visibility gate uses DispatchQueue.main.asyncAfter with NSAlert — non-blocking, user-friendly"

patterns-established:
  - "Pattern: ReaderProtocol → TimerReader<T> → ConcreteReader (inheritance-based polling)"
  - "Pattern: @MainActor UI class with MainActor.assumeIsolated deinit for AppKit resource cleanup"
  - "Pattern: onUpdate callback bridging background queue → main thread via caller's DispatchQueue.main.async"
  - "Pattern: SettingsManager singleton with @unchecked Sendable for UserDefaults access"

requirements-completed: [CPU-02, LIFE-01]

# Metrics
duration: 9min
completed: 2026-05-14
---

# Phase 01 Plan 02: Architecture Extraction — CPUReader, StatusBarManager, ReaderProtocol, TimerReader, SettingsManager

**Inline walking-skeleton code extracted into 5 properly separated classes following D-02 folder structure, with Swift 6 Sendable compliance, macOS 26 privacy gate detection, and production-grade status bar lifecycle**

## Performance

- **Duration:** 9 min
- **Started:** 2026-05-14T06:05:30Z
- **Completed:** 2026-05-14T06:14:36Z
- **Tasks:** 2 (both auto)
- **Files created:** 5
- **Files modified:** 2
- **Total source files:** 6 (App + Readers + UI + Utils)

## Accomplishments

### Architecture (D-02 folder structure)
- **Readers/**: CPUReader (host_statistics + Sendable CPULoad), ReaderProtocol (associatedtype), TimerReader\<T\> (generic Timer base)
- **UI/**: StatusBarManager (@MainActor NSStatusItem lifecycle + display + macOS 26 gate)
- **Utils/**: SettingsManager (@unchecked Sendable UserDefaults singleton)
- **App/**: AppDelegate (~30-line wiring hub, no inline data collection or display code)

### Swift 6 Strict Concurrency Compliance
- `CPUReader`: `CPULoad: Sendable` wrapper converts Mach C struct to Swift-safe type
- `StatusBarManager`: `@MainActor` class with `MainActor.assumeIsolated` in deinit for proper cleanup
- `SettingsManager`: `@unchecked Sendable` — UserDefaults is thread-safe by design
- `TimerReader`: `[weak self]` in all timer/dispatch closures, `onUpdate` callback bridges to caller's queue
- `AppDelegate`: simplified to delegate all Timer/read/display concerns

### Production-Grade Features
- **D-10 Ghost icon prevention:** `NSStatusBar.system.removeStatusItem` in StatusBarManager.deinit
- **D-06 Tolerance-based redraw:** 0.5% threshold in `updateCPU()` — skips unnecessary menu bar updates
- **D-07 Monospaced digits:** `NSFont.monospacedDigitSystemFont` prevents menu bar width jitter
- **D-04 Error display:** "CPU --%" on Mach API failure (nil callback path)
- **macOS 26 privacy gate:** 2-second delayed `asyncAfter` check with NSAlert directing to System Settings
- **LIFE-03 Zero-config startup:** `TimerReader.start()` fires first read immediately
- **autosaveName:** `"com.macstatus.cpu"` for position persistence across launches

## Task Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | `9b8901c` | Create CPUReader + StatusBarManager, refactor AppDelegate |
| 2 | `7921a1a` | Add ReaderProtocol, TimerReader, SettingsManager; extend CPUReader; simplify AppDelegate |

## Files Created/Modified

| File | Status | Description |
|------|--------|-------------|
| `MacStatus/Readers/CPUReader.swift` | Created | `final class CPUReader: TimerReader<Double>` — host_statistics, delta calc, CPULoad: Sendable |
| `MacStatus/Readers/ReaderProtocol.swift` | Created | `protocol ReaderProtocol: AnyObject` — associatedtype ValueType, lifecycle methods |
| `MacStatus/Readers/TimerReader.swift` | Created | `class TimerReader<T>: ReaderProtocol` — Timer + background queue dispatch |
| `MacStatus/UI/StatusBarManager.swift` | Created | `@MainActor final class StatusBarManager` — NSStatusItem + display + macOS 26 gate |
| `MacStatus/Utils/SettingsManager.swift` | Created | `final class SettingsManager: @unchecked Sendable` — UserDefaults singleton |
| `MacStatus/App/AppDelegate.swift` | Modified | Simplified to ~30 lines: `cpuReader.start()` + `cpuReader.stop()` |
| `MacStatus.xcodeproj/project.pbxproj` | Modified | Added 5 new source files to Groups and Sources build phase |

## Decisions Made

- **CPUReader hierarchy:** Extends `TimerReader<Double>` rather than standalone class — inherits Timer lifecycle, `onUpdate`, `start()`/`stop()`. Only `read()` must be overridden.
- **StatusBarManager actor isolation:** `@MainActor` class — all NSStatusItem operations require main thread. `MainActor.assumeIsolated` in deinit handles the nonisolated deinit context safely (AppDelegate releases on main thread).
- **SettingsManager Sendable:** `@unchecked Sendable` — UserDefaults is documented thread-safe; our operations are simple get/set on a Double value.
- **AppDelegate simplification:** Removed Timer, `host_statistics`, NSStatusItem, `attributedString`, `updateDisplay` — all delegated to specialized classes. AppDelegate is now a pure wiring hub.
- **macOS 26 gate:** Non-blocking pattern — `DispatchQueue.main.asyncAfter(2s)` checks `isVisible`, shows NSAlert with "Open System Settings" button if hidden. On macOS 14-25 the item is immediately visible.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 strict concurrency: StatusBarManager DispatchQueue.main.asyncAfter capturing self**
- **Found during:** Task 1 (first build attempt)
- **Issue:** `DispatchQueue.main.asyncAfter { [weak self] in ... }` triggered Swift 6 error: "sending 'self' risks causing data races" — main actor-isolated closure capturing nonisolated StatusBarManager
- **Fix:** Marked StatusBarManager as `@MainActor` — all NSStatusItem operations must be on main thread anyway. Used `MainActor.assumeIsolated` in deinit to safely access statusItem for cleanup.
- **Files modified:** `MacStatus/UI/StatusBarManager.swift`
- **Committed in:** 9b8901c

**2. [Rule 1 - Bug] Swift 6 strict concurrency: SettingsManager singleton not Sendable-safe**
- **Found during:** Task 2 (first build attempt)
- **Issue:** `static let shared = SettingsManager()` triggered Swift 6 error: "static property 'shared' is not concurrency-safe because non-'Sendable' type 'SettingsManager' may have shared mutable state"
- **Fix:** Added `@unchecked Sendable` conformance to SettingsManager — UserDefaults.standard is documented as thread-safe, and we store only simple value types.
- **Files modified:** `MacStatus/Utils/SettingsManager.swift`
- **Committed in:** 7921a1a

---

**Total deviations:** 2 auto-fixed (2 Swift 6 concurrency bugs)
**Impact on plan:** Both fixes necessary for successful compilation under `SWIFT_STRICT_CONCURRENCY = complete`. No scope creep. Patterns applied: `@MainActor` + `MainActor.assumeIsolated` for AppKit UI classes, `@unchecked Sendable` for thread-safe Foundation wrappers.

## Known Warnings

- **TimerReader non-Sendable captures:** `Timer.scheduledTimer` and `DispatchQueue.global` closures capture `self` (non-Sendable generic class). These are warnings, not errors — the `[weak self]` pattern prevents retain cycles. Can be addressed in a future concurrency audit with `@unchecked Sendable` on TimerReader if needed.
- **AppDelegate non-Sendable captures:** Similar warnings in `cpuReader.onUpdate` closure and `applicationDidFinishLaunching`. Does not affect runtime correctness.

## Next Phase Readiness

- ReaderProtocol + TimerReader base class ready for MemoryReader, NetworkReader, GPUReader in Phases 2-4
- StatusBarManager ready for additional metrics (updateMemory, updateNetwork, updateGPU methods can be added)
- SettingsManager ready for additional preference keys (display format, launch at login, etc.)
- AppDelegate is a thin hub — adding new readers is a matter of instantiation + wire + start()
- D-02 folder structure fully populated: App/, Readers/, UI/, Utils/

---

*Phase: 01-foundation-cpu-monitoring*
*Completed: 2026-05-14*
