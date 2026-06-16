# Project Research Summary

**Project:** MacStatus — macOS Menu Bar System Monitor
**Domain:** macOS status bar system monitoring (native)
**Researched:** 2026-05-14
**Confidence:** HIGH

## Executive Summary

MacStatus is a **macOS menu bar system monitor** — a lightweight, native Swift application that displays CPU, memory, network, and GPU utilization directly in the menu bar. The target audience is Chinese-speaking Mac users who want at-a-glance system resource awareness without the overwhelming configuration panels and feature bloat of existing tools like iStat Menus.

Experts build menu bar monitors using **AppKit's `NSStatusBar` API** for the menu bar lifecycle and **direct Mach/IOKit C-level system calls** for metrics — zero external dependencies are needed, and the Stats project (exelban/stats, 38.8k GitHub stars) proves this approach is production-grade. The recommended architecture is a single-target Xcode project with a **Reader→Widget callback pipeline**: dedicated `Reader` classes poll system APIs on background queues, then fan out typed data to display `Widget` views via closure callbacks. This decouples data gathering from presentation and makes each metric independently testable.

Key risks center on **GPU monitoring** (IOReport APIs are sparsely documented and Apple Silicon-specific), **NSStatusItem lifecycle management** (retain cycles create ghost icons that accumulate in the menu bar), and **sleep/wake state handling** (sensor data freezes after lid-open without explicit `didWakeNotification` re-initialization). All three are preventable with patterns proven in Stats' source code. The combined research strongly recommends a phased build: foundation + CPU first (validates the pipeline at lowest risk), then network + memory (user-visible differentiators), then GPU (highest-risk, isolated behind a protocol for graceful degradation), followed by combined display polish and launch-at-login quality-of-life features.

## Key Findings

### Recommended Stack

The stack is deliberately minimal — **zero external dependencies for core functionality**. Swift 6.x + Xcode 26.x (current as of May 2026) with AppKit for `NSStatusBar` lifecycle and direct Mach/IOKit C API calls for all system metrics. SwiftUI is reserved for the optional settings panel only; menu bar content must use AppKit `NSView` subclasses because `MenuBarExtra` cannot render dynamic, frequently-updating custom views. A single Xcode target (not SPM modules) is recommended for v1 — folder grouping preserves modular code architecture without build-system complexity.

**Core technologies:**
- **Swift 6.x + AppKit (NSStatusBar):** Non-negotiable for menu bar apps. `NSStatusBar.system.statusItem(withLength:)` is the only API that supports arbitrary `NSView` content with live text updates. SwiftUI `MenuBarExtra` cannot render dynamic gauges or frequently-updating custom views.
- **Mach Kernel APIs (`host_statistics`, `host_processor_info`):** CPU and memory readings directly from the kernel — zero overhead, well-documented, stable across macOS versions. Used by every production menu bar monitor.
- **IOKit (`IOServiceGetMatchingServices` / `IOAccelerator`):** GPU utilization on both Apple Silicon and Intel. Standard production path used by Stats and iStat Menus. IOReport for GPU *pressure* on Apple Silicon is sparsely documented but represents a genuine technical differentiator.
- **`getifaddrs()` + SystemConfiguration:** Network bandwidth via BSD-layer interface byte counters with delta calculation. Combine with `SCDynamicStoreCopyValue` to dynamically detect the primary network interface (avoid the "en0 is always Wi-Fi" trap).
- **`SMAppService.mainApp.register()` (macOS 13+):** Single API call for launch-at-login — replaces the legacy helper-app pattern. Our macOS 14+ deployment target makes this safe.
- **`LSUIElement = YES`:** Hides Dock icon entirely — non-negotiable for a pure menu bar app.
- **`UserDefaults` (not CoreData/SwiftData):** Sufficient for ~5 preference keys. Overhead of a persistence framework is unwarranted.

### Expected Features

The competitive landscape is dominated by **Stats** (free, 38.8k stars, feature-comprehensive) and **iStat Menus** (premium, kitchen-sink feature set). MacStatus competes on **focus and simplicity**, not breadth. The core differentiator is a **single combined menu bar item** displaying all four metrics in compact text — saving precious menu bar space vs. competitors' 5+ separate items. A **Chinese-first design** fills an underserved niche: no actively maintained Chinese-native menu bar monitor exists.

