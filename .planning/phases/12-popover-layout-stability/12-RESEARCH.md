# Phase 12: Popover Layout Stability - Research

**Researched:** 2026-06-24 [VERIFIED: local current_date]
**Domain:** SwiftUI/AppKit popover layout stability for a native macOS menu bar app [VERIFIED: AGENTS.md] [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md]
**Confidence:** HIGH [VERIFIED: codebase grep] [CITED: https://developer.apple.com/documentation/swiftui/view/frame%28width%3Aheight%3Aalignment%3A%29]

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
## Implementation Decisions

### Stable Numeric Rows
- **D-01:** Use a reusable stable value-row/value-column abstraction for Phase 12 high-jitter popover rows, instead of patching every row independently.
- **D-02:** Scope that abstraction to the known Phase 12 hotspots: network metric values, temperature rows, fan RPM rows, power/battery values, and Top-N process trailing values. Do not rewrite the entire dashboard UI just to introduce the helper.
- **D-03:** Key numeric values must be right-aligned and use monospaced digits. Widths should be explicit per value kind and sized for worst-case fixtures such as `9999 RPM`, `100°C`, `N/A`, large network rates, and large wattage values.

### Popover Width
- **D-04:** Do not keep `320pt` as a hard constraint. Phase 12 may fixed-expand the popover to a value in the `360-380pt` range.
- **D-05:** The selected popover width must be fixed once and must not change on refresh, data availability, network spikes, longer fan labels, or process list changes.
- **D-06:** Keep the current compact popover identity; expansion is for stable readability, not a new large dashboard redesign.

### Long Text Behavior
- **D-07:** When labels or process names compete with values, the text side yields. Long process names, long sensor labels, PID text, and capability/status copy must truncate or move to a separate line before they squeeze the numeric value column.
- **D-08:** Numeric columns remain stable even when explanatory copy such as fan boundary/control status is shown. Full-width captions are acceptable when they do not affect the paired value-column width.
- **D-09:** Network display can keep the current compact up/down presentation; stabilization should come from a fixed value block and row/card sizing, not from changing the meaning of the network metric.

### Deterministic Verification
- **D-10:** Phase 12 must include deterministic extreme test data or preview fixtures. It is not enough to rely on normal live readings or visual inspection during one run.
- **D-11:** Fixtures must cover at least: short and large network rates, `9999 RPM`, `100°C`, `N/A`, large power values, long process names, long sensor labels, and mixed availability across battery, thermal, fan, and process sections.
- **D-12:** Verification must explicitly check that popover width is fixed and that rows/value columns do not jump across short-value and long-value states.

### the agent's Discretion
- The planner may choose exact helper names and file splits, but should prefer small SwiftUI components or modifiers that match the existing `DashboardView` style.
- The planner may choose the precise width inside `360-380pt`, as long as it is fixed and justified by the deterministic fixture.
- The planner may choose whether verification is implemented as SwiftUI previews, XCTest/view-size tests, snapshot-style fixtures, or a lightweight debug fixture, as long as UAT-04 is satisfied deterministically.

### Deferred Ideas (OUT OF SCOPE)
## Deferred Ideas

None — discussion stayed within Phase 12 layout-stability scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LAYOUT-01 | 网络上下行、温度、RPM、功率等数值长度变化时，popover 不发生横向或纵向抖动 [VERIFIED: .planning/REQUIREMENTS.md] | Use one fixed root width plus stable value frames, not only monospaced fonts. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:135] [CITED: https://developer.apple.com/documentation/swiftui/view/frame%28width%3Aheight%3Aalignment%3A%29] |
| LAYOUT-02 | 关键数值列使用固定宽度、右对齐、monospaced digits，并能容纳 `9999 RPM`、`100°C`、`N/A` 和大网络值 [VERIFIED: .planning/REQUIREMENTS.md] | Apply explicit fixed widths per value kind and `.monospacedDigit()` or `.system(..., design: .monospaced)`. [CITED: https://developer.apple.com/documentation/swiftui/font/monospaceddigit%28%29] [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:200] |
| LAYOUT-03 | 长进程名、长传感器标签、能力状态文本使用稳定裁切或换行策略，不挤压相邻数值列 [VERIFIED: .planning/REQUIREMENTS.md] | Give value columns higher layout priority and constrain label/name text with `lineLimit`, truncation, and full-width captions where needed. [CITED: https://developer.apple.com/documentation/swiftui/view/layoutpriority%28_%3A%29] [CITED: https://developer.apple.com/documentation/swiftui/view/linelimit%28_%3A%29-513mb] |
| LAYOUT-04 | popover 宽度优先保持现有约 320pt；若新增散热区块需要扩展，允许上限到 360-380pt，但必须保持稳定布局 [VERIFIED: .planning/REQUIREMENTS.md] | Replace current `.frame(width: 320)` with a single fixed width constant in the approved 360-380pt range, and keep `NSHostingController.sizingOptions = [.preferredContentSize]`. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:135] [VERIFIED: MacStatus/MacStatus/UI/PopoverManager.swift:49] |
| UAT-04 | 布局稳定必须用确定性快照或测试数据覆盖极端数值，不只依赖肉眼观察 [VERIFIED: .planning/REQUIREMENTS.md] | Add deterministic short/extreme `DashboardState` fixtures and automated or scriptable size checks; current project has no XCTest target, so planner must include a validation task. [VERIFIED: local `xcodebuild -list`] |
</phase_requirements>

## Project Constraints (from AGENTS.md)

- Communicate with the user in Chinese. [VERIFIED: AGENTS.md]
- Keep the app native Swift on macOS 14+ with SwiftUI + AppKit; menu bar lifecycle remains AppKit/`NSStatusBar`. [VERIFIED: AGENTS.md]
- Keep the app lightweight with no external dependencies unless there is a strong reason. [VERIFIED: AGENTS.md]
- Avoid update loops or polling patterns that increase visible CPU load. [VERIFIED: AGENTS.md]
- Do not edit source outside a GSD workflow unless explicitly bypassed; this research phase only writes the research artifact. [VERIFIED: AGENTS.md]
- Project skills under `.agents/skills/` are document/SQL/review/git oriented and no SwiftUI layout-specific project skill was found. [VERIFIED: local project skills discovery]

## Summary

Phase 12 should be planned as a focused layout hardening pass over the existing SwiftUI popover, not as a data-model or monitoring feature phase. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] The main integration point is `DashboardView.body`, where the popover is currently pinned to `.frame(width: 320)`, while `PopoverManager` sizes the AppKit popover from the SwiftUI hosting controller preferred content size. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:135] [VERIFIED: MacStatus/MacStatus/UI/PopoverManager.swift:49]

