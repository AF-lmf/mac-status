---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: 风扇与热状态
status: open
stopped_at: Phases 13 & 14 cancelled — fan control write path descoped
last_updated: "2026-06-30T00:00:00.000Z"
last_activity: 2026-06-30 -- Phases 13 & 14 cancelled (fan control descoped); v3.0 kept open
progress:
  total_phases: 3
  completed_phases: 3
  total_plans: 9
  completed_plans: 9
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-24)

**Core value:** 用户无需打开任何窗口，在菜单栏一眼就能看到当前系统资源的实时使用情况
**Current focus:** 无活跃阶段 — v3.0 只读监控范围（Phase 10–12）已完成；风扇控制写入路径已撤销，里程碑保持开放

## Current Position

Phase: 无活跃阶段（Phase 10–12 已完成）
Plan: —
Status: v3.0 保持开放 — 可新增非硬件 phase，或在准备好时收口里程碑
Last activity: 2026-06-30 -- Phases 13 & 14 cancelled (fan control descoped)

Progress: [██████████] 100%（仅计 v3.0 现有范围 Phase 10–12）

## Performance Metrics

**Velocity:**

- v3.0 plans completed: 9 of 9 planned so far
- Average duration: N/A
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 10 | 3 | - | - |
| 11 | 3 | - | - |
| 12 | 3 | - | - |
| ~~13~~ | cancelled 2026-06-30 | - | - |
| ~~14~~ | cancelled 2026-06-30 | - | - |

**Recent Trend:**

- Phase 12 completed 3/3 plans, passed code review, and passed final verification.

| Phase 10 P01 | 3 min | 2 tasks | 3 files |
| Phase 10 P02 | 3 min | 2 tasks | 2 files |
| Phase 10 P03 | 3 min | 2 tasks | 4 files |
| Phase 11 P01 | 5min | 2 tasks | 3 files |
| Phase 11 P02 | 5min | 3 tasks | 4 files |
| Phase 11 P03 | 5min | 2 tasks | 2 files |
| Phase 12 P01 | 4min | 2 tasks | 4 files |
| Phase 12 P02 | 4min | 2 tasks | 4 files |
| Phase 12 P03 | 4min | 2 tasks | 4 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Current roadmap decisions:

- [v3.0]: Read-only first — thermal and fan read paths ship before any SMC write path.
- [v3.0]: Popover layout stability is its own early phase before fan control UI.
- [v3.0]: Fan control is fail-closed — opt-in only, bounded RPM, write/readback verification, restore-auto on lifecycle/failure.
- [v3.0]: SMC write/control may require helper/XPC or be blocked on some Apple Silicon machines; unsafe or unverifiable control stays disabled.
- [v3.0][2026-06-30]: 风扇硬件控制写入路径取消 — Phase 13（写入路径）与 Phase 14（生命周期/真机 UAT）一并撤销，从未执行、无代码落地；规划产物归档至 .planning/cancelled/。FCTRL-01..06、UAT-01/02/03 标为本里程碑撤销，可后续重提。v3.0 保持开放。只读温度/风扇监控（Phase 10–12）不受影响。
- [Phase 10]: 10-01: ThermalReader only populates CPU/SoC and GPU temperatures from explicit Mac15,9 candidate lists; unsupported models return nil.
- [Phase 10]: 10-01: ProcessInfo thermalState is semantic SystemThermalState and never substitutes for CPU/SoC temperature.
- [Phase 10]: 10-01: Battery temperature uses AppleSmartBattery Temperature first, with only TB1T/TB2T as SMC fallback.
- [Phase 10]: 10-02: Thermal snapshots are read on the existing MetricCollector tick and cached outside MetricSample/history/status-bar data. — Keeps thermal current-snapshot-only and prevents persistence/status-bar scope creep.
- [Phase 10]: 10-02: DashboardState owns a non-optional ThermalSnapshot defaulting to unavailable for stable popover rows. — Prevents nil crashes and row churn when sensors are unsupported or temporarily unreadable.
- [Phase 10]: 10-02: ThermalSectionView renders CPU/SoC, system state, GPU, and battery as dedicated read-only rows with N/A degradation. — Preserves the UI-SPEC copy and avoids substituting semantic thermal state or secondary sensors into CPU/SoC.
- [Phase 10]: 10-03: Thermal popover visibility defaults on and is controlled live by SettingsManager.showThermalSection / 散热区块.
- [Phase 10]: 10-03: Mac15,9 probe confirmed trusted CPU/SoC and GPU catalog candidates; untrusted or unsupported reads remain N/A.
- [Phase 10]: 10-03: Final gates preserved read-only popover-only scope with no fan, SMC write, helper/XPC, SSD, status-bar, history, alert, or notification surface.
- [Phase 11]: 11-01: FNum uses SMCReader integer type whitespace normalization; fan reads remain read-only. — Mac15,9 FNum evidence uses ui8 with trailing whitespace, and the plan forbids widening the SMC boundary.
- [Phase 11]: 11-01: Fan capability fields stay independent and safeControlAvailable remains false in Phase 11. — Prevents downstream UI or control work from treating readable telemetry as safe fan control.
- [Phase 11]: 11-03: Mac15,9 hardware evidence confirms two readable numbered fan rows; F0ID/F1ID are missing, so no left/right inference is made.
- [Phase 11]: 11-03: Phase 11 remains read-only and fail-closed: safeControlAvailable is false and no control/helper/write UI or source surface exists.
- [Phase 11]: 11-03: Broad UI forbidden greps may be narrowed to fan-specific gates when pre-existing non-fan controls match generic UI tokens.
- [Phase 12]: Network Top Processes keep existing ByteFormatting plus /s semantics while reserving a fixed 148pt upload/download trailing block. — Preserves formatter meaning while moving stability responsibility into SwiftUI fixed-width layout.
- [Phase 12]: DashboardLayoutFixture remains DEBUG-only and is not referenced from live app, collector, status-bar, popover, or settings paths. — Keeps deterministic layout data available for tests without changing runtime behavior.

### Pending Todos

None.

### Blockers/Concerns

- None.（原风扇控制相关的硬件 UAT / SMC 写入可行性顾虑已随 Phase 13/14 撤销而移除。）

## Deferred Items

| Category | Item | Status |
|----------|------|--------|
| fan-control | 手动风扇控制写入路径（原 Phase 13/14） | Descoped 2026-06-30 — 可后续重提 |
| fan-control | Full automatic fan curves / quiet mode | Future requirement |
| thermal-history | Long-term temperature/fan history | Future requirement |

## Session Continuity

Last session: 2026-06-30
Stopped at: Phases 13 & 14 cancelled — fan control write path descoped; v3.0 kept open
Resume file: none (no active phase)
