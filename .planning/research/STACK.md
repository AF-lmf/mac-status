# Stack Research — MacStatus v2.0 (Insight & Customization)

**Domain:** macOS Menu Bar System Monitor — feature additions to a shipped app
**Researched:** 2026-06-16
**Confidence:** HIGH
**Scope:** ONLY the native API additions needed for the three v2.0 features (per-process CPU/memory Top-N, battery/power, settings window). v1.0 stack (Swift 6, AppKit, IOKit GPU, Mach CPU/mem, getifaddrs networking, SMAppService, popover) is validated and NOT re-derived here — see `.planning/milestones/v1.0-research/STACK.md`.

## Hard Constraints Carried Forward

- **ZERO external dependencies.** Every addition below is a system framework already on the SDK (`libproc.h`, `IOKit`, `IOKit/ps`, `SwiftUI`, `AppKit`). No SPM/CocoaPods/Homebrew packages.
- **No private APIs that risk notarization.** All chosen symbols are public, documented in headers, and used by notarized App Store / Developer ID apps. Two areas (AppleSmartBattery registry keys, per-process sampling outside sandbox) are public-but-unsandboxed — called out explicitly below. The app is already **non-sandboxed** (it shells out to `nettop` for per-process network in v1.0), so the unsandboxed requirement is already satisfied and costs nothing new.
- **No `task_for_pid`.** Confirmed avoidable for all three features (see below).

---

## Recommended Stack Additions

### Feature 1 — Per-Process CPU & Memory Top-N

| API / Symbol | Header / Framework | Purpose | Why Recommended |
|--------------|--------------------|---------|-----------------|
| `proc_listpids(PROC_ALL_PIDS, 0, buf, size)` | `<libproc.h>` (libSystem) | Enumerate all PIDs | Public, no entitlement. Returns the full PID list in one call; allocate buffer sized by an initial zero-length probe call, then iterate. |
| `proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, sizeof(ti))` → `struct proc_taskinfo` | `<libproc.h>` | Per-process CPU ticks + resident memory in one call | **Single struct gives both metrics.** `pti_total_user` + `pti_total_system` are cumulative CPU time in **nanoseconds** (mach time already converted by the kernel for this flavor); `pti_resident_size` is RSS in bytes. CPU% is delta-based: `(Δ(user+system) / Δwallclock_ns) × 100` per process. |
| `proc_pidpath(pid, buf, PROC_PIDPATHINFO_MAXSIZE)` | `<libproc.h>` | Executable path → display name | For labeling the Top-N rows. Cheap; only call for the surviving top 3-5 after sorting, not for every PID. |
| `proc_name(pid, buf, size)` *(or last path component)* | `<libproc.h>` | Short process name | Fallback display name; `proc_name` truncates to ~16 chars, so prefer last component of `proc_pidpath` for readable names. |

**CPU% method (delta-based, mirrors v1.0 host_statistics pattern):**
1. Snapshot `{pid → (user+system) ns}` for all PIDs at time T0.
2. Snapshot again at T1.
3. Per-PID CPU% = `(ns_T1 − ns_T0) / (T1 − T0 in ns) × 100`. This is "% of one core"; divide by core count (or not) per the display convention chosen for v1.0 CPU.
4. Sort descending, take top N, resolve names only for those N.

**Memory method:** `pti_resident_size` (bytes) is an instantaneous read — no delta needed. Sort the same snapshot by RSS for the memory Top-N. One `proc_pidinfo` pass feeds both the CPU and memory lists.

