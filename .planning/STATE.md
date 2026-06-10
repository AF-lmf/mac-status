---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: Awaiting next milestone
stopped_at: Completed 05-01-PLAN.md
last_updated: "2026-06-10T00:22:54.310Z"
last_activity: 2026-06-10 — Milestone v1.0 completed and archived
progress:
  total_phases: 5
  completed_phases: 5
  total_plans: 9
  completed_plans: 9
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-14)

**Core value:** 用户无需打开任何窗口，在菜单栏一眼就能看到当前系统资源的实时使用情况
**Current focus:** Phase 04 — combined-display-formatting

## Current Position

Phase: Milestone v1.0 complete
Plan: —
Status: Awaiting next milestone
Last activity: 2026-06-10 — Milestone v1.0 completed and archived

## Performance Metrics

**Velocity:**

- Total plans completed: 7
- Average duration: N/A
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 02 | 3 | - | - |
| 03 | 2 | - | - |
| 04 | 1 | - | - |
| 5 | 1 | - | - |

**Recent Trend:**

- No plans executed yet.

*Updated after each plan completion*
| Phase 01-foundation-cpu-monitoring P01-01 | 14m | 2 tasks | 4 files |
| Phase 01-foundation-cpu-monitoring P01-02 | 9min | 2 tasks | 5 files |
| Phase 02-network-memory-monitoring P01 | 8min | 2 tasks | 5 files |
| Phase 02-network-memory-monitoring P02-02 | 6m | 2 tasks | 4 files |
| Phase 02-network-memory-monitoring P03 | 2 min | 1 tasks | 1 files |
| Phase 03 P01 | 4 min | 2 tasks | 2 files |
| Phase 03 P02 | 5 min | 3 tasks | 3 files |
| Phase 04 P01 | 2 min | 3 tasks | 1 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Init]: Swift + AppKit/SwiftUI stack — macOS native, zero external dependencies for core functionality
- [Init]: Menu bar only (LSUIElement = YES) — no Dock icon, pure status bar app
- [Init]: Risk-ascending build order — CPU first (lowest risk), GPU last (riskiest, isolated)
- [Init]: Three-layer architecture — Reader → Module/Wiring → Presentation (Stats-proven pattern)
- [Init]: Single Xcode target — folder grouping for modularity without SPM complexity
- [Phase ?]: host_statistics(HOST_CPU_LOAD_INFO) for aggregate CPU% instead of host_processor_info() — simpler API, no vm_deallocate, identical output
- [Phase ?]: NSAttributedString on NSStatusBarButton.attributedTitle instead of custom NSView — simpler for Phase 1 single-text display
- [Phase ?]: Swift 6 concurrency: @MainActor class + nonisolated readCPU() + Task { @MainActor } for main-thread dispatch from background queue
- [Phase ?]: CPUReader extends TimerReader<Double> — Timer lifecycle inherited, only read() override needed
- [Phase ?]: StatusBarManager is @MainActor — all NSStatusItem operations must be on main thread per AppKit requirement
- [Phase ?]: SettingsManager uses @unchecked Sendable — UserDefaults is documented thread-safe
- [Phase ?]: AppDelegate delegates Timer management to TimerReader.start/stop — no inline Timer code
- [Phase ?]: macOS 26 visibility gate uses DispatchQueue.main.asyncAfter with NSAlert — non-blocking, user-friendly
- [Phase ?]: Network delta uses max(current - previous, 0) with Int64 conversion to handle 32-bit u_int32_t counter wraparound (PITFALL P2)
- [Phase ?]: Network tolerance threshold: 1 KB/s (1024 bytes/s) absolute — not the 0.5% relative threshold from CPU
- [Phase ?]: Primary interface resolved every read cycle via SCDynamicStoreCopyValue — handles Wi-Fi/Ethernet/VPN transitions instantly
- [Phase ?]: freeifaddrs() in defer block immediately after getifaddrs() — prevents ~86 MB/day memory leak at 1 Hz polling (PITFALL P3)
- [Phase ?]: MemoryReader extends TimerReader<MemoryStats> with 2-second polling interval (D-10)
- [Phase ?]: Uses host_basic_info.max_mem for total RAM (NOT memory_size — 2 GB cap)
- [Phase ?]: getpagesize() instead of vm_page_size C global for Swift 6 conformance
- [Phase 2 UAT]: Independent CPU/memory NSStatusItems are not reliably visible in the user's menu bar; visible display should use the combined networkStatusItem.
- [Phase 2 Quick]: Memory display should show pressure via kern.memorystatus_vm_pressure_level, not used/total GB.
- [Phase 3]: GPUReader uses IOKit IOAccelerator PerformanceStatistics with nil fallback for unavailable data.
- [Phase 3]: GPU pressure is represented as a v1 utilization-threshold color on the `G ...%` segment only.
- [Phase 3]: CPU/MEM coloring remains deferred to Phase 4 combined display formatting.
- [Phase 04]: Value-level menu bar colors are derived from raw metric state, not parsed display strings — This prevents stale warning/critical colors after fallback and keeps labels default-colored.

