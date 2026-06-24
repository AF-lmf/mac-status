---
phase: 10-thermal-read-only-monitoring
verified: 2026-06-24T02:25:28Z
status: passed
score: 8/8 must-haves verified
overrides_applied: 0
---

# Phase 10: Thermal Read-Only Monitoring Verification Report

**Phase Goal:** 用户打开弹窗即可看到可信的 CPU/SoC 热状态；传感器缺失或不可信时显示稳定的 `N/A`，不会崩溃或弹错。
**Verified:** 2026-06-24T02:25:28Z
**Status:** passed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | 用户能在弹窗中看到一个主 CPU/SoC 温度值；该值来自可信传感器，无法确认时显示 `N/A`。 | VERIFIED | `ThermalSensorCatalog.supportedModel = "Mac15,9"` and CPU/SoC candidates are explicit allowlists only (`ThermalReader.swift:54-75`). `readValue()` populates `cpuSocTemperatureCelsius` only from `cpuSocCandidates(for:)` (`ThermalReader.swift:86-99`). UI formats nil as `N/A` (`DashboardView.swift:146-185`). |
| 2 | 用户能看到系统 thermal state（正常、偏热、严重、临界等语义状态），即使精确温度不可读也能理解当前热压力。 | VERIFIED | `SystemThermalState` maps `ProcessInfo.ThermalState` semantically (`ThermalReader.swift:5-25`), `readValue()` stores it separately (`ThermalReader.swift:89-99`), and `ThermalSectionView` renders `系统状态` as `正常`/`偏热`/`严重`/`临界`/`未知` (`DashboardView.swift:155-205`). |
| 3 | GPU、电池、SSD 等次要温度只在可读且可信时显示；不可读时不会出现假值、旧值或误导标签。 | VERIFIED | GPU uses a Mac15,9 allowlist (`ThermalReader.swift:63-75`), battery uses `AppleSmartBattery` temperature with `0...100` bounds and trusted SMC fallback (`ThermalReader.swift:135-157`), and rows render independently (`DashboardView.swift:154-157`). SSD is explicitly deferred/not required for Phase 10; no SSD/SMART/NVMe reader exists by grep gate. |
| 4 | 传感器缺失、机型不支持或单次读取失败时，温度区块保持可用并以 `N/A`/隐藏次要行降级，不刷错误弹窗。 | VERIFIED | `ThermalSnapshot.unavailable()` is non-optional and stable (`ThermalReader.swift:28-43`); unsupported models return empty CPU/GPU candidate lists (`ThermalReader.swift:69-75`); UI rows are always present when the section is enabled (`DashboardView.swift:139-158`). Forbidden alert/notification grep returned no matches. |
| 5 | `ProcessInfo.thermalState` is never used as a CPU/SoC temperature substitute. | VERIFIED | `ProcessInfo.processInfo.thermalState` only feeds `SystemThermalState` (`ThermalReader.swift:89`); CPU/SoC is populated only through `firstTemperature(in: cpuSocCandidates)` (`ThermalReader.swift:91-94`). |
| 6 | Thermal data is popover-only current snapshot data, not status-bar, history, MetricSample, persistence, or stale substitution. | VERIFIED | `MetricCollector` stores `lastThermalSnapshot` outside `MetricSample` (`MetricCollector.swift:48-51`), reads current thermal values on the unified tick (`MetricCollector.swift:172-173`), and sends status bar updates without thermal arguments (`MetricCollector.swift:241-246`). Storage/status-bar/Metric thermal grep returned no matches. |
| 7 | Dedicated `散热` section is default-on and can be toggled from Settings. | VERIFIED | `showThermalSection` key/backing/property exist with default true and UserDefaults persistence (`SettingsManager.swift:86`, `SettingsManager.swift:115`, `SettingsManager.swift:310-320`, `SettingsManager.swift:490-494`). Settings exposes `Toggle("散热区块", isOn: $settings.showThermalSection)` (`SettingsView.swift:43-47`). Dashboard gates only by this setting (`DashboardView.swift:69-71`). |
| 8 | Mac15,9 hardware probe is recorded and final exclusions hold: no fan/RPM/control, SMC writes, helper/XPC, SSD reader, status-bar thermal metric, thermal persistence/history, alerts, or notifications. | VERIFIED | `10-HARDWARE-PROBE.md` records Mac15,9, build, trusted CPU/SoC/GPU/battery outcomes, and source gates. Fresh verification repeated build, forbidden scope grep, and a local Swift probe; all passed. |

