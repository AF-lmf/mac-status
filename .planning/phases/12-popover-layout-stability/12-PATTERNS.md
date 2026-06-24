# Phase 12: Popover Layout Stability - Pattern Map

**Mapped:** 2026-06-24
**Files analyzed:** 8
**Analogs found:** 7 / 8

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `MacStatus/MacStatus/UI/Views/DashboardView.swift` | component | request-response | `MacStatus/MacStatus/UI/Views/DashboardView.swift` | exact |
| `MacStatus/MacStatus/UI/Views/ProcessListView.swift` | component | transform | `MacStatus/MacStatus/UI/Views/ProcessListView.swift` | exact |
| `MacStatus/MacStatus/Utils/ByteFormatting.swift` | utility | transform | `MacStatus/MacStatus/Utils/ByteFormatting.swift` | exact |
| `MacStatus/MacStatus/UI/Views/StableValueLayout.swift` | component/utility | transform | `MacStatus/MacStatus/UI/Views/DashboardView.swift` | role-match |
| `MacStatus/MacStatus/UI/Fixtures/DashboardLayoutFixtures.swift` | fixture | transform | `MacStatus/MacStatus/UI/Views/DashboardView.swift` | partial |
| `MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift` | test | request-response | none | no-analog |
| `MacStatus/MacStatus.xcodeproj/project.pbxproj` | config | build graph | `MacStatus/MacStatus.xcodeproj/project.pbxproj` | role-match |
| `MacStatus/MacStatus/UI/PopoverManager.swift` | provider | request-response | `MacStatus/MacStatus/UI/PopoverManager.swift` | exact |

## Pattern Assignments

### `MacStatus/MacStatus/UI/Views/DashboardView.swift` (component, request-response)

**Analog:** `MacStatus/MacStatus/UI/Views/DashboardView.swift`

**Imports and state pattern** (lines 1-12):
```swift
import SwiftUI

// MARK: - Dashboard View

/// Main popover content — iStat-style card layout with sparkline trends.
/// Shows CPU, Memory, Network, GPU cards + top processes list.
struct DashboardView: View {
    @EnvironmentObject private var state: DashboardState

    var body: some View {
        let settings = SettingsManager.shared
        VStack(spacing: 8) {
```

**Root popover width integration point** (lines 133-135):
```swift
        }
        .padding(12)
        .frame(width: 320)
```

Copy this root-only width pattern, but replace the magic number with one named fixed constant from the UI contract, `372pt`. Do not also set an independent fixed width in `PopoverManager`.

**Metric grid/card composition pattern** (lines 21-60):
```swift
LazyVGrid(
    columns: [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ],
    spacing: 8
) {
    MetricCardWithSparkline(title: "CPU", value: state.cpuText, ...)
    MetricCardWithSparkline(title: "Network", value: state.networkText, ...)
}
```

Keep the two equal columns. Apply stable value widths inside card content, not by changing grid semantics.

**Thermal/fan row hotspot** (lines 194-220):
```swift
private func temperatureRow(_ label: String, _ value: String, color: Color = .secondary) -> some View {
    HStack(spacing: 8) {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
        Text(value)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .frame(minWidth: 52, alignment: .trailing)
    }
}

Text(fanRPMText(fan))
    .font(.system(.caption, design: .monospaced))
    .foregroundStyle(fan.currentRPM == nil ? .secondary : .primary)
    .multilineTextAlignment(.trailing)
    .frame(minWidth: 72, alignment: .trailing)
```

Copy the visual style and inline `N/A` degradation, but change Phase 12 value columns from `minWidth` to fixed width through the shared helper: temperature `56pt`, RPM `78pt`.

**Full-width caption pattern for explanatory copy** (lines 224-242):
```swift
if let range = fanRangeText(fan) {
    Text(range)
        .font(.caption2)
        .foregroundStyle(.secondary)
}

if fanRangeText(fan) != nil || fanTargetText(fan) != nil {
    Text("边界可读，控制未启用")
        .font(.caption2)
        .foregroundStyle(.secondary)
}
```

Keep fan range/target/control-boundary copy as caption text outside the paired value row so it does not participate in numeric column width negotiation.

**Battery row hotspot** (lines 425-434):
```swift
private func row(_ label: String, _ value: String) -> some View {
    HStack {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
        Text(value)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}
```

Copy the compact row style, but make the trailing text a fixed-width stable value cell. Use UI-SPEC widths: power `104pt`, health/time `112pt`.