The highest-risk layout surfaces are: metric-card values, especially the two-line network value; `TemperatureAndFanSectionView` rows and fan captions; `BatterySectionView.row`; and `ProcessMetricRow` trailing values for network/CPU/memory process lists. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:21] [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:194] [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:425] [VERIFIED: MacStatus/MacStatus/UI/Views/ProcessListView.swift:73] Existing code already uses monospaced fonts and some `minWidth`, but `minWidth` and `Spacer()` do not guarantee a stable value column when long labels or process names compete for space. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:204] [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:220] [VERIFIED: MacStatus/MacStatus/UI/Views/ProcessListView.swift:91]

**Primary recommendation:** Use a small reusable SwiftUI stable value-column/row helper, set the popover to one fixed width such as `372pt` inside the approved `360-380pt` range, and add deterministic short/extreme fixtures with size assertions or a scriptable layout probe before signoff. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] [ASSUMED]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Fixed popover width | SwiftUI popover view | AppKit popover host | `DashboardView` pins the content width; `PopoverManager` consumes the SwiftUI preferred content size through `NSHostingController`. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:135] [VERIFIED: MacStatus/MacStatus/UI/PopoverManager.swift:49] |
| Stable numeric columns | SwiftUI popover view | Formatting utilities | Column reservation and layout priority are view responsibilities; `ByteFormatting` only determines string length and should remain compatible. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:194] [VERIFIED: MacStatus/MacStatus/Utils/ByteFormatting.swift:12] |
| Long process/sensor label behavior | SwiftUI row components | Process/reader snapshots | Process names and sensor labels enter as data, but truncation/wrapping policy belongs in `ProcessMetricRow` and dashboard rows. [VERIFIED: MacStatus/MacStatus/UI/Views/ProcessListView.swift:80] [VERIFIED: MacStatus/MacStatus/Readers/FanReader.swift:17] |
| Deterministic layout fixtures | Test/debug support layer | Dashboard state model | Fixtures should construct `DashboardState`-compatible short and extreme visible states without live sensors, because UAT-04 forbids relying only on live data. [VERIFIED: .planning/REQUIREMENTS.md] [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:557] |
| Runtime monitoring data | Existing collectors/readers | Dashboard state | Phase 12 should not change sampling, SMC reads, process reads, status-bar data, or history storage. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] [VERIFIED: MacStatus/MacStatus/Collectors/MetricCollector.swift] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift | Project `SWIFT_VERSION = 6.0`; local compiler Swift 6.3.2 | Implement small SwiftUI helpers and fixtures | Existing project language and compiler settings. [VERIFIED: MacStatus/MacStatus.xcodeproj/project.pbxproj] [VERIFIED: local `swift --version`] |
| SwiftUI | macOS SDK through Xcode 26.5 | Popover view composition, fixed frames, text truncation, layout priority, monospaced digits | Existing UI layer and official APIs cover the required layout behavior. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift] [CITED: https://developer.apple.com/documentation/swiftui/view/frame%28width%3Aheight%3Aalignment%3A%29] |
| AppKit | macOS SDK through Xcode 26.5 | `NSPopover`/`NSHostingController` bridge | Existing popover host uses AppKit and should keep preferred-content sizing. [VERIFIED: MacStatus/MacStatus/UI/PopoverManager.swift:38] [VERIFIED: MacStatus/MacStatus/UI/PopoverManager.swift:49] |
| XCTest | Xcode 26.5 available, no test target currently | Recommended automated view-size/layout assertions if planner chooses a durable test target | XCTest is built into Xcode and avoids external snapshot packages; adding a test target is a Wave 0 planning gap. [VERIFIED: local `xcodebuild -list`] [ASSUMED] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `ByteFormatting` | Project-local | Determine current worst-case network/process rate text such as `999T` or `999T/s` | Use fixture values against current formatter instead of inventing new network string semantics. [VERIFIED: MacStatus/MacStatus/Utils/ByteFormatting.swift:20] |
| `DashboardState` | Project-local | Shared visible state for short/extreme fixtures | Use to drive `DashboardView` without live readers. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:557] |
| `NSHostingController` | AppKit | Measure SwiftUI view fitting size in deterministic validation | Use in XCTest or a lightweight debug probe to compare short vs extreme fixture sizes. [VERIFIED: MacStatus/MacStatus/UI/PopoverManager.swift:41] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Small stable-row helper | Patch every `HStack` independently | Independent patches are faster initially but tend to drift; user explicitly locked a reusable abstraction for hotspots. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] |
| Fixed `372pt` popover width [ASSUMED] | `360pt` or `380pt` | Any value in range is allowed; `372pt` leaves more room than 360 while preserving compact identity better than 380. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] [ASSUMED] |
| XCTest/view-size probe | SwiftUI previews only | Previews are useful for humans but do not satisfy deterministic automated size checks by themselves. [VERIFIED: .planning/REQUIREMENTS.md] [ASSUMED] |
| Built-in SwiftUI layout APIs | Third-party snapshot/layout packages | External packages are unnecessary for fixed frames, truncation, and size assertions, and project constraints prefer zero/minimal dependencies. [VERIFIED: AGENTS.md] [CITED: https://developer.apple.com/documentation/swiftui/view/frame%28width%3Aheight%3Aalignment%3A%29] |

**Installation:**

No external packages are recommended for Phase 12. [VERIFIED: AGENTS.md] [VERIFIED: local package audit]

## Package Legitimacy Audit

No external packages should be installed for this phase. [VERIFIED: AGENTS.md]

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| none | — | — | — | — | slopcheck unavailable, not needed | Approved: no install surface [VERIFIED: local `command -v slopcheck`] |

**Packages removed due to slopcheck [SLOP] verdict:** none. [VERIFIED: no packages recommended]
**Packages flagged as suspicious [SUS]:** none. [VERIFIED: no packages recommended]

## Architecture Patterns

### System Architecture Diagram

```text
Live collector snapshots
  -> DashboardState published fields
  -> DashboardView fixed-width root
     -> metric cards
        -> StableValueText for CPU/memory/network/GPU display values
     -> battery / temperature / fan rows
        -> StableValueRow(label, StableValueText(kind))
        -> full-width captions for explanatory fan copy
     -> process sections
        -> ProcessMetricRow(leftText yields, trailing fixed block wins)
  -> NSHostingController preferredContentSize
  -> NSPopover visible size

Deterministic fixture path
  -> short fixture DashboardState
  -> extreme fixture DashboardState
  -> host each DashboardView
  -> assert same width and no value-column/frame regression
```

This diagram reflects the current `DashboardState -> DashboardView -> NSHostingController -> NSPopover` flow. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:8] [VERIFIED: MacStatus/MacStatus/UI/PopoverManager.swift:41]

