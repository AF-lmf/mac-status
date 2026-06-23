# Stack Research — MacStatus v3.0 Fan and Thermal Features

**Project:** MacStatus
**Researched:** 2026-06-23
**Scope:** stack/API additions only for fan RPM, key temperatures, safe fan control, and stable popover layout. Existing CPU/network/memory/GPU basics are intentionally not re-researched.
**Overall confidence:** MEDIUM-HIGH

## Summary

MacStatus v3.0 should keep the current zero/minimal-dependency native stack. Fan RPM and temperature monitoring can be built by extending the existing `SMCReader` AppleSMC user-client path, because the project already reads `PSTR` and `PPBR` through `IOServiceOpen("AppleSMC")` + `IOConnectCallStructMethod`. The main implementation work is not adding a library; it is widening `SMCReader` from "numeric read-only power keys" into a small typed SMC boundary that can read numeric, string, fan, and temperature keys defensively.

Fan control must be separated from fan/thermal monitoring. Reading SMC keys can remain in the main app with no extra entitlement, but writing fan mode/target keys is hardware-sensitive and should not be enabled from the normal menu-bar process by default. If v3.0 ships actual control, use a narrow privileged helper registered with `SMAppService.daemon(plistName:)`, accessed over XPC, and limit that helper to "set fan target within hardware bounds" and "restore automatic control". If the helper is absent, unapproved, or cannot verify a write, MacStatus should stay read-only and hide/disable control.

Temperature coverage is inherently model-dependent. Use probe-and-nil SMC key lists, not hard assumptions. For CPU/SoC primary display, read platform-specific CPU core/package SMC keys first, compute average/hottest valid values, and show `N/A` when no plausible value exists. GPU/battery/SSD temperatures should be best-effort: GPU via existing IOAccelerator temperature when available plus SMC fallback keys, battery via `TB1T`/`TB2T` or AppleSmartBattery `Temperature`, SSD only if a public SMART/NVMe path is already present later; do not add a disk SMART dependency for v3.0.

The popover layout issue is a UI stack change, not a system API change. Keep SwiftUI/AppKit and solve it with fixed-width monospaced value columns, stable row/grid dimensions, and no card resizing based on live network string length. Do not add a layout library.

## Recommended Stack/API

### 1. AppleSMC read-only monitoring path

| API / Pattern | Purpose | Recommendation | Confidence |
|---|---|---|---|
| `IOServiceMatching("AppleSMC")` + `IOServiceOpen` | Open AppleSMC user-client | Reuse existing `SMCReader.open()`; keep one connection owned by a reader/manager and closed on deinit. Apple documents `IOServiceOpen` as the user-space path for opening an IOKit service user client, but AppleSMC keys themselves are undocumented. | HIGH for IOKit call, MEDIUM for AppleSMC key behavior |
| `IOConnectCallStructMethod` selector `2` | AppleSMC read/write struct calls | Keep existing 80-byte `SMCParamStruct` layout guard. Add write support only inside helper, not in the main app. Apple documents the IOKit function; the AppleSMC command protocol is inferred from local implementation and open-source SMC tools. | HIGH for function, MEDIUM for protocol |
| SMC command `readKeyInfo` (`data8 = 9`) then `readBytes` (`data8 = 5`) | Read typed SMC values | Current two-step `SMCReader.readValue(key:)` is correct. Extend decoding to include `ui8 `, `ui16`, `ui32`, `flt `, `fpe2`, `sp78`/generic `spXY`/`fpXY`, and string/bytes for `F{i}ID`. | HIGH local evidence |
| SMC key enumeration via `#KEY` + read-index (`data8 = 8`) | Discover available keys | Add a debug/probe-only method, not a normal hot path. Useful for hardware UAT and selecting valid sensors, but avoid enumerating every tick. | MEDIUM |

Why: this matches MacStatus's current `SMCReader.swift` and the Stats SMC implementation, without adding SMCKit/SystemKit dependencies.

### 2. Fan RPM monitoring

