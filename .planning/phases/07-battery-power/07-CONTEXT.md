# Phase 7: Battery & Power - Context

**Gathered:** 2026-06-17
**Status:** Ready for planning

<domain>
## Phase Boundary

在 popover 内新增一个完整的电池信息区：电量%、充电状态、剩余时间、实时充放电功率(W)、电池健康度（含循环次数）。笔记本展示全貌；台式机（无电池）整段优雅隐藏。新增 `BatteryReader`（仅产出 `Sendable` 快照），复用 v1.0 的 reader/MetricCollector/sleep-wake 架构。

本阶段**仅 popover**：不进状态栏、不持久化、不进 sparkline。覆盖需求 BATT-01..05。
</domain>

<decisions>
## Implementation Decisions

### 数据源与读取策略 (Data Source & Reading Strategy)
- 电量%/充电状态/剩余时间：用 **IOKit Power Sources**（`IOPSCopyPowerSourcesInfo` + `IOPSGetPowerSourceDescription`）—— 直接给出百分比、充电态、时间估计及 `-1`(计算中)/`-2`(不可用) 哨兵。
- 功率(W)/健康度/循环次数：读 **`AppleSmartBattery` IORegistry 键**（Amperage × Voltage → 带符号瓦数；MaxCapacity/DesignCapacity 或 NominalChargeCapacity → 健康%；CycleCount）。**逐键 probe-and-nil**，任一键缺失/类型不符即该字段为 nil，绝不强解包、绝不造假值。
- 读取节奏：**复用 MetricCollector 现有主 tick**（与其他指标同一计时器；电池读取廉价，瓦数需"实时"故跟随 tick）。电池数据**不**写入 `MetricSample`/`RingBuffer`/`HistoryStore`（v2.0 不持久化电池、不做电池 sparkline），每 tick 读取后直接推给 `DashboardState`。
- 台式机检测：Power Sources 无内置电池 或 `AppleSmartBattery` 服务缺失 → `BatteryReader.readValue()` 返回 `nil` → popover 整段隐藏（沿用 v1.0 GPU nil 降级范式）。

### 展示与格式 (Display & Formatting — popover 电池区)
- 位置：**2x2 指标网格下方、进程列表上方的独立整宽 section**（多子字段，不挤进网格卡片）；仅当有电池时渲染该 section。
- 充电态文案（中文）：**充电中 / 已充满 / 使用电池**。
- 剩余时间：充电中显示"距充满"，使用电池显示"剩余"，格式 "X小时Y分"（不足 1 小时显示 "Y分钟"）；`-1`/`-2` 哨兵 → **"计算中"**（不显示错误数字）。
- 功率(W)：**带符号**，充电 `+18.5W`、放电 `−12.3W`，1 位小数；不可读 → **"—"**。
- 健康度：**"健康度 92%（XXX 次循环）"**（max-capacity% + 循环数）；任一不可读 → "—"。

### 健壮性、Sendable、sleep/wake 与作用域 (Robustness & Scope)
- 降级粒度：**整段隐藏仅在无电池（台式机）时**；笔记本上个别不可读字段（W/健康/循环）**各自**降级为 "—"，而电量%/充电状态/时间照常显示（满足成功标准 #3 与 #4）。
- 跨 actor 快照：定义 **`BatterySnapshot: Sendable` struct**，probe-and-nil 字段全为 Optional；`BatteryReader.readValue() -> BatterySnapshot?`（返回 nil = 无电池）。镜像 `GPUStats` 的 Sendable 范式。
- sleep/wake：**`BatteryReader` 观察 `NSWorkspace.didWakeNotification`**（沿用 `NetworkReader.swift` 已有的唤醒观察范式）；唤醒后剩余时间估计先显示"计算中"，直到取得一次稳定读数（延迟信任 —— macOS 唤醒瞬间常报 `-1`），保证 sleep/wake 后读数正确恢复。
- 作用域：**Phase 7 仅 popover**。不把 `.battery` 加入状态栏 `enabledMetrics`/`metricOrder`；`StatusBarManager.updateTitle` 的 `case .battery: break` 保持不变。状态栏电池显示留待 Phase 9 定制决定。

### 研究阶段澄清 (resolved post-research, HIGH 置信度 — 对照真机 SDK 验证)
- **健康度公式**：用 `AppleRawMaxCapacity / DesignCapacity × 100`（**不要**用 `MaxCapacity`——Apple Silicon 上它=100 是百分比而非 mAh 容量，会算出错误的 100%）。Intel/AS 通用。
- **Watts 符号权威源**：用 `kIOPSIsChargingKey` + `kIOPSPowerSourceStateKey` 判定充/放方向，取 `abs(watts)` 作幅值（**不要**单信 `Amperage` 符号——跨机型不一致）。watts = `Amperage`(mA, `as? Int`) × `Voltage`(mV, `as? Int`) / 1_000_000。
- **充电三态规则**（`kIOPSIsChargedKey` 在优化充电下不可靠，97% 仍报 false）：`isCharging → 充电中`；`!isCharging && state == "AC Power" → 已充满`；`state == "Battery Power" → 使用电池`。
- **CF 内存管理**：`IOPSGetPowerSourceDescription` 用 `takeUnretainedValue()`（info blob 拥有该字典，过释放会崩溃）；`IOPSCopyPowerSourcesInfo`/`IOPSCopyPowerSourcesList` 用 `takeRetainedValue()`；`IORegistryEntryCreateCFProperties` 后 `IOObjectRelease`。
- **时间哨兵**：仅 `-1` = 计算中；`0` = 当前状态不适用（非错误，按"计算中"或不显示处理，勿当错误）。单位为分钟。
- **Watts ≈ 0 边缘**（AC 待机不充电时 Amperage=0）：`|watts| < 0.1` 时显示 **"—"**，避免误导性的 `+0.0W`/`−0.0W`（与"不可读→—"一致；Claude 已据研究员建议定稿，未单独打断用户）。

