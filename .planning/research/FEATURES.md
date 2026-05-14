# Feature Research: macOS Menu Bar System Monitor

**Domain:** macOS status bar system monitor apps
**Researched:** 2026-05-14
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

These are non-negotiable. Every competitor has them. Missing any = product feels broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| CPU usage % in menu bar | Users on Apple Silicon want to see core utilization at a glance | LOW | `host_processor_info()` or `sysctl` — well-documented system APIs |
| Memory usage in menu bar | Memory pressure is a daily concern, especially on 8GB/16GB machines | LOW | `host_statistics64()` for vm stats, format as used/total or GB free |
| Network up/down rate in menu bar | Users want to know if something is saturating their connection | MEDIUM | Requires polling interface counters via `getifaddrs()`; need to handle Wi-Fi vs Ethernet and VPN interfaces |
| Real-time refresh (every 1-3 seconds) | Static data is worthless; users need second-level awareness | LOW-MEDIUM | Timer-based polling; must balance refresh rate vs CPU overhead (1s for network, 2-3s for CPU/memory is typical) |
| Launch at login (auto-start) | If users have to manually launch it every reboot, they stop using it | LOW | `SMAppService` (macOS 13+) or a LoginItem helper — Stats uses LaunchAtLogin module |
| Menu bar only (no Dock icon) | Users install these to save screen real estate, not add window clutter | LOW | Set `LSUIElement = YES` in Info.plist; use `NSStatusBar` + `NSStatusItem` |
| Light/Dark mode compatible | macOS users expect seamless theme integration; broken in dark mode = unshippable | LOW | SwiftUI handles this automatically if using system colors; need to test custom text colors in both modes |
| Zero-config operation | Running the app should immediately show data without setup wizards | LOW | Sensible defaults out of the box; configuration is opt-in, not required |
| Low CPU overhead (<1% idle) | Users uninstall menu bar apps that drain battery or cause fan spin | MEDIUM | Efficient polling strategy (avoid busy-waiting), use system APIs not shell commands, batch reads where possible |

### Differentiators (Competitive Advantage for MacStatus)

These align with the **lightweight, essentials-only** positioning and the Chinese-first audience.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **GPU usage + GPU pressure** | Apple Silicon Macs have unified GPU that impacts system feel — most free tools don't show GPU pressure well | MEDIUM-HIGH | `IOReport` / IOKit (`IOReportCreateSubscription`) for GPU utilization; GPU pressure is newer metric (Activity Monitor added it for Apple Silicon). Stats has basic GPU %, but GPU *pressure* is rarer |
| **Single combined menu bar item** | All four metrics (CPU/Mem/Net/GPU) in ONE compact status bar text — saves precious menu bar space vs competitors that use multiple items | MEDIUM | Requires careful string formatting: `⏏ 12% · MEM 8.2G · ↓2.1M ↑512K · GPU 34%`. Must handle truncated text when menu bar is crowded (macOS limits status item width) |
| **Ultra-minimalist, no settings UI** | Install and forget — the "no decisions" monitor. Competing apps have overwhelming settings panels (iStat Menus is notorious for this) | STRATEGIC (not technical) | Deliberately omit preferences window in v1. If users want customization, they can use competing products. This is a philosophical differentiator |
| **Chinese-first design** | All Chinese competitors are either English-first with translations or unmaintained. A natively Chinese menu bar app has zero competition in this niche | LOW | Default UI text in Chinese. The combined display format (`CPU 12% │ 内存 8.2G │ 网络 ↓2.1M ↑512K │ GPU 34%`) reads naturally in Chinese |
| **GPU pressure for Apple Silicon** | Apple's GPU pressure metric (like memory pressure — green/yellow/red zones) is unique to Apple Silicon. Displaying it in the menu bar is a genuine technical differentiator | HIGH | Requires `IOReport` API. The pressure metric is not exposed through simpler APIs. May need to reverse-engineer the key name from IOKit registry. Stats doesn't show GPU pressure — only GPU utilization % |
| **Adaptive update frequency** | Slow down polling when system is idle (e.g., background tasks paused), speed up under load — saves battery | MEDIUM | Monitor system power state via `IOPowerSources`; reduce timer frequency when on battery; increase when CPU load crosses threshold |