**Must have (table stakes — P1, v1.0):**
- **CPU usage %** — Every system monitor starts here; simplest and most reliable metric
- **Memory usage** — Displayed as used GB / total GB; critical for Apple Silicon users with limited RAM
- **Network up/down rate** — Delta-calculated bandwidth in KB/s or MB/s; most user-visible differentiator
- **GPU usage** — Basic utilization % via IOKit; Apple Silicon differentiator; graceful degradation on Intel
- **Launch at login** — Without auto-start, users try the app once and forget it exists
- **Single combined menu bar item** — All four metrics in one compact text: `CPU 12% · MEM 8.2G · ↓2.1M ↑512K · GPU 34%`
- **Zero-config operation** — Sensible defaults; works immediately on first launch
- **Menu bar only (no Dock icon)** — `LSUIElement = YES`
- **Light/Dark mode compatible** — System colors + `NSColor.labelColor` for automatic adaptation

**Should have (differentiators — P2, v1.x):**
- **GPU pressure color coding** (green/yellow/red) — Apple Silicon-only; adds urgency awareness without dropdown
- **Adaptive refresh frequency** — Slow polling on battery/low-power mode; normal speed on AC power
- **Compact mode** — Let users choose which metrics appear for ultra-narrow menu bars
- **English localization** — Broadens audience with minimal effort

**Defer (v2+):**
- Historical charts / performance graphs (destroys simplicity)
- CPU temperature / fan speed (SMC API lockdowns; Stats maintainer abandoned this)
- Per-app process breakdown (complex UI + I/O overhead)
- Custom notification rules (significant infrastructure)
- Battery display, customizable formats, color themes

### Architecture Approach

**Three-layer pipeline architecture** proven by Stats: **Reader Layer** (system API polling on background queues) → **Module/Wiring Layer** (callback-based fan-out to display components) → **Presentation Layer** (`NSStatusItem` + `NSView` widgets). Each resource type gets an independent Reader with its own polling interval (CPU at 1-2s, network at 1s, memory at 2-3s, GPU at variable). Readers are protocol-conformant and independently testable. Widgets are pure display components that know nothing about data sources — the same `TextWidget` can display CPU%, memory GB, or network speed depending on what value is pushed to it.

