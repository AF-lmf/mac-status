---
phase: 12-popover-layout-stability
verified: 2026-06-24T17:12:59Z
status: passed
score: 15/15 must-haves verified
overrides_applied: 0
---

# Phase 12: Popover Layout Stability Verification Report

**Phase Goal:** 用户打开 popover 时，网络、温度、RPM、功率和进程文本变化不会造成横向或纵向抖动。
**Verified:** 2026-06-24T17:12:59Z
**Status:** passed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | 网络上下行、温度、RPM、功率等数值从短值变成长值时，popover 不发生横向或纵向跳动。 | VERIFIED | `xcodebuild test` passed 6 tests; `testPopoverWidthIsFixedForShortAndExtremeFixtures` measured short/extreme width `372.0`; `testSameVisibilityFixturesKeepStableHeight` measured both heights `834.0`. |
| 2 | 关键数值列固定宽度、右对齐并使用 monospaced digits，能稳定容纳 `9999 RPM`、`100°C`、`N/A` 和大网络值。 | VERIFIED | `StableValueText` applies `.monospacedDigit()`, `.frame(width:alignment: .trailing)`, `layoutPriority(1)`; tests assert exact `StableValueWidth` contract and metric-card fit. |
| 3 | 长进程名、长传感器标签和长能力状态文本被稳定裁切或换行，不挤压相邻数值列。 | VERIFIED | `StableValueRow` truncates labels; `ProcessMetricRow` reserves fixed trailing width; `StableCaptionText` keeps fan captions full-width with two-line policy; process-row test confirms short/long names keep trailing x `224.0` and width `148.0`. |
| 4 | popover 宽度保持明确上限：固定在 360-380pt 范围内且不随刷新变化。 | VERIFIED | `DashboardLayout.popoverWidth = 372`; `DashboardView` root uses `.frame(width: DashboardLayout.popoverWidth)`; `PopoverManager` keeps `.preferredContentSize` and sets no competing popover width. |
| 5 | 极端数值和长文本通过确定性快照或测试数据验证，不只依赖肉眼观察。 | VERIFIED | DEBUG fixtures `.short` and `.extreme` populate required values; hosted XCTest target runs deterministic `NSHostingController` measurements. |
| 6 | D-04/D-05: DashboardView root width is fixed at exactly 372pt and no refresh/data state changes that value. | VERIFIED | `DashboardView.swift` has a single root fixed-width source through `DashboardLayout.popoverWidth`; tests compare short/extreme fixture widths to that constant with `accuracy: 0.5`. |
| 7 | D-01/D-02/D-03: high-jitter dashboard values render through shared fixed-width, right-aligned, monospaced-digit helpers. | VERIFIED | Metric cards, temperature rows, fan RPM rows, battery/power rows, and CPU/memory process trailing values use `StableValueText`/`StableValueRow` and `StableValueWidth` constants. |
| 8 | D-06/D-08/D-09: compact identity is preserved and network metric meaning is unchanged. | VERIFIED | No `ByteFormatting.swift` diff; network process rows still use `ByteFormatting.format(...)+"/s"`; touched views add fixed layout only, not new controls/charts/alerts. |
| 9 | D-02/D-07: Top-N process left text and PID yield before network/CPU/memory trailing values move. | VERIFIED | `ProcessMetricRow` groups name/PID in a low-priority truncating left region and wraps trailing content in fixed `trailingWidth`; network/CPU/memory call sites pass the required widths. |
| 10 | D-10/D-11: deterministic DEBUG fixtures cover short/extreme network, RPM, temperature, N/A, power, long text, and mixed availability. | VERIFIED | `DashboardLayoutFixtures.swift` is guarded by `#if DEBUG`; source contains `9999 RPM` via `9_999`, `100°C`, `999T`, `N/A`, `999.9W`, `99小时59分`, long process names, and mixed unavailable rows. |
| 11 | D-09: network rows keep compact upload/download semantics and only reserve stable trailing space. | VERIFIED | `NetworkTrafficValueBlock` renders upload/download as two fixed `68pt` monospaced cells inside a `148pt` trailing reservation; no formatter semantics changed. |
| 12 | D-10/D-11: short and extreme fixture states are executed by an automated deterministic test path. | VERIFIED | `DashboardLayoutStabilityTests` calls `DashboardLayoutFixture.make(.short/.extreme)` from hosted XCTest. |
| 13 | D-12: tests explicitly assert fixed 372pt width and same-visible-section layout stability. | VERIFIED | `testPopoverWidthIsFixedForShortAndExtremeFixtures` and `testSameVisibilityFixturesKeepStableHeight` passed. |
| 14 | D-12: tests compare value-column x-position and width for network card, temperature, fan RPM, battery/power, and process trailing surfaces. | VERIFIED | `testDashboardValueColumnFramesStayStableAcrossFixtures` compares all required `LayoutProbeID`s; x/width output is identical across short/extreme fixtures. |
| 15 | LAYOUT-01 through LAYOUT-04 and UAT-04 have reproducible command output captured in a verification artifact. | VERIFIED | `12-LAYOUT-VERIFICATION.md` records command, fixture values, source gates, and frame comparison results; verifier also reran `xcodebuild test` successfully. |