### Anti-Features (Commonly Requested, We Will NOT Build)

Prevent scope creep. These seem good but would destroy the lightweight positioning or require inordinate effort for v1.

| Anti-Feature | Why Requested | Why Problematic | What to Do Instead |
|--------------|---------------|-----------------|-------------------|
| Historical charts / performance graphs | Users coming from iStat Menus expect dropdown graphs | Requires data storage, graphing library, and complex UI — destroys the "status bar text only" simplicity. Stats does this but it adds significant code | Point users to macOS Activity Monitor for history. MacStatus is real-time-only, by design |
| CPU temperature / fan speed | "Is my Mac overheating?" — a genuine but infrequent concern | Requires SMC (System Management Controller) access. Apple increasingly locks down SMC APIs. Stats maintainer explicitly stopped maintaining fan control. Causes elevated CPU usage (Stats FAQ says sensors are "most inefficient module") | Not in scope for MacStatus. If thermal is a concern, use iStat Menus or TG Pro |
| Weather / time / calendar widgets | iStat Menus includes weather and world clocks — users expect "all-in-one" | Scope explosion. Weather needs network API, location services, paid data feeds. Time/calendar is a solved problem (macOS menu bar clock is sufficient) | Use dedicated weather app or macOS built-in clock. Don't bundle unrelated features |
| Per-app process breakdown | "Which app is using all the CPU?" — Activity Monitor does this natively | Requires `proc_listallpids()` + `proc_pidinfo()` to enumerate all processes — significant I/O overhead and complex dropdown UI. iStat Menus has this but it's their most complex feature | Open Activity Monitor (⌘Space "Activity Monitor") — it's already installed and free |
| Custom notification rules | "Alert me when CPU > 80% for 10 seconds" — power users love this | Requires persistent notification infrastructure, rules engine, and background operation that persists across sleep/wake. Significant complexity for marginal value | Not now. This is a v3 feature at best |
| Multiple language support in v1 | App Store requires localization for broad markets | Adds per-string translation overhead, slows iteration, doesn't help the Chinese-first target audience. Most competitors have localization but it's a maintenance burden | v1: Chinese only. v2+: Add English (low effort, broadens audience). Other languages only if demand exists |
| Remote/networked monitoring | "See my server's stats from my laptop" | Requires network server, authentication, security model, and completely different architecture. Explicitly listed as Out of Scope in PROJECT.md | Use dedicated server monitoring tools (htop, Prometheus, Grafana) |
| Fan speed control | "My fans are too loud, let me control them" | Dangerous — can cause thermal damage. Stats maintainer explicitly abandoned fan control as legacy/unmaintained. SMC manipulation can void warranty | Never. This is a hardware-level concern. Use TG Pro or Macs Fan Control by professionals |
| Disk space / activity monitoring | "How much space is left on my SSD?" | Apple Silicon SSDs are large enough that disk space is rarely a daily concern. Disk I/O monitoring requires polling `IOBlockStorageDriver` and adds overhead. Stats includes it but it's their least-used module | macOS "About This Mac" → Storage shows disk usage. For I/O, use Activity Monitor Disk tab |

## Feature Dependencies

```
[GPU pressure display]
    └──requires──> [IOReport/IOKit API access]
                       └──requires──> [Apple Silicon Mac detection]

[Network rate display]
    └──requires──> [Network interface enumeration]
                       └──enhances──> [Adaptive refresh frequency]

[Launch at login]
    └──requires──> [SMAppService registration or LoginItem]
                       └──requires──> [Code signing for distribution]

[Single combined menu bar item]
    └──requires──> [All four metric readers working]
    └──requires──> [Status item text formatting utility]
    └──constrains──> [Truncation handling for narrow menu bars]

[Adaptive update frequency]
    └──enhances──> [All metric readers]
    └──requires──> [Power source detection]
    └──requires──> [CPU load threshold detection]
```

### Dependency Notes

