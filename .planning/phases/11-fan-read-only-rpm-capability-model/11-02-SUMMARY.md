---
phase: 11-fan-read-only-rpm-capability-model
plan: 02
subsystem: ui
tags: [swift, swiftui, fan-rpm, settings, popover]

requires:
  - phase: 11-fan-read-only-rpm-capability-model
    provides: FanReader/FanSnapshot read-only capability model from 11-01
provides:
  - Default-on showFanSection UserDefaults setting and Settings toggle
  - FanReader sampling on the existing MetricCollector cadence
  - DashboardState fan snapshot state
  - Combined 温度与风扇 popover section with read-only fan RPM rows
affects: [phase-12-popover-layout-stability, phase-13-safe-fan-control]

tech-stack:
  added: []
  patterns:
    - Popover-only current hardware snapshots kept outside MetricSample/history/status-bar surfaces
    - Independent SettingsManager section toggles with settingsDidChange repaint
    - Capability-gated optional fan detail rendering

key-files:
  created: []
  modified:
    - MacStatus/MacStatus/Utils/SettingsManager.swift
    - MacStatus/MacStatus/UI/Views/SettingsView.swift
    - MacStatus/MacStatus/Collectors/MetricCollector.swift
    - MacStatus/MacStatus/UI/Views/DashboardView.swift

key-decisions:
  - "Fan visibility is independent from thermal visibility through SettingsManager.showFanSection."
  - "Fan snapshots are sampled only on the existing collector cadence and are reused for settings-only repaint."
  - "Fan rows live inside 温度与风扇 and use numbered labels from FanReader; no left/right inference or control affordance is added."

patterns-established:
  - "Dashboard popover sections can combine independently gated row groups while preserving the 320pt frame contract."
  - "Readable fan bounds/target details are gated by FanCapabilities and explain that control is not enabled."

requirements-completed: [FAN-01, FAN-02, FAN-03, FAN-04]

duration: 5min
completed: 2026-06-24
---

# Phase 11 Plan 02: Fan Popover Wiring Summary

**Read-only fan RPM snapshots now flow through the existing collector into a combined 温度与风扇 popover section with independent visibility settings.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-06-24T07:13:14Z
- **Completed:** 2026-06-24T07:18:41Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- Added `showFanSection` as a default-on UserDefaults-backed preference and exposed it as `风扇区块` directly after `散热区块`.
- Wired `FanReader` into `MetricCollector` setup/tick/update flow with cached `lastFanSnapshot`, keeping fan data out of history, storage, status bar, `MetricSample`, `metricOrder`, and `enabledMetrics`.
- Replaced the standalone thermal card with `TemperatureAndFanSectionView`, rendering temperature rows first and read-only numbered fan RPM rows second.
- Rendered current RPM as whole-number monospaced text, optional `范围 {min}-{max} RPM` / `目标 {target} RPM` details only when capability flags say readable, and `边界可读，控制未启用` without any control promise.
- Preserved `.frame(width: 320)` and omitted unsupported/fanless fan copy when fan rows are not supported.

## Task Commits

1. **Task 1: Add independent fan section setting** - `14f033d` (feat)
2. **Task 2: Flow fan snapshots through MetricCollector and DashboardState** - `2d0b357` (feat)
3. **Task 3: Render the combined 温度与风扇 popover section** - `71fe627` (feat)

## Files Created/Modified

- `MacStatus/MacStatus/Utils/SettingsManager.swift` - Adds `showFanSection` key, backing storage, public property, persistence, notifications, and default-preserving load.
- `MacStatus/MacStatus/UI/Views/SettingsView.swift` - Adds the `风扇区块` visibility toggle after `散热区块`.
- `MacStatus/MacStatus/Collectors/MetricCollector.swift` - Adds `FanReader`, `lastFanSnapshot`, cadence-based reads, and dashboard fan updates.
- `MacStatus/MacStatus/UI/Views/DashboardView.swift` - Adds dashboard fan state and the combined temperature/fan popover section.

## Decisions Made

