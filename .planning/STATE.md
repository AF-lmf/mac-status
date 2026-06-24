---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: 风扇与热状态
status: planning
stopped_at: Phase 10 UI-SPEC approved
last_updated: "2026-06-24T01:09:16.924Z"
last_activity: 2026-06-23 — v3.0 roadmap created with 5 phases and 22/22 requirements mapped
progress:
  total_phases: 5
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-23)

**Core value:** 用户无需打开任何窗口，在菜单栏一眼就能看到当前系统资源的实时使用情况
**Current focus:** v3.0 风扇与热状态 — 温度/风扇只读监控、popover 稳定布局、安全风扇控制与硬件 UAT

## Current Position

Phase: 10 (1 of 5 v3.0 phases) — Thermal Read-Only Monitoring
Plan: TBD
Status: Planning complete; ready to discuss Phase 10
Last activity: 2026-06-23 — v3.0 roadmap created with 5 phases and 22/22 requirements mapped

Progress: [----------] 0%

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

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Current roadmap decisions:

- [v3.0]: Read-only first — thermal and fan read paths ship before any SMC write path.
- [v3.0]: Popover layout stability is its own early phase before fan control UI.
- [v3.0]: Fan control is fail-closed — opt-in only, bounded RPM, write/readback verification, restore-auto on lifecycle/failure.
- [v3.0]: SMC write/control may require helper/XPC or be blocked on some Apple Silicon machines; unsafe or unverifiable control stays disabled.

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

Last session: 2026-06-24T00:47:19.907Z
Stopped at: Phase 10 UI-SPEC approved
Resume file: .planning/phases/10-thermal-read-only-monitoring/10-UI-SPEC.md