### Recommended Project Structure

```text
MacStatus/MacStatus/UI/Views/
├── DashboardView.swift              # edit existing popover root and section integration
├── ProcessListView.swift            # edit existing process row/trailing layout
└── StableValueLayout.swift          # add small SwiftUI helpers if planner chooses separate file

MacStatus/MacStatus/UI/Fixtures/
└── DashboardLayoutFixtures.swift    # add deterministic short/extreme layout states, preferably DEBUG/test-only

MacStatus/MacStatusTests/
└── DashboardLayoutStabilityTests.swift  # add only if planner chooses XCTest target
```

The helper file and fixture folder names are recommendations; the user allowed planner discretion on helper names and file splits. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] [ASSUMED]

### Pattern 1: Stable Value Text

**What:** A single helper renders jitter-prone values with explicit width, trailing alignment, and fixed-width digits. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] [CITED: https://developer.apple.com/documentation/swiftui/font/monospaceddigit%28%29]

**When to use:** Use for network rates, temperatures, RPM, wattage/power, battery health, and process trailing values. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md]

**Example:**

```swift
// Source: SwiftUI frame + monospacedDigit official APIs and existing DashboardView row style.
// Width constants are planning recommendations and must be validated by fixtures.
enum StableValueWidth {
    static let temperature: CGFloat = 56   // "100°C", "N/A"
    static let rpm: CGFloat = 78           // "9999 RPM", "N/A"
    static let watts: CGFloat = 92         // "耗电 999.9W", "—"
    static let rate: CGFloat = 68          // "999T/s", "N/A"
}

struct StableValueText: View {
    let text: String
    let width: CGFloat
    var color: Color = .secondary
    var textStyle: Font.TextStyle = .caption

    var body: some View {
        Text(text)
            .font(.system(textStyle, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .frame(width: width, alignment: .trailing)
            .layoutPriority(1)
    }
}
```

