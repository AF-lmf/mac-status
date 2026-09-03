---
phase: quick-260903-iki
plan: 01
subsystem: ui
tags: [swiftui, appkit, xctest, popover, layout, snapshots]

requires:
  - phase: 10-thermal-read-only-monitoring
    provides: 独立的 SoC、GPU、电池温度和系统热状态快照语义
  - phase: 11-fan-read-only-rpm-capability-model
    provides: 只读风扇 RPM、目标、边界及独立能力模型
  - phase: 12-popover-layout-stability
    provides: 固定弹窗宽度、StableValueText 和 DEBUG 布局探针
provides:
  - 单卡内电池、温度与状态、风扇三段表格详情区
  - 322pt 内宽的风扇四列固定布局及关键值探针
  - 短值/极端值详情几何测试与亮暗视觉快照
affects: [dashboard-detail, popover-layout, thermal-ui, fan-ui]

tech-stack:
  added: []
  patterns:
    - 只读硬件快照在固定列详情表中原位降级为 N/A
    - SwiftUI anchor probe 验证短值和极端值的列几何稳定性

key-files:
  created: []
  modified:
    - MacStatus/MacStatus/UI/Views/DashboardView.swift
    - MacStatus/MacStatus/UI/Views/StableValueLayout.swift
    - MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift
    - MacStatus/MacStatusTests/DesignSnapshotTests.swift

key-decisions:
  - "260903-iki: 详情区保持一张 cardSurface，按电池、温度与状态、风扇三段组织；现有设置门控和默认收起交互不变。"
  - "260903-iki: 风扇当前、目标、范围分别占用 52pt、52pt、84pt 固定列，标签列 110pt；缺值按能力在原列显示 N/A。"
  - "260903-iki: 详情 UI 只消费现有快照和能力字段，不增加采集、SMC 写入或控制入口。"
  - "260903-iki: VoiceOver 按分组标题、键值对、独立温度项和完整风扇行读取；装饰图标与分隔线不进入可访问性树。"

patterns-established:
  - "DetailSectionHeader/DetailKeyValueRow/DetailFanTableRow: 用紧凑标题、hairline 和固定列构造详情表格。"
  - "Detail layout probes: 首个风扇行使用互不重复的当前、目标、范围探针，避免 ForEach 覆盖。"

requirements-completed: [THERM-01, THERM-02, THERM-03, THERM-04, FAN-01, FAN-02, FAN-03, FAN-04, LAYOUT-01, LAYOUT-02, LAYOUT-03, LAYOUT-04, UAT-04]

duration: 17min
completed: 2026-09-03
---

# Quick 260903-iki: Status Detail Card Summary

**展开详情已改为单张三段式只读表格卡，并以固定风扇列、极端值几何断言和亮暗 PNG 快照锁定参考图中的信息层级。**

## Performance

- **Duration:** 17 min
- **Started:** 2026-09-03T05:31:19Z
- **Completed:** 2026-09-03T05:48:05Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- 将展开详情改成电池、温度与状态、风扇三段，并加入 SF Symbols 标题、hairline 分隔线及紧凑表格行。
- 电池供电状态、健康度/循环次数和独立电池温度按现有快照展示；SoC、GPU 和电池温度缺失时分别显示 `N/A`，没有跨传感器补值。
- 每个可见风扇固定显示当前、目标、范围三列；不可读能力原位显示 `N/A`，底部汇总边界能力和“控制未启用”。
- 新增详情布局测试，确认 short/extreme 均为 `372×310pt`，6 个关键值探针的 x 位置和宽度一致。
- 生成并目检亮暗详情快照，三段顺序、标题图标、分隔线、右对齐和风扇四列表格与用户黄框参考一致。
- 完成 P2 可访问性复核修复：标题图标/分隔线标记为装饰，键值与双温度项关联 label/value，每个风扇行组合朗读当前、目标和范围。

## Task Commits

1. **Task 1: 将展开详情重构为三段固定列表格卡** - `243cec6` (feat)
2. **Task 2: 固化详情表格的极端值布局与亮暗视觉证据** - `a50018f` (test)
3. **Review fix: 完善详情卡 VoiceOver 语义** - `f810a53` (fix)

## Files Created/Modified

- `MacStatus/MacStatus/UI/Views/DashboardView.swift` - 单卡三段详情 UI、供电/温度/风扇格式化及能力降级逻辑。
- `MacStatus/MacStatus/UI/Views/StableValueLayout.swift` - 风扇四列宽度常量和详情关键值布局探针。
- `MacStatus/MacStatusTests/DashboardLayoutStabilityTests.swift` - short/extreme 详情尺寸和列几何断言。
- `MacStatus/MacStatusTests/DesignSnapshotTests.swift` - 参考数值驱动的亮暗详情快照及稳定输出目录。

