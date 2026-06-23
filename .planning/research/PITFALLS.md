# Pitfalls Research — MacStatus v3.0 Fan and Thermal Features

**Domain:** native macOS menu bar monitor adding SMC temperatures, MacBook Pro fan RPM, safe fan control, lifecycle recovery, unsupported-machine degradation, and popover layout stability.
**Researched:** 2026-06-23
**Confidence:** MEDIUM-HIGH

## Summary

v3.0's risk is not the read path alone. MacStatus already has a working read-only `SMCReader` for `PSTR` / `PPBR`, with the important Swift ABI lesson captured in code: `SMCParamStruct` must stay 80 bytes or AppleSMC calls silently fail. The dangerous change is adding writes for fan mode and target RPM. That crosses from "display nil if unavailable" into hardware control, where a bad default, failed reset, sleep/wake drift, or false UI state can leave the user believing the machine is protected when it is not.

The roadmap should separate fan/thermal into ascending-risk phases:

1. **Thermal and fan read-only foundation** — extend SMC decoding, discover available keys, display N/A for unsupported sensors, and add sanity filtering. No writes.
2. **Fan capability model and unsupported-machine UX** — derive fan count, min/max/current RPM, mode availability, Apple Silicon key casing, and control eligibility. Still no writes.
3. **Safe fan write path behind explicit user action** — add write support, bounds, actual-RPM verification, reset-to-auto, failure rollback, and hardware UAT.
4. **Lifecycle recovery** — application termination, sleep, wake, crash-adjacent mitigations, and stale manual-state cleanup.
5. **Popover layout stability** — fixed columns, monospaced digits, explicit row widths, stable popover sizing, and visual regression checks for large network/process/fan values.

Hardware safety priority: **manual fan control must be opt-in, bounded by detected hardware min/max, verified after every write, and always paired with a visible "restore automatic" control plus lifecycle resets.** If any part of capability detection or reset verification is inconclusive, ship read-only fan RPM first and defer control.

## High-Risk Pitfalls

### 1. Extending `SMCReader` from read-only to write without a hard safety boundary

**What goes wrong:** A shared `readValue(key:)` utility is expanded with generic `write(key:value:)`, then UI code writes arbitrary SMC keys. A wrong key, wrong byte encoding, or write to a fan mode key can persist until system/SMC recovery. Worse, IOKit can return success while the SMC-level result rejects the write; treating only `kIOReturnSuccess` as success creates a false "manual mode active" UI.

**Why it happens:** Existing [SMCReader.swift](MacStatus/MacStatus/Readers/SMCReader.swift) is intentionally small and read-only. Stats' SMC implementation has separate `writeBytes`, write encoding, retry, and SMC-level output-result validation. MacStatus does not yet have any of that.

**Warning signs:**
- A public `writeValue(key: String, value: Double)` accepts any 4-char key.
- Write code checks only `IOConnectCallStructMethod == kIOReturnSuccess`.
- UI updates to "manual" before reading back `F0Md`/`F0md` and actual RPM.

**Prevention:**
- Keep read-only `SMCReader` intact; introduce a narrow `FanController` with methods like `setManual(fanID:rpm:)`, `restoreAutomatic(fanID:)`, `restoreAllAutomatic()`.
- Write only allowlisted keys: `FNum`, `F{id}Ac`, `F{id}Mn`, `F{id}Mx`, `F{id}Tg`, mode key (`F{id}Md` or `F{id}md`), `FS! ` where applicable, and `Ftst` only when Apple Silicon unlock logic is explicitly implemented.
- Validate SMC-level result byte from the output struct after write, not only IOKit return.
- After every write, read back mode/target/current RPM and expose "pending / failed / verified" state.

**Phase placement:** Phase 3 — Safe Fan Control Write Path. Do not add any write API in Phase 1/2.

### 2. Using the wrong SMC encoding for RPM, temperature, or fan target values

**What goes wrong:** Fan RPM displays as millions, 0, or nonsense; fan target writes are ignored or set the wrong target; temperatures are implausible. Common causes are decoding `fpe2` as integer, treating `flt ` as big-endian, or assuming all temperature keys use the same fixed-point format.

**Why it happens:** Existing MacStatus decode supports `'flt '` and generic `spXY`/`fpXY`, but fan RPM commonly uses `fpe2` (`raw / 4`) and fan target can be `flt ` or `fpe2`. Stats explicitly handles many SMC data types; smcFanControl's old code also handles `fpe2`, `ui8`, `ui16`, and `sp78`.