The official `frame(width:height:alignment:)` API specifies fixed dimensions and alignment, and `monospacedDigit()` uses fixed-width numeric characters. [CITED: https://developer.apple.com/documentation/swiftui/view/frame%28width%3Aheight%3Aalignment%3A%29] [CITED: https://developer.apple.com/documentation/swiftui/font/monospaceddigit%28%29]

### Pattern 2: Text Yields, Value Wins

**What:** Rows should constrain labels/names first, then reserve a fixed trailing value block. [CITED: https://developer.apple.com/documentation/swiftui/view/layoutpriority%28_%3A%29] [CITED: https://developer.apple.com/documentation/swiftui/text/truncationmode/tail]

**When to use:** Use anywhere a label, process name, PID, or status string shares a row with a numeric value. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md]

**Example:**

```swift
// Source: Apple lineLimit/truncation/layoutPriority APIs and existing ProcessMetricRow shape.
struct StableValueRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)

            value()
                .layoutPriority(1)
        }
    }
}
```

Existing `ProcessMetricRow` already truncates the process name, but its trailing closure has no reserved width and can still compete with PID/name text. [VERIFIED: MacStatus/MacStatus/UI/Views/ProcessListView.swift:80] [VERIFIED: MacStatus/MacStatus/UI/Views/ProcessListView.swift:92]

### Pattern 3: Fixed Popover Width Constant

**What:** Replace the magic `320` with a named constant and use it once at the root. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:135]

**When to use:** Use for `DashboardView` only; do not set conflicting widths on cards or `NSPopover`. [VERIFIED: MacStatus/MacStatus/UI/PopoverManager.swift:49]

**Example:**

```swift
// Source: current DashboardView root .frame(width:) and Phase 12 D-04/D-05.
private enum DashboardLayout {
    static let popoverWidth: CGFloat = 372 // validate against fixtures
}

// DashboardView.body tail:
.padding(12)
.frame(width: DashboardLayout.popoverWidth)
```

The exact width is planner discretion inside `360-380pt`; it must be fixed and justified by the deterministic fixture. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md]

### Pattern 4: Deterministic Short/Extreme Fixtures

**What:** Build two states with identical section visibility but different text lengths, then measure or snapshot both. [VERIFIED: .planning/REQUIREMENTS.md]

**When to use:** Use for UAT-04 and for preventing regressions when future fan-control UI adds more copy. [VERIFIED: .planning/STATE.md]

**Example:**

```swift
// Source: DashboardState published fields and Phase 12 fixture requirements.
enum DashboardLayoutFixture {
    static func applyShort(to state: DashboardState) {
        state.cpuText = "1%"
        state.memoryText = "2% (OK)"
        state.networkText = "↑1K\n↓2K"
        state.gpuText = "N/A"
        state.thermal = ThermalSnapshot(
            cpuSocTemperatureCelsius: 35,
            systemState: .nominal,
            gpuTemperatureCelsius: nil,
            batteryTemperatureCelsius: nil,
            capturedAt: Date(timeIntervalSince1970: 0)
        )
        state.fan = FanSnapshot(
            supportState: .supported,
            fans: [
                FanReading(
                    id: 0,
                    index: 0,
                    displayName: "风扇 1",
                    currentRPM: 999,
                    minRPM: nil,
                    maxRPM: nil,
                    targetRPM: nil,
                    capabilities: FanCapabilities(
                        rpmReadable: true,
                        boundsReadable: false,
                        targetReadable: false,
                        safeControlAvailable: false
                    )
                )
            ],
            capturedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
```

