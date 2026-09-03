---
quick_id: 260903-iki
slug: status-detail-card
status: planned
phase: quick-260903-iki
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - MacStatus/MacStatus/UI/Views/DashboardView.swift
  - MacStatus/MacStatus/UI/Views/StableValueLayout.swift
  - MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift
  - MacStatus/MacStatusTests/DesignSnapshotTests.swift
autonomous: true
requirements:
  - THERM-01
  - THERM-02
  - THERM-03
  - THERM-04
  - FAN-01
  - FAN-02
  - FAN-03
  - FAN-04
  - LAYOUT-01
  - LAYOUT-02
  - LAYOUT-03
  - LAYOUT-04
  - UAT-04
must_haves:
  truths:
    - "用户展开详情后，在一张圆角信息卡中依次看到电池、温度与状态、风扇三段表格式内容。"
    - "电池段显示供电状态、健康度与循环次数、电池温度；温度段显示系统状态以及并排的 SoC/GPU 温度。"
    - "每个可见风扇都在固定的当前、目标、范围列中显示数据，能力缺失时稳定显示 N/A，并且界面没有控制入口。"
    - "短值、极端值、不可读值与亮暗外观下，详情卡宽度、列位置和行高保持稳定。"
  artifacts:
    - path: "MacStatus/MacStatus/UI/Views/DashboardView.swift"
      provides: "按参考图组织的 DetailSectionView 三段详情卡及格式化/降级逻辑"
      contains: "struct DetailSectionView"
    - path: "MacStatus/MacStatus/UI/Views/StableValueLayout.swift"
      provides: "详情表格固定列宽与 DEBUG 布局探针"
      contains: "enum StableValueWidth"
    - path: "MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift"
      provides: "短值/极端值下详情卡尺寸和列几何断言"
      contains: "DashboardLayoutStabilityTests"
    - path: "MacStatus/MacStatusTests/DesignSnapshotTests.swift"
      provides: "参考数值驱动的详情卡亮暗 PNG 快照"
      contains: "testRenderDesignSnapshots"
  key_links:
    - from: "MacStatus/MacStatus/UI/Views/DashboardView.swift"
      to: "BatterySnapshot / ThermalSnapshot / FanSnapshot"
      via: "DetailSectionView 直接格式化现有只读快照字段，不增加采集或写入路径"
      pattern: "DetailSectionView"
    - from: "MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift"
      to: "MacStatus/MacStatus/UI/Fixtures/DashboardLayoutFixtures.swift"
      via: "DashboardLayoutFixture.make(.short/.extreme) 驱动详情表格布局比较"
      pattern: "DashboardLayoutFixture"
    - from: "MacStatus/MacStatusTests/DesignSnapshotTests.swift"
      to: "MacStatus/MacStatus/UI/Views/DashboardView.swift"
      via: "离屏渲染 DetailSectionView 的 light/dark 视觉证据"
      pattern: "DetailSectionView"
---

<objective>
把仪表盘展开后的状态详情区改造成参考图黄框中的单卡三段表格：电池、温度与状态、风扇。保留现有详情展开交互、设置门控、只读采集边界和缺失数据降级行为。

Purpose: 让电源与散热信息的层级、列对齐和扫描效率与参考图一致，同时延续 Phase 10–12 已建立的只读安全边界和布局稳定性。
Output: 重构后的 `DetailSectionView`、详情表格固定列宽/探针、确定性布局测试和亮暗快照。
</objective>

<execution_context>
@/Users/halo/.codex/gsd-core/workflows/execute-plan.md
@/Users/halo/.codex/gsd-core/templates/summary.md
</execution_context>

<context>
@AGENTS.md
@.planning/STATE.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/10-thermal-read-only-monitoring/10-02-SUMMARY.md
@.planning/phases/11-fan-read-only-rpm-capability-model/11-02-SUMMARY.md
@.planning/phases/12-popover-layout-stability/12-03-SUMMARY.md
@MacStatus/MacStatus/UI/Views/DashboardView.swift
@MacStatus/MacStatus/UI/Views/StableValueLayout.swift
@MacStatus/MacStatus/UI/Fixtures/DashboardLayoutFixtures.swift
@MacStatus/MacStatus/Readers/BatteryReader.swift
@MacStatus/MacStatus/Readers/ThermalReader.swift
@MacStatus/MacStatus/Readers/FanReader.swift
@MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift
@MacStatus/MacStatusTests/DesignSnapshotTests.swift