**Score:** 8/8 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `MacStatus/MacStatus/Readers/SMCReader.swift` | Read-only raw/numeric/Celsius SMC decoding | VERIFIED | `SMCValue`, `readRawValue`, `readTemperatureCelsius`, numeric decoding, and `0...120` Celsius bounds exist (`SMCReader.swift:19-24`, `SMCReader.swift:130-173`, `SMCReader.swift:209-250`). No write/fan tokens found. |
| `MacStatus/MacStatus/Readers/ThermalReader.swift` | Snapshot, semantic state, strict catalog, diagnostics | VERIFIED | `ThermalSnapshot`, `SystemThermalState`, `ThermalSensorCatalog`, `ThermalReader`, battery reads, and diagnostics exist (`ThermalReader.swift:5-186`). |
| `MacStatus/MacStatus.xcodeproj/project.pbxproj` | `ThermalReader.swift` target membership | VERIFIED | Present as `PBXBuildFile`, `PBXFileReference`, Readers group child, and `PBXSourcesBuildPhase` entry (`project.pbxproj` grep lines 28, 65, 140, 299). |
| `MacStatus/MacStatus/Collectors/MetricCollector.swift` | ThermalReader setup/read/cache/updateUI integration | VERIFIED | `thermalReader`, `lastThermalSnapshot`, setup, initial read, tick read, and `dashboard.updateThermal` exist (`MetricCollector.swift:48-51`, `MetricCollector.swift:70-78`, `MetricCollector.swift:172-173`, `MetricCollector.swift:221-223`). |
| `MacStatus/MacStatus/UI/Views/DashboardView.swift` | Dashboard state and stable thermal section | VERIFIED | `ThermalSectionView`, stable rows, `@Published var thermal`, and `updateThermal(_:)` exist (`DashboardView.swift:136-228`, `DashboardView.swift:477`, `DashboardView.swift:567-570`). Width remains `320` (`DashboardView.swift:129`). |
| `MacStatus/MacStatus/Utils/SettingsManager.swift` | Default-on `showThermalSection` setting | VERIFIED | Key, backing field, property, persistence, notification, and nil-check default exist (`SettingsManager.swift:86`, `SettingsManager.swift:115`, `SettingsManager.swift:310-320`, `SettingsManager.swift:490-494`). |
| `MacStatus/MacStatus/UI/Views/SettingsView.swift` | Settings toggle labeled `散热区块` | VERIFIED | Toggle exists in the existing `弹窗区块` section (`SettingsView.swift:43-47`). |
| `.planning/phases/10-thermal-read-only-monitoring/10-HARDWARE-PROBE.md` | Mac15,9 probe and anti-scope evidence | VERIFIED | File records model, OS, build, local thermal probe output, trust outcome, and final source gates. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `ThermalReader.readValue()` | `SMCReader.readTemperatureCelsius(key:)` | Trusted candidate reads | WIRED | `readValue()` calls `firstTemperature(in:)`; `firstTemperature` calls `smcReader.readTemperatureCelsius(key:)` (`ThermalReader.swift:91-99`, `ThermalReader.swift:126-133`). |
| `ThermalReader.readValue()` | `ProcessInfo.processInfo.thermalState` | `SystemThermalState` mapping | WIRED | Semantic state is read directly and stored as `systemState`, not a temperature (`ThermalReader.swift:89-99`). |
| `MetricCollector.tick()` | `ThermalReader.readValue()` | Unified timer tick | WIRED | Tick reads `thermalReader.readValue()` and assigns `lastThermalSnapshot` (`MetricCollector.swift:153-173`). |
| `MetricCollector.updateUI(sample:)` | `DashboardState.updateThermal(_:)` | Cached snapshot outside `MetricSample` | WIRED | `dashboard.updateThermal(lastThermalSnapshot)` is called during UI update (`MetricCollector.swift:198-223`). |
| `DashboardView` | `ThermalSectionView` | `state.thermal` | WIRED | `ThermalSectionView(snapshot: state.thermal)` is rendered when the setting is true (`DashboardView.swift:69-71`). |
| `SettingsView` | `SettingsManager.showThermalSection` | Toggle binding | WIRED | `Toggle("散热区块", isOn: $settings.showThermalSection)` (`SettingsView.swift:43-47`). |
| `DashboardView` | `SettingsManager.showThermalSection` | Observable read in body | WIRED | Body reads `SettingsManager.shared`; render gate uses `settings.showThermalSection` (`DashboardView.swift:10-12`, `DashboardView.swift:69-71`). |
| `ThermalReader.diagnosticReadings()` | `10-HARDWARE-PROBE.md` | Temporary local probe | WIRED | Probe document records diagnostic rows; fresh local Swift probe also returned 26 diagnostics. |