| SMC Key | Meaning | Use |
|---|---|---|
| `FNum` | Number of fans | Read once at setup and after wake; `0`/nil means no fan section/control. |
| `F{i}Ac` | Actual RPM | Primary displayed fan RPM. Use `i = 0..<FNum`. |
| `F{i}Mn` | Hardware minimum RPM | Lower bound for manual control UI; never allow targets below this. |
| `F{i}Mx` | Hardware maximum RPM | Upper bound for manual control UI. |
| `F{i}Sf` | Safe speed | Display/debug only; if available, can be used as an extra lower-bound warning, but do not override Apple's `F{i}Mn` without real-device validation. |
| `F{i}Tg` | Target RPM | Read for current manual target; write only through helper. |
| `F{i}ID` | Fan display name | Optional; fallback to "左风扇/右风扇" for two-fan MacBook Pros or "Fan #N". |
| `F{i}Md` / `F{i}md` | Fan mode on newer hardware | Probe both casing variants. Treat `0` and `3` as automatic/system, `1` as manual/forced. |
| `FS! ` | Legacy Intel fan mode bitmask | Read-only fallback for Intel-era mode detection; not the primary Apple Silicon control surface. |

Recommended reader shape:

- `FanSnapshot: Sendable, Equatable` with `[FanReading]`, `controlAvailable`, `controlReason`, and `lastControlState`.
- `FanReading` includes `id`, `name`, `rpm`, `minRPM`, `maxRPM`, `targetRPM`, `mode`.
- Poll fan RPM at the existing refresh interval or a relaxed 2s cadence. Do not poll faster than the status-bar tick.
- Re-open/re-probe after `NSWorkspace.didWakeNotification`, following the existing BatteryReader wake pattern.

### 3. Temperature monitoring

Recommended primary path is SMC numeric reads, with a curated key catalog and plausibility filtering.

| Area | Preferred Keys / Sources | Notes |
|---|---|---|
| CPU, Intel/common fallback | `TC0D`, `TC0E`, `TC0F`, `TC0H`, `TC0P`, `TCAD` | Use first valid package/proximity value or compute hottest/average from valid CPU keys. Reject values `<= 0`, `< 10` for CPU core keys, `> 110`/`> 120` as implausible. |
| CPU, Apple Silicon M1/M2 | `Tp*` generation-specific lists such as `Tp09`, `Tp0T`, `Tp01`, `Tp05`, `Tp0D`, `Tp0H`, etc. | Model-dependent. Keep list data in a local `SensorCatalog` constant, not hardcoded in UI. |
| CPU, Apple Silicon M3/M4/M5 | `Te*`, `Tf*`, `Tp*` generation-specific lists | Recent open-source catalogs show generation drift. Probe keys; do not assume every key exists. |
| GPU | Existing IOAccelerator `Temperature(C)` when present; SMC fallbacks `TG0D`, `TG0H`, `TG0P`, `TCGC`, `TGDD`, generation-specific `Tg*` keys | Treat GPU temperature as optional. Existing GPU utilization path already has IOAccelerator access. |
| Battery | SMC `TB1T`, `TB2T`; AppleSmartBattery `Temperature` divided by 100 when present | Battery temp belongs in the thermal popover; do not block the whole thermal section if absent. |
| SSD/NAND | Defer unless a public project-local disk SMART path is added | Stats has disk SMART support, but adding SMART/NVMe plumbing is outside this v3.0 stack scope and violates the "minimal additions" posture. |
| SoC | Prefer any validated SMC/HID sensor found on target hardware; otherwise show CPU hottest as primary thermal signal and label SoC as unavailable | Some Stats SoC readings come from HID/IOReport-style sources, not plain SMC. Do not promise SoC on every MacBook Pro until real-device probe confirms keys. |

Code pattern:

```swift
struct ThermalSnapshot: Sendable, Equatable {
    let cpuAverageC: Double?
    let cpuHottestC: Double?
    let gpuC: Double?
    let batteryC: Double?
    let socC: Double?
    let sourceSummary: [String]
}
```

Rules:

- Store key definitions separately from reader logic: `SensorCatalog.cpuKeys(for modelIdentifier: String, architecture: String)`.
- Read all candidate keys once per tick, filter invalid values, then compute display fields.
- Never force unwrap sensor values. Missing sensor = `nil` = UI shows `N/A` or hides that row.
- Keep SMC reads synchronous inside the existing `MetricCollector` tick unless profiling shows SMC calls are slow; then move thermal/fan readers to a serial actor/queue and publish value snapshots only.

### 4. Safe fan control

Recommended v3.0 posture:

1. Ship fan RPM and temperature monitoring first, read-only.
2. Add fan control behind an explicit "Enable fan control" flow that installs/approves a helper.
3. If helper install/approval fails, the app remains fully useful in read-only mode.

Minimum viable control API:

| Operation | Implementation | Required Safety |
|---|---|---|
| `setManualTarget(fan: Int, rpm: Int)` | Helper reads `F{i}Mn`/`F{i}Mx`, clamps target, enables manual mode, writes `F{i}Tg`, verifies actual mode/target after write | Reject out-of-range inputs; never write below min; surface failure. |
| `restoreAutomatic(fan: Int?)` | Helper writes automatic mode for one/all fans; on Apple Silicon also resets `Ftst` when used | Run on app quit, helper disconnect, wake, and explicit UI button. |
| `readControlStatus()` | Main app can read SMC directly; helper can also return verified mode/target | UI must distinguish automatic/system/manual/unavailable. |

Apple Silicon control caveats:

- Mode key casing varies: probe `F0md` and `F0Md`.
- On Apple Silicon, mode `3` is system/automatic-like; treat it as not user manual.
- Recent research and Stats changes indicate modern Apple Silicon may require an `Ftst` force/test unlock before `F{i}Md`/`F{i}Tg` writes stick, and `thermalmonitord` may otherwise override direct writes.
- Because `Ftst` is undocumented and explicitly diagnostic-like, MacStatus should treat this as high-risk. Do not silently use it in the normal app process. If used at all, gate behind helper, explicit user consent, extensive logging, timeout, and automatic reset.

What NOT to do:

- Do not implement automatic fan curves in v3.0.
- Do not continuously fight `thermalmonitord`.
- Do not allow targets below `F{i}Mn`.
- Do not persist manual mode across app restarts unless the user explicitly opts in; default startup should restore/keep automatic.
- Do not ship control if it cannot be verified on the target MacBook Pro hardware matrix.

## Integration Points

### Existing files to extend

| File | Integration |
|---|---|
| `MacStatus/MacStatus/Readers/SMCReader.swift` | Expand into a typed SMC boundary: numeric reads, string reads, optional key enumeration, raw write only behind an internal interface used by helper code. Preserve the 80-byte layout guard. |
| `MacStatus/MacStatus/Readers/BatteryReader.swift` | Keep using current `SMCReader` for `PSTR`/`PPBR`; battery temperature can be folded into `ThermalReader` or exposed from `BatteryReader`, but avoid duplicate SMC reads for `TB1T`/`TB2T`. |
| `MacStatus/MacStatus/Collectors/MetricCollector.swift` | Add `fanReader` and `thermalReader`, cache last snapshots like `lastBatterySnapshot`, push to `DashboardState`. Control actions should not happen on the collector tick. |
| `MacStatus/MacStatus/UI/Views/DashboardView.swift` | Add thermal/fan sections as fixed-width rows. Keep network row/card stable with monospaced columns and fixed row dimensions. |
| `MacStatus/MacStatus/UI/PopoverManager.swift` | No new sampling loop needed for fan/thermal unless control status needs faster refresh while a control sheet is open. |
| `MacStatus/MacStatus/Utils/SettingsManager.swift` | Add settings: `showThermalSection`, `showFanSection`, optional temperature unit, optional fan-control enabled flag, and maybe per-fan remembered target only after helper is available. |

### New files recommended

| File | Purpose |
|---|---|
| `Readers/FanReader.swift` | Read fan count/RPM/bounds/mode from SMC. |
| `Readers/ThermalReader.swift` | Read and aggregate temperature sensors from SMC/IOAccelerator/AppleSmartBattery. |
| `Readers/SensorCatalog.swift` | Static candidate key lists by sensor group and model/generation, with no I/O. |
| `FanControl/FanControlClient.swift` | Main-app facade. Returns `.unavailable(reason)` unless helper is installed/approved. |
| `FanControl/FanControlPolicy.swift` | Clamp/validate RPM targets and control state transitions. Shared by app/helper if a helper target is added. |