### Pending Todos

- None.

### Blockers/Concerns

- [Phase 4] CPU and MEM color rules need final combined-display treatment.
- [Phase 5] macOS 26 menu bar privacy control — may need onboarding alert for users to allow in System Settings

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260514-r6z | 修复 CPU 状态不显示和网络速度换行溢出 | 2026-05-14 | ddf9307 | [260514-r6z-cpu](./quick/260514-r6z-cpu/) |
| 260514-rfa | 继续修复 CPU 状态不显示 | 2026-05-14 | c9f03bd | [260514-rfa-cpu](./quick/260514-rfa-cpu/) |
| 260514-rj1 | 把 CPU 并入可见网络菜单栏项显示 | 2026-05-14 | c9bbf1d | [260514-rj1-cpu](./quick/260514-rj1-cpu/) |
| 260514-s6f | 调整菜单栏顺序并以内存压力替代内存用量 | 2026-05-14 | 438d31c | [260514-s6f-cpu](./quick/260514-s6f-cpu/) |
| 260514-uxx | 生成 MacStatus app 图标并接入 AppIcon | 2026-05-14 | ef57696 | [260514-uxx-macstatus-app-appicon](./quick/260514-uxx-macstatus-app-appicon/) |
| 260514-vax | 将内存菜单栏显示改为 M OK 68% 格式 | 2026-05-14 | 0b4b1fa | [260514-vax-m-ok-68](./quick/260514-vax-m-ok-68/) |
| 260514-vhu | 准备并发布公开 GitHub README、效果图和 Release 包 | 2026-05-14 | 149763f | [260514-vhu-github-readme-release](./quick/260514-vhu-github-readme-release/) |
| 260514-vww | 修复 Release 分发时其他 Mac 无法验证 MacStatus.app 的签名/公证流程说明 | 2026-05-14 | f15b0c8 | [260514-vww-release-mac-macstatus-app](./quick/260514-vww-release-mac-macstatus-app/) |
| 260518-u7o | 将菜单栏显示格式改为紧凑版 C12 G0 M39 ↓1K ↑1K | 2026-05-18 | da37905 | [260518-u7o-c12-g0-m39-1k-1k](./quick/260518-u7o-c12-g0-m39-1k-1k/) |
| 260529-1th | 修复 macOS 26 下状态栏数据不可见提示与多实例保护 | 2026-05-29 | pending | [260529-1th-macstatus-cpu](./quick/260529-1th-macstatus-cpu/) |
| 260531-w4s | 状态栏下拉菜单显示当前网络占用最高的进程 | 2026-05-31 | pending | [260531-w4s-network-process-menu](./quick/260531-w4s-network-process-menu/) |
| 260531-wb7 | 调整状态栏网络进程菜单为最高五个进程单行展示 | 2026-05-31 | pending | [260531-wb7-network-process-menu-top5](./quick/260531-wb7-network-process-menu-top5/) |

## Deferred Items

Items acknowledged and deferred at milestone close on 2026-06-10:

| Category | Item | Status |
|----------|------|--------|
| debug | duplicate-macstatus-no-menubar | partially-resolved |
| quick_task | 260514-r6z-cpu | missing |
| quick_task | 260514-rfa-cpu | missing |
| quick_task | 260514-rj1-cpu | missing |
| quick_task | 260514-s6f-cpu | missing |
| quick_task | 260529-3a7-macstatus-position-cache | missing |
| verification | 01-VERIFICATION.md | human_needed |
| verification | 05-VERIFICATION.md | human_needed |

## Session Continuity

Last session: 2026-05-14T14:11:12.514Z
Stopped at: Completed 05-01-PLAN.md
Resume file: None

## Operator Next Steps

- Start the next milestone with /gsd-new-milestone