**Major components:**
1. **StatusBarManager** — Creates/destroys `NSStatusItem` instances; manages `autosaveName` for position persistence; must implement `deinit` with `removeStatusItem` to prevent ghost icons (Pitfall #1)
2. **ReaderProtocol + TimerReader base** — Generic reusable timer infrastructure: fires on background queue, calls system APIs, dispatches typed results to main thread via closure callback. Handles Mach API error checking and stale-data fallback (Pitfall #2, #3)
3. **Per-metric Readers** (CPUReader, MemoryReader, NetworkReader, GPUReader) — Each encapsulates one system API: `host_processor_info`, `host_statistics64`, `getifaddrs` + delta calc, IOKit `IOAccelerator`. CPU is simplest and validates the pipeline first; GPU is riskiest and must degrade gracefully
4. **TextWidget** — `NSView` subclass added to `NSStatusItem.button`; compares new value to last displayed (with tolerance) to avoid unnecessary redraws (Pitfall #8, Performance Trap #1)
5. **SettingsManager** — `UserDefaults` wrapper; no SwiftUI settings window in v1 (by design — "no decisions" philosophy)

**Key anti-patterns to avoid:**
- Polling on the main thread (blocks UI for 1-5ms per read)
- Over-redrawing when values haven't changed meaningfully
- Not checking `kern_return_t` on Mach API calls (crashes or NaN display)
- One giant reader doing all metrics (different polling frequencies per metric)
- Hardcoding "en0" as the network interface

### Critical Pitfalls

1. **NSStatusItem retain cycles → ghost icons:** System holds strong reference to `NSStatusItem`. If `StatusBarController` doesn't call `NSStatusBar.system.removeStatusItem(_:)` in `deinit`, orphaned icons accumulate in the menu bar on every restart. **Prevent:** Always implement `deinit` with cleanup; use `autosaveName` instead of recreating items.

2. **Sleep/wake sensor data freeze:** After Mac lid-close/reopen, IOKit services and kernel statistics may return stale or frozen values. **Prevent:** Listen on `NSWorkspace.didWakeNotification`; re-open IOKit services; mark data as stale and skip first post-wake reading; add "stuck data" detection (N consecutive identical readings triggers reconnect).

3. **High-frequency polling CPU/battery drain:** Even small mach calls per tick compound over 24/7 operation. **Prevent:** Default to 2-3s intervals; separate data collection frequency from UI refresh frequency; slow to 5s+ on battery; use `RunLoop.Mode.common` to avoid timer suppression during UI interactions.

4. **Hardcoded network interface names:** Assuming "en0" is always Wi-Fi breaks on VPN connection, USB-C ethernet, or interface reordering. **Prevent:** Use `SystemConfiguration` dynamic store to query `State:/Network/Global/IPv4` → `PrimaryInterface`; filter virtual interfaces (awdl, utun, bridge, gif, stf).

5. **Variable-width `NSStatusItem` layout jitter:** Dynamic text widths (e.g., "0 B/s" vs "125.3 MB/s") cause the status item and adjacent macOS icons to shift on every refresh. **Prevent:** Use fixed `statusItem.length` wide enough for worst-case text; use `.monospacedDigit()` font; compress format on notched MacBooks.

## Implications for Roadmap

Based on dependency analysis, architecture patterns, and pitfall prevention, the suggested phase structure follows a **risk-ascending build order**: validate the simplest pipeline first, then layer on progressively riskier metrics, then polish and QoL.

### Phase 1: Foundation + CPU Monitoring

**Rationale:** Every subsequent phase depends on a working AppKit lifecycle, NSStatusBar setup, and Reader→Widget pipeline. CPU is the simplest and best-documented metric — it validates the entire architecture with minimal risk. This phase proves end-to-end: a timer fires, calls a system API, formats the result, and displays it in the menu bar.

**Delivers:** Xcode project with LSUIElement set, AppDelegate with NSStatusBar initialization, StatusBarManager with proper `deinit` cleanup, `ReaderProtocol` + `TimerReader` base class, `CPUReader` using `host_processor_info()`, `TextWidget` showing "CPU 45%" in the menu bar, SettingsManager (UserDefaults wrapper). No Dock icon, no settings window, no other metrics.

**Addresses:** CPU usage % display (P1), Menu bar only (P1), Light/Dark mode (P1), Zero-config (P1), Low CPU overhead (P1, validated baseline).

**Must avoid:** Pitfall #1 (ghost icons — implement `deinit` from day one), Pitfall #4 (LSUIElement conflicts — test activation workflow immediately), Anti-pattern #1 (main thread polling — Reader must use background queue), Anti-pattern #3 (unchecked Mach return codes).

**Research flag:** LOW — Standard patterns, well-documented APIs. Skip `/gsd-research-phase`.

### Phase 2: Network + Memory Monitoring

**Rationale:** Network rate display is the most user-visible differentiator — users love seeing download/upload speeds in the menu bar. It validates the delta calculation pattern (storing previous readings, computing rate from counter changes) which is architecturally significant. Memory is straightforward and a fast follow. Grouping these together keeps momentum after the CPU pipeline is proven. Network is placed before GPU because GPU is the riskiest metric and should not block visible progress.

**Delivers:** `NetworkReader` with `getifaddrs()` + `SystemConfiguration` primary interface detection, delta calculation for bandwidth rate, filtering of virtual interfaces (awdl, utun, bridge, etc.), `MemoryReader` with `host_statistics64()` for used/free/total, formatted display text (e.g., "↓2.1M ↑512K" and "MEM 8.2G/16G"), wired to TextWidgets in the status bar.

**Addresses:** Network up/down rate (P1), Memory usage (P1), Adaptive refresh infrastructure (P2 prep).

**Must avoid:** Pitfall #5 (hardcoded "en0" — use SystemConfiguration dynamic primary interface detection), Pitfall #2 (sleep/wake freeze — at minimum mark data stale on wake), Performance Trap #4 (cumulative byte division — use sliding delta window), Integration Gotcha: IOKit on main thread (background queue), Integration Gotcha: `host_statistics` wrap-around (use signed diff).

**Research flag:** MEDIUM for Network (SystemConfiguration primary interface detection has edge cases with VPNs and multi-homed networks). Skip research-phase for Memory (trivial).

### Phase 3: GPU Monitoring

**Rationale:** GPU is the riskiest metric. IOReport APIs are sparsely documented and Apple may change them with macOS updates. GPU pressure specifically requires Apple Silicon detection and different code paths than Intel. This phase should be isolated — if it fails or is deferred, the other three metrics still work. The Reader should return `nil` and display "--" when GPU data is unavailable (graceful degradation).

**Delivers:** `GPUReader` with IOKit `IOServiceGetMatchingServices` for `IOAccelerator` class, Apple Silicon vs Intel detection, utilization % extraction from `PerformanceStatistics` dictionary, GPU pressure query via IOReport (if feasible — may need spike), graceful degradation: display "GPU --" when unavailable, `nil` propagation to combined display.

**Addresses:** GPU usage (P1), GPU pressure for Apple Silicon (P2 differentiator).

**Must avoid:** Pitfall #6 (Sandbox vs IOKit — verify GPU reading works with Sandbox enabled; if not, make a deliberate decision about App Store vs DMG distribution), Crash on missing GPU data (return nil, never force-unwrap), Anti-pattern #5 (don't bundle GPU logic into a monolithic reader).

**Research flag:** HIGH — IOReport is sparsely documented; may need `/gsd-spike` to reverse-engineer the pressure metric key name from IOKit registry. Stats source code is the best reference but doesn't include GPU pressure. Consider a spike before or during this phase.

### Phase 4: Combined Display + Formatting Polish

**Rationale:** The combined single menu bar item is MacStatus's core UX differentiator. This phase takes the four independently working readers and merges their output into one compact status bar text. Formatting utilities (byte formatters, percentage helpers, monospaced digit formatting) are built here. Fixed-width layout prevents menu bar jitter.

**Delivers:** `CombinedStatusView` that receives updates from all four readers, string formatting: `"CPU 12% · MEM 8.2G · ↓2.1M ↑512K · GPU 34%"`, fixed-width `NSStatusItem` to prevent layout jitter, monospaced digit font for stable column widths, tolerance-based redraw skipping (don't redraw if values haven't changed > 0.5%), dark/light mode text color adaptation, truncation strategy for narrow menu bars / notched MacBooks.

**Addresses:** Combined single menu bar item (P1, key differentiator), fixed-width display (Pitfall #8).

**Must avoid:** Pitfall #8 (variable-width jitter — use fixed `statusItem.length`), Performance Trap #1 (over-redrawing — cache last values with tolerance), UX Pitfall: low contrast in dark mode (use `NSColor.labelColor`), UX Pitfall: settings window on left-click (right-click for menu, left-click reserved for future popover).

**Research flag:** LOW — Standard AppKit layout. Skip research-phase.

### Phase 5: Launch at Login + Quality of Life

**Rationale:** Auto-launch is table stakes — without it, users stop using the app. Sleep/wake handling prevents the #1 post-launch bug (frozen data after lid-open). Adaptive refresh delivers the "no CPU impact" promise. This phase ties up loose ends from Pitfalls research that weren't critical for the core monitoring pipeline.

**Delivers:** `SMAppService.mainApp.register()` for launch at login, `NSWorkspace.willSleepNotification` / `didWakeNotification` handlers (pause/resume timers, re-open IOKit services, mark data stale on wake), adaptive refresh: reduce to 5s on low power mode / battery, normal 2s on AC, right-click `NSMenu` with Quit option (Preferences entry reserved for v2), "stuck data" detection (N consecutive identical readings triggers recovery), `applicationShouldHandleReopen` to prevent ghost window on Dock click.

**Addresses:** Launch at login (P1), Adaptive refresh frequency (P2), Right-click menu (basic QoL), Sleep/wake data recovery (bug prevention).

**Must avoid:** Pitfall #7 (SMAppService compatibility — verify on macOS 14 and 15, check `statusItem.button != nil` at launch since auto-start may race with system status bar initialization), Pitfall #2 (sleep/wake freeze — implement proper `didWakeNotification` with delayed recovery for network), Pitfall #3 (polling overhead — validate with Activity Monitor: <1% CPU after 30 minutes), Security Mistake: `NSApp.activate(ignoringOtherApps: true)` while user is in fullscreen.

**Research flag:** LOW — Standard APIs, well-documented patterns. Skip research-phase.

### Phase Ordering Rationale

- **Foundation + CPU first** because every other metric depends on the Reader→Widget pipeline working end-to-end. CPU is the lowest-risk, best-documented metric — it validates the architecture before investing in riskier metrics.
- **Network before GPU** because network is the most user-visible differentiator (people love seeing bandwidth in the menu bar) and validates the delta calculation pattern that's architecturally significant. GPU is isolated as the riskiest phase and can be deferred without blocking other functionality.
- **Memory alongside Network** because it's low-complexity and fast to implement — grouping maintains momentum without adding risk.
- **Combined display after all readers** because the combined string depends on all four metrics producing data. However, the combined display should handle partial data gracefully (show "--" for any missing metric) so it can ship before GPU if needed.
- **QoL last** because auto-launch, sleep handling, and adaptive refresh are polish items that don't block the core monitoring experience but are essential for production readiness.

### Research Flags

Phases likely needing deeper research or spikes during planning:

- **Phase 3 (GPU Monitoring):** IOReport API for GPU pressure is sparsely documented. Consider a `/gsd-spike` before this phase to reverse-engineer the pressure metric key from the IOKit registry. Apple Silicon vs Intel code paths may diverge significantly. **Recommendation:** Run `/gsd-research-phase` or a dedicated spike before Phase 3 planning.
- **Phase 2 (Network):** SystemConfiguration primary interface detection has edge cases (VPNs, multi-homed Macs). The happy path is well-understood but edge cases may surface during testing. **Recommendation:** Plan for extra testing time; no dedicated research phase needed.

Phases with standard, well-documented patterns (skip dedicated research):

- **Phase 1 (Foundation + CPU):** Mach APIs (`host_processor_info`, `host_statistics`) are stable, well-documented, and verified in Stats source code. NSStatusBar lifecycle is standard AppKit. No research needed.
- **Phase 4 (Combined Display):** Standard AppKit layout and text formatting. No research needed.
- **Phase 5 (Launch + QoL):** SMAppService is a single API call with official documentation. NSWorkspace notifications are standard. No research needed.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Verified against Stats source code (38.8k stars, production app), Apple Developer docs, Xcode 26.x release notes. Core monitoring APIs (`host_statistics`, `getifaddrs`, IOKit `IOAccelerator`) are proven stable across macOS versions. |
| Features | HIGH | Competitor analysis verified via GitHub READMEs, official product pages, and Stats issue tracker. Feature prioritization grounded in real user expectations from 4 major competitors. Anti-feature decisions aligned with Stats maintainer's documented abandonment of SMC/fan control. |
| Architecture | HIGH | Three-layer Reader→Widget pipeline verified in Stats source code. Patterns (delta calculation, LSUIElement, background queue polling) are time-tested in production. Build order is dependency-driven and risk-ascending. |
| Pitfalls | HIGH | Sourced from Stats issues (#3203, #3199, #2977, #2768, etc.), MenuMeters issues (#314, #155), Apple Developer Forums, and Context7-verified Apple docs. Each pitfall maps to a specific phase and has a prevention strategy with working code patterns. |

**Overall confidence:** HIGH — All four research vectors point to the same conclusions. The Stats project provides a production-verified reference for every decision. No significant contradictions across research files.

### Gaps to Address

- **GPU pressure metric feasibility:** IOReport is sparsely documented and GPU pressure is an Apple Silicon-specific metric (not exposed in Activity Monitor's standard GPU view, only in the GPU History window). This is the single biggest unknown. **Handle during planning:** Run a spike before Phase 3 to determine feasibility. If too risky or unstable, fall back to GPU utilization % only (still a differentiator vs. free competitors that don't show GPU at all). See FEATURES.md dependency note: "GPU pressure requires IOReport — the riskiest implementation task."

- **Sandbox compatibility with IOKit GPU readings:** `host_statistics` (CPU/memory) works under App Sandbox. `getifaddrs` (network) works. IOKit GPU readings may or may not work. **Handle during planning:** Test GPUReader with Sandbox enabled during Phase 1 or 2 (before GPU phase begins). If Sandbox blocks it, make a deliberate decision: ship via DMG without Sandbox (like Stats), or limit to CPU/Memory/Network for App Store distribution.

- **macOS 26 (Tahoe) menu bar privacy control:** macOS 26 introduced a new requirement where apps must be explicitly allowed in System Settings → Menu Bar. **Handle during Phase 5:** Detect if the status item is not visible after auto-launch; show an onboarding alert directing users to the new permission. This affects only macOS 26+ users and does not require API changes.

- **Notched MacBook Pro testing:** Variable-width status items are particularly problematic on notched displays where menu bar space is limited. **Handle during Phase 4:** Verify on a 14"/16" MacBook Pro (or simulator). Use fixed-width items + compact format as mitigation. If testing hardware is unavailable, use `NSScreen.main?.safeAreaInsets.top > 0` as heuristic.

## Sources

### Primary (HIGH confidence)

- **exelban/stats** (GitHub, 38.8k stars, MIT license) — Primary reference implementation for all system monitoring: CPU (`Modules/CPU/readers.swift`), GPU (`Modules/GPU/reader.swift`), RAM (`Modules/RAM/readers.swift`), Network (`Modules/Net/readers.swift`), AppDelegate (`Stats/AppDelegate.swift`), and Kit module architecture (`Kit/module/`). Verified source code directly.
- **Apple Developer Documentation — NSStatusBar** (`developer.apple.com/documentation/appkit/nsstatusbar`) — Official reference for menu bar item lifecycle and `removeStatusItem(_:)`.
- **Apple Developer Documentation — SMAppService** — `SMAppService.mainApp.register()` for login item registration.
- **Apple Developer Documentation — Xcode Support** (`developer.apple.com/support/xcode/`) — Verified Xcode 26.5 is current as of May 2026.
- **Apple Activity Monitor User Guide** (`support.apple.com/guide/activity-monitor`) — Confirms GPU pressure is Apple Silicon-specific feature; validates which metrics macOS exposes natively.
- **Mach Kernel APIs** (`host_processor_info`, `host_statistics`, `host_statistics64`) — Used directly in Stats' readers; proven stable across macOS versions.

### Secondary (MEDIUM confidence)

- **Stats Issues** — #3203 (sensor stuck after sleep), #3199 (RAM unreadable), #3176 (settings window on click), #3148 (notch spacing), #2987 (icon position), #2977 (fan 100% after sleep), #2768 (no show on login), #2733 (high disk writes), #2407 (refresh interval not working). Real-world issue tracker validates pitfall severity.
- **MenuMeters Issues** — #314 (wrong Wi-Fi label), #155 (network interface identification). Legacy project confirms long-standing pitfalls.
- **Apple Developer Forums** — Multiple NSStatusItem array issue, LSUIElement + WindowGroup problem, Menu Bar App's Menu Not Working. Community reports confirm pitfall prevalence.
- **IOReport Framework** — Sparsely documented; Stats' GPU module is the best open-source reference. API may change with macOS updates.

### Tertiary (LOW confidence — needs validation)

- **Context7** — Used for Swift language documentation and macOS API lookups. Returned mostly unrelated snippets for system monitoring queries. Useful for confirming API signatures, not for domain-specific guidance.
- **GPU pressure metric availability** — Existence confirmed via Activity Monitor's GPU History window on Apple Silicon. IOKit registry key name is unverified; needs spike/experimentation during Phase 3.

---

*Research completed: 2026-05-14*
*Ready for roadmap: yes*
*Next step: `/gsd-new-milestone` to create ROADMAP.md from these findings*
