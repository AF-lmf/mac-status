# Feature Research — MacStatus v3.0 Fan and Thermal UX

**Domain:** macOS menu-bar system monitor — fan RPM, key temperatures, safe fan control, stable popover layout  
**Researched:** 2026-06-23  
**Confidence:** MEDIUM-HIGH  
**Scope:** user-visible behavior only for NEW v3.0 features. Existing CPU/GPU/memory/network, battery/power, Top-N process lists, and settings are treated as shipped foundations.

## Summary

MacStatus v3.0 should treat cooling as a lightweight, glanceable status layer, not as a full thermal workstation. The primary user story is: "I open the menu-bar popover and immediately know whether the Mac is warm, whether the fans are spinning, and whether any manual fan override is active." The menu bar may expose an optional compact cooling segment, but the popover is the main surface for detail.

The recommended UX is a single **Cooling / Thermal** section in the popover, backed by two concepts: readable sensors and controllable fans. Temperature monitoring should prioritize a small curated set: CPU/SoC first, then GPU, battery, SSD only when available and trustworthy. Unsupported or unmapped sensors are normal; the UI should show "N/A", "未读取", or hide secondary rows rather than alarming the user.

Fan control is the highest-risk feature and must be opt-in. Default behavior is always **Auto (system controlled)**. Manual control should be bounded, reversible, visibly marked, and restored to Auto on app quit, sleep/wake recovery failure, control failure, or when the user clicks one obvious "恢复自动" action. Do not ship a fan-control UI that can set arbitrary raw values, disable fans, persist unsafe state invisibly, or fight macOS thermal management.

Popover layout stability is part of the feature, not polish. Existing code already pins `DashboardView` to 320pt, uses monospaced text in metric cards, and changed network values to vertical `↑/↓` lines. v3.0 should extend that discipline: fixed-width numeric columns, reserved RPM/temperature value space, stable row heights, and no popover width/height oscillation while network numbers, temperatures, fan RPM, or control state changes.

## Table Stakes

Features users will expect once "fan and thermal" exists. Missing these makes the milestone feel incomplete.

| Feature | Why Expected | Complexity | User-Visible Behavior |
|---------|--------------|------------|-----------------------|
| Cooling section in popover | A menu-bar monitor needs one obvious place for temperatures and fans. | LOW-MED | Add a full-width section after existing metric cards/battery. Title should be calm: `散热` or `温度与风扇`. It should not open a separate window for normal reading. |
| Primary CPU/SoC temperature | CPU/SoC temperature is the key thermal signal users ask for. | MEDIUM | Show one primary row/card value such as `SoC 58°C` or `CPU 62°C`. If unavailable, show `SoC N/A` and keep the rest of the app normal. |
| Curated secondary temperatures | Users expect GPU/battery/SSD when readable, but not a raw sensor dump. | MEDIUM-HIGH | Show GPU, Battery, SSD only when mapped/readable. Keep labels human-readable. Do not expose dozens of cryptic SMC keys in v3.0. |
| System thermal state label | Apple exposes system-level thermal state; it is useful context when exact sensors are missing. | LOW | Show `状态：正常 / 偏热 / 严重 / 临界` derived from `ProcessInfo.thermalState`. This is a supplement, not a replacement for sensor temperatures. |
| Fan RPM monitoring | MacBook Pro users expect current fan speed and fan count. | MEDIUM | Show `风扇 1 2400 RPM`; for dual-fan machines show two rows or a concise `左/右` pair. Fanless or unreadable hardware should show `无风扇` or hide the control rows without an error alert. |
| Auto/manual fan mode visibility | Users must always know whether MacStatus changed hardware behavior. | LOW-MED | Every fan row should show `Auto` or `Manual`. If any manual override is active, the section header should visibly indicate it, e.g. `手动中`. |
| Safe manual RPM control | Control is in scope, but only with bounds and recovery. | HIGH | Provide an explicit manual control per fan or "all fans" control. Slider/input must clamp to discovered min/max RPM or a conservative safe range. Never allow `0`, below-min, or arbitrary raw writes. |
| One-click restore Auto | Restoring system control is mandatory. | MEDIUM-HIGH | A persistent `恢复自动` button is visible whenever manual mode is active. It should work for all fans, not require visiting multiple rows. |
| Restore Auto on lifecycle events | Users should not be left in manual fan mode accidentally. | HIGH | On app quit, sleep, wake failure, write failure, and control disable, attempt to restore Auto. UI should reflect `Auto` only after restore succeeds; otherwise show a restrained warning. |
| Unsupported-control degradation | Many Macs may expose sensors but not reliable write control. | MEDIUM | Monitoring can still work while controls are disabled. Show `控制不可用` with no scary modal. Do not hide all thermal monitoring just because fan writes are unavailable. |
| Settings integration | v2.0 already has settings and popover-section toggles. | LOW-MED | Add toggles under `弹窗区块`: `散热区块`, and optionally `风扇控制` as a separate opt-in. Control should not appear merely because monitoring is enabled. |
| Optional status-bar cooling segment | Some users will want temp/RPM at a glance. | MEDIUM | Add optional metric(s) only if they fit existing `metricOrder`/`enabledMetrics` behavior. Recommended compact text: `T:58° F:2400`, with `N/A`/hidden fallback. Default can stay popover-only to protect menu-bar width. |
| Stable popover dimensions | Current v3.0 explicitly targets network-number layout jitter. | LOW-MED | Popover width must remain fixed while network changes from `0B` to `12.3MB`, while RPM changes from `0` to `6200`, and while temperatures move between 2-3 digits. |
| Normal unavailable state | Sensor availability varies by chip, OS, and model. | LOW | Missing GPU/battery/SSD temps, missing fans, or missing control support are normal UI states. They should not log-spam, alert-spam, crash, or turn the section red. |