**Entitlement / sandbox / `task_for_pid` analysis (the critical question):**
- ✅ **No `task_for_pid` required.** `proc_pidinfo`/`proc_listpids` are libproc syscalls that do NOT take a mach task port — they take a raw PID. `task_for_pid` is only needed for the `task_info`/`mach_*` family. Confirmed via Apple Developer Forums (thread 655349) and the libproc man pages.
- ✅ **No special entitlement** to read your own user's processes.
- ⚠️ **Other users' / root processes:** `proc_pidinfo` returns `0`/`ESRCH`/`EPERM` for processes you don't own (root-owned daemons, kernel_task). This is fine — silently skip them. Top consumers for an interactive desktop are almost always the current user's apps, so the Top-N is meaningful without root. **Do not** attempt privilege escalation.
- ⚠️ **App Sandbox would break this.** libproc process enumeration is blocked under the App Sandbox. The app is **already non-sandboxed** (v1.0 `nettop`), so this is a no-op constraint — but it must stay non-sandboxed (Developer ID / direct distribution, not Mac App Store). This is consistent with the existing project posture.
- ✅ **Notarization-safe.** libproc is fully public; no private symbol linkage.

**Why libproc over alternatives:** see Alternatives table. The short version — `proc_pidinfo(PROC_PIDTASKINFO)` returns CPU *and* RSS in one syscall with no port acquisition, vs `task_for_pid`+`task_info` which needs a port per PID and is entitlement-gated.

**Integration:** New `ProcessReader: TimerReader<[ProcessSample]>` holding the previous snapshot dictionary for delta computation (exactly the stateful-delta pattern the v1.0 CPU/network readers already use). It should run at a **lower frequency than the status-bar readers** (e.g. 2-3s, or only while the popover is open) because enumerating + sampling all PIDs is heavier than aggregate `host_statistics`. Gate sampling on popover visibility to keep idle cost near zero — the per-process data is only shown in the popover, never the status bar.

---

### Feature 2 — Battery & Power

Two complementary public APIs. **Neither one alone covers all required data** — this is the key finding. IOPS (high-level) is the stable source for charge/state/time; AppleSmartBattery (IORegistry node) is required for instantaneous Watts and health metrics.

#### Source A — IOKit Power Sources (`IOKit/ps`) — high-level, most stable

| Datum | Key / Function | Header |
|-------|----------------|--------|
| Power sources blob | `IOPSCopyPowerSourcesInfo()` → CFTypeRef | `<IOKit/ps/IOPowerSources.h>` |
| Per-source dictionary | `IOPSCopyPowerSourcesList()` + `IOPSGetPowerSourceDescription()` | `<IOKit/ps/IOPowerSources.h>` |
| Charge % | `kIOPSCurrentCapacityKey` ÷ `kIOPSMaxCapacityKey` (×100) | `<IOKit/ps/IOPSKeys.h>` |
| Charging state | `kIOPSIsChargingKey` (Bool) | `<IOKit/ps/IOPSKeys.h>` |
| On AC vs battery | `kIOPSPowerSourceStateKey` → `kIOPSACPowerValue` / `kIOPSBatteryPowerValue` | `<IOKit/ps/IOPSKeys.h>` |
| Time to empty | `kIOPSTimeToEmptyKey` (minutes; `-1` = calculating) | `<IOKit/ps/IOPSKeys.h>` |
| Time to full | `kIOPSTimeToFullChargeKey` (minutes) | `<IOKit/ps/IOPSKeys.h>` |
| Is present (desktop degrade) | `IOPSCopyPowerSourcesList` empty → no battery | — |
| AC adapter wattage (rated) | `IOPSCopyExternalPowerAdapterDetails()` → `kIOPSPowerAdapterWattsKey` | `<IOKit/ps/IOPowerSources.h>` |

**Stability:** These keys are documented in Apple's published `IOPSKeys.h` and are the **public, recommended** path. Use them for everything they cover. Desktop Macs (no battery) return an empty power-source list → trivial graceful degradation (hide the battery section).

**Important limitation:** The IOPS dictionary does **not** expose instantaneous draw in Watts, cycle count, or design capacity. `kIOPSPowerAdapterWattsKey` is the adapter's *rated* wattage, not actual draw. For those you must read Source B.

#### Source B — AppleSmartBattery IORegistry node — for Watts + health