### Optional helper target

Only add a helper target in the control phase, not for read-only monitoring.

Recommended architecture:

```text
MacStatus.app
  ├─ read-only SMCReader for fan/thermal status
  ├─ FanControlClient
  │    └─ XPC
  └─ Settings/UI

MacStatusFanHelper (privileged LaunchDaemon, optional)
  ├─ minimal SMC write boundary
  ├─ validates caller identity
  ├─ clamps target RPM using live F{i}Mn/F{i}Mx
  └─ restores automatic mode on explicit request/failure
```

## Security/Permission Notes

| Topic | Finding | Recommendation |
|---|---|---|
| Read fan RPM/temp | No extra entitlement found in current project; existing `SMCReader` reads AppleSMC keys without entitlement. | Keep read-only monitoring in main app. Mark unsupported keys as `nil`. |
| SMC write | AppleSMC write command exists (`data8 = 6`), but fan control changes hardware state and may require elevated helper on modern macOS. Stats uses a privileged helper for fan speed/mode operations. | Do not write from the main menu-bar process. Use optional helper for control. |
| Helper install | Apple documents `SMAppService` for registering helper executables including LaunchDaemons on macOS 13+. Stats now uses `SMAppService.daemon(plistName:)` on macOS 13+ and legacy `SMJobBless` only for older systems. | Because MacStatus targets macOS 14+, use `SMAppService` only; do not add SMJobBless legacy code. |
| Authorization | Apple says privileged operations should be factored into a helper and authorized immediately before privileged work; avoid running the whole app as root. | Keep helper tiny, auditable, and XPC-only. No shelling out to bundled `smc` binaries. |
| App Sandbox | Authorization Services privilege escalation is not supported in App Sandbox, and this app already relies on non-sandboxed monitoring patterns. | Keep sandbox off for Developer ID distribution. |
| Code signing | Privileged helper distribution needs Developer ID signing and user approval. Recent third-party examples report paid Developer ID as a practical requirement for installable LaunchDaemons. | Treat fan control as unavailable in unsigned/local debug builds unless running a developer helper explicitly. |
| Failure recovery | Helper crash, app quit, wake, or write failure can leave manual mode active. | Add `restoreAutomatic` on quit and wake; UI should always expose "恢复系统自动控制"; helper should reset all fans on uninstall. |
| Hardware safety | Fan control below Apple's min or based on one sensor can damage hardware. | v3.0 control is bounded target/manual only, not an auto curve. Use min/max from SMC every time. |

## Open Questions

- Which exact MacBook Pro models are v3.0 validation targets? Sensor key coverage differs between M1/M2/M3/M4/M5 and Intel/T2 machines.
- Can target hardware read a meaningful SoC temperature via plain SMC keys, or does it require IOHID/IOReport-style sensor discovery? If the latter, decide whether "CPU hottest" is sufficient for v3.0.
- Does fan control need to ship in v3.0, or can v3.0 ship read-only fan/thermal plus a researched control design? Given the safety risk, read-only first is the lower-risk roadmap.
- If control ships, is Developer ID signing available for a privileged helper? Without it, helper install and approval will not be a realistic user-facing feature.
- Does the target M3/M4+ hardware require `Ftst`, and is the project willing to use an undocumented diagnostic key? This needs explicit product approval and real-device UAT.
- SSD temperature: should it be deferred, or is an existing disk SMART path planned? Current recommendation is defer.

## Sources

### Project Source Evidence

- `MacStatus/MacStatus/Readers/SMCReader.swift` — existing AppleSMC user-client read path for `PSTR`/`PPBR`; local evidence for no-entitlement read-only SMC access and the critical 80-byte `SMCParamStruct` layout guard. **HIGH**
- `MacStatus/MacStatus/Readers/BatteryReader.swift` — existing `SMCReader` ownership, wake handling, and probe-and-nil optional snapshot pattern. **HIGH**
- `.planning/PROJECT.md` and `.planning/STATE.md` — v3.0 scope, zero-dependency constraint, fan-control safety requirement, and SMC layout decision from v2.0 UAT. **HIGH**