## Differentiators

Features that are valuable but should stay within MacStatus' lightweight identity.

| Feature | Value Proposition | Complexity | Recommendation |
|---------|-------------------|------------|----------------|
| Combined "cooling summary" row | A single scan line beats separate fan and temperature panels. | LOW-MED | At top of the section show `SoC 58°C · Fan 2400 RPM · Auto`. This directly serves the core value: one glance. |
| "Cool Boost" temporary override | Gives power users a safe action without building a full fan-curve product. | HIGH | Optional after basic manual mode: one action sets fans to a conservative high RPM for a short duration, then restores Auto. Label it as temporary. |
| Manual override expiry | Reduces risk of forgotten manual fan state. | MEDIUM-HIGH | If manual mode ships, consider a default timeout such as "until app quits" or "30 minutes". The UI should show remaining time if timed. |
| Sensor confidence display | Prevents users from over-trusting unmapped thermal zones. | MEDIUM | For secondary sensors, prefer `GPU N/A` or omit over showing dubious values. If a value is mapped by heuristic, label it conservatively, e.g. `GPU?`. |
| Thermal-state fallback mode | Keeps value on machines where exact SMC temps break. | LOW | If no temperature sensors are readable, still show system thermal state and fan RPM if available. |
| Per-section visibility control | Aligns with v2.0's `showBatterySection` / `showProcessSection` model. | LOW | `showThermalSection` should gate the whole cooling section. `showFanControls` should gate write controls separately. |
| Fixed-value typography polish | Makes the app feel stable and precise. | LOW | Use monospaced digits, right-aligned value columns, fixed row labels, and reserved width for `999°C`, `9999 RPM`, and `12.3MB/s`. |
| Safety status microcopy | Clear without being noisy. | LOW | When manual is active, show `系统自动控制已暂停` near controls. When Auto is restored, remove the message. Avoid modal warnings unless restore fails. |

## Anti-features

Explicitly do not build these in v3.0.