**DashboardState fixture construction surface** (lines 557-603):
```swift
@MainActor
final class DashboardState: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var cpuText: String = "--"
    @Published var networkText: String = "--"
    @Published var battery: BatterySnapshot? = nil
    @Published var thermal: ThermalSnapshot = .unavailable()
    @Published var fan: FanSnapshot = .unavailable()
    @Published var topProcesses: [ProcessNetworkUsage] = []
    @Published var topCPUProcesses: [ProcessResourceUsage] = []
    @Published var topMemoryProcesses: [ProcessResourceUsage] = []
}
```

Fixtures should populate this existing state object directly with short/extreme values. Keep fixture data developer/test-only; do not route it into live collector paths.

---

### `MacStatus/MacStatus/UI/Views/ProcessListView.swift` (component, transform)

**Analog:** `MacStatus/MacStatus/UI/Views/ProcessListView.swift`

**Imports and section style** (lines 1-17):
```swift
import SwiftUI

struct ProcessListView: View {
    let processes: [ProcessNetworkUsage]
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top Processes (by network)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
```

Keep the section as a compact card with `VStack(alignment: .leading, spacing: 4)`, `padding(10)`, and `Color.primary.opacity(0.04)` background.

**Loading/error/empty pattern** (lines 19-40):
```swift
if isLoading {
    HStack {
        ProgressView()
            .scaleEffect(0.6)
        Text("Sampling...")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.vertical, 8)
} else if let errorMessage {
    Text(errorMessage)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
}
```

If touched, update copy to the UI-SPEC Chinese strings, but keep inline centered degradation. Do not add modal/toast error UI.

**Network trailing values hotspot** (lines 42-57):
```swift
ForEach(processes.prefix(5), id: \.stableID) { proc in
    ProcessMetricRow(processName: proc.processName, pid: proc.processIdentifier) {
        Label(ByteFormatting.format(proc.uploadBytesPerSec) + "/s", systemImage: "arrow.up")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.orange)

        Label(ByteFormatting.format(proc.downloadBytesPerSec) + "/s", systemImage: "arrow.down")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.blue)
    }
}
```

Copy the color/icon semantics, but wrap upload/download in fixed cells: two `68pt` value cells plus `12pt` internal gap for `148pt` total.

**Left-yields row pattern to harden** (lines 73-94):
```swift
struct ProcessMetricRow<Trailing: View>: View {
    let processName: String
    let pid: Int32?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(processName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)

            if let pid {
                Text("(\(pid))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
            trailing()
        }
        .padding(.vertical, 1)
    }
}
```

Preserve generic trailing content, but group process name and PID into a left region with `frame(maxWidth: .infinity, alignment: .leading)`, `lineLimit(1)`, tail truncation, and lower layout priority than the trailing fixed-width value block.

---

### `MacStatus/MacStatus/Utils/ByteFormatting.swift` (utility, transform)

**Analog:** `MacStatus/MacStatus/Utils/ByteFormatting.swift`

**Formatter namespace pattern** (lines 1-12):
```swift
import Foundation

// MARK: - Compact Byte Formatting — menu bar optimized

enum ByteFormatting {
    private static let units = ["B", "K", "M", "G", "T"]

    static func format(_ bytes: Double) -> String {
```

**Bounded compact output pattern** (lines 13-30):
```swift
var value = max(bytes, 0)
var unitIndex = 0
while value >= 1000 && unitIndex < units.count - 1 {
    value /= 1000
    unitIndex += 1
}

let unit = units[unitIndex]
if unitIndex == 0 || value >= 9.95 {
    return "\(min(Int(value.rounded()), 999))\(unit)"
}
```

Do not change byte formatting semantics to solve layout. Phase 12 should reserve fixed UI width for the current bounded outputs such as `999T` and `999T/s`.

**Shared compatibility wrappers** (lines 32-50):
```swift
static func formatNetwork(download: Double, upload: Double) -> String {
    "↓\(format(download)) ↑\(format(upload))"
}

static func formatRate(_ bytesPerSec: Double) -> String {
    "\(format(bytesPerSec))/s"
}

func formatNetworkRateCompact(_ bytesPerSec: Double) -> String {
    ByteFormatting.formatRate(bytesPerSec)
}
```

If tests or fixtures need worst-case network strings, call this formatter rather than inventing a separate string convention.

---

### `MacStatus/MacStatus/UI/Views/StableValueLayout.swift` (component/utility, transform)

**Analog:** `MacStatus/MacStatus/UI/Views/DashboardView.swift`

**Copy imports and SwiftUI-only file shape** (DashboardView lines 1-7):
```swift
import SwiftUI

// MARK: - Dashboard View

struct DashboardView: View {
```

