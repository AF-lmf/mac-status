# Project Research Summary

**Project:** MacStatus — v2.0 洞察与可定制 (Insight & Customization)
**Domain:** macOS menu-bar system monitor — feature additions to a shipped, non-sandboxed Developer-ID app
**Researched:** 2026-06-16
**Confidence:** HIGH

## Executive Summary

MacStatus v2.0 adds three capabilities on top of a shipped v1.0 menu-bar monitor: per-process Top-N CPU/memory in the existing popover, a battery & power segment, and a real settings window with live customization. All four research streams converge strongly: every feature is achievable with **zero new dependencies** using public/`libproc`/IOKit system APIs, the app **must stay non-sandboxed** (already true — v1.0 shells out to `nettop`), and **`task_for_pid` must never be used** (it would force a hardened-runtime debugger entitlement that pollutes notarization and still can't read other processes). The recommended approach is to extend the existing `MetricCollector` → `StatusBarManager`/`PopoverManager`/`SettingsManager` seams rather than introduce new architecture — only two new source files (`BatteryReader`, `ProcessSampler`) are needed; everything else threads new fields through existing types.

The single most important finding is a **clear, dependency-driven build order all four agents independently arrived at**: the settings persistence model + a *live re-apply seam* is the critical-path prerequisite (per-metric intervals need `MetricCollector.reconfigure()`; toggles/reorder need `StatusBarManager` to read an enabled-set/order — neither exists today, and there is currently a two-sources-of-truth bug where `SettingsView` uses raw `@AppStorage` while collectors read `SettingsManager`). Once that foundation lands, **battery and per-process are independent, parallelizable branches**, and the settings *UI* surfaces come last because they are the control surface for everything before them.

The key risks are all well-mapped. Per-process CPU must be **delta-based over real wall-clock time** (not cumulative rusage), guarded with `max(delta,0)` and a `(pid, start-time)` composite key against PID reuse, sampled off-main and strictly popover-gated. Battery requires **two APIs** — IOKit Power Sources for charge/state/time and the AppleSmartBattery IORegistry node for Watts/health — with unstandardized Watt sign/bit-width, `-1`/`-2` time-remaining sentinels, and model-varying keys that absent on desktop Macs, all handled by the proven v1.0 "nil-degrade the whole segment" pattern. The status bar stays **one combined `NSStatusItem` rebuilt wholesale each tick** — toggling/reordering is conditional segment composition over a `metricOrder`, never adding/removing status items.

## Key Findings

### Recommended Stack

Zero external packages. v2.0 links only frameworks already in the SDK (`libproc`, `IOKit`, `IOKit/ps`, `SwiftUI`, `AppKit`). The app stays non-sandboxed (Developer ID / DMG, not App Store) and Hardened Runtime stays on with **no new entitlements**. See STACK.md for full API tables.

**Core technologies:**
- `proc_listpids` + `proc_pidinfo(PROC_PIDTASKINFO)` / `proc_pid_rusage` (`<libproc.h>`) — per-process CPU ticks + RSS in-process, no port, no entitlement — chosen over `task_for_pid`+`task_info` which is entitlement-gated and notarization-hostile.
- IOKit Power Sources (`IOPSCopyPowerSourcesInfo`/`IOPSGetPowerSourceDescription`, `IOPSKeys`) — charge %, charging state, AC/battery, time-to-empty/full — the documented, stable battery surface.
- AppleSmartBattery IORegistry (`IORegistryEntryCreateCFProperty`: `InstantAmperage`×`Voltage`→Watts, `CycleCount`, `AppleRawMaxCapacity`/`DesignCapacity`→health) — the only source for live Watts + health; undocumented-but-stable keys, read defensively with nil-fallback (same category as v1.0 GPU `PerformanceStatistics`).
- `NSWindow` + `NSWindowController` + `NSHostingView` (SwiftUI `Form`/`List`) — the settings window. The SwiftUI `Settings` scene does NOT work in this `LSUIElement` AppKit-hosted app (Sonoma removed `showSettingsWindow:`); a manually-owned NSWindow is the clean fit, identical in spirit to the existing popover.
- `UserDefaults` via the existing `SettingsManager` + `Codable` JSON (with a `schemaVersion`) — all new prefs are key-value; no DB.

### Expected Features

**Must have (table stakes):**
- CPU Top 3–5 and Memory Top 3–5 in the popover — the #1 reason users open a monitor dropdown; replicates the existing `nettop` Top-5 pattern (MEDIUM effort, not HIGH).
- Battery card: charge %, charging state, time remaining — baseline of any battery indicator.
- Desktop-Mac graceful degradation — mandatory; gates ALL battery UI (Mac mini/Studio/iMac have no battery).
- Metric enable/disable toggles + preference persistence — the most-used setting and its prerequisite.
- Compact/verbose status-bar mode — the headline customization differentiator.

**Should have (competitive):**
- Real-time power draw (Watts) — the developer/power-user metric iStat charges for; reachable without SMC.
- Battery health % + cycle count — "is my battery degrading"; low effort once AppleSmartBattery is wired.
- Per-metric refresh interval, drag-reorder metrics, custom thresholds + colors — extend existing value-level coloring.
- Click process row → reveal in Activity Monitor — lightweight read-only escape hatch.

**Defer / anti-features (align with PROJECT.md Out of Scope):**
- In-popover kill/force-quit button — Stats #593 cautionary tale; keep MacStatus read-only.
- Full sortable/filterable process table; per-process GPU; per-process energy impact; Bluetooth peripheral battery.
- Notification/alert rules engine; SMC temperature; unit pickers; per-state conditional theming; profiles/presets; iCloud sync.

### Architecture Approach

No new layers. The live-data seam is `MetricCollector.tick()` (single `@MainActor` timer calling each reader's synchronous `readValue()` → `MetricSample` → RingBuffer/HistoryStore/`DashboardState`/`StatusBarManager`). On-demand popover detail goes through `PopoverManager` + `Task.detached(.utility)`. Config goes through `SettingsManager`. v2.0 adds two files and threads new fields/keys through existing types.

**Major components:**
1. `BatteryReader: TimerReader<BatteryStats?>` (NEW) — synchronous `readValue()` on the collector tick; IOPS + AppleSmartBattery; returns `nil` on desktop (the GPU nil-stats pattern).
2. `ProcessSampler` (NEW, stateless enum) — on-demand Top-N CPU/mem via `libproc`, mirroring `ProcessNetworkReader`; invoked only while the popover is visible, off-main, returning `Sendable` value snapshots.
3. `SettingsManager` (MODIFIED) — single source of truth (kill the `@AppStorage` duplication), new keys (`metricOrder`, per-metric enabled/interval, custom colors), `schemaVersion`/migration, and a NotificationCenter change-broadcast.
4. `MetricCollector` (MODIFIED) — add `reconfigure()` (invalidate+rebuild the single timer; per-metric interval via tick-counter modulo) and `applyNow()` (re-push last sample) for the live re-apply seam.
5. `StatusBarManager` / `DashboardState` / `ProcessListView` (MODIFIED) — battery segment+card, generalized Top-N row, honor enabled-set/order/colors over a `metricOrder`.

### Critical Pitfalls

1. **`task_for_pid` for per-process stats** — entitlement-gated, can't read other processes, pollutes notarization. Avoid entirely; use `libproc`, assert no debugger entitlement in the build script.
2. **Cumulative rusage shown as instantaneous CPU%** — long-lived processes would dominate. Diff two snapshots over **real wall-clock** delta (CLOCK_MONOTONIC, not the configured interval); first sample shows "—".
3. **PID disappearance/reuse** — check every return code, `max(delta,0)`, key the cache by `(pid, start-time)`, prune vanished PIDs each round to avoid unbounded growth.
4. **Battery `-1`/`-2` time-remaining + unstandardized Watt sign/bit-width + model-varying health keys + desktop absence** — three-state time handling, two's-complement reinterpret + mA·mV→W + sign sanity check, multi-key health fallback, and detect-no-battery → degrade the whole segment (GPU pattern). Delay trusting estimates ~5s after wake.
5. **Settings live re-apply hazards** — changing an interval must invalidate the old timer (idempotent `setInterval`, `[weak self]`) or it leaks/double-fires; toggling/reorder must rebuild the one `NSStatusItem`'s segments (recompute fixed width), never add/remove items (flicker/ghost icons); UserDefaults needs a `schemaVersion` + migration before new keys land.

## Implications for Roadmap

All four agents converged on the same dependency-aware order. Suggested phases:

### Phase 1: Settings Foundation + Live Re-apply Seam
**Rationale:** Critical-path prerequisite — per-metric intervals need `MetricCollector.reconfigure()` and toggles/reorder need `StatusBarManager` to read an enabled-set/order; neither exists today, and the `@AppStorage`-vs-`SettingsManager` two-sources-of-truth bug must be reconciled first.
**Delivers:** `SettingsManager` as the single typed store (+ `schemaVersion`/migration, change broadcast); `MetricCollector.reconfigure()`/`applyNow()`; `TimerReader.setInterval` (idempotent, `[weak self]`); `StatusBarManager` honoring enabled-set/order over `metricOrder` (segment composition on one `NSStatusItem`).
**Addresses:** preference persistence, metric toggles, reorder, per-metric interval, compact/verbose mode (FEATURES table stakes + differentiators).
**Avoids:** Pitfalls 9 (timer leak on interval change), 10 (status-bar rebuild flicker/ghost), 11 (no schema version), 12 (LSUIElement settings window).

### Phase 2: Battery & Power
**Rationale:** Independent, low-risk; the desktop nil-degradation is the proven v1.0 GPU pattern. B1/B2 (reader + data) can start in parallel with Phase 1; B3/B4 (status segment + card) are cleaner once Phase 1's enabled/order/color plumbing exists.
**Delivers:** `BatteryReader: TimerReader<BatteryStats?>` (IOPS + AppleSmartBattery), `MetricSample` battery columns, status-bar battery segment, popover battery card (+ optional charge sparkline).
**Uses:** IOKit Power Sources (charge/state/time) + AppleSmartBattery IORegistry (Watts/health/cycles).
**Implements:** the new `BatteryReader` on the collector tick; whole-segment degradation on desktop.
**Avoids:** Pitfalls 6 (`-1`/`-2` time), 7 (Watt sign/bit-width/units), 8 (model-varying health keys + desktop crash).

### Phase 3: Per-Process Top-N CPU & Memory
**Rationale:** Fully self-contained; depends only on the existing `ProcessNetworkReader` on-demand pattern, not on Phase 1. Parallelizable with Phase 2.
**Delivers:** `ProcessSampler` (libproc Top-N, delta CPU%, `Sendable` result), generalized `ProcessListView` + `DashboardState.topCPU/topMemProcesses`, popover-open-triggered sampling (detached, cancel on close).
**Uses:** `proc_listpids` + `proc_pidinfo`/`proc_pid_rusage`.
**Implements:** stateless on-demand sampler gated strictly on popover visibility (NOT on the collector tick).
**Avoids:** Pitfalls 1 (task_for_pid), 2 (cumulative-as-instantaneous), 3 (PID reuse), 4 (permission boundary / no privileged helper), 5 (main-thread enumeration + Sendable).

### Phase 4: Settings UI Polish for the New Features
**Rationale:** The control surface for everything before it — must come after the model (Phase 1) and after the features exist (Phases 2–3) so there is something concrete to toggle/order/color.
**Delivers:** `SettingsView` sections — enable/reorder `List{}.onMove`, per-metric interval pickers, `ColorPicker` color wells, threshold editors, battery/process toggles — wired to the Phase 1 `SettingsManager` + broadcast.
**Avoids:** re-introducing raw `@AppStorage` (Anti-Pattern 3).

### Phase Ordering Rationale
- **Critical path is 1 → 4.** Phases 2 and 3 are parallelizable branches that only need Phase 1's plumbing for their *display* polish, not their core reader/sampler work. If single-threaded: 1 → 2 → 3 → 4.
- Grouping follows the architecture seams: live-tick readers (battery) vs on-demand sampler (per-process) vs config/UI — keeping the "zero new architecture" property the v1.0 retrospective credited.
- A cross-cutting concern threads all phases: every new reader must implement the v1.0 sleep/wake recovery (`prepareForSleep`/`recoverFromWake`) and emit only `Sendable` snapshots across actor boundaries (Pitfall 13) — fold this into each reader's success criteria, not a separate phase.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 2 (Battery):** MEDIUM-confidence area — AppleSmartBattery Watt sign/bit-width and health-key names vary by model (AS vs Intel) and are absent on desktop; needs a real-device matrix (AS laptop + desktop Mac + Intel laptop if available) and `ioreg -arc AppleSmartBattery` verification. Consider `/gsd-plan-phase --research-phase`.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Settings):** well-documented NSWindow/UserDefaults/NotificationCenter patterns; the hard parts are codebase-specific reconciliation, already mapped in ARCHITECTURE.md.
- **Phase 3 (Per-Process):** libproc path is HIGH confidence and the `ProcessNetworkReader` pattern is an in-repo template.
- **Phase 4 (Settings UI):** standard SwiftUI `Form`/`List`/`ColorPicker`.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Public/libproc/IOKit APIs verified against Apple forums, `IOPSKeys.h`, exelban/stats reference impl; only AppleSmartBattery keys are undocumented-but-stable. |
| Features | HIGH | Competitor behavior verified via Stats issues/releases + iStat Menus docs; complexity grounded in existing popover/nettop/coloring infra. |
| Architecture | HIGH | Grounded in directly-read source, not training data; integration seams keyed to real classes. |
| Pitfalls | HIGH | Per-process and settings pitfalls HIGH (Apple forums + v1.0 precedents); battery Watt/health specifics MEDIUM (community-sourced, model-dependent). |

**Overall confidence:** HIGH

### Gaps to Address
- **Battery Watts/health on heterogeneous hardware (MEDIUM):** sign convention, bit-width, and key names are model-dependent. Handle via probe-and-nil + sign sanity check + real-device matrix testing during Phase 2; never strong-unwrap.
- **Per-metric interval scheduling model:** the single-timer-with-modulo-gating approach is recommended but unproven in this codebase — validate during Phase 1 that GCD/min-interval ticking honors per-metric cadence without skew.
- **libproc under Swift 6 strict concurrency:** if C structs/handles prove awkward to keep off the actor boundary, the documented fallback is spawning `/bin/ps` with the existing `ProcessNetworkReader` scaffolding — prefer libproc, keep `ps` in pocket.

## Sources

### Primary (HIGH confidence)
- Apple Developer Forums (655349 process CPU, task_for_pid error 5, process-info-listpids sandbox) — libproc over task_for_pid; non-sandboxed requirement.
- Apple `IOPSKeys.h` + IOPS documentation (`IOPSCopyPowerSourcesInfo`, `IOPSGetTimeRemainingEstimate`, `kIOPSTimeRemainingUnknown`) — battery state/time.
- exelban/stats Battery module + iStat Menus 7 docs — IOPS-vs-AppleSmartBattery split; competitor feature/anti-feature baseline (Stats #593 kill button).
- Peter Steinberger "Showing Settings from macOS Menu Bar Items" (2025) — Sonoma removed `showSettingsWindow:`; NSWindow+NSHostingView is the clean route.
- MacStatus source + `.planning/milestones/v1.0-research/*` + RETROSPECTIVE.md — ground-truth integration seams and established patterns.

### Secondary (MEDIUM confidence)
- RehabMan AppleSmartBattery driver / SocPowerBuddy / macsmc-power — current/Watt sign & bit-width, Apple Silicon capacity-unit differences.
- PowerManagement `BatteryTimeRemaining.c` — post-wake estimate discontinuity / delayed publication.
- osquery #7459 — Apple Silicon per-process user/system time anomalies.

### Tertiary (LOW confidence)
- None load-bearing; undocumented AppleSmartBattery key strings are live-verifiable via `ioreg` and treated as optional/nil-degrading.

---
*Research completed: 2026-06-16*
*Ready for roadmap: yes*