**Warning signs:**
- RPM greater than detected `F{id}Mx` by large factors.
- Temperature is 0, 129, below 10 C under load, or above 120 C.
- Fan target write appears to succeed but `F{id}Ac` never moves toward target.

**Prevention:**
- Add explicit decode/encode support for `fpe2`, `ui8`, `ui16`, `ui32`, `sp78`, and `flt ` before reading fan/thermal keys.
- For RPM, require sanity: `0 <= current <= max + tolerance`, `min <= max`, `max` within plausible Mac fan range.
- For temperature, filter invalid readings: hide 0, negative, >110-120 C unless confirmed by another sensor.
- Unit-test codec round trips: `fpe2(1200 RPM) -> raw 4800 -> 1200`, `flt(2500.0) -> 2500`.

**Phase placement:** Phase 1 — Thermal and Fan Read-Only Foundation.

### 3. Assuming SMC temperature key names are stable across Intel, M1, M2, M3, M4

**What goes wrong:** The app shows N/A on supported hardware, chooses a cold/irrelevant sensor as "CPU", or crashes when a key is absent. Apple Silicon generations use different CPU/GPU key families; Stats maintains a platform-specific sensor list and also calculates averages/hottest values across multiple keys.

**Why it happens:** Project code currently reads specific power keys (`PSTR`, `PPBR`) but not a discovered temperature inventory. A single hard-coded "CPU diode" key such as `TC0D` is Intel-centric and insufficient for Apple Silicon.

**Warning signs:**
- CPU temperature is always N/A on M3/M4 while Stats or another monitor has values.
- A single sensor jumps wildly while others are stable.
- "CPU" temperature is lower than ambient or stuck.

**Prevention:**
- Build an inventory reader: enumerate SMC keys via `#KEY` + index reads, then intersect with a curated key list.
- Prefer "hottest CPU/SoC" and "average CPU/SoC" derived from multiple valid keys over one magic key.
- Ship a small platform map for known families, but always probe keys at runtime and degrade per field.
- Label confidence in UI: "CPU", "SoC", "GPU" only when key group is known; unknown keys stay hidden unless a debug setting exposes them.

**Phase placement:** Phase 1. Deeper key-map research may be needed per Apple Silicon generation.

### 4. Treating fan count and fan availability as "MacBook Pro == controllable fans"

**What goes wrong:** Fan controls appear on fanless MacBook Air, Mac mini/Studio, or machines where fan keys are absent/read-only. Users see sliders that do nothing, or the app writes mode keys for nonexistent fans.

**Why it happens:** Product scope says "MacBook Pro fan RPM", but hardware capability must come from SMC probing, not marketing model names. `FNum` can be 0/absent, fan ID strings can be absent, and some systems expose read-only telemetry without working control.

**Warning signs:**
- UI shows "Fan 0" with min/max 0/0.
- `FNum` absent but controls still render.
- `F{id}ID` missing and fallback labels are shown while min/max are invalid.

**Prevention:**
- Capability model per fan: `isPresent`, `canReadRPM`, `hasMinMax`, `canWriteTarget`, `canWriteMode`, `supportsAutoRestore`.
- Render read-only RPM when control is not verified; hide sliders unless all control capabilities pass.
- Treat unsupported as normal: display "Fan: N/A" or hide fan section, never show 0 RPM as "fan stopped" unless `FNum > 0` and current read is valid.

**Phase placement:** Phase 2 — Fan Capability Model and Unsupported-Machine UX.

### 5. Allowing fan target below Apple default minimum or outside detected bounds

**What goes wrong:** A slider or preset sets a fan below hardware default minimum, to 0, or above max. On older Intel Macs this can reduce cooling margin; on newer Apple Silicon it can cause no-op writes while the UI still claims control.

**Why it happens:** Users expect "quiet" control, but the project explicitly outlaws unbounded fan control. smcFanControl's README documents the safety principle: do not allow minimum speed below Apple's defaults.

**Warning signs:**
- UI slider range starts at 0 RPM.
- Settings persist manual RPM without clamping after hardware min/max changes.
- Presets like "silent" lower fan speed below `F{id}Mn`.

**Prevention:**
- Clamp target to `detectedMin...detectedMax`; if min/max missing, control is disabled.
- Provide only "Automatic", "Higher cooling", and bounded manual values, not "silent".
- Never store a target lower than current hardware min; re-clamp persisted values at startup.
- Display detected min/max next to controls for transparency.