## Decisions Made

- 供电状态沿用快照语义映射为“充电中 / 已充满 / 电源接入 / 使用电池”，不引入额外电源探测。
- 风扇范围使用 `min–max RPM` 单行格式，并对非有限值、负值、能力缺失和反向范围统一降级为 `N/A`。
- 只有所有可见行都有有效边界时显示“边界可读”；不存在安全控制能力时附加“控制未启用”，界面不呈现控制 affordance。
- VoiceOver 忽略 SF Symbols 和 hairline；每个数据行作为单个语义单元，避免列头与裸数字分离。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] 为 XCTest 快照提供仓库内确定性默认目录**
- **Found during:** Task 2（亮暗视觉快照）
- **Issue:** macOS hosted XCTest 进程没有继承外层 `SNAPSHOT_DIR` shell 环境变量，首次运行把文件写入系统临时目录，导致计划要求的 `build/design-snapshots/*.png` 验证路径不存在。
- **Fix:** 当测试进程看不到 `SNAPSHOT_DIR` 时，通过 `#filePath` 解析仓库根目录并默认输出到 `build/design-snapshots`；显式环境变量仍保持最高优先级。
- **Files modified:** `MacStatus/MacStatusTests/DesignSnapshotTests.swift`
- **Verification:** 重跑计划快照命令后日志输出 `DesignSnapshotDir /Users/halo/work/my-project/mac-status/build/design-snapshots`，两张目标 PNG 均非空。
- **Committed in:** `a50018f`

---

**Total deviations:** 1 auto-fixed blocking issue。
**Impact on plan:** 仅修复测试产物路径，不改变产品运行行为或视觉范围。

## Verification

- Debug app build：`BUILD SUCCEEDED`。
- `DashboardLayoutStabilityTests`：7 tests，0 failures，`TEST SUCCEEDED`。
- 详情几何：short/extreme 均为 `372×310pt`；电池值、SoC、GPU、首个风扇当前/目标/范围的 x 和 width 均一致。
- `DesignSnapshotTests.testRenderDesignSnapshots`：1 test，0 failures，`TEST SUCCEEDED`。
- 快照文件：
  - `/Users/halo/work/my-project/mac-status/build/design-snapshots/status_detail_light.png`（744×675 px，非空）
  - `/Users/halo/work/my-project/mac-status/build/design-snapshots/status_detail_dark.png`（744×675 px，非空）
- 视觉检查：亮暗模式三段顺序、标题图标、分隔线、双温度列、风扇当前/目标/范围列和底部能力说明均清晰稳定，与黄框结构一致。
- 只读门禁：详情生产代码没有新增风扇 `Button`、`Slider`、`Toggle`、SMC writer、写值或目标赋值路径。
- P2 可访问性复核后再次执行 Debug build：`BUILD SUCCEEDED`。
- P2 可访问性复核后再次执行 `DashboardLayoutStabilityTests`：7 tests，0 failures；详情 short/extreme 仍为 `372×310pt`，全部关键列位置和宽度不变。
- 可访问性语义采用 SwiftUI 原生 `accessibilityElement`、`accessibilityLabel`、`accessibilityValue` 和 `accessibilityHidden`；未增加只镜像文案的低价值测试。

## Issues Encountered

- Xcode 启动时提示本机 CoreSimulator framework 比 Xcode build 版本旧；本任务只运行 macOS destination，构建和全部测试仍成功。
- hosted XCTest 记录了 `com.apple.linkd.autoShortcut` 连接警告；不影响测试执行或快照生成。

## Known Stubs

None. 扫描命中的空数组和 `nil` 均为既有运行态/测试数据默认值，没有新增占位 UI 或未接线数据源。

## Threat Flags

None. 本任务只修改本地只读 SwiftUI 展示与测试，没有新增网络端点、认证路径、文件访问边界、数据模型或硬件写入面。

## Authentication Gates

None.

## User Setup Required

None.

## Self-Check: PASSED

- 四个计划源文件均存在且已提交。
- Task commits `243cec6`、`a50018f` 和 review fix `f810a53` 均存在于 git 历史。
- 两张状态详情亮暗 PNG 均存在且非空，并已实际目检。
- 最终 `git status --short` 仅保留计划明确禁止触碰的未跟踪 SettingsManager 冲突副本；未编辑、暂存、删除或提交该文件。

---
*Quick: 260903-iki-status-detail-card*
*Completed: 2026-09-03*
