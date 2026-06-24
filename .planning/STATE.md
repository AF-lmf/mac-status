---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: 风扇与热状态
status: executing
stopped_at: Completed 10-02-PLAN.md
last_updated: "2026-06-24T01:23:59.368Z"
last_activity: 2026-06-24
progress:
  total_phases: 5
  completed_phases: 0
  total_plans: 3
  completed_plans: 2
  percent: 67
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-23)

**Core value:** 用户无需打开任何窗口，在菜单栏一眼就能看到当前系统资源的实时使用情况
**Current focus:** Phase 10 — thermal-read-only-monitoring

## Current Position

Phase: 10 (thermal-read-only-monitoring) — EXECUTING
Plan: 3 of 3
Status: Ready to execute
Last activity: 2026-06-24

Progress: [███████░░░] 67%

## Performance Metrics

**Velocity:**

- v3.0 plans completed: 0
- Average duration: N/A
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 10 | TBD | - | - |
| 11 | TBD | - | - |
| 12 | TBD | - | - |
| 13 | TBD | - | - |
| 14 | TBD | - | - |

**Recent Trend:**

- No v3.0 plans executed yet.

| Phase 10 P01 | 3 min | 2 tasks | 3 files |
| Phase 10 P02 | 3 min | 2 tasks | 2 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Current roadmap decisions:

- [v3.0]: Read-only first — thermal and fan read paths ship before any SMC write path.
- [v3.0]: Popover layout stability is its own early phase before fan control UI.
- [v3.0]: Fan control is fail-closed — opt-in only, bounded RPM, write/readback verification, restore-auto on lifecycle/failure.
- [v3.0]: SMC write/control may require helper/XPC or be blocked on some Apple Silicon machines; unsafe or unverifiable control stays disabled.
- [Phase 10]: 10-01: ThermalReader only populates CPU/SoC and GPU temperatures from explicit Mac15,9 candidate lists; unsupported models return nil.
- [Phase 10]: 10-01: ProcessInfo thermalState is semantic SystemThermalState and never substitutes for CPU/SoC temperature.
- [Phase 10]: 10-01: Battery temperature uses AppleSmartBattery Temperature first, with only TB1T/TB2T as SMC fallback.
- [Phase 10]: 10-02: Thermal snapshots are read on the existing MetricCollector tick and cached outside MetricSample/history/status-bar data. — Keeps thermal current-snapshot-only and prevents persistence/status-bar scope creep.
- [Phase 10]: 10-02: DashboardState owns a non-optional ThermalSnapshot defaulting to unavailable for stable popover rows. — Prevents nil crashes and row churn when sensors are unsupported or temporarily unreadable.
- [Phase 10]: 10-02: ThermalSectionView renders CPU/SoC, system state, GPU, and battery as dedicated read-only rows with N/A degradation. — Preserves the UI-SPEC copy and avoids substituting semantic thermal state or secondary sensors into CPU/SoC.

### Pending Todos

None.

### Blockers/Concerns

- Fan control cannot be marked complete without real MacBook Pro hardware UAT.
- Apple Silicon SMC write feasibility is a decision gate; read-only monitoring must remain useful if control is blocked.

## Deferred Items

| Category | Item | Status |
|----------|------|--------|
| fan-control | Full automatic fan curves / quiet mode | Future requirement |
| thermal-history | Long-term temperature/fan history | Future requirement |

## Session Continuity

Last session: 2026-06-24T01:23:46.698Z
Stopped at: Completed 10-02-PLAN.md
Resume file: None