The final fixture must also include extreme network, `9999 RPM`, `100°C`, `N/A`, large power, long process names, long sensor labels, and mixed availability. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md]

### Anti-Patterns to Avoid

- **Only expanding `320pt` to `380pt`:** Width expansion alone does not stop long labels from compressing trailing values inside `HStack`. [VERIFIED: MacStatus/MacStatus/UI/Views/ProcessListView.swift:79] [ASSUMED]
- **Using `minWidth` where a fixed column is required:** `minWidth` reserves a floor, not a stable column contract; Phase 12 requires fixed value widths. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:204] [CITED: https://developer.apple.com/documentation/swiftui/view/frame%28minwidth%3Aidealwidth%3Amaxwidth%3Aminheight%3Aidealheight%3Amaxheight%3Aalignment%3A%29]
- **Putting capability copy inside paired value rows:** Full-width captions are acceptable, but they should not share the value row's label/value width negotiation. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md]
- **Changing `ByteFormatting` semantics to solve layout:** The phase is layout stabilization, and current formatter already keeps byte strings compact; solve by reserving space for current worst cases. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] [VERIFIED: MacStatus/MacStatus/Utils/ByteFormatting.swift:12]
- **Relying on live hardware values for acceptance:** UAT-04 explicitly requires deterministic snapshots or test data. [VERIFIED: .planning/REQUIREMENTS.md]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Fixed dimensions and alignment | Custom geometry math for every row | SwiftUI `.frame(width:alignment:)` | The official API already specifies fixed dimensions and alignment. [CITED: https://developer.apple.com/documentation/swiftui/view/frame%28width%3Aheight%3Aalignment%3A%29] |
| Fixed-width digits | Manual padding with spaces | `.monospacedDigit()` or system monospaced font | SwiftUI provides fixed-width numeric glyphs without locale-fragile string hacks. [CITED: https://developer.apple.com/documentation/swiftui/font/monospaceddigit%28%29] |
| Text truncation | Manual substring clipping | `.lineLimit(1)` plus `.truncationMode(.tail)` | Built-in text fitting handles glyph widths and accessibility better than byte/character clipping. [CITED: https://developer.apple.com/documentation/swiftui/view/linelimit%28_%3A%29-513mb] [CITED: https://developer.apple.com/documentation/swiftui/text/truncationmode/tail] |
| View size validation | Image diff library dependency | `NSHostingController`/XCTest or a lightweight debug probe | The project prefers no external dependencies, and deterministic size checks can be done with platform tools. [VERIFIED: AGENTS.md] [VERIFIED: MacStatus/MacStatus/UI/PopoverManager.swift:41] [ASSUMED] |
| Network large-value handling | New formatter or wider semantic units | Existing `ByteFormatting` plus fixed columns | Current formatter caps each unit at `999`, so layout can plan around bounded strings unless formatter semantics change. [VERIFIED: MacStatus/MacStatus/Utils/ByteFormatting.swift:20] |

**Key insight:** The bug class is not data collection; it is SwiftUI layout negotiation under changing text. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] The fix should reserve the scarce dimension, make labels yield, and prove the same fixture shape keeps stable dimensions. [CITED: https://developer.apple.com/documentation/swiftui/view/layoutpriority%28_%3A%29] [ASSUMED]

## Common Pitfalls

### Pitfall 1: `minWidth` Does Not Prove Column Stability

**What goes wrong:** A value can grow beyond its minimum and change row/card layout, or a long label can still participate in negotiation before the value settles. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:204] [ASSUMED]
**Why it happens:** Current thermal and fan rows use `.frame(minWidth:..., alignment: .trailing)` rather than a fixed `width`. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:204] [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:220]
**How to avoid:** Use fixed `width` for known value kinds, and validate the chosen widths against fixtures. [CITED: https://developer.apple.com/documentation/swiftui/view/frame%28width%3Aheight%3Aalignment%3A%29]
**Warning signs:** `frame(minWidth:)` remains on Phase 12 hotspots after implementation. [VERIFIED: codebase grep]

### Pitfall 2: Process PID Text Competes With Trailing Metrics

**What goes wrong:** A long process name plus PID can compress or push upload/download, CPU, or memory values. [VERIFIED: MacStatus/MacStatus/UI/Views/ProcessListView.swift:80] [VERIFIED: MacStatus/MacStatus/UI/Views/ProcessListView.swift:85]
**Why it happens:** `ProcessMetricRow` truncates the process name but does not group name/PID as a left region with a fixed trailing region. [VERIFIED: MacStatus/MacStatus/UI/Views/ProcessListView.swift:79]
**How to avoid:** Put name and PID inside a left container that has `maxWidth: .infinity`, low layout priority, and truncation; put the trailing metric block in a fixed-width container. [CITED: https://developer.apple.com/documentation/swiftui/view/layoutpriority%28_%3A%29]
**Warning signs:** `ProcessMetricRow` still ends with `Spacer(); trailing()` and no trailing frame. [VERIFIED: MacStatus/MacStatus/UI/Views/ProcessListView.swift:91]

### Pitfall 3: Network Metric Is Two Lines But Not a Stable Block

**What goes wrong:** Network value text can remain two-line while still changing horizontal pressure inside the metric card. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:650] [ASSUMED]
**Why it happens:** `MetricCardWithSparkline` uses `Text(value)` and `.fixedSize(horizontal: false, vertical: true)`, but it does not reserve a fixed network value width. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:353] [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:358]
**How to avoid:** Render the metric value through a stable value block, and reserve two lines for network text if needed. [CITED: https://developer.apple.com/documentation/swiftui/view/linelimit%28_%3Areservesspace%3A%29]
**Warning signs:** Fixture network states `↑1K\n↓2K` and `↑999T\n↓999T` produce different card or popover fitting sizes. [VERIFIED: MacStatus/MacStatus/Utils/ByteFormatting.swift:20] [ASSUMED]

### Pitfall 4: Full-Width Captions Accidentally Re-enter Row Negotiation

**What goes wrong:** Fan range/target/control-status copy can squeeze the fan RPM row or change row width when it should wrap/truncate independently. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:224] [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:238]
**Why it happens:** Captions are in the same `VStack` as the row and currently have no explicit wrapping/truncation contract. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:209]
**How to avoid:** Keep primary fan RPM as a stable paired row and render capability/range/target as full-width caption text with a fixed line policy. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md]
**Warning signs:** Long capability text affects the measured x-position or width of the RPM value block. [ASSUMED]

