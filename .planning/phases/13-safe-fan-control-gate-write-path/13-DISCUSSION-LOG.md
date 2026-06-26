# Phase 13: Safe Fan Control Gate & Write Path - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-26
**Phase:** 13-safe-fan-control-gate-write-path
**Areas discussed:** Gray-area selection (4 areas presented; user delegated all)

---

## Gray-Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| opt-in 入口与首次确认 | Settings toggle vs in-popover entry; one-time vs per-entry risk confirmation | |
| 控制方式与粒度 | Slider (clamped) / numeric / presets; unified vs per-fan target | |
| 失败与 fail-closed 呈现 | Write/read-back failure UX; gated-off hidden vs disabled | |
| 特权 helper / 管理员授权 | Appetite for a privileged helper + admin prompt vs fail-closed | |

**User's choice:** "全部由你决定" (decide everything) — delegated all four gray areas to Claude.
**Notes:** User asked Claude to make the calls. Claude made conservative, safety-first
decisions on each area, anchored to the locked ROADMAP success criteria, the FCTRL
requirements, and the project's recoverability posture. These are recorded as D-01..D-16
in CONTEXT.md and should be validated (not silently overridden) at planning time.

---

## Claude's Discretion

All four presented gray areas were resolved at the user's delegation:
- **Opt-in & consent** → default-off Settings toggle + one-time risk-confirmation dialog;
  control hidden (not disabled) when the hardware fails the gate.
- **Control method & granularity** → bounded slider as the source of truth; single
  unified target clamped per-fan; per-fan control deferred.
- **Failure & fail-closed presentation** → read-back-before-success; on failure restore
  auto + calm inline message; fail-closed hides the control path entirely.
- **Privilege appetite** → prefer root-less in-process write; privileged helper
  (SMAppService + XPC, one-time admin auth) acceptable as a fallback; fail-closed if
  neither can be proven safe and recoverable.

Latitude left to the planner: exact type names/file splits, the final
in-process-vs-helper decision (gated on research), read-back tolerance thresholds, and
precise Chinese copy.

## Deferred Ideas

- Per-fan independent manual targets (unified target this phase).
- Lifecycle recovery on quit/sleep/wake/rollback/capability re-probe (FCTRL-05) → Phase 14.
- Real-hardware UAT sign-off and full unsupported/failure-state UI matrix (UAT-01/02/03) → Phase 14.
- Auto fan curves, profiles, silent/low-noise modes, below-floor control, remote control,
  raw SMC key browser — out of scope (v3.0).
- Free-form numeric RPM entry as a primary input (rejected for a bounded slider).
