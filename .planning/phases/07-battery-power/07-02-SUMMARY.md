---
phase: "07-battery-power"
plan: "02"
status: complete
completed: "2026-06-17"
executor: inline (orchestrator fallback — subagent API 529 overloaded; partial executor work preserved + completed inline)
requirements:
  - BATT-01
  - BATT-02
  - BATT-03
  - BATT-04
  - BATT-05
key_files:
  created: []
  modified:
    - MacStatus/MacStatus/Collectors/MetricCollector.swift
    - MacStatus/MacStatus/UI/Views/DashboardView.swift
    - MacStatus/MacStatus.xcodeproj/project.pbxproj
commits:
  - "47246fe feat(07-02): integrate BatteryReader into MetricCollector tick + register in target"
  - "09969ea feat(07-02): add popover battery section (DashboardState fields + BatterySectionView)"
---

# Plan 07-02 Summary — MetricCollector 接入 + Popover 电池区块

## What was built

**Task 1 — MetricCollector 接入** (`MetricCollector.swift`)
- 新增 `private let batteryReader = BatteryReader()` 与 `private var lastBatterySnapshot: BatterySnapshot?` 缓存（独立于 MetricSample——不持久化、不进 RingBuffer/HistoryStore/sparkline）。
- `start()` 调 `batteryReader.setup()`（注册 wake observer）+ 首读。
- `tick()` 读取 `batteryReader.readValue()` 并缓存到 `lastBatterySnapshot`。
- `updateUI(sample:)` 调 `dashboard.updateBattery(lastBatterySnapshot)`——tick 与 applyNow 两条路径都会刷新电池区（设置变更重绘时电池保持实时）。
- `reconfigure()` 未触碰 batteryReader（保护读取基线，符合约定）。

**Task 2 — Popover 电池区块** (`DashboardView.swift`)
- `DashboardState`：新增 `@Published battery: BatterySnapshot?` + `@Published hasBattery: Bool` + `updateBattery(_:)`（nil → hasBattery=false → 整段隐藏）。
- `DashboardView.body`：在 2x2 网格与进程列表之间插入条件区块 `if state.hasBattery, let battery = state.battery { BatterySectionView(...) }`。
- `BatterySectionView`：整宽卡片（沿用 RoundedRectangle cornerRadius 8 / Color.primary.opacity(0.04) 风格），4 行：
  - 标题"电池" + `85% · 充电中/已充满/使用电池`（三态：isCharging→充电中；!isCharging&&isOnAC→已充满；否则使用电池——不依赖 kIOPSIsChargedKey）。
  - 距充满/剩余时间：`formatTime`（nil/-1→计算中，0→—，>0→"X小时Y分"/"Y分钟"）。
  - 功率：带符号 `+18.5W`/`−12.3W`，nil→"—"。
  - 健康度：`92%（320 次循环）`，健康度 nil→"—"，循环 nil 仅显示百分比。

## Scope honored
- **仅 popover**：未触碰 StatusBarManager / `.battery` / enabledMetrics（状态栏电池留待 Phase 9）。
- 电池数据**未**进入 MetricSample/RingBuffer/HistoryStore。

## Verification
- `xcodebuild ... build` → **BUILD SUCCEEDED**（exit 0）。
- 警告 2 条（非阻塞）：① BatteryReader.swift:81 wake observer `@Sendable` 捕获 self——与 NetworkReader 的既有同款模式一致（v1.0 已出货），按"匹配周边代码"保留；② MetricCollector:130 `changedKeysUserInfoKey`——Phase 6 (06-02) 遗留，非本阶段范围。

## Notes / gotchas
- **关键修正**：BatteryReader.swift（Plan 07-01 内联创建）此前**未登记进 Xcode target 的编译源**，导致 07-01 的 "BUILD SUCCEEDED" 实为假阳性（文件未被编译）。本 plan 在 `project.pbxproj` 补加了 4 处条目（PBXBuildFile / PBXFileReference / Readers group children / Sources phase），仿 GPUReader。内联执行需手动维护 pbxproj——这是 gsd-executor 子代理通常自动处理而内联回退易遗漏的点。
- **执行方式**：07-02 的 gsd-executor 子代理第三次遭遇 API 529（做了 ~14 次工具调用、写了 MetricCollector 部分集成后失败）；保留其干净的部分改动并内联补全 updateUI 推送 + DashboardState + DashboardView + pbxproj。