Create this file as a small SwiftUI helper module in `UI/Views`, not a broad design-system rewrite.

**Copy numeric style from existing rows/cards** (DashboardView lines 353-358, 431-433):
```swift
Text(value)
    .font(.system(.body, design: .monospaced))
    .fontWeight(.medium)
    .foregroundStyle(color)
    .multilineTextAlignment(.trailing)

Text(value)
    .font(.system(.caption, design: .monospaced))
    .foregroundStyle(.secondary)
```

The helper should centralize these traits: monospaced digits, right alignment, `lineLimit(1)`, fixed `frame(width:alignment:)`, and higher layout priority for values.

**Recommended helper shape from phase contract:**
```swift
enum StableValueWidth {
    static let percentage: CGFloat = 64
    static let networkCard: CGFloat = 76
    static let processNetworkPair: CGFloat = 148
    static let temperature: CGFloat = 56
    static let fanRPM: CGFloat = 78
    static let batteryPower: CGFloat = 104
    static let batteryHealthTime: CGFloat = 112
    static let processCPU: CGFloat = 52
    static let processMemory: CGFloat = 68
}
```

Keep widths as UI constants. Do not pad strings with spaces.

---

### `MacStatus/MacStatus/UI/Fixtures/DashboardLayoutFixtures.swift` (fixture, transform)

**Analog:** `MacStatus/MacStatus/UI/Views/DashboardView.swift`

**State fields to populate** (lines 557-603):
```swift
@MainActor
final class DashboardState: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var cpuText: String = "--"
    @Published var memoryText: String = "--"
    @Published var networkText: String = "--"
    @Published var battery: BatterySnapshot? = nil
    @Published var thermal: ThermalSnapshot = .unavailable()
    @Published var fan: FanSnapshot = .unavailable()
    @Published var topProcesses: [ProcessNetworkUsage] = []
    @Published var topCPUProcesses: [ProcessResourceUsage] = []
    @Published var topMemoryProcesses: [ProcessResourceUsage] = []
}
```

Fixtures should return same-visibility short/extreme `DashboardState` instances. Cover at least short/large network rates, `9999 RPM`, `100°C`, `N/A`, large power values, long process names, long sensor labels, and mixed availability.

**Network text construction pattern** (lines 640-650):
```swift
let up = ByteFormatting.format(stats.uploadBytesPerSec)
let down = ByteFormatting.format(stats.downloadBytesPerSec)
networkText = "↑\(up)\n↓\(down)"
```

Fixture network text should use the same two-line up/down structure so verification exercises the real card layout.

**No close analog:** No current fixture directory or preview fixture exists. Keep this file DEBUG/test-only if included in the app target.

---

### `MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift` (test, request-response)

**Analog:** none in codebase; use AppKit host pattern from `PopoverManager.swift`.

**Host and measure pattern** (PopoverManager lines 41-50):
```swift
let hostingController = NSHostingController(
    rootView: DashboardView()
        .environmentObject(dashboardState)
)
hostingController.sizingOptions = [.preferredContentSize]
popover.contentViewController = hostingController
```

Use the same `NSHostingController` preferred-size bridge in tests or a lightweight layout probe. Assertions should compare short/extreme fixture root widths to `372pt` with tolerance no larger than `0.5pt`, and compare same-visibility heights/value-column positions if the implementation exposes measurable anchors.

**Current test target state** (`xcodebuild -list`):
```text
Targets:
    MacStatus

Schemes:
    MacStatus
```

There is no existing XCTest target. If planner chooses XCTest, include explicit `project.pbxproj` target/scheme work. If planner chooses a scriptable probe instead, place it outside runtime UI and still capture deterministic verification output.

---

### `MacStatus/MacStatus.xcodeproj/project.pbxproj` (config, build graph)

**Analog:** `MacStatus/MacStatus.xcodeproj/project.pbxproj`

**File reference/build file pattern for Swift sources** (lines 32-35, 70-73):
```text
B10000000000000000000002 /* PopoverManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = B10000000000000000000001 /* PopoverManager.swift */; };
B10000000000000000000004 /* DashboardView.swift in Sources */ = {isa = PBXBuildFile; fileRef = B10000000000000000000003 /* DashboardView.swift */; };
B10000000000000000000008 /* ProcessListView.swift in Sources */ = {isa = PBXBuildFile; fileRef = B10000000000000000000007 /* ProcessListView.swift */; };

B10000000000000000000003 /* DashboardView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DashboardView.swift; sourceTree = "<group>"; };
```

New app-target Swift helper/fixture files need both `PBXFileReference` and `PBXBuildFile` entries.