| Anti-feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Unbounded SMC writes | Hardware-risk surface; can fight macOS thermal management or damage hardware if wrong. | Only write through a bounded control path after min/max discovery; fail closed to Auto. |
| Setting fans below system minimum or off | Cooling apps should not make the machine less safe than Apple defaults. | Manual mode may raise minimum/target RPM within safe bounds; never expose "off" or below-min control. |
| Persistent invisible manual mode | User may forget the app is controlling fans. | Manual state must be visible and reversible; restore Auto on quit and failure paths. |
| Full automatic fan curves | This becomes Macs Fan Control/TG Pro scope and needs extensive model-specific validation. | v3.0 should ship Auto, bounded manual RPM, restore Auto, and maybe a temporary boost. Defer curves. |
| Raw sensor explorer | A long SMC key list is confusing and many labels are model-specific guesses. | Curated primary/secondary sensors only. Hide or mark uncertain values. |
| Alerts/notification rules | Requires notification infrastructure and rule persistence; already out of scope for prior milestones. | Use color/status labels only. macOS and existing thermal management handle critical warnings. |
| Historical thermal charts | Adds persistence/storage and chart scope beyond "lightweight". | Current value plus maybe existing in-memory sparkline only if cheap. No disk history in v3.0. |
| Activity Monitor replacement | Thermal work should not add full process diagnosis, kill buttons, or energy tables. | Keep existing Top-N sections as-is; point users to Activity Monitor for deep process action. |
| Admin/helper install by default | Raises trust and distribution burden for a lightweight app. | Monitoring should work without helper. If future fan write control needs privilege, make it explicit, optional, and separately researched. |
| Treating unsupported sensors as errors | Sensor availability changes by Mac model and OS version. | Unsupported is a first-class state: `N/A`, hidden row, disabled control, or "不支持". |
| Fighting `thermalmonitord`/diagnostic unlocks in v3.0 | Apple Silicon fan writes are not publicly documented and current research shows macOS actively enforces system mode. | Prefer read-only monitoring plus safe controls only where the implementation can prove restore behavior. Flag advanced unlock/write paths for deeper technical research. |

## UX Acceptance Notes

These are phrased as testable user-centric capabilities for requirements and UAT.

### Thermal Monitoring

- On a supported MacBook Pro, opening the popover shows a `散热` / `温度与风扇` section without changing existing CPU/GPU/memory/network/battery/process sections.
- The section shows one primary CPU/SoC temperature in Celsius with monospaced digits.
- If GPU, battery, or SSD temperatures are readable, they appear as secondary rows; if not readable, the section still works and does not show an error modal.
- If no temperature sensors are readable, the section shows system thermal state and `N/A` for exact temperature rather than fake or stale values.
- Thermal status labels are calm and semantic: normal values use default text, warm values use warning color, severe/critical uses critical color. Labels should reuse existing threshold/color patterns where possible.
- Temperature values do not create new persistent history by default.

### Fan Monitoring

- On a MacBook Pro with one or more fans, the popover shows current RPM for each detected fan.
- If multiple fans exist, users can distinguish them by stable labels (`风扇 1`, `风扇 2`, or left/right if reliably known).
- On fanless or unsupported hardware, the fan area says `无风扇`/`不支持` or is hidden; the app remains otherwise useful.
- RPM changes do not resize the popover or shift adjacent labels.

### Safe Fan Control

- The app starts in Auto mode. Installing or launching v3.0 must not change fan behavior.
- Manual fan control is not shown unless control support is detected and the user has enabled/entered the control surface.
- Manual control uses a bounded slider or stepper; values are clamped to discovered min/max or a conservative safe range.
- When manual mode is active, the UI visibly says manual control is active.
- `恢复自动` is visible whenever any fan is manual.
- Quitting MacStatus attempts to restore all fans to Auto.
- Closing the popover does not hide the fact that manual control is active if the menu-bar/status segment is enabled; at minimum reopening the popover shows it immediately.
- If a write fails, the UI shows `恢复自动失败` or `控制失败` in the fan section and does not pretend the requested RPM was applied.
- After sleep/wake, the app should re-read actual mode/RPM before showing manual state. If state cannot be verified, restore Auto or disable controls.

### Popover Layout Stability

- Popover width remains fixed while network values change across unit lengths, e.g. `0B/s`, `999KB/s`, `12.3MB/s`.
- Network upload/download remain vertically stacked and right-aligned.
- Temperature and RPM rows reserve enough width for worst normal values, e.g. `100°C`, `9999 RPM`, and `N/A`.
- Toggling unsupported secondary sensors on/off does not make the main metric grid jump during normal refresh ticks.
- Loading, unavailable, Auto, Manual, and failure states fit within the existing 320pt popover width or an intentionally revised fixed width.
- Settings changes apply live like existing v2.0 settings and do not require relaunch.