**Phase placement:** Phase 3. This is a release blocker for fan control.

### 6. Apple Silicon protected fan mode: writes appear successful but thermalmonitord overrides them

**What goes wrong:** Manual fan speed UI says it is active, but fans do not change. On newer Apple Silicon, Stats issue #2928 reports that `thermalmonitord` can block direct writes to mode/target unless a force/test key (`Ftst`) is coordinated; writes may require retries over seconds and `Ftst=0` to restore automatic control.

**Why it happens:** Intel-era fan control (`FS! ` + `F{id}Md` + `F{id}Tg`) is not enough for all Apple Silicon systems. Stats' current SMC code probes lower-case mode keys on arm64, tries `Ftst`, waits/retries, and resets `Ftst` or modes on return to automatic.

**Warning signs:**
- `F{id}Tg` readback changes but `F{id}Ac` does not respond after 5-10 seconds.
- Mode key alternates between automatic/system/manual after write.
- Manual works only after the system has already spun fans up.

**Prevention:**
- For arm64, probe mode key casing (`F0md` vs `F0Md`) before writes.
- Treat `Ftst` support as a separate capability; if absent or unverified, disable manual control rather than guessing.
- Implement retry with bounded timeout and rollback on failure.
- Confirm actual RPM response within a tolerance window before declaring manual mode active.

**Phase placement:** Phase 3, with hardware-specific research flag. Consider shipping Apple Silicon fan control behind an experimental toggle until verified on target models.

### 7. Sleep/wake and long uptime can desynchronize fan mode from UI state

**What goes wrong:** The app goes to sleep in automatic mode and wakes showing manual, or wakes showing manual while the system has regained automatic control. Stats issues #2094 and #2104 show real-world failures: newer Apple Silicon systems can turn fans off, later resume system control, or wake with stale manual state.

**Why it happens:** SMC/thermal daemon state changes while the app is suspended. Existing MacStatus has wake recovery for battery time estimates, but no fan-mode reconciliation or automatic reset path.

**Warning signs:**
- After wake, UI mode disagrees with `F{id}Md`/`F{id}md` or `FS! ` readback.
- Manual target persists in UserDefaults but actual mode is automatic.
- Fan target of 0% is shown as manual after sleep.

**Prevention:**
- On `NSWorkspace.willSleepNotification`: restore all fans to automatic if MacStatus has ever entered manual mode in the session.
- On `didWakeNotification`: delay 3-5 seconds, re-open/revalidate SMC if needed, read fan mode/RPM, and reconcile UI from hardware truth.
- Never infer active manual state from settings alone; hardware readback is source of truth.
- Add visible status: "Automatic", "Manual verified", "Restoring automatic...", "Manual unavailable".

**Phase placement:** Phase 4 — Lifecycle Recovery.

### 8. Missing termination recovery leaves fans in manual mode

**What goes wrong:** User quits the menu bar app while manual fan mode is active. If `applicationWillTerminate` does not restore automatic mode, the SMC may retain manual setting until another tool, reboot, or system daemon restores it. This is a hardware-safety issue.

**Why it happens:** Current [AppDelegate.swift](MacStatus/MacStatus/App/AppDelegate.swift) starts collectors but has no termination hook. Existing code did not need one because all readers were telemetry-only.

**Warning signs:**
- No `applicationWillTerminate`.
- Quit button directly calls `NSApplication.shared.terminate(nil)` with no fan cleanup.
- Manual fan mode remains after app quit in manual UAT.

**Prevention:**
- Add `applicationWillTerminate` and call `FanController.restoreAllAutomatic()` synchronously with a short timeout.
- Also restore on settings toggle-off, fan section disabled, and before releasing SMC connection.
- Keep a session flag `hasTakenManualControl`; avoid writing reset keys on machines where MacStatus never took control.
- Document that `kill -9` cannot be recovered; mitigate by making manual control opt-in and not persisted as an always-on default.

**Phase placement:** Phase 4. Must be completed before any public fan-control build.

### 9. Blocking the main actor with SMC enumeration, retries, or fan-control waits

**What goes wrong:** Popover animation stutters, settings controls freeze, or status updates pause while SMC key enumeration or `Ftst` retry loops run. Stats' Apple Silicon unlock path can wait/retry for several seconds; doing that on `@MainActor` would be visible.

**Why it happens:** Current `MetricCollector` is `@MainActor` and calls all readers synchronously on its timer. That is acceptable for cheap read paths, but fan-control retries and full key enumeration are heavier and stateful.