Note: `gsd-tools query verify.key-links` could not resolve Swift function names in `from:` and returned `Source file not found`; manual source-level verification above is the authoritative key-link evidence.

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `ThermalReader.swift` | `cpuSocTemperatureCelsius` | `hw.model == Mac15,9` -> allowlisted SMC keys -> `readTemperatureCelsius` | Yes on Mac15,9; nil otherwise | FLOWING |
| `ThermalReader.swift` | `systemState` | `ProcessInfo.processInfo.thermalState` -> `SystemThermalState` | Yes | FLOWING |
| `ThermalReader.swift` | `gpuTemperatureCelsius` | `hw.model == Mac15,9` -> allowlisted GPU SMC keys | Yes on Mac15,9; nil otherwise | FLOWING |
| `ThermalReader.swift` | `batteryTemperatureCelsius` | `AppleSmartBattery Temperature / 100` with bounds, fallback `TB1T`/`TB2T` | Yes when battery API/keys readable; nil otherwise | FLOWING |
| `MetricCollector.swift` | `lastThermalSnapshot` | `thermalReader.readValue()` in `start()` and `tick()` | Yes | FLOWING |
| `DashboardView.swift` | `state.thermal` | `DashboardState.updateThermal(lastThermalSnapshot)` | Yes | FLOWING |
| `ThermalSectionView` | Stable row values | `ThermalSnapshot` fields, nil formatted as `N/A` | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| App target builds with thermal files compiled | `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` | `** BUILD SUCCEEDED **` | PASS |
| Local thermal reader returns current snapshot and diagnostics | `swiftc -framework IOKit SMCReader.swift ThermalReader.swift /tmp/.../main.swift -o /tmp/.../thermal-verify && /tmp/.../thermal-verify` | `cpuSoc=54.14`, `systemState=nominal`, `gpu=47.39`, `battery=30.41`, `diagnostics=26`, first diagnostic `cpuSoc Te05 flt 54.14` | PASS |
| Forbidden scope absent | `rg` over `MacStatus/MacStatus` for SMC write, fan/RPM/control, helper/XPC, SSD/SMART/NVMe, thermal alert/notification/history/status-bar tokens | no matches | PASS |
| Settings and UI symbols present | `rg` for `showThermalSection`, `散热区块`, `ThermalSectionView`, `CPU/SoC`, `系统状态`, `N/A`, `.frame(width: 320)` | expected matches in SettingsManager, SettingsView, DashboardView | PASS |

### Probe Execution

| Probe | Command | Result | Status |
|---|---|---|---|
| Conventional probe scripts | `find scripts -path '*/tests/probe-*.sh' -type f` plus phase PLAN/SUMMARY probe path grep | no probe scripts declared or found | SKIP |
| Local Swift thermal probe | `swiftc -framework IOKit MacStatus/MacStatus/Readers/SMCReader.swift MacStatus/MacStatus/Readers/ThermalReader.swift /tmp/.../main.swift -o /tmp/.../thermal-verify && /tmp/.../thermal-verify` | Snapshot and diagnostics printed successfully on Mac15,9 | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| THERM-01 | 10-01, 10-02, 10-03 | 用户能在弹窗中看到 CPU/SoC 主温度，显示值必须来自可信传感器或明确标为 `N/A` | SATISFIED | Model-gated CPU/SoC catalog in reader; UI renders CPU/SoC header/row and nil as `N/A`; local probe confirmed Te05 on Mac15,9. |
| THERM-02 | 10-01, 10-02, 10-03 | 用户能在弹窗中看到系统 thermal state，用于补充说明当前系统热压力 | SATISFIED | `ProcessInfo.thermalState` mapped to `SystemThermalState`; UI renders separate `系统状态` row. |
| THERM-03 | 10-01, 10-02, 10-03 | 用户能看到可信的 GPU、电池、SSD 等次要温度；不可读或不可信时不显示假值 | SATISFIED | GPU and battery implemented as independent trusted optional fields. SSD is explicitly deferred/not required for Phase 10 by phase decisions and user instruction; code confirms no SSD reader was added. |
| THERM-04 | 10-01, 10-02, 10-03 | 传感器缺失、机型不支持或读取失败时，温度区块优雅降级，不崩溃、不刷错误弹窗 | SATISFIED | Optional snapshots, unsupported-model nil candidates, stable rows, build pass, local probe pass, and no alert/notification/log-spam path found. |

No orphaned Phase 10 requirement IDs were found; `.planning/REQUIREMENTS.md` maps only THERM-01 through THERM-04 to Phase 10.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---:|---|---|---|
| `MacStatus/MacStatus/UI/Views/SettingsView.swift` | 89 | `TODO: Implement via MetricCollector.purgeAll()` | Warning | Pre-existing disabled clear-history button, unrelated to Phase 10 thermal behavior. Not a blocker for thermal goal achievement. |

No `TBD`, `FIXME`, or `XXX` debt markers were found in Phase 10 scoped files. No placeholder/stub thermal rows, empty handlers, hardcoded empty thermal props, or console-log-only implementations were found.

### Human Verification Required

None. The Phase 10 must-haves are sufficiently verified by source-level wiring, Xcode build, local hardware probe, and forbidden-scope gates. No unresolved visual/user-flow ambiguity remains for deciding this phase goal.

### Gaps Summary

No blocking gaps found. Phase 10 achieves the read-only thermal monitoring goal: trusted Mac15,9 CPU/SoC values display when available, untrusted/missing data degrades to stable `N/A`, system thermal state is semantic and separate, GPU/battery are independent optional secondary values, the `散热` section is default-on and settings-gated, and forbidden scope remains absent.

---

_Verified: 2026-06-24T02:25:28Z_
_Verifier: the agent (gsd-verifier)_