### Claude's Discretion
- `BatteryReader` 是否继承 `TimerReader<BatterySnapshot>`（如 GPUReader）还是仅实现一个同步 `readValue()`：由 Claude 依 MetricCollector 接入方式裁定；MetricCollector 当前只调用各 reader 的 `readValue()`，故至少需提供同步 `readValue() -> BatterySnapshot?`。
- 瓦数计算的具体键名与单位换算（Amperage 可能为有符号 mA、Voltage 为 mV）、健康度分母用 DesignCapacity 还是 NominalChargeCapacity：交由研究阶段在真机/文档核实后定稿（见下方 deferred 的硬件矩阵关切）。
- 电池 section 的具体 SwiftUI 布局细节（图标、行排列）由 Claude 依现有 DashboardView 风格裁定。
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MacStatus/Readers/GPUReader.swift` — **nil 降级范式样板**：`readValue() -> GPUStats?`，服务/键不可读时返回 nil；`GPUStats: Sendable` struct。BatteryReader 直接照此结构。
- `MacStatus/Readers/NetworkReader.swift` — **sleep/wake 范式样板**：第 61 行 `addObserver(forName: NSWorkspace.didWakeNotification, ...)`。BatteryReader 复用此唤醒观察 + 延迟信任。
- `MacStatus/Readers/ReaderProtocol.swift` / `TimerReader` — reader 生命周期协议（setup/read/start/stop + onUpdate）。
- `MacStatus/Collectors/MetricCollector.swift` — `@MainActor` 单一 tick；第 29-32 行声明各 reader，第 62-65/144 行用 `reader.readValue()` 同步取值；`updateUI(sample:)` 把数据推给 DashboardState 与 StatusBar。BatteryReader 在此新增并在 tick 中读取、推给 dashboard。
- `MacStatus/UI/Views/DashboardView.swift` — popover 内容：2x2 `MetricCardWithSparkline` 网格 + `ProcessListView` + footer；`DashboardState: @MainActor ObservableObject`（@Published 字段）。电池区作为新 section 插入网格与进程列表之间，新增 `@Published` 电池字段。
- `MacStatus/UI/PopoverManager.swift` — `dashboardState = DashboardState()`（第 21 行），popover toggle/open 逻辑。

### Established Patterns
- 三层：Reader（readValue 同步、Sendable 输出、probe-and-nil）→ MetricCollector（@MainActor tick）→ DashboardState（@Published）→ SwiftUI。
- nil 降级：reader 返回 nil → UI 隐藏/显示占位，绝不造假值（v1.0 GPU/Intel 降级）。
- 唤醒恢复：NSWorkspace.didWakeNotification 观察 + 延迟信任。

### Integration Points
- 新建 `MacStatus/Readers/BatteryReader.swift`（+ `BatterySnapshot` Sendable struct）。
- `MetricCollector`：新增 `batteryReader`，tick 中 `readValue()` 并 `dashboard.updateBattery(snapshot)`；start() 中 setup/首读；reconfigure() 不触碰。
- `DashboardState`：新增电池 `@Published` 字段 + `updateBattery(_:)`（nil → 隐藏标志）。
- `DashboardView`：新增电池 section（条件渲染：仅有电池时）。
</code_context>

<specifics>
## Specific Ideas

- probe-and-nil 是硬约束：异构 Mac 机型的 `AppleSmartBattery` 键名/符号/位宽各异且台式机缺失（见 STATE Phase 7 关切），任何字段不可读必须降级为 "—"/隐藏，绝不强解包。
- 沿用已验证的 v1.0 GPU nil 降级 + NetworkReader 唤醒观察两套范式，降低风险。
- 用户三个灰区全部接受推荐方案。
</specifics>

<deferred>
## Deferred Ideas

- 状态栏电池显示（把 .battery 加入 enabledMetrics/order、状态栏功率/电量段）→ Phase 9 定制决定。
- 电池历史趋势/sparkline、落盘持久化 → v2.0 明确 Out of Scope。
- 真机硬件矩阵核实（AppleSmartBattery Amperage 符号、Voltage 单位、健康度分母 DesignCapacity vs NominalChargeCapacity、各机型键名差异）→ 研究阶段（gsd-phase-researcher）在官方文档/真机上定稿；STATE 已记录 MEDIUM 置信度关切。
- 低电量告警/通知 → v2.0 未纳入（需通知基础设施）。
</deferred>