**Warning signs:**
- `usleep`, long retry loops, or `getAllKeys()` called from `MetricCollector.tick()`.
- Fan write action blocks UI until complete.
- Self CPU footer spikes during popover open.

**Prevention:**
- Keep periodic read path cheap: read only discovered keys, not full enumeration every tick.
- Run full inventory once at startup or on manual refresh in a dedicated actor/queue.
- Run fan writes in a `FanControlActor`; publish Sendable snapshots to MainActor.
- Never run multi-second unlock/retry loops inside SwiftUI button actions on MainActor.

**Phase placement:** Phase 1 for inventory design; Phase 3 for write actor.

### 10. Assuming one SMC connection is safe across sleep, wake, and failed writes

**What goes wrong:** Reads degrade to nil forever after wake; writes fail after a transient SMC/IOKit state change; the app keeps showing stale last values.

**Why it happens:** Existing `SMCReader.open()` is idempotent and opens once. That is fine for v2 power display, but v3 fan control needs stronger recovery semantics.

**Warning signs:**
- After wake, all SMC fields become N/A until app restart.
- `isOpen == true` but every `IOConnectCallStructMethod` fails.
- Close/open is not attempted after repeated failures.

**Prevention:**
- Count consecutive SMC call failures; after threshold, close and reopen the AppleSMC connection.
- On wake, explicitly reopen or validate with a cheap key (`FNum` or `#KEY`) before trusting readings.
- Clear stale fan/thermal snapshots to N/A if validation fails; do not keep old temperatures/RPM.

**Phase placement:** Phase 4, with read-path hooks established in Phase 1.

## Layout Pitfalls

### 1. Popover preferred size changes every tick as network/fan strings change

**What goes wrong:** The NSPopover resizes or shifts as network values grow from `999K` to `1.2GB`, fan rows appear/disappear, or temperatures change digit count. Current `PopoverManager` uses `NSHostingController.sizingOptions = [.preferredContentSize]`, so SwiftUI content's ideal size can drive popover size.

**Existing project evidence:** [PopoverManager.swift](MacStatus/MacStatus/UI/PopoverManager.swift) opts into preferred-content sizing; [DashboardView.swift](MacStatus/MacStatus/UI/Views/DashboardView.swift) fixes width at 320 but lets height follow content. Phase 9 already fixed network card jitter by forcing up/down onto separate lines.

**Warning signs:**
- Popover width or arrow position shifts while open.
- Network card alternates between one-line and two-line layout.
- Adding thermal/fan rows causes bottom footer to jump.

**Prevention:**
- Keep `.frame(width: 320)` or choose a new fixed width; do not let fan rows widen the popover.
- Use `Grid` / aligned columns for rows: label column fixed or leading, value column fixed trailing.
- Use monospaced digits for all numeric values: `.font(.system(.caption, design: .monospaced))` or `.monospacedDigit()`.
- Reserve stable row count where possible: show `N/A` in the same row instead of inserting/removing rows on every tick; hide whole sections only on capability changes, not transient nil reads.
- If content grows taller than target, use a bounded `ScrollView` rather than changing popover size on every update.

**Phase placement:** Phase 5 — Popover Layout Stability, with a small pre-check in each feature phase before merging UI rows.

### 2. Process/network rows have unconstrained trailing content

**What goes wrong:** Long process names plus upload/download labels squeeze each other; labels overlap or shift. The current `ProcessMetricRow` puts process name, optional PID, `Spacer()`, then trailing content with no fixed value width.

**Warning signs:**
- A process with a long name pushes network labels offscreen.
- `MB/s`/`GB/s` units wrap unexpectedly.
- CPU/memory rows and network rows align differently.

**Prevention:**
- Give process name a bounded max width and value cluster a fixed width.
- For network process rows, replace two inline `Label`s with a compact two-column value view (`up`, `down`) using fixed width and trailing alignment.
- Use `.layoutPriority(1)` on value columns and `.lineLimit(1).truncationMode(.middle)` on process names.
- Add preview/test data with long process names, six-digit PIDs, and `999.9 MB/s` / `1.2 GB/s`.

**Phase placement:** Phase 5. This can be implemented independently of fan control.

### 3. Dynamic section insertion causes vertical jumping while popover is open

**What goes wrong:** Thermal/fan sections appear, disappear, or change row count as keys temporarily fail. The footer and process lists jump, and a user trying to click a fan control may click the wrong row after a tick.