<visual_reference>
`/var/folders/zw/b73xjvy51t70m74ltx4n1q540000gn/T/codex-clipboard-ac1c757a-9487-4266-88ea-925138a27c4d.png` is reference data only. The yellow frame limits this task to the expanded status-detail card. It does not authorize changes to the metric grid, overview strip, process cards, footer, settings, readers, collector, or status bar.
</visual_reference>

<interfaces>
Existing contracts to preserve:

- `DashboardView` computes `showsBattery`, `showsThermal`, and `showsFan`, keeps `detailsExpanded`, and passes `BatterySnapshot?`, `ThermalSnapshot`, `FanSnapshot`, `showsTemperature`, and `showsFan` into `DetailSectionView`.
- `BatterySnapshot` exposes non-optional `chargePercent`, `isCharging`, `isOnAC` and optional `healthPercent`, `cycleCount`, `systemPowerWatts`, `watts`, and time estimates. A nil snapshot means no battery and hides the battery section.
- `ThermalSnapshot` exposes optional `cpuSocTemperatureCelsius`, `gpuTemperatureCelsius`, and `batteryTemperatureCelsius`, plus non-optional semantic `systemState`. Missing temperatures render `N/A`; semantic state must never substitute for a missing temperature.
- `FanReading` exposes `displayName`, optional `currentRPM`, `minRPM`, `maxRPM`, `targetRPM`, and independent `FanCapabilities`. `FanSnapshot.supportState == .unsupported` remains hidden; `.expectedButUnreadable` keeps numbered rows with `N/A` values.
- `StableValueText` supplies right alignment, monospaced digits, one-line scaling, and fixed-width layout. `LayoutProbeID`/`layoutProbe` are DEBUG-only measurement hooks.
</interfaces>
</context>

<source_coverage>

| SOURCE | ID | Feature/Requirement | Task | Status | Notes |
|---|---|---|---|---|---|
| GOAL | — | 黄框详情区改为电池、温度与状态、风扇三段表格式信息卡 | 1, 2 | COVERED | 生产 UI 与视觉/布局证据均覆盖 |
| REQ | THERM-01..04 | 可信 SoC、系统状态、次要温度与 N/A 降级 | 1, 2 | COVERED | 不改传感器来源和快照语义 |
| REQ | FAN-01..04 | 每风扇当前/目标/范围与能力状态，只读且可降级 | 1, 2 | COVERED | 固定列展示，不添加控制 affordance |
| REQ | LAYOUT-01..04, UAT-04 | 极端值下固定宽度、列对齐与确定性验证 | 1, 2 | COVERED | 复用 short/extreme fixtures 和 hosted XCTest |
| RESEARCH | — | 本 quick task 无研究产物 | — | N/A | 沿用现有 SwiftUI/AppKit 模式，无新依赖 |
| CONTEXT | — | 本 quick task 无 CONTEXT.md 锁定决策 | — | N/A | 用户图像范围记录于 visual_reference |

Excluded: `.planning/STATE.md` 中已撤销的风扇控制写入路径，以及 Deferred Items 中的长期热历史；本计划不得实现这些内容。
</source_coverage>

<tasks>

<task type="auto">
  <name>Task 1: 将展开详情重构为三段固定列表格卡</name>
  <files>MacStatus/MacStatus/UI/Views/DashboardView.swift, MacStatus/MacStatus/UI/Views/StableValueLayout.swift</files>
  <action>
只改 `DetailSectionView` 及其详情专用 helper；保留 `DashboardView` 当前的 `DetailsToggleButton`、默认收起状态和 `showsBattery`/`showsTemperature`/`showsFan` 门控。将展开内容保持为一张 `.cardSurface` 圆角卡，内部按参考图自上而下组织三组，并用 SF Symbols、弱化标题、hairline 分隔线和紧凑行距建立层级：