### Apple / Official Sources

- Apple Developer Documentation — `IOServiceOpen(_:_:_:_:)`: https://developer.apple.com/documentation/iokit/1514515-ioserviceopen — public IOKit user-client open function. Page requires JavaScript in fetched output, but search snippet states non-kernel clients open a connection through `IOServiceOpen`. **HIGH for API existence**
- Apple Developer Documentation — `IOConnectCallStructMethod(_:_:_:_:_:_:)`: https://developer.apple.com/documentation/iokit/1514274-ioconnectcallstructmethod — public IOKit struct-call function used by AppleSMC clients. Page requires JavaScript in fetched output. **HIGH for API existence**
- Apple Developer Documentation — `SMAppService`: https://developer.apple.com/documentation/servicemanagement/smappservice — official service-management API; search result states macOS 13+ uses it to register/control LoginItems, LaunchAgents, and LaunchDaemons. **HIGH**
- Apple Developer Documentation — Updating helper executables: https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos — search result notes LaunchDaemons require user authentication/authorization. **MEDIUM-HIGH**
- Apple Authorization Services Programming Guide — https://developer.apple.com/library/archive/documentation/Security/Conceptual/authorization_concepts/02authconcepts/authconcepts.html — fetched lines 19, 44-45, 155-170, 174-184 state sandbox limitation, least-root guidance, and factored helper pattern for privileged operations. **HIGH**

### Open-Source Reference Implementations

- exelban/stats at `9a8e6e26cc0c779194fd4a2accdf0e37edf30178`: https://github.com/exelban/stats — `SMC/smc.swift` confirms SMC data types, read/write commands (`readBytes=5`, `writeBytes=6`, `readIndex=8`, `readKeyInfo=9`), fan mode/target writes, Apple Silicon `Ftst` retry/reset logic, and firmware-result checking. **MEDIUM-HIGH** because SMC keys are undocumented but implementation is current and widely used.
- exelban/stats — `Modules/Sensors/readers.swift` confirms `FNum`, `F{i}ID`, `F{i}Mn`, `F{i}Mx`, `F{i}Ac`, `F{i}Md`/`FS! ` fan reads, temperature filtering, and optional Apple Silicon HID/IO sensor paths. **MEDIUM-HIGH**
- exelban/stats — `Kit/helpers.swift` confirms privileged SMC helper pattern using `SMAppService.daemon(plistName:)` on macOS 13+, XPC connection with `.privileged`, and reset/uninstall behavior. **MEDIUM-HIGH**
- hholtmann/smcFanControl at `e1bd672bcd2d72eddff9b6da7b9cae38e35c4206`: https://github.com/hholtmann/smcFanControl — README states it never sets below Apple's defaults; `smc-command/README.md` documents `FNum`, `F0Ac`, `F0Mn`, `F0Mx`, `F0Sf`, `F0Tg`, `FS! ` and warns SMC writes can permanently damage hardware. **MEDIUM**
- agoodkind/macos-smc-fan at `f36a49cd7839d08b8c6002338b1ddde37d1a9075`: https://github.com/agoodkind/macos-smc-fan — recent Apple Silicon fan-control research; README and `FanController.swift` document `thermalmonitord`, `Ftst`, helper/XPC architecture, and unlock/retry/reset sequence. **MEDIUM** because it is recent reverse engineering, not Apple documentation.

### Confidence Notes

- SMC read and fan RPM keys: **HIGH enough to build**, because local `SMCReader` already works and two mature projects agree on fan keys.
- Temperature key catalog: **MEDIUM**, because key availability changes by model/generation. Build with probing and UAT.
- Fan control: **MEDIUM/needs real-device validation**, because write behavior is undocumented, hardware-sensitive, and Apple Silicon behavior changed across generations.
- Helper/security architecture: **HIGH**, because Apple explicitly recommends factoring privileged operations and `SMAppService` is the macOS 13+ service-management path.