**Warning signs:**
- A fan row disappears when one read returns nil, then reappears next tick.
- A slider moves vertically while the user is dragging it.
- Battery/fan/thermal section order changes based on available keys.

**Prevention:**
- Split capability (`available sensors/fans`) from live values. Capability changes only after startup scan, manual rescan, or wake recovery, not every tick.
- For transient read failure, keep the row and show `N/A` / stale marker for a short grace period.
- Disable controls during write/recovery rather than removing them.

**Phase placement:** Phase 2 for capability model; Phase 5 for layout acceptance tests.

## Safety Guardrails

These guardrails should be acceptance criteria, not implementation notes.

| Guardrail | Required Behavior | Phase |
|-----------|-------------------|-------|
| Read-only first | First fan/thermal phase must not contain any SMC write method or UI fan control. | Phase 1 |
| Narrow writer | Only `FanController` can write SMC; no generic public SMC key writer. | Phase 3 |
| Capability-gated UI | Controls render only when `FNum`, current RPM, min/max, mode key, target key, and auto-restore are verified. | Phase 2/3 |
| Bounded target | Manual target is clamped to detected hardware min/max; never below Apple default min. | Phase 3 |
| Actual-state source of truth | UI mode is derived from readback, not UserDefaults. | Phase 3/4 |
| Restore automatic | Provide one-click restore, restore on quit, restore before sleep, restore on disabling control, and verify readback. | Phase 3/4 |
| Failure rollback | Any failed write/unlock/retry attempts immediate restore automatic and marks control unavailable. | Phase 3 |
| No stale telemetry | Invalid temp/RPM values show N/A, not cached old values, after a short explicit grace if needed. | Phase 1/4 |
| Low overhead | No full SMC key enumeration on every tick; no multi-second retries on MainActor. | Phase 1/3 |
| Hardware UAT | Fan control cannot be marked complete without real MacBook Pro hardware tests: Intel if supported, Apple Silicon target model, sleep/wake, quit, and unsupported-machine path. | Phase 3/4 |

## Verification Traps

### Trap 1: `xcodebuild` succeeds while new files are not in the Xcode target

Phase 7 had a documented false positive: `BatteryReader.swift` initially existed but was not registered in `project.pbxproj`, so build success did not prove the file compiled. v3 phases adding `FanController.swift`, `ThermalReader.swift`, or new views must assert target membership.

**Verification:** `xcodebuild` plus `project.pbxproj` source entry grep for every new Swift file.

### Trap 2: Simulator or developer machine cannot validate hardware behavior

Thermal/fan behavior requires real hardware. A MacBook Air fanless path, MacBook Pro fan path, and desktop unsupported path are different. If only one machine is available, mark verification `human_needed` and do not claim full support.

**Verification:** UAT matrix includes at least:
- Apple Silicon MacBook Pro with fans.
- Fanless or unsupported Apple Silicon Mac if available.
- Desktop Mac path if available.
- Sleep/wake and quit while manual control is active.

### Trap 3: "Write returned success" is not a successful fan-control test

IOKit success does not prove the fan changed. The SMC output result and actual `F{id}Ac` RPM response must be checked. On Apple Silicon, thermal daemon can override writes.

**Verification:** For a manual target, read back mode/target immediately, then actual RPM over 5-10 seconds. If actual RPM does not trend toward target, UI must show failure/unavailable.

### Trap 4: Layout tests with ordinary values miss the jitter

Normal values (`12K/s`, short process names, two-digit temperatures) won't expose layout jitter.

**Verification:** Add deterministic preview/test snapshots:
- Network card: `↑999.9 MB/s`, `↓1.2 GB/s`.
- Process row: very long process name, six-digit PID, high upload and download labels.
- Fan row: two fans, `0 RPM`, `9999 RPM`, long fan names, unavailable target.
- Thermal row: all values N/A, three-digit temperatures, warning labels.

### Trap 5: Persisted manual settings outlive capability changes

If manual target is stored in UserDefaults and hardware capability changes after OS update, reboot, or model migration, startup may apply stale values to the wrong fan or invalid range.

**Verification:** Startup must load settings, probe capabilities, clamp/drop invalid persisted values, and never auto-apply manual fan control without explicit user action in the current session.

## Sources/Evidence

### Project Source Evidence