Accessed via `IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))` then `IORegistryEntryCreateCFProperty(...)` per key. Framework: `<IOKit/IOKitLib.h>`.

| Datum | Registry Key | Notes |
|-------|--------------|-------|
| Instantaneous current | `InstantAmperage` (mA, signed; two's-complement when discharging) | Negative = discharging, positive = charging. |
| Voltage | `Voltage` (mV) | |
| **Instantaneous Watts** | `(InstantAmperage / 1000.0) × (Voltage / 1000.0)` | Derived. Sign indicates charge/discharge direction. This is the only way to get live power draw. |
| Cycle count | `CycleCount` (Int) | Battery health primary metric. |
| Raw current capacity | `AppleRawCurrentCapacity` (mAh) | Apple Silicon raw value. |
| Raw max capacity | `AppleRawMaxCapacity` (mAh) | Current full-charge capacity. |
| Design capacity | `DesignCapacity` (mAh) | |
| **Max-capacity health %** | `(AppleRawMaxCapacity / DesignCapacity) × 100` | Matches "Battery Health → Maximum Capacity". |
| Charging flag | `IsCharging` (Bool) | Redundant with IOPS; prefer IOPS key. |

**Stability / risk assessment:** These AppleSmartBattery keys are **not in Apple's documented public headers** — they are well-known, long-stable IORegistry property strings (inspectable live via `ioreg -arc AppleSmartBattery`). Reading IORegistry properties is a fully public operation (`IORegistryEntryCreateCFProperty` is public API); only the *key strings* are undocumented. This is the same category as the v1.0 GPU `PerformanceStatistics` keys (`Device Utilization %`), which the project already accepted and shipped. **Notarization is unaffected** — no private symbols are linked; you are reading a property dictionary by string key. Treat each key as optional: if a `CFProperty` lookup returns nil, degrade that datum (return `nil`, show "—"), exactly like the v1.0 GPU degradation path. On Apple Silicon the `AppleRaw*` keys are the correct ones (Intel sometimes used `MaxCapacity`/`CurrentCapacity` without the `Raw` prefix); since the target is macOS 14+ and primarily Apple Silicon, prefer `AppleRaw*` with `MaxCapacity`/`CurrentCapacity` as fallback.

**Recommended split:**
- Charge %, charging state, AC/battery, time-to-empty/full → **IOPS** (stable, documented).
- Instantaneous Watts, cycle count, design/max capacity, health % → **AppleSmartBattery registry**.
- Desktop degradation → IOPS empty list **or** `IOServiceMatching("AppleSmartBattery")` returns `MACH_PORT_NULL`.

**Integration:** New `BatteryReader: TimerReader<BatteryInfo?>`. Battery state changes slowly — sample at a relaxed interval (e.g. 5-10s) or, optionally, register `IOPSNotificationCreateRunLoopSource` for change-driven updates (public API, eliminates polling). For v2.0 simplicity, a slow timer reusing the existing `TimerReader<T>` lifecycle is sufficient and consistent. Return `nil` on desktop Macs → the popover battery card and any status-bar battery segment hide via the existing degradation convention.

---

### Feature 3 — Settings Window + Customization

| Technology | Framework | Purpose | Why Recommended |
|------------|-----------|---------|-----------------|
| `NSWindow` + `NSWindowController` hosting `NSHostingView(rootView:)` | AppKit + SwiftUI | The preferences window | **Recommended.** Build the settings UI in SwiftUI (forms, toggles, color pickers, drag-reorder `List`) and host it in a manually-managed `NSWindow`. The AppDelegate already owns app lifecycle; it opens/focuses this window from a menu item. Avoids every SwiftUI `Settings`-scene pitfall for agent apps. |
| `NSApp.setActivationPolicy(.regular)` ↔ `.accessory` (optional) | AppKit | Make the settings window focusable/frontmost | An `LSUIElement`/`.accessory` app's windows can't become key/front normally. Either temporarily switch to `.regular` while the window is open and back to `.accessory` on close, **or** call `NSApp.activate(ignoringOtherApps: true)` + `window.makeKeyAndOrderFront(nil)` + `window.level = .floating`. The policy-toggle is the robust pattern. |
| `UserDefaults` via existing `SettingsManager` | Foundation | Persist all preferences | **Reuse the shipped `SettingsManager` (@unchecked Sendable UserDefaults wrapper).** All new prefs — metric visibility set, metric order array, per-metric interval, custom thresholds/colors (store `NSColor`/hex), compact-vs-verbose mode enum — are key-value and belong here. No CoreData/SwiftData. |
| `Codable` structs → JSON in UserDefaults | Foundation | Structured prefs (ordered metric list, threshold tables) | Encode the ordered list of metric configs as a `Codable` array persisted as `Data`. Keeps `SettingsManager` typed and the drag-reorder state trivially serializable. |

**Why NOT the SwiftUI `Settings` scene:** Confirmed problem for AppKit-hosted agent apps on macOS 14+:
- Apple **removed** the legacy `showSettingsWindow:` / `showPreferencesWindow:` selectors in Sonoma; the only sanctioned openers are the SwiftUI-only `SettingsLink` view and the `openSettings` environment action — **both require an existing SwiftUI render tree**, which an AppKit `NSApplicationDelegate`-driven menu bar app does not have.
- The documented workaround (hidden SwiftUI `Window` scene + activation-policy juggling + `NotificationCenter` bridging, per Steinberger 2025) is *more* complex and fragile than just owning an `NSWindow`.
- A plain `NSWindow` + `NSWindowController` with an `NSHostingView` sidesteps all of it: the AppDelegate already manages the menu/popover, so adding "open settings" is one method that lazily creates and focuses the window. This is the cleanest fit for "AppKit-hosted with SwiftUI islands" — identical in spirit to the existing popover (which already hosts SwiftUI in AppKit).

**Integration:** A `SettingsWindowController` lazily instantiated by AppDelegate, opened from the existing right-click status-bar menu (add a "设置…" item alongside "退出"). The SwiftUI settings view reads/writes through `SettingsManager`; readers observe changed intervals/thresholds. Per-metric refresh interval maps directly onto each `TimerReader<T>`'s timer interval — expose a `setInterval(_:)` on the base class so the settings view can retune a reader live. Metric visibility/order and compact/verbose mode are consumed by the status-bar composition layer (AppDelegate) and the popover.

---

## Installation

No package manager. New code links only frameworks already available in the macOS SDK:

```swift
import Darwin          // libproc (proc_listpids, proc_pidinfo, proc_pidpath)
import IOKit           // IOServiceMatching, IORegistryEntryCreateCFProperty (AppleSmartBattery)
import IOKit.ps        // IOPSCopyPowerSourcesInfo, IOPSGetPowerSourceDescription, IOPSKeys
import SwiftUI         // settings view, hosted in NSHostingView
import AppKit          // NSWindow / NSWindowController / NSHostingView
```

`libproc` symbols come in via `import Darwin` (or a one-line bridging `#include <libproc.h>` if the Swift overlay doesn't surface a symbol). No new Info.plist entitlements. **Confirm App Sandbox stays OFF** (already the case).

---

## Alternatives Considered

| Recommended | Alternative | When the Alternative Wins (and why we still reject it here) |
|-------------|-------------|-----------------------------------------------------------|
| `proc_pidinfo(PROC_PIDTASKINFO)` (CPU+RSS in one call, no port) | `task_for_pid()` + `task_info(TASK_BASIC_INFO/TASK_THREAD_TIMES)` | task_info gives richer per-thread data — but requires acquiring a mach task port per PID, which is **entitlement-gated** (`com.apple.security.cs.debugger` or root) and breaks for other-user processes. Strictly worse for our needs; reject. |
| `proc_pid_rusage(pid, RUSAGE_INFO_V2/_CURRENT, &buf)` *(secondary)* | — | Also public, no `task_for_pid`; useful if disk-I/O or finer counters are later wanted. For v2.0 CPU%+RSS, `PROC_PIDTASKINFO` is simpler (one struct, both fields). Keep `proc_pid_rusage` in pocket for future. |
| libproc enumeration | Shell out to `ps -A -o pid,%cpu,rss,comm` / `top -l` | The v1.0 network Top-N already shells to `nettop`, so precedent exists — but `ps`/`top` add process-spawn cost (~ms) every cycle, locale-dependent parsing, and `top` smooths CPU oddly. libproc is in-process and exact. Prefer libproc; only fall back to a tool if a datum proves unavailable. |
| IOPS (`IOKit/ps`) for charge/state/time | AppleSmartBattery registry for *everything* | The registry can supply charge too, but IOPS is the documented/stable surface — use it for what it covers and only drop to the registry for Watts/health that IOPS lacks. |
| AppleSmartBattery registry for Watts/health | SMC keys (e.g. `B0AC`, `B0AV`) via `AppleSMC` | SMC reads give amperage/voltage too — but Apple is progressively **locking down SMC** (noted in v1.0 Out-of-Scope for temp/fans), and SMC access is fiddlier. Registry `InstantAmperage`×`Voltage` is simpler and lower-risk. |
| `NSWindow` + `NSHostingView` for settings | SwiftUI `Settings` scene + `SettingsLink`/`openSettings` | Only viable if the app were SwiftUI-`App`-lifecycle hosted. It is AppKit-hosted with no SwiftUI render tree, so the scene approach needs a hidden-window + activation-policy hack. Reject for complexity. |
| `UserDefaults`/`SettingsManager` + `Codable` | SwiftData / CoreData / property-list files | Overkill for key-value prefs. Reuse the shipped wrapper. |

---

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Any third-party package (SystemKit, SMCKit, Sparkle-style battery libs, sindresorhus/Settings, SettingsAccess) | Violates the zero-dependency constraint; each is a future Xcode/Swift-bump breakage point for ~50 lines of system calls. | Native libproc / IOKit / NSWindow as above. |
| `task_for_pid()` for per-process stats | Entitlement-gated, fails for non-owned processes, notarization/hardened-runtime friction. Unnecessary — `proc_pidinfo` covers it. | `proc_pidinfo(PROC_PIDTASKINFO)`. |
| Enabling App Sandbox | Would break libproc enumeration AND the existing `nettop` per-process network feature. | Keep the app non-sandboxed (Developer ID / direct distribution), as it already is. |
| Private/undocumented *functions* (vs property keys) | Notarization and future-OS risk. | Only public functions; undocumented *string keys* (AppleSmartBattery, GPU PerformanceStatistics) are acceptable and already in use — read defensively with nil-degradation. |
| SwiftUI `Settings` scene / `SettingsLink` / hidden-window activation hack | Doesn't fit an AppKit-hosted agent app; fragile, more code. | `NSWindow` + `NSWindowController` + `NSHostingView`. |
| Polling battery at status-bar cadence (1-3s) | Battery state changes slowly; wastes cycles. | 5-10s timer, or `IOPSNotificationCreateRunLoopSource` change notifications. |
| Sampling all PIDs continuously while popover is closed | Per-process enumeration is heavier than aggregate `host_statistics`; idle cost matters for a monitor. | Gate `ProcessReader` on popover visibility; lower interval (2-3s). |
| SMC for battery amperage/voltage | Apple is locking SMC down (same reason temp/fans are Out-of-Scope). | AppleSmartBattery `InstantAmperage`×`Voltage`. |
| Per-process GPU | No public API (already Out-of-Scope in PROJECT.md). | — |

---

## Version Compatibility (target macOS 14+)

| API | Min macOS | Notes |
|-----|-----------|-------|
| `proc_listpids` / `proc_pidinfo` / `proc_pidpath` / `proc_pid_rusage` | 10.5 / 10.9 | Long-stable libproc; fully available on 14+. Requires non-sandboxed process. |
| `IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceDescription` / `IOPSKeys` | 10.0+ | Documented public IOKit.ps. Available 14+. |
| `IOPSCopyExternalPowerAdapterDetails` | 10.9+ | Rated adapter wattage. |
| `IOServiceMatching("AppleSmartBattery")` + `IORegistryEntryCreateCFProperty` | 10.0+ | Public functions; key strings undocumented but stable. `kIOMainPortDefault` (renamed from `kIOMasterPortDefault` in macOS 12) — use `kIOMainPortDefault` for 14+. |
| `NSHostingView` | 10.15+ | SwiftUI-in-AppKit hosting; already used by v1.0 popover. |
| `NSApp.setActivationPolicy(.regular/.accessory)` | 10.6+ | For focusing the settings window in an agent app. |
| SwiftUI `Settings` scene `openSettings` action | 14.0+ | Noted only to explain why we avoid it. |

**`kIOMainPortDefault` note:** On macOS 14+ use `kIOMainPortDefault`; the old `kIOMasterPortDefault` is deprecated. The v1.0 GPU reader already calls IOKit, so confirm it uses the current spelling and match it.

---

## Sources

- **Apple Developer Forums — thread 655349** (Obtaining CPU usage by process) — confirmed `proc_pidinfo(PROC_PIDTASKINFO)` is the public path, **no `task_for_pid`**, works for own processes without entitlement, fails (skip) for non-owned, broken under sandbox. — **HIGH**
- **Apple Developer Forums — thread 769021 / 712711 / 128048** — libproc for other-process info; IOPS battery state/level patterns. — **MEDIUM/HIGH**
- **exelban/stats — Modules/Battery/readers.swift** (38.8k★, MIT; same reference impl validated for v1.0) — confirmed the IOPS-vs-AppleSmartBattery split per datum: charge/state/time via IOPS, Amperage/Voltage/CycleCount/MaxCapacity/DesignCapacity via AppleSmartBattery registry. — **HIGH**
- **Apple published `IOPSKeys.h`** (IOKitUser) — exact public key constants (`kIOPSCurrentCapacityKey`, `kIOPSMaxCapacityKey`, `kIOPSIsChargingKey`, `kIOPSPowerSourceStateKey`, `kIOPSTimeToEmptyKey`, `kIOPSTimeToFullChargeKey`, `kIOPSPowerAdapterWattsKey`). — **HIGH**
- **AppleSmartBattery IORegistry** (RehabMan/OS-X-ACPI-Battery-Driver; `ioreg -arc AppleSmartBattery`) — `InstantAmperage`, `Voltage`, `CycleCount`, `AppleRawMaxCapacity`, `AppleRawCurrentCapacity`, `DesignCapacity`; Watts = (InstantAmperage/1000)×(Voltage/1000). — **MEDIUM** (undocumented keys, but long-stable and live-verifiable). 
- **Peter Steinberger — "Showing Settings from macOS Menu Bar Items" (2025)** + **Apple Developer Forums 739831 / SerialCoder.dev** — confirmed Sonoma removed `showSettingsWindow:`; SwiftUI `Settings` scene requires a SwiftUI render tree and activation-policy hacks for agent apps → `NSWindow`+`NSHostingView` is the clean route. — **HIGH**
- **v1.0 STACK.md** (`.planning/milestones/v1.0-research/STACK.md`) — non-sandboxed posture (`nettop` precedent), `TimerReader<T>`/`SettingsManager`/`NSHostingView` patterns, GPU undocumented-key degradation precedent. — **HIGH**

---
*Stack research for: MacStatus v2.0 — per-process CPU/memory, battery/power, settings window. Zero-dependency, public-API-only, non-sandboxed Developer ID app, macOS 14+.*
*Researched: 2026-06-16*