**Score:** 15/15 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `MacStatus/MacStatus/UI/Views/StableValueLayout.swift` | Stable width constants, value row/text/caption helpers, layout probe support | VERIFIED | Exists, substantive, in app target, provides `DashboardLayout`, `StableValueWidth`, `StableValueText`, `StableValueRow`, `StableCaptionText`, `LayoutProbeID`, and frame store. |
| `MacStatus/MacStatus/UI/Views/DashboardView.swift` | Fixed root width and dashboard integration | VERIFIED | Uses `.frame(width: DashboardLayout.popoverWidth)` and stable helpers for metric, thermal/fan, battery, and CPU/memory process sections. |
| `MacStatus/MacStatus/UI/Views/ProcessListView.swift` | Stable network process trailing block and left-yields process row | VERIFIED | `NetworkTrafficValueBlock` and `ProcessMetricRow(trailingWidth:)` reserve fixed trailing columns. |
| `MacStatus/MacStatus/UI/Fixtures/DashboardLayoutFixtures.swift` | DEBUG deterministic short/extreme fixtures | VERIFIED | Guarded by `#if DEBUG`; not referenced from live app, collector, popover, status-bar, or settings paths. |
| `MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift` | Automated layout stability assertions | VERIFIED | Hosted XCTest target runs 6 deterministic tests against fixtures and probes. |
| `.planning/phases/12-popover-layout-stability/12-LAYOUT-VERIFICATION.md` | Recorded deterministic layout evidence | VERIFIED | Contains test command result, width/height output, fixture coverage, and value-column frame table. |

`gsd-tools query verify.artifacts` passed for all three PLAN files: 6/6 artifacts.

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `DashboardView.swift` | `StableValueLayout.swift` | SwiftUI helper usage | WIRED | `DashboardView` references `DashboardLayout.popoverWidth`, `StableValueText`, `StableValueRow`, `StableCaptionText`, and `StableValueWidth`. |
| `project.pbxproj` | `StableValueLayout.swift` | App target source membership | WIRED | Manual grep confirms `StableValueLayout.swift in Sources` and file reference in project. |
| `ProcessListView.swift` | `StableValueLayout.swift` | Fixed network process widths | WIRED | Uses `StableValueWidth.processNetworkRate` and `StableValueWidth.processNetworkPair`. |
| `DashboardLayoutFixtures.swift` | `DashboardView.swift` | `DashboardState` fixture population | WIRED | Fixtures construct real `DashboardState` values consumed by `DashboardView`. |
| `DashboardLayoutStabilityTests.swift` | `DashboardLayoutFixtures.swift` | Short/extreme fixture execution | WIRED | Tests call `DashboardLayoutFixture.make(kind)` for measured dashboard size and frame snapshots. |
| `DashboardLayoutStabilityTests.swift` | `DashboardView.swift` | `NSHostingController` measurement | WIRED | Tests host `DashboardView().environmentObject(state)` with `.preferredContentSize`. |

