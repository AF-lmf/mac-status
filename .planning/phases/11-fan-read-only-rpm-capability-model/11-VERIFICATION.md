---
phase: 11-fan-read-only-rpm-capability-model
verified: 2026-06-24T07:46:01Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 11: Fan Read-Only RPM & Capability Model Verification Report

**Phase Goal:** 用户能在支持风扇的 MacBook Pro 上看到风扇 RPM 和能力状态；不支持或 fanless 机器不会出现误导性的控制入口。
**Verified:** 2026-06-24T07:46:01Z
**Status:** passed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | 支持风扇的 MacBook Pro 弹窗中显示风扇数量，并为每个风扇显示当前 RPM。 | VERIFIED | `FanReader` decodes `FNum`, maps one `FanReading` per fan count, reads `F{i}Ac`, and the current hardware probe returned `supportState=supported`, `fanCount=2`, `风扇 1 current=2116.12`, `风扇 2 current=2239.27`. `DashboardView` renders `ForEach(visibleFans)` inside `温度与风扇`. |
| 2 | 每个风扇的 min/max/target 或控制能力状态在可读时可见，不可读字段以稳定 `N/A` 呈现。 | VERIFIED | `FanReading` fields are optional; `FanReader` sets `boundsReadable` only when min/max are plausible and `min <= max`, and `targetReadable` independently. `DashboardView` renders `N/A` for nil current RPM and omits range/target when capability gates fail. Current probe returned readable min/max/target for both fans. |
| 3 | fanless、非 MacBook Pro 或不支持读取的机型显示普通降级状态，不显示手动风扇控制入口。 | VERIFIED | Current `46c0e83` code path returns `.unavailable` for non-target hardware when no fan has readable RPM, and `DashboardView` hides rows when `supportState == .unsupported`. Source gates found no fan control UI strings/buttons/sliders, no SMC write APIs, no helper/XPC, no status-bar fan, no fan history/storage, and no raw SMC browser. |
| 4 | UI 能区分“可读取 RPM”“可读取硬件边界”“可安全控制”，不会把可读 RPM 误判为可控。 | VERIFIED | `FanCapabilities` has separate `rpmReadable`, `boundsReadable`, `targetReadable`, and `safeControlAvailable`; all Phase 11 readings set `safeControlAvailable: false`. UI consumes read capability for RPM/range/target text and shows only `边界可读，控制未启用`, never `控制可用`. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `MacStatus/MacStatus/Readers/SMCReader.swift` | Read-side SMC numeric decode accepts `ui8 ` trailing whitespace | VERIFIED | `decodeNumeric(_:)` keeps `flt ` exact and trims whitespace for integer types before `ui8`/`ui16`/`ui32` decode. |
| `MacStatus/MacStatus/Readers/FanReader.swift` | Fan snapshot, readings, capability model, diagnostics, non-target fallback | VERIFIED | Defines `FanSupportState`, `FanCapabilities`, `FanReading`, `FanSnapshot`, `FanDiagnosticReading`, `FanReader`; current non-target no-readable-RPM path returns `.unavailable`. |
| `MacStatus/MacStatus.xcodeproj/project.pbxproj` | `FanReader.swift` target membership | VERIFIED | `FanReader.swift` has PBX file reference and `FanReader.swift in Sources`. |
| `MacStatus/MacStatus/Collectors/MetricCollector.swift` | FanReader setup/read/cache/update flow | VERIFIED | Calls `fanReader.setup()`, caches `lastFanSnapshot`, refreshes on tick, and calls `dashboard.updateFans(lastFanSnapshot)`. |
| `MacStatus/MacStatus/UI/Views/DashboardView.swift` | Combined `温度与风扇` rendering and dashboard fan state | VERIFIED | Adds `@Published var fan`, `updateFans(_:)`, combined section, `visibleFans`, optional range/target rendering, and preserved `.frame(width: 320)`. |
| `MacStatus/MacStatus/Utils/SettingsManager.swift` | Default-on `showFanSection` setting | VERIFIED | Defines key/backing property/public property; load preserves explicit false and defaults absent key to true. |
| `MacStatus/MacStatus/UI/Views/SettingsView.swift` | Visibility-only `风扇区块` toggle | VERIFIED | `Toggle("风扇区块", isOn: $settings.showFanSection)` appears directly after `散热区块`; no fan control setting exists. |
| `.planning/phases/11-fan-read-only-rpm-capability-model/11-HARDWARE-PROBE.md` | Mac15,9 read-only evidence and source gates | VERIFIED | Records `Mac15,9`, `FNum=2`, `F0Ac/F1Ac`, min/max/target, missing IDs, no-write source gates, and `BUILD SUCCEEDED`. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `FanReader.swift` | `SMCReader.swift` | `smcReader.readValue/readRawValue` | WIRED | Manual grep found diagnostic, fan count, current, min, max, and target reads through `smcReader`. |
| `project.pbxproj` | `FanReader.swift` | PBX file reference and sources phase | WIRED | Manual grep found file reference, Readers group child, build file, and sources build phase entry. |
| `MetricCollector.swift` | `FanReader.swift` | `fanReader.setup/readValue` | WIRED | `start()` sets up and does initial fan read; `tick()` refreshes `lastFanSnapshot`. |
| `MetricCollector.swift` | `DashboardView.swift` | `dashboard.updateFans` | WIRED | `updateUI(sample:)` pushes cached fan snapshot into `DashboardState`. |
| `SettingsView.swift` | `SettingsManager.swift` | Toggle binding | WIRED | `风扇区块` binds to `$settings.showFanSection`. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `DashboardView.swift` | `state.fan.fans` | `MetricCollector.lastFanSnapshot` from `FanReader.readValue()` | Yes | FLOWING - current probe against product reader files returned 2 fans with current/min/max/target RPM. |
| `FanReader.swift` | `FanSnapshot.fans` | `SMCReader.readValue("FNum")` and `F{i}Ac/Mn/Mx/Tg` | Yes | FLOWING - `FNum type=ui8 size=1 value=2.00`; `F0Ac/F1Ac` and bounds/target decoded. |
| `SettingsView.swift` | `showFanSection` | `SettingsManager` UserDefaults-backed property | Yes | FLOWING - setter persists and posts `.settingsDidChange`; load preserves explicit user false. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| App builds with current Phase 11 code | `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` | `** BUILD SUCCEEDED **` | PASS |
| Scheme test capability | `xcodebuild test ... -skipUnavailableActions` | `Skipping test action as the scheme is not testable.` Project lists only one app target and no test target. | SKIP - no test target configured |
| Current read-only fan probe | Temporary `swiftc -framework IOKit SMCReader.swift FanReader.swift /tmp/.../main.swift` | `supportState=supported`, `fanCount=2`, readable current/min/max/target for both fans, `safeControlAvailable=false` | PASS |