- **GPU pressure requires IOReport:** The only way to access GPU pressure on Apple Silicon is through IOReport/CoreAnalytics. Standard IOKit `IOHID` and `sysctl` do not expose it. This is the riskiest implementation task.
- **Launch at login requires code signing:** `SMAppService` on macOS 13+ requires a signed app bundle. For development, a manual LoginItem approach or using the open-source `LaunchAtLogin` library (used by Stats) is more practical.
- **Combined menu bar item depends on all metric readers:** If any reader fails, the display degrades — the app must handle partial data gracefully (show `--` for unavailable metrics rather than crashing).
- **Adaptive refresh conflicts with network accuracy:** Network rate calculation degrades if polling interval is too long (bursts get averaged out). Floor should be 2 seconds for network, 3 seconds for CPU/memory.
- **GPU pressure may not be available on Intel Macs:** The feature should degrade gracefully on Intel hardware — fall back to GPU utilization only or omit GPU entirely for Intel.

## MVP Definition

### Launch With (v1.0)

The absolute minimum that provides the Core Value: "一眼看到系统资源使用情况".

- [ ] **CPU usage %** in menu bar — Most important metric; every user needs this
- [ ] **Memory usage** in menu bar — Displayed as used GB / total GB or compact percentage. Essential for Apple Silicon users with limited RAM
- [ ] **Network up/down rate** in menu bar — Second-level updates; users want to catch network hogs instantly
- [ ] **GPU usage / pressure** in menu bar — Apple Silicon differentiator; even a basic GPU % is table stakes now
- [ ] **Launch at login** — Without this, most users try the app once and forget it exists
- [ ] **All four metrics in a single compact menu bar item** — `CPU 12% · 内存 8.2G · ↓2.1M ↑512K · GPU 34%` — saves menu bar real estate, aligns with lightweight philosophy

### Add After Validation (v1.x)

Once core monitoring works and users confirm the format is useful:

- [ ] **Adaptive refresh frequency** — Battery vs AC power; idle vs load-aware polling — validates the "no CPU impact" promise
- [ ] **GPU pressure color coding** (green/yellow/red) — Adds at-a-glance urgency awareness without dropdown
- [ ] **Compact mode** — Allow users to choose which metrics appear (e.g., CPU + Network only) for ultra-narrow menu bars
- [ ] **English localization** — Broadens audience to non-Chinese macOS power users with minimal effort

### Future Consideration (v2+)

Defer until product-market fit is validated:

- [ ] Dropdown with slightly more detail (per-core CPU, swap usage, network interface name)
- [ ] Customizable display format (layout, decimal places, units)
- [ ] Battery percentage display (for MacBook users)
- [ ] Color themes for menu bar text
- [ ] SMC sensors (temperature) — only if Apple doesn't further lock down SMC APIs

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| CPU usage % display | HIGH | LOW | P1 |
| Memory usage display | HIGH | LOW | P1 |
| Network up/down rate display | HIGH | MEDIUM | P1 |
| GPU usage display | HIGH | MEDIUM | P1 |
| Launch at login | HIGH | LOW | P1 |
| Combined single menu bar item | HIGH | MEDIUM | P1 |
| GPU pressure (Apple Silicon) | MEDIUM | HIGH | P2 |
| Adaptive refresh frequency | MEDIUM | MEDIUM | P2 |
| GPU pressure color coding | MEDIUM | LOW | P2 |
| Compact mode (select metrics) | MEDIUM | LOW | P2 |
| English localization | MEDIUM | LOW | P2 |
| Dropdown detail view | MEDIUM | MEDIUM | P3 |
| Customizable display format | LOW | MEDIUM | P3 |
| Battery display | MEDIUM | LOW | P3 |
| SMC temperature sensors | LOW | HIGH | P3 |
| Notification rules | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for launch (v1.0)
- P2: Should have, add in v1.x after validation
- P3: Nice to have, v2+ consideration only

## Competitor Feature Analysis