### Pitfall 5: Deterministic Verification Becomes a Preview Only

**What goes wrong:** The phase passes visually on one live machine but regresses under extreme fixture data. [VERIFIED: .planning/REQUIREMENTS.md]
**Why it happens:** The project currently has no XCTest target, and prior phases primarily used build/grep/hardware probes. [VERIFIED: local `xcodebuild -list`] [VERIFIED: .planning/phases/11-fan-read-only-rpm-capability-model/11-VERIFICATION.md]
**How to avoid:** Plan an explicit validation task that creates short/extreme fixtures and either an XCTest size assertion or a scriptable debug probe. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] [ASSUMED]
**Warning signs:** Final verification says "opened popover and looked stable" without fixture output. [VERIFIED: .planning/REQUIREMENTS.md]

## Code Examples

Verified patterns from official sources and current code:

### Stable Process Row

```swift
// Source: ProcessMetricRow current shape + Apple layoutPriority/frame/truncation APIs.
struct StableProcessMetricRow<Trailing: View>: View {
    let processName: String
    let pid: Int32?
    let trailingWidth: CGFloat
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(processName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let pid {
                    Text("(\(pid))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            trailing()
                .frame(width: trailingWidth, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.vertical, 1)
    }
}
```

Current `ProcessMetricRow` has the same conceptual parts but no fixed trailing region. [VERIFIED: MacStatus/MacStatus/UI/Views/ProcessListView.swift:73]

### Network Traffic Trailing Block

```swift
// Source: current ProcessListView upload/download labels and ByteFormatting bounded output.
struct NetworkTrafficValueBlock: View {
    let upload: String
    let download: String

    var body: some View {
        HStack(spacing: 6) {
            StableValueText(text: upload, width: StableValueWidth.rate, color: .orange, textStyle: .caption2)
            StableValueText(text: download, width: StableValueWidth.rate, color: .blue, textStyle: .caption2)
        }
    }
}
```

The current process network row renders upload/download as two labels with monospaced caption fonts. [VERIFIED: MacStatus/MacStatus/UI/Views/ProcessListView.swift:44]

### View Size Assertion Shape

```swift
// Source: NSHostingController use in PopoverManager and XCTest recommendation.
@MainActor
func measuredSize(for fixture: DashboardLayoutFixture.Kind) -> CGSize {
    let state = DashboardState()
    DashboardLayoutFixture.apply(fixture, to: state)
    let controller = NSHostingController(
        rootView: DashboardView().environmentObject(state)
    )
    controller.view.layoutSubtreeIfNeeded()
    return controller.view.fittingSize
}

@MainActor
func testExtremeFixtureKeepsPopoverWidth() {
    let short = measuredSize(for: .short)
    let extreme = measuredSize(for: .extreme)
    XCTAssertEqual(short.width, DashboardLayout.popoverWidth, accuracy: 0.5)
    XCTAssertEqual(extreme.width, DashboardLayout.popoverWidth, accuracy: 0.5)
    XCTAssertEqual(short.width, extreme.width, accuracy: 0.5)
}
```

