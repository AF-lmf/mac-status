# Phase 13: Safe Fan Control Gate & Write Path - Context

**Gathered:** 2026-06-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 13 delivers the **first SMC write path** in MacStatus: an explicitly opt-in,
bounded, verified manual fan-control loop on supported MacBook Pro hardware. Users
who opt in can set a manual fan target that is clamped to live hardware min/max,
every write is read-back verified before being shown as "in effect", and a one-click
"restore system auto control" is always available and also read-back verified. All
raw SMC writes are centralized in a restricted control component/helper; SwiftUI
views call only high-level intent actions.

This phase covers requirements **FCTRL-01, FCTRL-02, FCTRL-03, FCTRL-04, FCTRL-06**.

**Out of this phase (do NOT pull forward):**
- Lifecycle/recovery on quit, sleep, wake, rollback, capability re-probe failure
  (**FCTRL-05**) → Phase 14.
- Real-hardware UAT sign-off and the full unsupported/failure-state UI matrix
  (**UAT-01, UAT-02, UAT-03**) → Phase 14.
- Auto fan curves, temperature-driven scheduling, profiles, silent/low-noise modes,
  any control below the Apple default floor, remote control, raw SMC key browser
  (all v3.0 Out of Scope / Future requirements).
- Status-bar fan/temperature segments and popover-wide layout re-work (Phase 12 done).

</domain>

<decisions>
## Implementation Decisions

> The user delegated every gray-area decision ("全部由你决定"). The decisions below
> are conservative, safety-first calls aligned with the locked ROADMAP success
> criteria, REQUIREMENTS (FCTRL-01..04, 06), and the project's recoverability posture.
> See **Claude's Discretion** for where the planner retains latitude.

### Opt-in Gate & Consent (FCTRL-01)
- **D-01:** Manual fan control is OFF by default; system auto control is always the
  baseline. The master opt-in is a new Settings toggle (e.g. `风扇手动控制`,
  default off), reusing the existing `SettingsManager` UserDefaults toggle +
  `.settingsDidChange` live-reapply pattern.
- **D-02:** The first time the user enables manual control, show a one-time explicit
  risk-confirmation dialog: it explains the hardware risk, that targets are clamped
  to safe hardware bounds, and that the app restores system auto control on failure
  or exit. Explicit confirm required to proceed; cancel leaves system auto control.
- **D-03:** One-time consent. After the first confirmation, re-entering manual control
  does NOT re-prompt with a modal. The manual-control affordance then lives inside the
  existing `温度与风扇` popover section; the current mode and a one-click restore are
  always visible while manual mode is active.
- **D-04:** If the hardware does not pass the safety gate
  (`FanCapabilities.safeControlAvailable == false`), the opt-in toggle is **not offered
  at all** (hidden, not shown-disabled). Read-only monitoring continues unchanged.
  This keeps the "no misleading control entry" promise (FAN-03, Phase 11 D-18).

### Manual Control UI — Input & Granularity (FCTRL-02)
- **D-05:** Primary input is a **slider bounded to the live hardware min/max** for the
  target fan(s). The slider cannot physically request a value below the hardware min /
  Apple default floor, nor a stall/silent value. The resulting target RPM renders as a
  read-only numeric label using the Phase 12 fixed-width, right-aligned, monospaced
  value column.
- **D-06:** No free-form numeric text entry as the primary control (it fights the clamp
  and invites out-of-range input). The planner may add small convenience presets
  (e.g. snap-to-min / snap-to-max), but the slider remains the source of truth.
- **D-07:** Granularity for v3.0 = a **single unified target applied to all fans**. On
  apply, the unified target is clamped per-fan against each fan's own live min/max.
  Per-fan independent control is deferred (more surface, more failure modes; not needed
  for a safe closed loop).

### Write & Read-Back Verification (FCTRL-03)
- **D-08:** Every control action (enter manual / set target / restore auto) writes via
  the restricted control component, then reads back **mode + target RPM + current RPM**.
  The UI shows "手动已生效" only after read-back confirms the expected mode and target.
  An IOKit "success" return is never trusted on its own.
- **D-09:** Read-back reuses the existing read path for the same key family the
  diagnostic probe already covers (`FS! ` / `F{i}Md` / `F{i}Tg` / `F{i}Ac`). Mode and
  target must match exactly; current RPM may be within a ramp tolerance (fans take time
  to spin up/down). The planner sets the exact tolerance.

