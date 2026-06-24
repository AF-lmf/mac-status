---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: 风扇与热状态
status: planning
stopped_at: Phase 12 UI-SPEC approved
last_updated: "2026-06-24T15:55:55.721Z"
last_activity: 2026-06-24
progress:
  total_phases: 5
  completed_phases: 2
  total_plans: 6
  completed_plans: 6
  percent: 40
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-24)

**Core value:** 用户无需打开任何窗口，在菜单栏一眼就能看到当前系统资源的实时使用情况
**Current focus:** Phase 12 — popover-layout-stability

## Current Position

Phase: 12
Plan: Not started
Status: Phase 11 verified complete — ready for Phase 12 planning
Last activity: 2026-06-24

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- v3.0 plans completed: 6 of 6
- Average duration: N/A
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 10 | 3 | - | - |
| 11 | 3 | - | - |
| 12 | TBD | - | - |
| 13 | TBD | - | - |
| 14 | TBD | - | - |

**Recent Trend:**

- Phase 10 completed 3/3 plans and passed final verification.

| Phase 10 P01 | 3 min | 2 tasks | 3 files |
| Phase 10 P02 | 3 min | 2 tasks | 2 files |
| Phase 10 P03 | 3 min | 2 tasks | 4 files |
| Phase 11 P01 | 5min | 2 tasks | 3 files |
| Phase 11 P02 | 5min | 3 tasks | 4 files |
| Phase 11 P03 | 5min | 2 tasks | 2 files |

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
- [Phase 10]: 10-03: Thermal popover visibility defaults on and is controlled live by SettingsManager.showThermalSection / 散热区块.
- [Phase 10]: 10-03: Mac15,9 probe confirmed trusted CPU/SoC and GPU catalog candidates; untrusted or unsupported reads remain N/A.
- [Phase 10]: 10-03: Final gates preserved read-only popover-only scope with no fan, SMC write, helper/XPC, SSD, status-bar, history, alert, or notification surface.
- [Phase 11]: 11-01: FNum uses SMCReader integer type whitespace normalization; fan reads remain read-only. — Mac15,9 FNum evidence uses ui8 with trailing whitespace, and the plan forbids widening the SMC boundary.
- [Phase 11]: 11-01: Fan capability fields stay independent and safeControlAvailable remains false in Phase 11. — Prevents downstream UI or control work from treating readable telemetry as safe fan control.
- [Phase 11]: 11-03: Mac15,9 hardware evidence confirms two readable numbered fan rows; F0ID/F1ID are missing, so no left/right inference is made.
- [Phase 11]: 11-03: Phase 11 remains read-only and fail-closed: safeControlAvailable is false and no control/helper/write UI or source surface exists.
- [Phase 11]: 11-03: Broad UI forbidden greps may be narrowed to fan-specific gates when pre-existing non-fan controls match generic UI tokens.

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

Last session: 2026-06-24T15:55:55.715Z
Stopped at: Phase 12 UI-SPEC approved
Resume file: .planning/phases/12-popover-layout-stability/12-UI-SPEC.md