Note: `gsd-tools query verify.key-links` returned false negatives for a few escaped Swift/Xcode regex patterns. Manual grep and source inspection verify the links above.

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `DashboardView.swift` | `DashboardState` published metrics, battery, thermal, fan, process arrays | Live `MetricCollector` path in app; deterministic `DashboardLayoutFixture.make` in tests | Yes | FLOWING |
| `ProcessListView.swift` | `processes`, `isLoading`, `errorMessage` props | `DashboardView` passes `state.topProcesses`, `state.processesLoading`, `state.processError` | Yes | FLOWING |
| `DashboardLayoutStabilityTests.swift` | Short/extreme dashboard states and probe frames | `DashboardLayoutFixture.make` plus `LayoutProbeFrameStore` | Yes | FLOWING |
| `DashboardLayoutFixtures.swift` | Fixture values | DEBUG fixture constructors only | Yes, deterministic test data | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Hosted test target is present | `xcodebuild -list -project MacStatus/MacStatus.xcodeproj` | Lists `MacStatus` and `MacStatusTests`; scheme `MacStatus` present | PASS |
| Deterministic layout tests pass | `xcodebuild test -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -destination 'platform=macOS' -derivedDataPath build` | `TEST SUCCEEDED`; 6 tests, 0 failures | PASS |
| Short/extreme root width and same-height evidence | Same `xcodebuild test` | Printed `short width=372.0 height=834.0`, `extreme width=372.0 height=834.0` | PASS |
| Required value-column frames are stable | Same `xcodebuild test` | Required probes report identical x-position and width across short/extreme fixtures | PASS |
| Fixture is not live-wired | `rg "DashboardLayoutFixture" MacStatus/MacStatus/App MacStatus/MacStatus/Collectors ...` | No matches | PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` probes were declared for this phase. Phase verification uses the hosted XCTest layout probe path instead.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| LAYOUT-01 | 12-01, 12-02, 12-03 | 数值长度变化时 popover 不横向或纵向抖动 | SATISFIED | Width/height tests pass for short/extreme fixtures; value-column frames stable. |
| LAYOUT-02 | 12-01, 12-02, 12-03 | 固定宽度、右对齐、monospaced digits，容纳 `9999 RPM`、`100°C`、`N/A`、大网络值 | SATISFIED | `StableValueText` contract plus exact width tests and extreme fixture values. |
| LAYOUT-03 | 12-01, 12-02, 12-03 | 长进程名、传感器标签、能力状态文本裁切/换行，不挤压数值列 | SATISFIED | `StableValueRow`, `StableCaptionText`, `ProcessMetricRow` and process trailing frame test. |
| LAYOUT-04 | 12-01, 12-03 | popover 固定在允许上限内并保持稳定 | SATISFIED | `DashboardLayout.popoverWidth = 372`, root frame uses that constant, tests assert it. |
| UAT-04 | 12-02, 12-03 | 确定性快照或测试数据覆盖极端值，不只靠肉眼观察 | SATISFIED | DEBUG fixtures plus hosted XCTest deterministic measurements; verifier reran test command. |

All Phase 12 requirement IDs in PLAN frontmatter are accounted for. REQUIREMENTS.md has no additional Phase 12 orphaned IDs beyond `LAYOUT-01`, `LAYOUT-02`, `LAYOUT-03`, `LAYOUT-04`, and `UAT-04`.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `DashboardView.swift` | 204 | `return []` | Info | Normal unsupported-fan fallback in `visibleFans`, not a stub. |
| `SettingsView.swift` | 203, 213 | `Slider(` | Info | Pre-existing CPU/memory threshold sliders; not Phase 12 fan control. |
| `MetricCollector.swift` | 136 | `token` in comment | Info | Existing observer-token comment; not a secret. |

No unreferenced `TBD`, `FIXME`, or `XXX` markers were found in Phase 12 touched files. No placeholder UI, console-only handlers, fan control, SMC write, helper/XPC, status-bar fan/thermal, raw sensor browser, alert, chart, network/API surface, or secrets were introduced.

### Human Verification Required

None. The phase's acceptance posture was deterministic layout verification; the popover width, same-visible-section height, fixed value widths, and value-column frames are covered by automated tests.

### Gaps Summary

No gaps found. The implementation satisfies the Phase 12 roadmap contract, PLAN must-haves, requirement traceability, deterministic test evidence, and layout-only scope boundary.

---

_Verified: 2026-06-24T17:12:59Z_
_Verifier: the agent (gsd-verifier)_