### Probe Execution

| Probe | Command | Result | Status |
|---|---|---|---|
| Conventional shell probes | `find scripts -path '*/tests/probe-*.sh' -type f` | No probe shell scripts found. | SKIP - no runnable probe script |
| Phase 11 temporary Swift hardware probe | Recompiled a new `/tmp` Swift probe against current `SMCReader.swift` and `FanReader.swift` | Current output confirmed `FNum=2`, `F0Ac/F1Ac`, min/max/target, and fail-closed capabilities. | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| FAN-01 | 11-01, 11-02, 11-03 | Fan count and current RPM in MacBook Pro popover | SATISFIED | `FNum` -> fan rows -> `DashboardView` `ForEach`; current probe has 2 current RPM readings. |
| FAN-02 | 11-01, 11-02, 11-03 | min/max/target or stable unavailable/capability state | SATISFIED | Optional fields and independent UI gates; current probe has readable bounds/target; nil current renders `N/A`. |
| FAN-03 | 11-01, 11-02, 11-03 | Fanless/unsupported graceful degradation; no misleading control entry | SATISFIED | `.unsupported` hides fan rows; `46c0e83` non-target fallback verified; no fan controls/status/history/write surface. |
| FAN-04 | 11-01, 11-02, 11-03 | Distinguish RPM-readable, boundary-readable, safe-control capability | SATISFIED | Separate booleans in `FanCapabilities`; `safeControlAvailable` remains false and UI never promises control. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---:|---|---|---|
| `MacStatus/MacStatus/UI/Views/SettingsView.swift` | 90 | `TODO` in pre-existing disabled `清除历史` button | INFO | Unrelated to Phase 11 fan work; not a FAN blocker. |
| `MacStatus/MacStatus/UI/StatusBarManager.swift` | 97 | comment says `placeholder` for status-bar fallback glyph | INFO | Existing status-bar empty-state fallback; no fan/RPM/status-bar segment. |
| `DashboardView.swift` / `MetricCollector.swift` | multiple | Empty array initial state | INFO | Live UI/sample buffers, populated by collector; not hardcoded rendered fan data. |

### Human Verification Required

None. Phase 11 is read-only and was verified with current source inspection, current build, current hardware probe, and source gates. No visual/manual UAT is required for this phase.

### Gaps Summary

No blocking gaps found. Phase 11 achieves the roadmap goal and remains read-only, current-snapshot-only, popover-only, and fail-closed for safe fan control.

---

_Verified: 2026-06-24T07:46:01Z_
_Verifier: the agent (gsd-verifier)_
