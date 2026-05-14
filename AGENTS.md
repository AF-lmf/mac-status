<!-- GSD:project-start source:PROJECT.md -->
## Project

**MacStatus**

一个轻量级 macOS 菜单栏应用，在状态栏实时展示系统资源使用情况，包括网络上下行速率、CPU 占用率、内存使用量和 GPU 占用率/压力。面向需要持续监控系统状态的 macOS 用户（开发者、运维、重度用户）。

**Core Value:** 用户无需打开任何窗口，在菜单栏一眼就能看到当前系统资源的实时使用情况。

### Constraints

- **平台**: macOS 14+（Sonoma 及以上）
- **语言**: Swift
- **框架**: SwiftUI + AppKit（混合，菜单栏应用需要 AppKit 的 NSStatusBar）
- **性能**: 状态栏更新不能导致明显 CPU 消耗（采样间隔合理，避免高频轮询）
- **包体**: 尽量小，无外部依赖或最小依赖
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Core Technologies
| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Swift | 6.x (Language Mode Swift 6) | Programming language | Required by PROJECT.md; Swift 6 delivers strict concurrency safety (Sendable checking, data-race prevention) which directly benefits the multi-source polling architecture of a system monitor. Xcode 26+ ships Swift 6.2–6.3 as the current compiler. |
| Xcode | 26.x (26.3+) | IDE, toolchain, signing | Current stable as of May 2026. Supports macOS Sequoia 15.6+ development and can target macOS 14+ deployment. Ships Swift 6.2.3 compiler. |
| AppKit (Cocoa) | — (macOS SDK) | Menu bar lifecycle, NSStatusBar | **Non-negotiable for menu bar apps.** SwiftUI still lacks native `NSStatusBar` integration. The app must use `NSApplicationDelegate` with `NSStatusBar.system.statusItem(withLength:)` to create the menu bar item. This is the pattern used by every production menu bar monitor (Stats, iStat Menus, MenuMeters). |
| SwiftUI | 6 (macOS 14+) | Settings/preferences window | Use for the settings panel only. SwiftUI is lightweight for form-based preferences. Embedding SwiftUI views inside NSStatusItem button via `NSHostingView` is possible for the menu bar display if richer UI is needed, but plain `NSAttributedString` in `NSStatusBarButton` is simpler and lower-overhead. |
| Foundation | — (macOS SDK) | Core types, UserDefaults, Timer | `UserDefaults` for persisting user preferences (refresh interval, display format). `Timer.scheduledTimer` or `DispatchSourceTimer` for periodic data collection. |
### System Monitoring APIs (Zero External Dependencies)
| API | Purpose | How It Works | Source Confidence |
|-----|---------|-------------|-------------------|
| `host_statistics()` / `host_processor_info()` | CPU usage (total + per-core) | Mach kernel APIs. `host_processor_info` with `PROCESSOR_CPU_LOAD_INFO` gives per-core CPU states; `host_statistics` with `HOST_CPU_LOAD_INFO` gives aggregate. Compute delta between reads for percentage. | **HIGH** — Verified in Stats source (exelban/stats, 38.8k stars), Apple open source xnu kernel headers. |
| `host_statistics64()` + `host_info()` | Memory usage (used, free, pressure, swap) | `HOST_VM_INFO64` returns page counts (active, inactive, wired, compressed, etc.); `HOST_BASIC_INFO` returns total physical memory; `sysctlbyname("vm.swapusage")` for swap; `kern.memorystatus_vm_pressure_level` for memory pressure. | **HIGH** — Verified in Stats RAM module. |
| IOKit (`IOServiceGetMatchingServices`) | GPU utilization | Query `IOAccelerator` class services, read `PerformanceStatistics` dictionary for keys like `Device Utilization %`, `GPU Activity(%)`, `Renderer Utilization %`. Works for integrated (Apple Silicon), discrete (AMD), and Intel GPUs. | **HIGH** — Verified in Stats GPU module. This is the standard path; Metal Performance Counters require GPU frame capture and are not designed for live monitoring. |
| `getifaddrs()` + `if_data` | Network bandwidth (bytes in/out) | BSD-layer API. Iterates network interfaces via `getifaddrs()`, reads `ifa_data` cast to `if_data` for `ifi_ibytes`/`ifi_obytes`. Compute delta between reads divided by elapsed time for throughput. | **HIGH** — Verified in Stats Net module. This is the standard method; `nettop` command-line tool is heavier and requires admin privileges for some modes. |
| `SCDynamicStoreCopyValue` | Active network interface detection | SystemConfiguration framework. Reads `State:/Network/Global/IPv4` to find the primary network interface name. | **HIGH** — Verified in Stats Net module. |
### Launch at Login
| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `SMAppService` | macOS 13+ | Register as login item | **Use `SMAppService.mainApp.register()`** — single API call, no helper app needed, no entitlements complexity. Introduced in Ventura (macOS 13), well within our macOS 14+ target. This replaces the old `LaunchAtLogin` helper-app pattern (used by Stats, but Stats supports Big Sur+ so can't use it). |
| `LSUIElement` (Info.plist) | — | Hide Dock icon | Set to `YES` in Info.plist. Makes the app a pure menu bar app with no Dock presence. Required. |
### Development Tools
| Tool | Purpose | Notes |
|------|---------|-------|
| SwiftLint | Code style enforcement | Stats project uses `.swiftlint.yml`. Install via Homebrew: `brew install swiftlint`. Add a build phase script in Xcode. |
| Xcode Cloud / GitHub Actions | CI | For automated builds and testing. Xcode Cloud is free tier for small projects. |
| SF Symbols | Menu bar icons | Apple's system icon library. Use `NSImage(systemSymbolName:accessibilityDescription:)` for menu bar icons. Lightweight, no asset bundling needed. |
## Installation
# Clone and open in Xcode
# Or generate via xcodebuild
### What goes in the Xcode project:
## Alternatives Considered
| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| App lifecycle | AppKit `NSApplicationDelegate` | Pure SwiftUI `@main App` | SwiftUI `App` protocol cannot create `NSStatusBar` items — no `NSApplicationDelegate` lifecycle hooks for menu bar setup. Must use AppKit. |
| Menu bar item | `NSStatusBar.system.statusItem` | `MenuBarExtra` (SwiftUI, macOS 13+) | `MenuBarExtra` creates its own menu, but cannot display dynamic text/gauges inline in the menu bar the way system monitors need. `NSStatusBar` is the only API that supports arbitrary `NSView` content in the menu bar. |
| Launch at login | `SMAppService.mainApp.register()` | Helper app (LaunchAtLogin target) | Helper app pattern requires a separate target, code signing complexity, and extra binary. `SMAppService` is one line and macOS 13+ (our target is 14+). |
| GPU monitoring | IOKit `IOAccelerator` | Metal Performance Counters | Metal counters require active frame capture via `MTLCaptureManager` — designed for GPU debugging, not live monitoring. IOKit is the production path (used by Stats, iStat Menus). |
| Network monitoring | `getifaddrs()` + `if_data` | `nettop` command / `NWPathMonitor` | `nettop` incurs process-spawn overhead on every read; `NWPathMonitor` only reports connectivity state, not throughput. `getifaddrs` is a C call with near-zero overhead. |
| Data persistence | `UserDefaults` | CoreData / SwiftData | Overkill for simple key-value preferences (refresh interval, display format). UserDefaults is zero-setup and sufficient. |
| Build system | Xcode project (`.xcodeproj`) | Swift Package Manager (`Package.swift`) | SPM does not support macOS app targets with Info.plist, code signing, and `LSUIElement` configuration needed for menu bar apps. Xcode project is the standard. |
## What NOT to Use
| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Electron / React Native / Catalyst | Massive bundle size (100MB+), high memory baseline (~200MB idle), poor energy efficiency. A menu bar monitor must be near-invisible in resource usage. | Native Swift + AppKit |
| Third-party system monitoring libraries (SMCKit, SystemKit, etc.) | Adds dependency risk for functionality that's 20-50 lines of system C API calls. Every dependency is a future compilation breakage point on Xcode/Swift version bumps. | Call Mach/IOKit APIs directly — Stats project proves it's manageable |
| `nettop` / `top` / `ps` command calls for primary data | Process-spawn overhead (~1-5ms) per read cycle adds up. Parsing CLI output is fragile and locale-dependent. | Use C-level APIs (`host_statistics`, `getifaddrs`) directly |
| `Process()` for readings (at all in v1) | Same performance concern. Stats resort to `top` and `nettop` only for per-process details, not for aggregate metrics. | Direct Mach/IOKit calls |
| Swift Concurrency (`async/await`) for polling | Timer-based polling with callbacks is simpler and more predictable. Async/await adds `Task` management complexity without benefit for a polling pattern. | `Timer.scheduledTimer` with a dedicated serial `DispatchQueue` |
| SwiftData / CoreData | Overengineered for storing ~5 preference keys. | `UserDefaults` |
| Multiple frameworks/targets | Stats uses per-module frameworks for extensibility across 9+ modules with independent settings screens. For a v1 with 4 metrics and one settings panel, a single target is simpler. | Single Xcode target |
## Stack Patterns by Variant
- macOS 26 introduced a new privacy control: System Settings → Menu Bar, where apps must be explicitly allowed to display menu bar items. This is **only applicable on macOS 26+** and does not affect macOS 14-15 users.
- No API change needed — the user manually enables the app in System Settings. The app should detect if its status item is not visible and show an onboarding alert directing the user to System Settings → Menu Bar.
- Skip Intel GPU vendor detection in GPU monitor
- All Apple Silicon Macs running macOS 14+ have `IOAccelerator` with `AGX` class for GPU
- Fall back gracefully — return `nil` utilization and display "N/A" in menu bar
- Do not crash or show errors for missing GPU data
## Version Compatibility
| Dependency | Min Version | Max Version | Notes |
|------------|-------------|-------------|-------|
| macOS deployment target | 14.0 (Sonoma) | 26.x | Set in Xcode build settings |
| Xcode | 26.0 | 26.5 | Required to build with current tools |
| Swift language mode | Swift 6 | Swift 6 | Use `SWIFT_STRICT_CONCURRENCY = complete` for full Sendable checking |
| SMAppService | macOS 13.0 | — | Available on all our target OS versions |
## Sources
- **exelban/stats** (GitHub, 38.8k stars, MIT license) — Primary reference implementation. Verified source code for CPU (`Modules/CPU/readers.swift`), GPU (`Modules/GPU/reader.swift`), RAM (`Modules/RAM/readers.swift`), Network (`Modules/Net/readers.swift`), AppDelegate (`Stats/AppDelegate.swift`), LaunchAtLogin (`LaunchAtLogin/main.swift`), and Kit module architecture (`Kit/module/`). — **HIGH confidence**
- **Apple Developer — Xcode Support** (`developer.apple.com/support/xcode/`) — Verified Xcode 26.5 is current as of May 2026, with Swift 6.3 compiler. Xcode 26.3+ (Swift 6.2.3) runs on macOS Sequoia 15.6+. — **HIGH confidence**
- **Apple Developer Documentation — SMAppService** — `SMAppService.mainApp.register()` for login item registration. — **HIGH confidence**
- **Apple Developer Forums / HIG** — `LSUIElement = YES` in Info.plist for agent apps (no Dock icon). — **HIGH confidence**
- **Context7 — /swiftlang/swift** — Swift language documentation for concurrency features and C interop. — **MEDIUM confidence** (Context7 was used but returned mostly unrelated snippets for system monitoring queries)
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