### Failure & Fail-Closed Presentation
- **D-10:** If a write fails OR read-back disagrees, immediately attempt to restore
  system auto control, revert the UI to the system-auto state, and show a calm **inline**
  message (e.g. `控制未生效，已恢复自动`). No modal, no repeated error spam
  (Phase 10/11 calm-degradation pattern).
- **D-11:** The one-click "恢复系统自动控制" is always present while manual mode is
  engaged; restore also read-back verifies and only shows success once the mode confirms
  auto (FCTRL-04). If restore itself cannot be verified, surface it calmly but clearly
  and hold the restore-to-auto posture. (Full lifecycle hardening is Phase 14.)
- **D-12:** Decision-gate fail-closed: if, on the validation hardware, the write /
  read-back / restore cannot be proven safe and recoverable, the manual-control path
  stays unavailable (toggle hidden) and read-only thermal+fan monitoring continues.
  Use a calm capability note consistent with Phase 11 (`控制未启用`) rather than
  disabled buttons.

### Write Mechanism & Privilege (appetite for FCTRL-06)
- **D-13:** Prefer least privilege. Research MUST first determine whether SMC fan-control
  writes succeed from the in-process AppleSMC user-client **without root**. If root-less
  writes work and read-back verifies, keep the single-process, zero-dependency model
  (matches MacStatus's lightweight identity).
- **D-14:** If writes require root, a **privileged helper (SMAppService daemon + XPC,
  one-time admin authorization)** is an ACCEPTABLE fallback — the app already uses
  SMAppService for the login item, and a one-time admin prompt is a reasonable cost for
  hardware control. The helper must expose only high-level bounded control actions
  (`setManualTarget(rpm:)`, `restoreAutoControl()`), never raw-key passthrough.
- **D-15:** Fail-closed always wins. If neither a verified root-less write nor a
  verifiable helper path can be proven safe + recoverable on the hardware, ship
  read-only (control unavailable). Do not ship an unverifiable write path.

### Write Centralization (FCTRL-06)
- **D-16:** All raw SMC writes are centralized in a **restricted control component /
  helper**, separate from the existing read-only `SMCReader` (which stays read-only).
  SwiftUI views call only high-level intent actions and never construct or write raw
  SMC keys.

### Claude's Discretion
- The planner chooses exact type names and file splits, the final in-process-vs-helper
  decision (gated on research findings), read-back tolerance thresholds, and the precise
  Chinese copy — as long as the locked safety invariants above hold:
  default-auto, explicit opt-in, clamp-to-live-bounds, read-back-before-success,
  always-available verified restore, centralized writes, and fail-closed.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Scope & Requirements
- `.planning/PROJECT.md` — v3.0 scope, lightweight menu-bar identity, hardware-safety
  constraints, and the pending fan-control key decisions.
- `.planning/REQUIREMENTS.md` — FCTRL-01..06 and UAT-01..03 (note FCTRL-05 + UAT are
  Phase 14), plus Out-of-Scope / Future items that prevent fan-control scope creep.
- `.planning/ROADMAP.md` — Phase 13 goal, the 5 success criteria, the explicit
  **decision gate** (fail-closed if SMC write / helper-XPC / mode switch / read-back
  cannot be proven safe and recoverable), and dependencies on Phases 11 & 12.

### Prior Phase Decisions & Evidence
- `.planning/phases/11-fan-read-only-rpm-capability-model/11-CONTEXT.md` — fan capability
  model, no-control-affordance posture (D-17/D-18), and `Mac15,9` validation target.
- `.planning/phases/11-fan-read-only-rpm-capability-model/11-HARDWARE-PROBE.md` — local
  `Mac15,9` read-only SMC fan probe evidence (FNum, F{i}Ac/Mn/Mx/Tg, FS! / Ftst).
- `.planning/phases/11-fan-read-only-rpm-capability-model/11-SECURITY.md` — the no-write
  security gate this phase deliberately opens (and must keep bounded).
- `.planning/phases/10-thermal-read-only-monitoring/10-SECURITY.md` — original SMC
  no-write threat posture and calm-degradation expectations.
- `.planning/phases/12-popover-layout-stability/12-CONTEXT.md` — 372pt popover + fixed
  value-column rules the new control UI must preserve.

### v3.0 Research
- `.planning/research/STACK.md` — zero-dependency macOS monitoring/SMC stack constraints.
- `.planning/research/ARCHITECTURE.md` — proposed separation between `FanReader` and a
  future `FanControlManager`.
- `.planning/research/PITFALLS.md` — SMC trust, write-safety, and recovery pitfalls.
- `.planning/research/FEATURES.md` — fan-control UX and anti-features.

### Existing Code
- `MacStatus/MacStatus/Readers/SMCReader.swift` — read-only AppleSMC client; the write
  path is a NEW, separate restricted type (this file stays read-only).
- `MacStatus/MacStatus/Readers/FanReader.swift` — `FanCapabilities.safeControlAvailable`
  (currently hardcoded `false`, the fail-closed gate), `diagnosticReadings()` already
  probing `FS! ` / `F{i}Md` / `F{i}Tg`, and the `Mac15,9` catalog.
- `MacStatus/MacStatus/Collectors/MetricCollector.swift` — @MainActor tick, last fan
  snapshot, DashboardState update flow the control state must integrate with.
- `MacStatus/MacStatus/UI/Views/DashboardView.swift` — the `温度与风扇` popover section
  the control affordance attaches to.
- `MacStatus/MacStatus/UI/Views/SettingsView.swift` + `Utils/SettingsManager.swift` —
  the opt-in toggle placement and live `.settingsDidChange` pattern.
- `MacStatus/MacStatus/App/AppDelegate.swift` — existing `SMAppService` login-item usage
  (precedent for a privileged-helper fallback, if research requires one).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SMCReader` provides the read path used for read-back verification; it must remain
  read-only. The control write path is a new, restricted, separate type.
- `FanReader` / `FanCapabilities` already model `safeControlAvailable` (the gate to flip)
  and already probe the control-relevant keys read-only via `diagnosticReadings()`.
- `MetricCollector` keeps fan snapshots out of persisted history — control state should
  likewise stay non-persistent runtime state (no SQLite/history writes).
- `SettingsManager`/`SettingsView` already support default-valued toggles + live reapply,
  ideal for the opt-in master switch.
- `SMAppService` is already used for the login item — a reusable precedent if a
  privileged helper turns out to be required.

### Established Patterns
- Calm degradation: `N/A` / inline notes instead of modals; no error spam.
- Optional/nil = normal unavailable state, not an exception path.
- Popover-only, non-persistent runtime data for v3.0 cooling features.
- Live settings reapply preserving the current data model as source of truth.

### Integration Points
- New restricted control component/helper owning all raw SMC writes (FS!/F{i}Md/F{i}Tg).
- New control state on the collector/DashboardState (mode, target, last-verified result).
- Opt-in toggle in `SettingsManager`/`SettingsView`; control affordance + mode indicator
  + restore button inside the `温度与风扇` `DashboardView` section.
- Flip `FanCapabilities.safeControlAvailable` only when the hardware passes the gate.

</code_context>

<specifics>
## Specific Ideas

- The user delegated all gray-area decisions to Claude ("全部由你决定"); decisions above
  are the conservative safety-first defaults to validate at planning time.
- Validation hardware is MacBook Pro `Mac15,9` (Apple M3 Max), 2 fans, `FNum=2`,
  `F{i}Ac/Mn/Mx/Tg` readable, `F{i}ID` missing.

</specifics>

<deferred>
## Deferred Ideas

- Per-fan independent manual targets — deferred beyond v3.0; unified target this phase.
- Lifecycle recovery on quit/sleep/wake/rollback/capability re-probe (FCTRL-05) → Phase 14.
- Real-hardware UAT sign-off and full unsupported/failure-state UI matrix
  (UAT-01/02/03) → Phase 14.
- Auto fan curves, temperature-driven scheduling, profiles, silent/low-noise modes,
  below-floor control, remote control, raw SMC key browser — out of scope (v3.0).
- Free-form numeric RPM entry as a primary input — rejected in favor of a bounded slider.

</deferred>

---

*Phase: 13-Safe Fan Control Gate & Write Path*
*Context gathered: 2026-06-26*