**Views group membership pattern** (lines 158-168):
```text
B10000000000000000000010 /* Views */ = {
    isa = PBXGroup;
    children = (
        B10000000000000000000003 /* DashboardView.swift */,
        B10000000000000000000005 /* MetricCard.swift */,
        B10000000000000000000007 /* ProcessListView.swift */,
        B10000000000000000000009 /* SparklineView.swift */,
        B1000000000000000000000B /* SettingsView.swift */,
    );
    path = Views;
    sourceTree = "<group>";
};
```

Add `StableValueLayout.swift` next to other `UI/Views` files. If adding `UI/Fixtures`, create a sibling group under `UI` or a child group under `UI`.

**Sources build phase pattern** (lines 280-315):
```text
08FB7793FE84155DC02AAC18 /* Sources */ = {
    isa = PBXSourcesBuildPhase;
    files = (
        B10000000000000000000004 /* DashboardView.swift in Sources */,
        B10000000000000000000008 /* ProcessListView.swift in Sources */,
        B1000000000000000000000A /* SparklineView.swift in Sources */,
        B1000000000000000000000C /* SettingsView.swift in Sources */,
    );
};
```

Every new app-target Swift source must be present here or Debug build verification will miss it.

**Build settings to preserve** (lines 451-456, 473-478):
```text
PRODUCT_BUNDLE_IDENTIFIER = com.aflmf.macstatus;
PRODUCT_NAME = MacStatus;
SWIFT_STRICT_CONCURRENCY = complete;
SWIFT_VERSION = 6.0;
```

Keep Swift 6 and strict concurrency settings. Do not introduce external package references.

---

### `MacStatus/MacStatus/UI/PopoverManager.swift` (provider, request-response)

**Analog:** `MacStatus/MacStatus/UI/PopoverManager.swift`

**AppKit/SwiftUI bridge pattern** (lines 37-50):
```swift
private override init() {
    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = true
    let hostingController = NSHostingController(
        rootView: DashboardView()
            .environmentObject(dashboardState)
    )
    hostingController.sizingOptions = [.preferredContentSize]
    popover.contentViewController = hostingController
    self.popover = popover
    super.init()
}
```

Preserve this host pattern. Phase 12 should keep AppKit sizing driven by SwiftUI preferred content size and avoid setting a competing popover width here.

## Shared Patterns

### Compact Card Surface
**Source:** `DashboardView.swift` lines 180-184, 384-388, 418-422, 546-550; `ProcessListView.swift` lines 61-65
**Apply to:** `DashboardView`, `ProcessListView`, `StableValueLayout` integrations
```swift
.padding(8)
.background(
    RoundedRectangle(cornerRadius: 8)
        .fill(Color.primary.opacity(0.04))
)
```

Use existing adaptive semantic colors and 8pt radius. Do not introduce decorative backgrounds or nested cards.

### Inline Degradation
**Source:** `DashboardView.swift` lines 246-253, 454-490; `ProcessListView.swift` lines 19-40
**Apply to:** thermal/fan/battery/process rows and fixtures
```swift
guard let value else { return "N/A" }
guard let w = snapshot.watts else { return "—" }
Text(errorMessage)
    .font(.caption2)
    .foregroundStyle(.secondary)
```

Use `N/A`, `—`, and inline centered text. No modal errors.

### Monospaced Numeric Values
**Source:** `DashboardView.swift` lines 156-160, 200-204, 216-220, 431-433; `ProcessListView.swift` lines 44-56
**Apply to:** all Phase 12 stable value cells
```swift
Text(value)
    .font(.system(.caption, design: .monospaced))
    .multilineTextAlignment(.trailing)
    .frame(width: stableWidth, alignment: .trailing)
```

Phase 12 change: use fixed `width`, not current `minWidth`, and add `.monospacedDigit()` where the helper centralizes numeric typography.

### Existing Verification Baseline
**Source:** prior phase plans/research and current project list
**Apply to:** all implementation plans
```bash
xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build
xcodebuild -list -project MacStatus/MacStatus.xcodeproj
```

Current `xcodebuild -list` shows only the `MacStatus` target and scheme. Any XCTest plan must include creating a test target; otherwise use a scriptable layout probe plus the Debug build.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift` | test | request-response | No current XCTest target or test files exist; project currently has only the app target. |

## Metadata

**Analog search scope:** `MacStatus/MacStatus/**/*.swift`, `MacStatus/MacStatus.xcodeproj/project.pbxproj`, prior Phase 10/11 planning artifacts
**Files scanned:** 22 Swift/project files plus 3 required Phase 12 artifacts
**Pattern extraction date:** 2026-06-24
