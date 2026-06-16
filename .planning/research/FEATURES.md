# Feature Research — MacStatus v2.0 (Insight & Customization)

**Domain:** macOS menu-bar system monitor — three new feature areas
**Researched:** 2026-06-16
**Confidence:** HIGH (competitor behavior verified via Stats GitHub issues/releases + iStat Menus official docs; complexity grounded in existing MacStatus architecture)

## Scope

Research covers ONLY the three v2.0 features, each split into Table Stakes / Differentiators / Anti-Features:

1. **Per-process Top-N** for CPU and Memory (in the existing popover)
2. **Battery & power** (charge %, charging state, watts, time remaining, health)
3. **Settings window + customization** (toggles/reorder, intervals, thresholds/colors, display mode, persistence)

Anti-features tie back to the minimalist "极简" positioning and PROJECT.md Out of Scope.

Existing infrastructure these features depend on (already built — reuse, don't rebuild):
- **Popover dashboard** with live metric cards + sparklines + in-memory history (commits `ccd7bf4`, `1730b24`)
- **Reader → Manager → AppDelegate** three-layer architecture
- **Per-process network top-5 via `nettop`** — proven pattern to copy for CPU/memory
- **Value-level coloring** in status bar (reuse for thresholds)
- No persistence layer yet — Settings introduces `UserDefaults`/SettingsManager (new)

---

## Category 1 — Per-Process Top-N (CPU & Memory)

### Table Stakes

| Feature | Why Expected | Complexity | Notes / Dependencies |
|---------|--------------|------------|----------------------|
| Top 3–5 CPU consumers in popover | Stats and iStat both show a top-process list per module; "which app is eating my CPU" is the #1 reason users open a monitor dropdown | MEDIUM | Reuse the **existing popover** + the **nettop top-5 pattern**. Source via `top -l 2 -stats pid,command,cpu` (2 samples for accurate delta) or `proc_pid_rusage`. Mirror network-top UI. |
| Top 3–5 memory consumers in popover | Same dropdown expectation; memory pressure (already shown) begs "what's using it" | MEDIUM | `top -l 1 -stats pid,command,mem -o mem` or `proc_pidinfo`. Sort by RSS/physical footprint, descending. |
| Process name + value, descending sort | A list without sort or value is useless; users scan for the top offender | LOW | Show `app name` + `%`/`MB`. Right-align numeric column. Reuse status-bar fixed-width / coloring approach. |
| App-level naming (not raw pid) | "kernel_task / 23491" is noise; users think in app names | LOW | Map pid → bundle/app display name where possible; fall back to process name. |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Click row → reveal in Activity Monitor | Lightweight escape hatch that respects the "don't replace Activity Monitor" boundary; gives power without owning the action | LOW | Launch Activity Monitor via `NSWorkspace`; or `open -a "Activity Monitor"`. Keeps MacStatus out of the privileged-action business. |
| Unified Top-N styling across CPU/Mem/Network | The three top-lists look/behave identically — a coherence touch competitors lack (Stats' modules feel bolted-together) | LOW | Single reusable SwiftUI row/list component. Reduces code and reinforces minimalist identity. |
| Tiny per-process trend hint (optional) | A 1px bar showing relative share within the top-N adds glanceability without a chart | LOW-MED | Optional; only if it stays in-memory and doesn't add a charting dependency. |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Kill / force-quit button in popover** | Stats had it (v2.6.6); convenient | Stats users immediately filed Issue #593 asking to *hide* it — accidental kills are dangerous, and it makes MacStatus own a privileged, destructive action that clashes with "极简, install-and-glance". Crosses from "monitor" to "task manager". | Click-through to Activity Monitor (which has a guarded kill). Keep MacStatus read-only. |
| **Full sortable/filterable process table** | "Let me sort by anything, see all processes" | Explicitly Out of Scope in PROJECT.md ("完整活动监视器… 不与 Activity Monitor 重叠"). Becomes a second Activity Monitor; heavy UI + continuous full-process enumeration overhead. | Fixed Top-N (3–5). Activity Monitor for the full list. |
| **Per-process GPU usage** | Symmetry with CPU/Mem | No public macOS API (Out of Scope). Would require private/unstable interfaces. | Omit. Keep aggregate GPU only. |
| **Top-N count slider (1–20)** | "Let me choose how many" | Over-configuration; >5 turns the popover into a table and harms scannability. | Hardcode 5 (or a single compact/verbose 3-vs-5 tied to display mode). |
| **Continuous high-frequency process polling** | "Real-time process %" | `top`/`nettop` process spawns are the expensive path; sub-2s sampling spikes CPU — the exact failure mode that gets monitors uninstalled (Stats FAQ). | Sample process lists only while popover is open, at ≥2s; pause when popover closed. |

**Key insight:** The network-top-5 feature already establishes the pattern, UI, sampling cadence, and the "spawn an external sampler only when needed" discipline. CPU/memory Top-N is largely *replication*, which is why complexity is MEDIUM not HIGH.

---

## Category 2 — Battery & Power

### Table Stakes

| Feature | Why Expected | Complexity | Notes / Dependencies |
|---------|--------------|------------|----------------------|
| Charge % | Baseline of any battery indicator; macOS itself shows it | LOW | `IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceDescription` (IOKit power sources). No external dep. |
| Charging / discharging / charged state | Users need to know if it's actually charging | LOW | `kIOPSPowerSourceStateKey` + `kIOPSIsChargingKey`. |
| Time remaining (to empty / to full) | Classic battery-app expectation (iStat, macOS) | LOW | `kIOPSTimeToEmptyKey` / `kIOPSTimeToFullKey`. Handle "calculating" (-1) gracefully. |
| Battery card in popover | The popover already hosts metric cards; battery fits the established pattern | LOW | Reuse **existing popover card** component. |
| **Graceful degradation on desktop Macs** | Mac mini / Studio / iMac have no battery; PROJECT.md requires "非笔记本机型优雅降级" | LOW | If `IOPSCopyPowerSourcesInfo` returns no internal battery → hide the battery card / status segment entirely. Mandatory, not optional. |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Real-time power draw (Watts)** | Charge/discharge wattage is the developer/power-user metric iStat charges for; pairs naturally with CPU/GPU load ("X watts under this load") | MEDIUM | Compute from `AppleSmartBattery` IORegistry keys: `Amperage` (mA) × `Voltage` (mV) → W. Sign indicates charge vs discharge. No SMC (avoids the locked-down SMC path that killed eul). |
| **Battery health (max capacity %)** | "Is my battery degrading?" — high-value, low-frequency. Reads as a serious tool | LOW-MED | `AppleSmartBattery`: `MaxCapacity` / `DesignCapacity` (or `AppleRawMaxCapacity`). Display as health %. |
| **Cycle count** | Apple surfaces it in System Settings; power users track it | LOW | `CycleCount` from `AppleSmartBattery` IORegistry. |
| **Charge % in status bar (compact)** | MacBook users want battery in the combined item without the macOS clock-area battery | LOW | Append to the combined status string; tie visibility to display-mode + the "battery exists" check. Optional segment. |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Low-battery notifications / custom alert rules** | "Warn me at 20%" | macOS already warns at 20%/10%. Custom rules = persistent notification infrastructure + rules engine — explicitly Out of Scope ("自定义通知规则 / 告警 — v2.0 未纳入"). | Rely on macOS native low-battery alert. At most, a color cue (red %) in the popover/status bar — reuse existing value-level coloring, no new infra. |
| **Per-process energy impact** | iStat/Activity Monitor show it | Energy "impact" is an opaque Apple heuristic, not a clean public number; duplicates Activity Monitor's Energy tab; adds another full-process enumeration. | Activity Monitor Energy tab. Keep battery to device-level metrics. |
| **Bluetooth peripheral battery (keyboard/mouse/AirPods)** | iStat and eul show it | Scope creep beyond "system resource monitor"; separate IOBluetooth surface, flaky reporting. Not a system-resource metric. | Out of scope; macOS Control Center already shows peripheral battery. |
| **Battery history charts / charge graphs over time** | iStat shows battery history | PROJECT.md: only in-memory short-term trend, no persistence. A long battery graph needs storage. | Optional in-memory sparkline only (reuse existing sparkline), no disk. |
| **Temperature / adapter wattage via SMC** | "Show battery temp" | SMC is progressively locked by Apple and is the most CPU-expensive path (Stats FAQ; killed eul). Out of Scope ("CPU 温度… SMC API 逐步被锁定"). | IOKit power-source + AppleSmartBattery keys only. No SMC. |

**Key insight:** Everything here is achievable through **IOKit power sources + `AppleSmartBattery` IORegistry** — zero external deps, no SMC. Watts + health + cycles are the differentiators that make it feel like a real tool; everything beyond device-level metrics is anti-feature.

---

## Category 3 — Settings Window + Customization

### Table Stakes

| Feature | Why Expected | Complexity | Notes / Dependencies |
|---------|--------------|------------|----------------------|
| **Metric enable/disable toggles** | Both Stats and iStat let users turn modules on/off; the single most-used preference | LOW-MED | New **SettingsManager** (UserDefaults). Status-bar formatter + popover read enabled set. |
| **Persistence of preferences** | Settings that reset on relaunch are broken | LOW | `UserDefaults` (no DB — aligns with zero-dep). Required foundation for every other setting. |
| **Per-metric refresh interval** | Stats exposes per-module update intervals; users tune CPU overhead vs freshness | MEDIUM | Each Reader/Manager timer reads its interval from settings. Enforce sane floors (≥1s network, ≥2s CPU/mem, ≥2s process lists). |
| **Standard macOS Settings window** | Users expect ⌘, to open a real Settings window, not a giant menu | LOW-MED | SwiftUI `Settings`/`SettingsLink` or an AppKit window. App is currently `LSUIElement`/menu-bar-only — ensure window can foreground (activation policy nuance). |
| **Reorder metrics** | Drag-to-reorder is standard (Stats, iStat) and PROJECT.md lists it explicitly | MEDIUM | Persist an ordered list; status-bar formatter renders in that order. List reorder UI in SwiftUI. |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Custom thresholds + colors** | PROJECT.md requirement; turns the existing value-level coloring into user-controlled bands (e.g., CPU red at 70 vs 90) | MEDIUM | Reuse **existing value-level coloring**; replace hardcoded bands with settings-driven thresholds. Keep palette small/curated. |
| **Compact / verbose status-bar mode** | Single toggle that meaningfully changes density — a coherent, low-config differentiator vs iStat's overwhelming panels | LOW-MED | One enum (compact = abbreviated/fewer segments; verbose = labels + more). Status-bar formatter branches on it. Can also drive Top-N 3-vs-5. |
| **Curated, minimal settings set** | The anti-iStat: a *small coherent* panel is itself the differentiator ("no decisions overload") | STRATEGIC | Deliberately cap the surface area. Every toggle must earn its place. This is positioning, not code. |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Per-state / per-condition custom icon sets** (iStat-style) | "Different look when charging vs draining" | iStat's deep conditional customization is the exact "overwhelming settings panel" MacStatus positions against. Combinatorial complexity. | One compact/verbose toggle + threshold colors. That's the customization ceiling. |
| **Fully custom display-format string / templating** | "Let me design the exact menu-bar string" | Templating engine + validation + truncation edge cases; breaks fixed-width layout guarantees. Power-user rabbit hole. | Compact/verbose modes + metric toggles cover the real need. |
| **Custom notification/alert rules engine** | "Alert when CPU>80% for 10s" | Out of Scope (needs persistent notification infra). Pulls Settings into background-rules territory. | Not in v2.0. Color cues only. |
| **Unit pickers everywhere (bit/byte, GB/GiB, °C/°F, etc.)** | "Let me pick every unit" | Each picker multiplies QA surface and formatter branches; mostly bikeshedding. No temperature anyway (SMC out). | Sensible fixed units (bytes/s, GB, %). Skip unit pickers entirely in v2.0. |
| **Profiles / presets / import-export config** | "Save my setups" | Persistence-heavy, niche; contradicts zero-config/minimalist. | Single persisted config. No profiles. |
| **iCloud / cross-device settings sync** | "Sync my prefs" | Needs entitlements, container, conflict handling — far beyond a menu-bar monitor. | Local `UserDefaults` only. |

**Key insight:** Settings is the riskiest area for the minimalist identity. The whole value is a *small coherent* panel. The hard constraint: every preference in PROJECT.md's Active list ships, and almost nothing else. Persistence (`UserDefaults`) is the prerequisite that unblocks all other settings — it must land first within this category.

---

## Feature Dependencies

```
[SettingsManager / UserDefaults persistence]   ← must land first in Category 3
    ├──enables──> [Metric enable/disable toggles]
    ├──enables──> [Reorder metrics]
    ├──enables──> [Per-metric refresh interval]
    ├──enables──> [Custom thresholds + colors]
    └──enables──> [Compact / verbose status-bar mode]

[Existing popover + sparklines + nettop top-5 pattern]   ← reuse, already built
    ├──enables──> [CPU Top-N]   (replicate nettop pattern)
    ├──enables──> [Memory Top-N]
    └──enables──> [Battery card]

[CPU Top-N] ─┐
[Memory Top-N] ─┼──share──> [Reusable Top-N list/row component]
[Network Top-5 (existing)] ─┘

[Existing value-level coloring]
    └──extended-by──> [Custom thresholds + colors]

[IOKit power sources + AppleSmartBattery]
    ├──enables──> [Charge % / state / time remaining]
    ├──enables──> [Watts (Amperage × Voltage)]
    └──enables──> [Health % / cycle count]

[Desktop-Mac battery degradation check] ──gates──> [all battery UI]

[Compact/verbose mode] ──can-drive──> [Top-N count (3 vs 5)]
```

### Dependency Notes

- **Persistence is the unblocker:** Every Category-3 customization reads/writes settings. Build `SettingsManager` (UserDefaults-backed) before any toggle/threshold UI. No DB — preserves zero-dependency constraint.
- **Top-N reuses the network pattern, not new infra:** The existing `nettop` top-5 already solved sampling cadence, external-sampler lifecycle, and popover list UI. CPU/Mem Top-N is replication → MEDIUM, not HIGH.
- **Battery card reuses the popover card:** No new container UI; battery is another card + status segment.
- **Custom colors extend, not replace, coloring:** Value-level coloring exists; thresholds make the bands user-driven. Avoid string-parsing colors (a known v1.0 pitfall already avoided).
- **Battery degradation gate is mandatory and upstream:** The "is there an internal battery" check must gate every battery surface (card + status segment) to satisfy desktop-Mac graceful degradation.
- **Refresh-interval floors interact with Top-N overhead:** Per-metric intervals must not let users set process-list sampling below ~2s, or the "no CPU impact" promise breaks.

---

## MVP Definition (this milestone = v2.0)

### Launch With (v2.0 core)

- [ ] **SettingsManager + UserDefaults persistence** — prerequisite for all customization
- [ ] **Metric enable/disable toggles** — most-used preference, validates Settings
- [ ] **CPU Top-3/5 in popover** — replicate nettop pattern
- [ ] **Memory Top-3/5 in popover** — replicate nettop pattern
- [ ] **Battery card: %, state, time remaining** — via IOKit power sources
- [ ] **Desktop-Mac graceful degradation** — hard requirement, gates all battery UI
- [ ] **Compact/verbose status-bar mode** — the headline customization differentiator

### Add After Validation (within / right after v2.0)

- [ ] **Watts (real-time power draw)** — AppleSmartBattery; high-value differentiator
- [ ] **Battery health % + cycle count** — low effort once AppleSmartBattery wired
- [ ] **Per-metric refresh interval** — tuning knob
- [ ] **Reorder metrics (drag)** — once toggles proven
- [ ] **Custom thresholds + colors** — extends existing coloring
- [ ] **Click process → Activity Monitor** — lightweight escape hatch

### Future Consideration (v3+ / explicitly deferred)

- [ ] Notification/alert rules — needs persistent infra (Out of Scope now)
- [ ] Per-process energy impact — duplicates Activity Monitor
- [ ] Bluetooth peripheral battery — beyond system-resource scope
- [ ] English / i18n — PROJECT.md keeps Chinese-only for now

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| SettingsManager / persistence | HIGH | LOW | P1 |
| Metric enable/disable toggles | HIGH | LOW-MED | P1 |
| CPU Top-N (popover) | HIGH | MEDIUM | P1 |
| Memory Top-N (popover) | HIGH | MEDIUM | P1 |
| Battery %, state, time remaining | HIGH | LOW | P1 |
| Desktop-Mac battery degradation | HIGH (correctness) | LOW | P1 |
| Compact/verbose status-bar mode | MEDIUM-HIGH | LOW-MED | P1 |
| Real-time Watts power draw | MEDIUM-HIGH | MEDIUM | P2 |
| Battery health % + cycle count | MEDIUM | LOW-MED | P2 |
| Per-metric refresh interval | MEDIUM | MEDIUM | P2 |
| Reorder metrics (drag) | MEDIUM | MEDIUM | P2 |
| Custom thresholds + colors | MEDIUM | MEDIUM | P2 |
| Click process → Activity Monitor | MEDIUM | LOW | P2 |
| Kill button in popover | LOW (net-negative) | LOW | P3 (anti-feature) |
| Notification/alert rules | LOW | HIGH | P3 (out of scope) |
| Bluetooth peripheral battery | LOW | MEDIUM | P3 (out of scope) |
| Custom display-format templating | LOW | MEDIUM | P3 (anti-feature) |

**Priority key:** P1 = must have for v2.0 · P2 = should have, add when possible · P3 = nice-to-have / deferred / anti-feature

---

## Competitor Feature Analysis

| Feature | Stats (exelban) | iStat Menus 7 | MacStatus v2.0 Approach |
|---------|-----------------|---------------|--------------------------|
| Top CPU processes | Live top-process list in CPU popup | Per-app CPU breakdown, sortable | Fixed Top-3/5 in existing popover, click → Activity Monitor |
| Top memory processes | Top memory-consuming apps | Per-app memory, swap, compressed | Fixed Top-3/5, RSS-sorted |
| Kill process | Added v2.6.6, then made hideable (Issue #593) | Yes | **No kill** — read-only, click-through to Activity Monitor |
| Battery % / state / time | Yes (battery module) | Yes, with per-state customization | Yes — IOKit power sources |
| Power draw (Watts) | Limited | Yes | **Yes** — AppleSmartBattery (differentiator) |
| Battery health + cycles | Yes | Yes (health, cycles, condition) | Yes — AppleSmartBattery |
| Desktop-Mac handling | Module simply absent | N/A focus | **Explicit graceful degradation** (gated) |
| Settings: toggles/reorder | Per-module enable + reorder | Extensive | Yes — curated, drag-reorder |
| Settings: per-module interval | Yes | Yes | Yes — with sane floors |
| Settings: thresholds/colors | Custom colors + notification thresholds | Extensive conditional theming | Thresholds + small curated palette; **no conditional icon sets** |
| Settings philosophy | Many modules, many panels | "Kitchen sink," notoriously deep | **Small coherent panel** (the anti-iStat) |
| Persistence | Yes | Yes | UserDefaults (zero-dep, no DB) |

### Key Insights from Competitor Analysis

1. **Kill button is a cautionary tale, not a target.** Stats shipped it (v2.6.6) then users demanded an option to hide it (Issue #593) due to accidental destructive clicks. For a minimalist read-only monitor, omitting it is the *correct* differentiator — click-through to Activity Monitor preserves the boundary.
2. **iStat's depth is the anti-pattern to define against.** Per-state conditional theming, exhaustive unit pickers, and deep panels are exactly the "overwhelming settings" MacStatus rejects. The differentiator is a *small coherent* panel, not feature parity.
3. **Watts + health + cycles are reachable without SMC.** IOKit power sources + `AppleSmartBattery` IORegistry give every battery metric users want with zero external deps and none of the SMC fragility that killed eul.
4. **The network-top-5 already de-risks Top-N.** MacStatus solved the hard parts (sampling cadence, sampler lifecycle, popover list UI) for network. CPU/Mem Top-N is replication, lowering both cost and risk.
5. **Persistence is the keystone of v2.0.** Unlike v1.0 (zero-config, no stored state), v2.0 introduces a settings layer. Everything customizable depends on it landing first — and it must stay `UserDefaults`-only to honor the zero-dependency constraint.

## Sources

- [Stats (exelban) GitHub](https://github.com/exelban/stats) — top-process lists per module, settings, releases. Active.
- [Stats Issue #593 — Option to hide kill buttons](https://github.com/exelban/stats/issues/593) — evidence the in-popover kill action is net-negative for non-power users.
- [Stats Issue #1084 — combined-view request](https://github.com/exelban/stats/issues/1084) and [#2498 — enhance combined view](https://github.com/exelban/stats/issues/2498) — combined/compact display demand and complexity.
- [Stats Issue #2377 — custom colors](https://github.com/exelban/stats/issues/2377) and [Release v2.10.13](https://github.com/exelban/stats/releases/tag/v2.10.13) — custom colors, per-module intervals, thresholds.
- [iStat Menus 7 — Power help](https://bjango.com/help/istatmenus7/power/) — battery %, state, time remaining, per-state customization, wireless device battery; confirms conditional-theming depth (anti-feature reference).
- [iStat Menus product page](https://bjango.com/mac/istatmenus/) — battery health, cycle count, watts, time remaining feature set.
- [Apple Activity Monitor User Guide](https://support.apple.com/guide/activity-monitor/welcome/mac) — the native baseline MacStatus intentionally does not replace (full process table, energy impact, kill).
- MacStatus `.planning/PROJECT.md` — v2.0 Active requirements + Out of Scope boundaries (notifications, full process list, per-process GPU, SMC, disk, i18n).
- MacStatus `.planning/milestones/v1.0-research/FEATURES.md` — prior competitor analysis; anti-feature precedents (history persistence, SMC, kill/process table).

---
*Feature research for: macOS menu-bar system monitor (MacStatus v2.0 — Insight & Customization)*
*Researched: 2026-06-16*
*Confidence: HIGH — competitor behavior verified via Stats issues/releases and iStat Menus official docs; complexity grounded in existing MacStatus popover/nettop/coloring infrastructure*