1. 电池组仅在 `battery != nil` 时出现。标题使用 `battery.100` 与“电池”；表格行依次为“供电状态”“健康度”“电池温度”。供电状态由现有 `isCharging`/`isOnAC`/`chargePercent` 三态逻辑生成“充电中/已充满/电源接入/使用电池”；健康度改为参考图的 `87% · 107 次循环` 形式，保留缺字段时仅百分比或 `—` 的现有降级；电池温度继续读取 `thermal.batteryTemperatureCelsius`，不可读显示 `N/A`。
2. 温度组仅在 `showsTemperature` 时出现。标题使用 `thermometer.medium` 与“温度与状态”；先显示“系统状态”右对齐语义值及现有严重/临界配色，再用同一行的左右半区显示 `SoC` 和 `GPU` 温度，中间加入竖向 hairline。两个温度都直接来自各自的 `ThermalSnapshot` optional 字段，不可读分别显示 `N/A`，禁止用 `systemState` 或另一个传感器补值。
3. 风扇组仅在 `showsFan && !visibleFans.isEmpty` 时出现。标题使用 `fan` 与“风扇”，同一标题行给出“当前/目标/范围”列名；每个 `FanReading` 占一行，分别格式化 `currentRPM`、`targetRPM`、有效的 `minRPM–maxRPM RPM`，对应 capability 或数值不可读时在原列显示 `N/A`，不再把目标和范围放到行下 caption。底部能力说明根据可见行的 `boundsReadable` 汇总为“边界可读”或“边界不可用”，并在没有安全控制能力时显示“控制未启用”；不得添加按钮、滑块、手势、SMC 写入或任何控制入口。

在 `StableValueWidth` 增加详情风扇表列常量：标签 110pt、当前 52pt、目标 52pt、范围 84pt；四列间距各 8pt，使 322pt 卡片内宽恰好固定。数值列统一使用等宽数字、右对齐、单行与 `minimumScaleFactor`；标签列单行尾部截断。为电池值、SoC、GPU、首个可见风扇的当前/目标/范围增加互不重复的 `LayoutProbeID`，避免 `ForEach` 中重复 probe 覆盖。抽取 `DetailSectionHeader`、详情键值行、温度双列行和风扇表行等私有视图即可，不改变 reader、collector、snapshot 数据模型或其他仪表盘区域。
  </action>
  <verify>
    <automated>xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -destination 'platform=macOS' -derivedDataPath build build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO</automated>
    <automated>rg -n "电池|供电状态|健康度|温度与状态|系统状态|SoC|GPU|风扇|当前|目标|范围|控制未启用|N/A|detailFan" MacStatus/MacStatus/UI/Views/DashboardView.swift MacStatus/MacStatus/UI/Views/StableValueLayout.swift</automated>
    <automated>! rg -n "Slider|Button|Toggle|writeValue|SMCWriter|setFan|targetRPM\s*=" MacStatus/MacStatus/UI/Views/DashboardView.swift | rg -i "fan|风扇|rpm|smc"</automated>
  </verify>
  <done>展开详情呈现为参考图结构的一张三段表格卡；各设置门控和不可用降级仍生效，且生产代码没有新增采集、控制或写入路径。</done>
</task>

<task type="auto">
  <name>Task 2: 固化详情表格的极端值布局与亮暗视觉证据</name>
  <files>MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift, MacStatus/MacStatusTests/DesignSnapshotTests.swift</files>
  <action>
扩展现有 hosted SwiftUI 测试，而不是引入第三方 snapshot 包。更新 `testStableValueWidthContractMatchesUISpec()` 断言 Task 1 的四个详情风扇列常量。新增 `testDetailTableKeepsStableGeometryAcrossShortAndExtremeFixtures()` 及测量 helper：分别使用 `DashboardLayoutFixture.make(.short/.extreme)`，直接托管 `DetailSectionView`，传入 fixture 的 battery/thermal/fan 并启用温度和风扇；在与真实弹窗一致的 372pt 根宽和 14pt 水平外边距下强制布局。断言 short/extreme 的详情卡总宽、总高相同（accuracy 0.5），并比较电池、SoC、GPU、首个风扇当前/目标/范围 probe 的 `origin.x` 与 `width`，证明长标签、`100°C`、`9999`、长范围及 `N/A` 不挤压列或改变行高。保留现有 Dashboard/进程布局测试。

