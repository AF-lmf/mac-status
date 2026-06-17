---
phase: "07-battery-power"
plan: "01"
status: complete
completed: "2026-06-17"
executor: inline (orchestrator fallback — subagent API 529 overloaded)
requirements:
  - BATT-01
  - BATT-02
  - BATT-03
  - BATT-04
  - BATT-05
key_files:
  created:
    - MacStatus/MacStatus/Readers/BatteryReader.swift
  modified: []
commits:
  - "05c8f51 feat(07-01): add BatteryReader + BatterySnapshot (IOKit Power Sources + AppleSmartBattery, probe-and-nil)"
---

# Plan 07-01 Summary — BatterySnapshot + BatteryReader

## What was built

新建 `MacStatus/MacStatus/Readers/BatteryReader.swift`，包含两个符号：

1. **`BatterySnapshot: Sendable, Equatable`** — 8 个值类型字段（`chargePercent: Int`、`isCharging: Bool`、`isOnAC: Bool`、`timeToEmptyMinutes: Int?`、`timeToFullMinutes: Int?`、`watts: Double?`、`healthPercent: Double?`、`cycleCount: Int?`）。无 CF 类型跨 actor 边界，Swift 6 严格并发零警告。

2. **`BatteryReader` final class**（非 TimerReader 子类，由 MetricCollector 同步 `readValue()` 驱动）：
   - **Layer 1（Power Sources）**：`IOPSCopyPowerSourcesInfo`/`IOPSCopyPowerSourcesList`（`takeRetainedValue()`），遍历找 `kIOPSTypeKey == kIOPSInternalBatteryType && kIOPSIsPresentKey == true` 的源；`IOPSGetPowerSourceDescription` 用 **`takeUnretainedValue()`**（防过释放崩溃）。取电量%/充电态/AC 态/剩余时间。
   - **Layer 2（AppleSmartBattery IORegistry）**：`IOServiceGetMatchingService("AppleSmartBattery")` + `defer { IOObjectRelease(service) }`；`IORegistryEntryCreateCFProperties`。取 Watts/健康度/循环数。
   - **sleep/wake**：`setup()` 注册 `NSWorkspace.didWakeNotification` 观察器，唤醒后 `postWakeSkipCount=3`，`readValue()` 期间递减并将时间字段置 nil（显示"计算中"）；`deinit` 移除观察器。

## Key decisions / research facts honored

- **健康度** = `AppleRawMaxCapacity / DesignCapacity × 100`（`min(100, …)`），**不用** `MaxCapacity`（Apple Silicon 上为 100 百分比 → 会算成 ~1%）。
- **Watts 符号**来自 `kIOPSIsChargingKey`（非 Amperage 符号，跨机型不可靠）；`|watts| < 0.1 → nil`（显示"—"，避免误导性 +0.0W）。**注意**：研究示例此处返回 `0.0`，本实现按 CONTEXT/plan 锁定改为 `nil`。
- **充电三态**用 `isCharging` + `PowerSourceState`，**不用** `kIOPSIsChargedKey`（优化充电下 97% 仍 false）。
- **probe-and-nil**：每个 IOKit 键均 `as?`，**零 `as!` 强解包**。
- **台式机检测**：`AppleSmartBattery` 服务 `== IO_OBJECT_NULL` 或无内置电池源 → `readValue()` 返回 nil。
- CF 内存管理：`GetPowerSourceDescription` → unretained；`Copy*` → retained；`IORegistryEntryCreateCFProperties` → `IOObjectRelease`(defer)。

## Verification

- 全部 acceptance grep 断言通过（`struct BatterySnapshot`=1、`takeUnretainedValue`≥1、`AppleRawMaxCapacity`≥1、`IOObjectRelease`≥1、`as!`=0、`postWakeSkipCount`/`didWakeNotification` 在位）。
- `xcodebuild ... build` → **BUILD SUCCEEDED**（exit 0）。
- 行为验证（运行时）延后到 Plan 02 集成后的相位人工验证（笔记本非 nil / 台式机 nil）。

## Notes

- **执行方式**：Wave 1 的 gsd-executor 子代理连续两次遭遇 API 529 Overloaded（服务端过载，零工作产出）；按 execute-phase 的"Agent 不可用→串行内联执行"回退，由编排器内联完成本 plan。产物与子代理路径一致。
- Plan 02 将在此 `BatterySnapshot` 类型上构建 MetricCollector 接入 + DashboardState 字段 + DashboardView 电池区块。