- Kept fan telemetry popover-only and current-snapshot-only, matching the Phase 10 thermal pattern.
- Used `fanSnapshot.supportState != .unsupported` to hide fanless/unsupported fan surfaces quietly.
- Used `FanCapabilities.boundsReadable` and `FanCapabilities.targetReadable` before showing optional range/target copy.
- Did not add fan status-bar text, fan history, raw SMC key UI, manual controls, disabled future controls, or left/right fan labels.

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` — PASS (`BUILD SUCCEEDED`).
- `rg -n "showFanSection|_showFanSection|风扇区块" MacStatus/MacStatus/Utils/SettingsManager.swift MacStatus/MacStatus/UI/Views/SettingsView.swift` — PASS.
- `rg -n "object\(forKey: Keys\.showFanSection\)" MacStatus/MacStatus/Utils/SettingsManager.swift` — PASS.
- Task 1 fan-control UI gate — PASS with targeted diff verification; no fan-related forbidden control words or controls were added.
- `rg -n "fanReader|lastFanSnapshot|dashboard\.updateFans|@Published var fan|func updateFans" MacStatus/MacStatus/Collectors/MetricCollector.swift MacStatus/MacStatus/UI/Views/DashboardView.swift` — PASS.
- `! rg -n "fan|Fan|RPM|风扇" MacStatus/MacStatus/Storage MacStatus/MacStatus/UI/StatusBarManager.swift MacStatus/MacStatus/Utils/Metric.swift` — PASS.
- `rg -n "温度与风扇|showThermalSection|showFanSection|FanSnapshot|FanReading|capabilities|N/A|范围|目标|边界可读，控制未启用|updateFans|frame\(width: 320\)" MacStatus/MacStatus/UI/Views/DashboardView.swift` — PASS.
- `! rg -n "控制可用|手动|恢复自动|静音|风扇控制|即将支持|F0Ac|FNum|FS!|F0Tg|Slider\(|Stepper\(|Button\(\".*风扇|左风扇|右风扇" MacStatus/MacStatus/UI/Views/DashboardView.swift` — PASS.

## Deviations from Plan

### Verification Adjustments

**1. Task 1 forbidden SettingsView grep narrowed to this task's diff**
- **Found during:** Task 1
- **Issue:** The planned whole-file command `! rg -n "手动|自动|恢复自动|静音|风扇控制|即将支持|Slider\(|Stepper\(" SettingsView.swift` matched pre-existing non-fan threshold sliders and comments containing `自动`.
- **Resolution:** Preserved unrelated existing settings UI and verified the Task 1 diff plus fan-specific SettingsView lines instead.
- **Files modified:** None beyond planned Task 1 files.
- **Verification:** `git show --unified=0 14f033d -- SettingsView.swift | rg ...` returned no fan-control additions; `rg -n "风扇|showFanSection" SettingsView.swift` shows only `Toggle("风扇区块", isOn: $settings.showFanSection)`.
- **Committed in:** `14f033d`

---

**Total deviations:** 1 verification adjustment, 0 functional scope changes.
**Impact on plan:** Acceptance intent is satisfied without deleting unrelated pre-existing settings features.

## Issues Encountered

- Final builds still emit an existing Swift 6 warning about `SettingsManager.changedKeysUserInfoKey` from the notification closure in `MetricCollector.swift`; it does not fail the build and was not introduced by the fan UI work.

## Known Stubs

- `MacStatus/MacStatus/UI/Views/SettingsView.swift:90` — pre-existing disabled `清除历史` TODO; unrelated to Phase 11 fan read-only UI and does not block this plan.
- Existing empty arrays/nil defaults in `DashboardState`, `MetricCollector`, and `SettingsManager` are live state defaults, not mock UI data.

## Authentication Gates

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for Plan 11-03. The read-only fan path is now visible in the popover on supported hardware, remains quiet on unsupported hardware, and preserves the no-control Phase 11 boundary for later safe-control planning.

## Self-Check: PASSED

- Found modified files: `SettingsManager.swift`, `SettingsView.swift`, `MetricCollector.swift`, `DashboardView.swift`.
- Found task commits: `14f033d`, `2d0b357`, `71fe627`.
- Final Debug build passed.
- Final storage/status-bar/metric fan absence gate passed.
- Final dashboard forbidden fan-control/raw-key UI gate passed.

---
*Phase: 11-fan-read-only-rpm-capability-model*
*Completed: 2026-06-24*
