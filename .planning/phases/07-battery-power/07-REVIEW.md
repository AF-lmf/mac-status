---
phase: 07-battery-power
reviewed: 2026-06-17T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - MacStatus/MacStatus/Readers/BatteryReader.swift
  - MacStatus/MacStatus/Collectors/MetricCollector.swift
  - MacStatus/MacStatus/UI/Views/DashboardView.swift
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: clean
---

# Phase 07: Code Review Report（迭代 2 复审）

**Reviewed:** 2026-06-17
**Depth:** standard
**Files Reviewed:** 3
**Status:** clean

## Summary

本次为迭代 2 复审，重点验证前次两项警告（WR-01 / WR-02）的修复是否正确、无回归，并对三个文件进行完整 standard-depth 扫描。

构建结果：`BUILD SUCCEEDED`（Swift 6，`SWIFT_STRICT_CONCURRENCY = complete`，零编译警告，零并发警告）。

---

## Structural Findings (fallow)

无结构化预分析结果传入，跳过本节。

---

## Narrative Findings (AI reviewer)

### WR-01 修复验证 — `chargeStateText` 状态覆盖（已修复，无回归）

**文件：** `MacStatus/MacStatus/UI/Views/DashboardView.swift:204-210`

修复后的四态逻辑：

| 条件 | 显示文本 |
|------|----------|
| `isCharging == true` | 充电中 |
| `!isCharging && isOnAC && chargePercent >= 99` | 已充满 |
| `!isCharging && isOnAC && chargePercent < 99` | 电源接入 |
| `!isCharging && !isOnAC` | 使用电池 |

四态完整，无缺口，无重叠。边界值 `chargePercent >= 99` 正确处理了"优化充电暂停"场景（macOS Battery Health Management 可能在 80% 停止充电，届时显示"电源接入"而非"已充满"）。修复有效，原 WR-01 问题已消除。

额外验证的边界情形：`isCharging=true && chargePercent=99` 时仍返回"充电中"（正确，Apple 硅在接近满电时 isCharging 可为 true），`timeText` 路径对应返回 `formatTime(timeToFullMinutes)`，无矛盾。

### WR-02 修复验证 — wake observer `queue: .main`（已修复，无回归）

**文件：** `MacStatus/MacStatus/Readers/BatteryReader.swift:76-82`

`NSWorkspace.didWakeNotification` 观察者改为 `queue: .main`（`OperationQueue.main`）。在 Swift 6 中，`OperationQueue.main` 与 `DispatchQueue.main` 均被 Swift 运行时桥接至 MainActor 执行器（SE-0338 / SE-0394），因此闭包内对 `postWakeSkipCount` 的写入与 `MetricCollector`（`@MainActor`）调用 `readValue()` 的读写处于同一串行执行上下文，数据竞争已消除。

唤醒语义未改变：`didWakeNotification` 依然在系统唤醒后单次触发，`postWakeSkipCount` 被重置为 3，随后 3 次 tick 将时间估算抑制为"计算中"（`nil`）。观察者闭包为单向赋值，不持有任何锁，无死锁风险。修复有效，原 WR-02 问题已消除。

### 其余扫描结论

**BatteryReader：**
- IOKit 内存管理正确：`takeRetainedValue` 用于 `IOPSCopyPowerSourcesInfo` / `IOPSCopyPowerSourcesList` 的拥有型指针；`takeUnretainedValue` 用于 `IOPSGetPowerSourceDescription` 的借用型指针；`defer IOObjectRelease(service)` 覆盖 Layer 2 的所有代码路径（含两个 guard 的 early-return 均在 `defer` 注册后，故均正确释放）。
- probe-and-nil 贯彻，无强解包。
- `postWakeSkipCount` 的递减用 `> 0` 守卫，不会下溢。

**MetricCollector：**
- Battery 数据流路径正确：`lastBatterySnapshot` 独立缓存，不写入 `MetricSample` / `RingBuffer` / `HistoryStore`；`applyNow()` 通过 `updateUI` 复用快照，settings 驱动的重渲染可正常带出电池数据。
- `reconfigure()` 不触碰 `batteryReader`，保留 wake 观察者和计数状态，符合设计意图。

**DashboardView / DashboardState：**
- `formatTime` 对 `nil`（post-wake 抑制）、`-1`（Apple PMU 哨兵值）、`0`（不适用）、正数均有覆盖。
- `wattsText` 符号逻辑正确（`snapshot.watts` 的符号已由 `BatteryReader` 在写入时根据 `isChargingPS` 决定，显示层仅判断 `>= 0` 取符号字符）。
- `healthText` 的 `Int(h.rounded())` 正确避免了截断误差。
- `appendSample` 正确将样本数限制于 `maxSamples=60`。

### 已知 INFO 条目（明确置于本次复审范围外，不计入 findings）

- **IN-01**：`hasBattery` 与 `battery != nil` 冗余
- **IN-02**：AC 待机时 `timeLabel` 显示"剩余时间"行语义歧义
- **IN-03**：`updateUI` 内 `NetworkStats` 对象重复构造

All reviewed files meet quality standards. No new or remaining critical/warning issues found.

---

_Reviewed: 2026-06-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