This pattern is a recommendation; the project currently lacks a test target, so the planner must decide whether to add XCTest or implement a lightweight debug probe. [VERIFIED: local `xcodebuild -list`] [ASSUMED]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Proportional digits in changing numeric text | `.monospacedDigit()` or monospaced system fonts | Available in SwiftUI API used by current SDK [CITED: https://developer.apple.com/documentation/swiftui/font/monospaceddigit%28%29] | Prevents digit glyph-width jitter, but still needs fixed value frames for full stability. [ASSUMED] |
| `Spacer()` plus flexible text rows | Explicit fixed value frames plus `layoutPriority` | SwiftUI layout APIs available in current SDK [CITED: https://developer.apple.com/documentation/swiftui/view/layoutpriority%28_%3A%29] | Makes the numeric column win when text competes for space. [ASSUMED] |
| Human-only preview checks | Deterministic fixtures plus size assertions/probe output | Required by Phase 12 UAT-04 [VERIFIED: .planning/REQUIREMENTS.md] | Catches regressions when values become extreme or labels are long. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] |

**Deprecated/outdated:**

- Treating `320pt` as an immutable popover width is outdated for Phase 12; the user explicitly allowed fixed expansion to `360-380pt`. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md]
- Using local `minWidth` as the final layout-stability mechanism is insufficient for Phase 12 because the locked decision requires explicit per-kind widths. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `372pt` is a good default fixed width inside the allowed range. | Summary, Architecture Patterns | Planner may choose a different width after fixture measurement. |
| A2 | Initial width constants such as `rpm = 78`, `watts = 92`, and `rate = 68` are sufficient before measurement. | Code Examples | Fixture tests may require adjusting constants. |
| A3 | XCTest view-size assertions are worth the xcodeproj cost for UAT-04. | Standard Stack, Code Examples | Planner may choose a lighter debug probe instead to avoid adding a test target. |
| A4 | `NSHostingController.view.fittingSize` is sufficient for detecting root width regressions in this app. | Code Examples | AppKit/SwiftUI fitting behavior may require setting an explicit frame or forcing layout in the test harness. |

## Open Questions

1. **Exact popover width**
   - What we know: user approved a fixed width in `360-380pt`; current code is `320pt`. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:135]
   - What's unclear: whether `360`, `372`, or `380` best fits all extreme fixtures. [ASSUMED]
   - Recommendation: plan a first task that implements fixtures and validates the chosen width before finalizing helper constants. [ASSUMED]

2. **Automated validation vehicle**
   - What we know: no test target exists, and UAT-04 requires deterministic data rather than visual-only validation. [VERIFIED: local `xcodebuild -list`] [VERIFIED: .planning/REQUIREMENTS.md]
   - What's unclear: whether the project wants to carry a permanent XCTest target now. [ASSUMED]
   - Recommendation: use XCTest if planner accepts xcodeproj setup; otherwise add a lightweight debug layout probe that prints measured short/extreme sizes and commit the output to phase verification. [ASSUMED]

3. **Long sensor label source**
   - What we know: current fan labels default to `风扇 N`, and current thermal labels are short fixed strings. [VERIFIED: MacStatus/MacStatus/Readers/FanReader.swift:160] [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift:166]
   - What's unclear: whether Phase 12 should add fixture-only long labels without changing real reader labels. [ASSUMED]
   - Recommendation: use fixture-only long labels for layout stress; do not add new real sensor-label semantics. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] [ASSUMED]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Xcode / `xcodebuild` | Build and optional XCTest layout checks | yes | Xcode 26.5 build 17F42 [VERIFIED: local `xcodebuild -version`] | none needed |
| Swift compiler | Build and possible local debug probe | yes | Swift 6.3.2 [VERIFIED: local `swift --version`] | none needed |
| XCTest target | Automated layout tests | no | Project lists only `MacStatus` target [VERIFIED: local `xcodebuild -list`] | Add test target or use debug probe |
| Context7 CLI | Library documentation lookup | no | `ctx7 not found` [VERIFIED: local `command -v ctx7`] | Official Apple docs via web search were used |
| slopcheck | Package legitimacy gate | no | unavailable [VERIFIED: local `command -v slopcheck`] | No packages recommended, so not blocking |

**Missing dependencies with no fallback:**

- None for implementation. [VERIFIED: environment audit]

**Missing dependencies with fallback:**

