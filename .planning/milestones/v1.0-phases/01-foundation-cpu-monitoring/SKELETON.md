# Walking Skeleton — MacStatus

**Phase:** 1
**Generated:** 2026-05-14

## Capability Proven End-to-End

> A user launches the app and immediately sees their CPU usage percentage ("CPU 45%") updating live in the macOS menu bar, with no Dock icon, no windows, and zero configuration.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| App lifecycle | AppKit `@main` NSApplicationDelegate with `static func main()` | SwiftUI `App` protocol cannot create NSStatusBar items and `MenuBarExtra` cannot display dynamic text inline. AppKit is the only path for menu bar system monitors. [D-08, STACK.md] |
| Menu bar content | `NSAttributedString` set directly on `NSStatusBarButton.attributedTitle` | Simpler than custom NSView subclass for a single text metric. Uses `NSColor.labelColor` for automatic light/dark mode adaptation and `NSFont.monospacedDigitSystemFont` for stable digit widths. [D-04, D-07, RESEARCH.md A2] |
| CPU data source | `host_statistics()` with `HOST_CPU_LOAD_INFO` flavor | Returns aggregate CPU tick counters as stack-allocated `host_cpu_load_info` struct. Simpler than `host_processor_info()` — no `vm_deallocate` needed. Delta calculation against previous sample yields usage percentage. [RESEARCH.md §Core CPI Reader Decision] |
| Polling pattern | `Timer.scheduledTimer` at 2-second interval, reads execute on `DispatchQueue.global(qos: .utility)`, results dispatched to main thread via callback | Production-proven by Stats (exelban/stats, 38.8k stars). Separates data collection from UI updates. Avoids main-thread polling that causes UI jank. [D-05, ARCHITECTURE.md Pattern 1] |
| Preference storage | `UserDefaults` via `SettingsManager` singleton | Sufficient for ~5 simple key-value preferences (refresh interval, display format). No CoreData/SwiftData overhead. [RESEARCH.md §SettingsManager] |
| Build system | Single Xcode project (`.xcodeproj`), single macOS App target | SPM does not support macOS app targets with Info.plist, `LSUIElement`, and code signing. Single target avoids multi-module complexity for v1. [D-01, STACK.md Alternatives] |
| Deployment target | macOS 14.0 (Sonoma) minimum, build with Xcode 26.x | Matches PROJECT.md platform constraint. `SMAppService` (Phase 5) requires macOS 13+, well within range. [PROJECT.md, STACK.md] |
| Directory layout | `MacStatus/App/` (AppDelegate, Info.plist), `MacStatus/Readers/` (CPUReader, ReaderProtocol, TimerReader), `MacStatus/UI/` (StatusBarManager), `MacStatus/Utils/` (SettingsManager) | Matches locked decision D-02. Groups by architectural layer (Reader→UI) rather than feature, which works for a single-concern app where all modules share the same layers. [D-02] |

## Stack Touched in Phase 1

- [x] Project scaffold — Xcode project with macOS App target, Swift 6, deployment target 14.0
- [x] App lifecycle — AppKit `@main` AppDelegate with `static func main()`, `setActivationPolicy(.accessory)`
- [x] Menu bar presence — `NSStatusBar.system.statusItem(withLength:)` with `NSStatusItem.variableLength`
- [x] CPU data collection — `host_statistics(HOST_CPU_LOAD_INFO)` on background `DispatchQueue`, delta calculation with `&-` overflow-safe subtraction
- [x] Real-time display — `NSAttributedString` on `NSStatusBarButton.attributedTitle`, formatted as `"CPU XX%"`
- [x] Ghost icon prevention — `NSStatusBar.system.removeStatusItem(_:)` in `deinit`
- [x] Light/dark mode — `NSColor.labelColor` for automatic adaptation
- [x] Dev launchability — Xcode build & run (⌘R) — app appears in menu bar with live CPU data

## Out of Scope (Deferred to Later Slices)

- Network monitoring (`getifaddrs`, `SCDynamicStoreCopyValue`) — Phase 2
- Memory monitoring (`host_statistics64`) — Phase 2
- GPU monitoring (IOKit `IOAccelerator`) — Phase 3
- Combined display layout (multi-metric single status item) — Phase 4
- Settings window (SwiftUI preferences) — Phase 4/5
- Launch at login (`SMAppService.mainApp.register()`) — Phase 5
- Right-click menu (Quit, Preferences) — Phase 5
- Sleep/wake recovery — Phase 5
- Per-core CPU breakdown — Future
- CPU temperature / fan speed (SMC) — Out of Scope (Apple locking SMC)

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this skeleton without altering its architectural decisions:

- **Phase 2: Network + Memory Monitoring** — Add two new readers (NetworkReader via `getifaddrs`, MemoryReader via `host_statistics64`) that plug into the existing Reader→StatusBarManager pipeline
- **Phase 3: GPU Monitoring** — Add GPUReader via IOKit `IOAccelerator`, with graceful degradation on Intel Macs
- **Phase 4: Combined Display + Formatting** — Merge all metrics into one compact status item with fixed-width layout, auto-unit formatting
- **Phase 5: Launch at Login + Quality of Life** — `SMAppService` auto-start, sleep/wake recovery, right-click Quit menu