| Feature | Stats (exelban) | iStat Menus 7 | eul (gao-sun) | MenuMeters | Our Approach |
|---------|-----------------|---------------|---------------|------------|--------------|
| CPU % | Per-core + total, graphs | Per-core, history, per-app, frequency | Basic % | Basic bar graph | Compact single % in menu bar text |
| Memory | Used/Free, pressure graph | Fully detailed, per-app, swap, compressed | Basic used/total | Basic bar graph | Used GB / total GB, one number |
| Network | Bandwidth + public IP | Bandwidth + per-app + public/private IP + connectivity | Basic up/down | Basic up/down arrows | Up/down rate in one line with units |
| GPU | Utilization % | GPU processor/memory/temp/frequency | Not available | Not available | **GPU utilization + pressure** (differentiator) |
| Disk | Used/free, activity | S.M.A.R.T., per-app, activity, free space | Not available | Read/write rate | Not in scope (low daily concern) |
| Battery | Level % | Level + health + cycles + Bluetooth devices | Level + Bluetooth devices | Not available | P3 future consideration |
| Sensors | Fans, temps, voltage, power | All sensors + fan speed curves | Limited (App Store version has none) | Not available | Not in scope (SMC overhead) |
| Combined mode | No (each module separate) | Yes (highly customizable) | No (separate widgets) | No (separate meters) | **Yes, all four in one item by default** |
| Launch at login | Yes (LaunchAtLogin module) | Yes (built-in) | Requires manual setup | Yes (preference pane) | Yes (SMAppService) |
| Auto-update | Sparkle framework | Built-in | Self-update module | Sparkle framework | P3 (Sparkle in v2) |
| Widgets | macOS widgets | Not available | macOS widgets | Not available | Not in scope |
| Language support | 30+ languages | English (primary) | 20+ languages | English only | Chinese first, English v1.x |
| License/Price | Free (MIT) | Paid ($) | Free (MIT) | Free (GPL-2.0) | TBD |
| Active maintenance | Yes (v2.12.13, May 2026) | Yes (v7.3) | No (last release Aug 2021) | No (last release Nov 2021) | New project |

### Key Insights from Competitor Analysis

1. **Stats dominates free/open-source:** 38.8k stars, active maintenance, comprehensive features. Competing on breadth is impossible. Compete on focus and simplicity instead.
2. **iStat Menus dominates premium:** 14-day trial, paid license, incredibly feature-rich. It's the "kitchen sink" — MacStatus should be the opposite.
3. **eul was promising but abandoned:** 9.9k stars, SwiftUI-first, but last updated 2021. Proves there's demand but also that maintenance is hard. Part of why eul died: SMC API lockdowns by Apple.
4. **GPU monitoring is the gap:** Stats has basic GPU utilization. iStat Menus has comprehensive GPU. But neither focuses on GPU *pressure* as a first-class metric. On Apple Silicon, GPU pressure matters as much as memory pressure. This is MacStatus's technical edge.
5. **Combined single-item display is under-served:** Stats uses separate menu items per module (consuming 5+ status bar slots). iStat Menus has combined mode but it's a power-user feature buried in settings. A default combined single-item display is genuinely distinctive.

## Sources

- [Stats (exelban) GitHub Repository](https://github.com/exelban/stats) — 38.8k stars, MIT license, active as of May 2026 (v2.12.13). Primary free competitor.
- [iStat Menus 7 Product Page](https://bjango.com/mac/istatmenus/) — Commercial product, v7.3, feature-rich. Primary premium competitor.
- [MenuMeters (yujitach fork) GitHub Repository](https://github.com/yujitach/MenuMeters) — 3.1k stars, GPL-2.0, legacy (last release Nov 2021). Historic reference — shows what the category looked like pre-SwiftUI.
- [eul (gao-sun) GitHub Repository](https://github.com/gao-sun/eul) — 9.9k stars, MIT license, abandoned (last release Aug 2021). Reference for SwiftUI-first approach architecture.
- [Apple Activity Monitor User Guide](https://support.apple.com/guide/activity-monitor/welcome/mac) — macOS built-in baseline. Shows what metrics macOS exposes natively: CPU, GPU, Memory, Energy, Disk, Network, Cache. Confirms GPU pressure is Apple Silicon-specific feature.
- Stats FAQ on CPU overhead — Documents that Sensors and Bluetooth modules are the most expensive (up to 50% more CPU usage). Validates the anti-feature decision to exclude sensors.
- macOS 26 (Tahoe) Menu Bar privacy control — Stats Issue #3120 documents new macOS 26 requirement: apps must be explicitly granted permission in System Settings → Menu Bar. Relevant for MacStatus launch.

---

*Feature research for: macOS menu bar system monitor (MacStatus)*
*Researched: 2026-05-14*
*Confidence: HIGH — Competitor analysis verified via GitHub READMEs, official product pages, and Apple documentation*