- `.planning/PROJECT.md` — v3.0 active requirements and safety constraints: fan RPM, key temperatures, bounded fan control, unsupported-machine N/A, layout stability.
- `.planning/STATE.md` — existing decisions: Swift 6 strict concurrency, SMC `PSTR`/`PPBR`, SMCParamStruct 80-byte ABI issue, network vertical layout fix.
- `.planning/milestones/v2.0-phases/07-battery-power/07-*.md` — IOKit memory-management patterns, probe-and-nil, wake suppression, false-positive target registration lesson.
- `.planning/milestones/v2.0-phases/09-settings-window-ui-customization/09-*.md` — SettingsManager observation pitfalls, popover section gating, network vertical-layout stabilization.
- `MacStatus/MacStatus/Readers/SMCReader.swift` — current read-only AppleSMC client, 80-byte struct guard, `flt ` and fixed-point decode, `IOServiceOpen`/`IOServiceClose` lifecycle.
- `MacStatus/MacStatus/Readers/BatteryReader.swift` — SMC integration in existing tick path, `PSTR`/`PPBR`, `AppleSmartBattery`, wake observer on `.main`.
- `MacStatus/MacStatus/Collectors/MetricCollector.swift` — `@MainActor` synchronous tick; safe for cheap reads, risky for enumeration/retry writes.
- `MacStatus/MacStatus/UI/PopoverManager.swift` — `NSPopover`, `.transient`, `NSHostingController.sizingOptions = [.preferredContentSize]`.
- `MacStatus/MacStatus/UI/Views/DashboardView.swift` and `ProcessListView.swift` — fixed 320 width, network forced multiline, process rows with unconstrained trailing content.
- `MacStatus/MacStatus/App/AppDelegate.swift` — no termination recovery hook yet; required before fan control.

### External Primary / Near-Primary Evidence

- Linux `drivers/hwmon/applesmc.c` (Codebrowser) — defines fan keys `FNum`, `FS! `, `F%dAc`, `F%dMn`, `F%dMx`, `F%dSf`, `F%dTg`; shows fan control is an SMC write domain and uses serialized SMC access. Confidence: MEDIUM for macOS key semantics, HIGH for historical SMC key names.
- exelban/stats `SMC/smc.swift` — current production-grade Swift SMC implementation: many data types, `fpe2` decode, arm64 `F{id}md` vs `F{id}Md` probing, `Ftst` unlock/retry, reset fan control, and SMC-level write-result validation. Confidence: HIGH as ecosystem source evidence.
- exelban/stats `Modules/Sensors/readers.swift` and `values.swift` — fan loading via `FNum`, key inventory, invalid temperature filtering, per-generation temperature key lists, calculated hottest/average sensors. Confidence: HIGH for ecosystem patterns.
- hholtmann/smcFanControl source and README — historical fan-control safety stance: raise minimum speed only and do not allow below Apple's defaults; old Objective-C source reads `FNum`, `F{id}Ac`, `F{id}Mn`, `F{id}Mx`, `F{id}ID`. Confidence: MEDIUM because project is old, but safety principle remains relevant.
- exelban/stats issue #2928 (opened 2026-01-24) — Apple Silicon M3/M4+ manual fan writes can silently fail because thermal daemon blocks direct writes unless protected-mode coordination is done. Confidence: MEDIUM (issue evidence, but matches current Stats code changes).
- exelban/stats issues #2094 and #2104 — real lifecycle failures around fans turning off, sleep/wake, stale manual state, and UI disagreeing with system control. Confidence: MEDIUM.
- smcFanControl issue #77 — old unsupported 2018 MacBook Pro showing wildly wrong RPM, evidence that new models can break old key/encoding assumptions. Confidence: LOW-MEDIUM.
- Apple Developer Documentation URLs: `NSHostingController.sizingOptions`, `NSPopover.Behavior.transient`, `NSPopoverDelegate.popoverDidClose(_:)`. Pages require JavaScript in WebFetch, but official docs confirm the APIs used by current project. Confidence: HIGH for API existence, LOW for details from fetched content.

### Inferences Labeled

- **Inference:** Manual SMC fan mode may persist after normal quit unless reset. This is inferred from SMC write semantics and ecosystem issues; exact persistence varies by model/daemon behavior. Treat as high risk because prevention is cheap and hardware-safety critical.
- **Inference:** Apple Silicon fan control should start experimental or read-only unless tested on the user's target MacBook Pro generation. This follows from Stats' recent M3/M4 issue and current code complexity.
- **Inference:** Full SMC key enumeration on every status tick would harm responsiveness. Current MacStatus tick is `@MainActor`; Stats does inventory separately and maintains sensor lists. Treat as a performance risk requiring design prevention.