### Suggested Requirement Split

1. **Thermal read-only MVP** — Cooling section, primary CPU/SoC temperature, system thermal state, graceful N/A.
2. **Fan read-only MVP** — Fan count/RPM, fanless unsupported state, stable row layout.
3. **Layout stability hardening** — Fixed columns/monospaced digits for network, thermal, RPM, and state labels.
4. **Safe fan control** — Opt-in bounded manual control, restore Auto, lifecycle recovery, failure UI.

This order avoids coupling layout and monitoring to the riskiest write-control work.

## Sources/Evidence

### Project Evidence

- `.planning/PROJECT.md` — v3.0 active requirements define key temperature monitoring, MacBook Pro fan RPM monitoring, safe bounded fan control, restore-auto, unsupported-sensor graceful degradation, and stable popover layout. **Confidence: HIGH**
- `.planning/STATE.md` — records v2.0 constraints: single combined status item, settings as single source of truth, popover-gated expensive sampling, existing SMCReader experience, and network vertical layout enhancement. **Confidence: HIGH**
- `.planning/milestones/v2.0-phases/09-settings-window-ui-customization/09-03-SUMMARY.md` — confirms v2.0 settings window, `showBatterySection` / `showProcessSection`, threshold/color customization, and live settings patterns. **Confidence: HIGH**
- `MacStatus/MacStatus/UI/Views/DashboardView.swift` — current popover is fixed width (`.frame(width: 320)`), uses metric cards, monospaced values, network vertical text, battery graceful rows, and settings-gated sections. **Confidence: HIGH**
- `MacStatus/MacStatus/UI/Views/SettingsView.swift` — current settings structure already has `弹窗区块`, metric order/enabled controls, thresholds, colors, and grouped form layout. **Confidence: HIGH**
- `MacStatus/MacStatus/UI/StatusBarManager.swift` — status-bar rendering already uses one variable-length `NSStatusItem`, metric ordering, enabled metrics, and monospaced digit font. New status-bar cooling segments should reuse this model. **Confidence: HIGH**
- `MacStatus/MacStatus/Readers/SMCReader.swift` — project already has a read-only SMC client with nil degradation and strict ABI-size guard; write/control behavior is not implemented and should be treated as higher risk. **Confidence: HIGH**

### External / Primary Sources

- [Apple Developer — `ProcessInfo.thermalState`](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property) and [`ProcessInfo.ThermalState`](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum) — official system thermal state API; good for semantic state, not exact sensor temperatures. **Confidence: HIGH**
- [Apple Developer — IOKit](https://developer.apple.com/documentation/iokit) — official framework for non-kernel access to IOKit objects; supports the general native-system-access approach already used by MacStatus. **Confidence: HIGH**
- [Stats GitHub README](https://github.com/exelban/stats) — comparable menu-bar monitor includes sensors and fan control, but marks fan control "not maintained"; FAQ warns periodic sensor modules have meaningful energy cost and Apple changes sensor mappings by SoC. **Confidence: HIGH for competitor behavior; MEDIUM for generalizing to MacStatus**
- [Macs Fan Control official site](https://crystalidea.com/macs-fan-control) — mature fan-control UX patterns: two lists for fans/sensors, Auto vs Custom modes, RPM/sensor-based control, configurable menu-bar display, and restore Auto on quit. **Confidence: MEDIUM-HIGH**
- [Asahi Linux SMC documentation](https://asahilinux.org/docs/hw/soc/smc/) — SMC handles temperature sensors, power meters, battery status, and fan status; SMC protocol includes read/write concepts but is only partially documented. **Confidence: MEDIUM**
- [SMCKit documentation](https://beltex.github.io/SMCKit/) — Intel-era SMC tool exposes temperature/fan/power reads and warns fan speed setting is hardware-sensitive and root-required. **Confidence: MEDIUM**
- [macos-smc-fan research](https://github.com/agoodkind/macos-smc-fan/blob/main/README.md) — Apple Silicon macOS manual fan control research reports `thermalmonitord` enforcement and hardware-damage risk. Use as a risk signal only, not as a v3.0 implementation blueprint. **Confidence: LOW-MEDIUM**