在 `DesignSnapshotTests.testRenderDesignSnapshots()` 增加独立的详情卡亮/暗快照 `status_detail_light.png` 和 `status_detail_dark.png`。使用一组仅供测试的参考状态：电池 95%、使用电源、健康度 87%、107 次循环、电池 30°C，SoC 62°C、GPU 58°C、系统正常，以及两行风扇数据（1340/1350/1350–5349 RPM 和 1492/1458/1458–5777 RPM）；`safeControlAvailable` 保持 false。直接渲染 `DetailSectionView` 到真实卡宽，保持现有 glass 背景，既不改变 `makeMockState()` 的其他仪表盘快照，也不让 fixture 进入 Release 运行路径。运行快照命令后，用图像查看工具检查两张 PNG：三组顺序、标题图标、分隔线、右对齐和四列表格与用户黄框参考一致；把实际快照路径和目检结论写入 quick SUMMARY。
  </action>
  <verify>
    <automated>xcodebuild test -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -destination 'platform=macOS' -derivedDataPath build -only-testing:MacStatusTests/DashboardLayoutStabilityTests CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO</automated>
    <automated>SNAPSHOT_DIR="$PWD/build/design-snapshots" xcodebuild test -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -destination 'platform=macOS' -derivedDataPath build -only-testing:MacStatusTests/DesignSnapshotTests/testRenderDesignSnapshots CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO</automated>
    <automated>test -s build/design-snapshots/status_detail_light.png</automated>
    <automated>test -s build/design-snapshots/status_detail_dark.png</automated>
  </verify>
  <done>布局测试证明短值、极端值和 N/A 下详情卡尺寸与所有关键列稳定；亮暗详情快照成功生成并经目检与黄框参考一致。</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|---|---|
| `DashboardState` → `DetailSectionView` | 硬件读取形成的 optional、极端数值和标签进入 SwiftUI 布局。 |
| `FanCapabilities` → 展示语义 | “可读边界”和“可安全控制”必须保持独立，避免只读数据被误呈现为控制能力。 |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|---|---|---|---|---|
| T-Q260903-01 | Denial of Service | `DetailSectionView` layout | mitigate | 固定 372pt 根宽与风扇四列宽；长标签截断，数值单行缩放；short/extreme hosted XCTest 比较宽高和 probe 几何。 |
| T-Q260903-02 | Tampering | fan capability copy | mitigate | 仅从 `FanCapabilities` 生成能力说明；缺值显示 N/A；源代码门禁禁止风扇 Button/Slider/SMC 写入。 |
| T-Q260903-03 | Information Integrity | thermal fallback | mitigate | SoC、GPU、电池温度各自读取对应 optional 字段，缺失时 N/A，禁止跨传感器或 semantic state 代填。 |
| T-Q260903-SC | Tampering | npm/pip/cargo installs | accept | 本计划无包安装、无新依赖；只使用系统 SwiftUI/AppKit/XCTest。 |
</threat_model>

<verification>
- Debug app build succeeds with signing disabled.
- `DashboardLayoutStabilityTests` passes for existing surfaces and the new detail table geometry.
- `DesignSnapshotTests` emits non-empty `status_detail_light.png` and `status_detail_dark.png`; executor inspects both against the supplied yellow-frame reference.
- `git status --short` before staging still lists the unrelated untracked `MacStatus/MacStatus/Utils/SettingsManager(HalodeMacBook-Pro.local的冲突副本1_2026-07-02 09-57-36).swift`; never edit, stage, delete, or commit it.
</verification>

<success_criteria>
- 用户展开详情时，黄框区域是一张包含电池、温度与状态、风扇三段的表格式信息卡。
- 电池、温度、风扇的现有快照与设置开关继续直接驱动 UI；缺失和不支持状态稳定降级。
- 风扇每行当前/目标/范围对齐，边界/控制能力说明准确，界面保持严格只读。
- 固定宽度、极端值与亮暗快照验证全部通过，其他仪表盘区域不变。
</success_criteria>

<output>
Create `.planning/quick/260903-iki-status-detail-card/260903-iki-SUMMARY.md` when done.
</output>