- XCTest target is missing; planner can add it or use a scriptable debug probe for UAT-04. [VERIFIED: local `xcodebuild -list`] [ASSUMED]
- Context7 CLI is missing; official Apple documentation links were used instead. [VERIFIED: local `command -v ctx7`] [CITED: https://developer.apple.com/documentation/swiftui/view/frame%28width%3Aheight%3Aalignment%3A%29]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | No auth surface is involved in popover layout. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] |
| V3 Session Management | no | No session or network service surface is involved. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] |
| V4 Access Control | no | No privilege boundary changes are planned. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] |
| V5 Input Validation | yes | Treat process names, sensor labels, and status copy as untrusted-length UI text; constrain via line limits/truncation/wrapping. [VERIFIED: MacStatus/MacStatus/UI/Views/ProcessListView.swift:80] [CITED: https://developer.apple.com/documentation/swiftui/view/linelimit%28_%3A%29-513mb] |
| V6 Cryptography | no | No cryptography is involved. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] |

### Known Threat Patterns for SwiftUI Popover Layout

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Layout denial via very long process names | Denial of Service | Line-limit/truncate left text and reserve fixed trailing value block. [VERIFIED: MacStatus/MacStatus/UI/Views/ProcessListView.swift:80] [CITED: https://developer.apple.com/documentation/swiftui/text/truncationmode/tail] |
| Misleading clipped numeric values | Information Integrity | Size value columns for worst-case fixtures and only allow text side to yield. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] |
| Scope creep into fan control/status-bar surfaces | Tampering / Safety boundary expansion | Keep Phase 12 layout-only; do not add fan controls, status-bar fan/thermal segments, new readers, or SMC writes. [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md] [VERIFIED: .planning/STATE.md] |

## Sources

### Primary (HIGH confidence)

- `.planning/phases/12-popover-layout-stability/12-CONTEXT.md` - locked decisions D-01 through D-12 and Phase 12 boundaries. [VERIFIED: local read]
- `.planning/REQUIREMENTS.md` - LAYOUT-01 through LAYOUT-04 and UAT-04. [VERIFIED: local read]
- `.planning/STATE.md` - Phase 10/11 completion state and deferred fan-control boundaries. [VERIFIED: local read]
- `AGENTS.md` - Chinese communication, native Swift/AppKit/SwiftUI, performance, zero/minimal dependency constraints. [VERIFIED: local read]
- `MacStatus/MacStatus/UI/Views/DashboardView.swift` - root width, metric cards, temperature/fan rows, battery rows, process sections, dashboard state. [VERIFIED: codebase grep]
- `MacStatus/MacStatus/UI/Views/ProcessListView.swift` - process row truncation and trailing layout. [VERIFIED: codebase grep]
- `MacStatus/MacStatus/Utils/ByteFormatting.swift` - compact bounded byte/rate formatting. [VERIFIED: codebase grep]
- `MacStatus/MacStatus/UI/PopoverManager.swift` - `NSHostingController` preferred content size bridge. [VERIFIED: codebase grep]
- Apple Developer Documentation: SwiftUI `frame(width:height:alignment:)`, `monospacedDigit()`, `lineLimit`, `truncationMode`, `layoutPriority`, `fixedSize`, and `lineLimit(_:reservesSpace:)`. [CITED: https://developer.apple.com/documentation/swiftui/view/frame%28width%3Aheight%3Aalignment%3A%29] [CITED: https://developer.apple.com/documentation/swiftui/font/monospaceddigit%28%29]

### Secondary (MEDIUM confidence)

- Prior Phase 10 and Phase 11 summaries, UI specs, and verification docs for established popover style, fixed `320pt` pre-Phase-12 contract, and build/probe verification pattern. [VERIFIED: local read]

### Tertiary (LOW confidence)

- None. [VERIFIED: research source log]

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH - phase uses existing SwiftUI/AppKit/Xcode stack and no package installs. [VERIFIED: AGENTS.md] [VERIFIED: local `xcodebuild -version`]
- Architecture: HIGH - current `DashboardState -> DashboardView -> NSHostingController -> NSPopover` flow is directly visible in code. [VERIFIED: MacStatus/MacStatus/UI/Views/DashboardView.swift] [VERIFIED: MacStatus/MacStatus/UI/PopoverManager.swift]
- Pitfalls: HIGH - unstable hotspots are present in current `HStack`/`Spacer`/`minWidth` code and match locked Phase 12 requirements. [VERIFIED: codebase grep] [VERIFIED: .planning/phases/12-popover-layout-stability/12-CONTEXT.md]
- Validation approach: MEDIUM - UAT-04 need is clear, but exact XCTest vs debug-probe implementation is still planner discretion because no test target exists today. [VERIFIED: local `xcodebuild -list`] [ASSUMED]

**Research date:** 2026-06-24 [VERIFIED: local current_date]
**Valid until:** 2026-07-24 for codebase-specific layout planning; re-check if `DashboardView`, `ProcessListView`, or Xcode project targets change before implementation. [ASSUMED]
