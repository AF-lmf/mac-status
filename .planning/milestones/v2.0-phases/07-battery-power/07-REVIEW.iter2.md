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
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 07: Code Review Report

**Reviewed:** 2026-06-17
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

本次评审覆盖电池功能三个核心文件：`BatteryReader`（IOKit 读取层）、`MetricCollector`（集成层）、`DashboardView`（显示层，含 `BatterySectionView` 与 `DashboardState`）。

**整体评价：** IOKit 内存管理规范（CF retain 语义正确、`defer IOObjectRelease` 位置合理、probe-and-nil 贯彻）；MetricCollector 集成干净（电池数据不写入 `MetricSample`/`RingBuffer`/`HistoryStore`，`reconfigure()` 不触碰 `batteryReader`）；功率符号逻辑（sign from `isChargingPS`，非 Amperage 符号）和健康度公式（`AppleRawMaxCapacity/DesignCapacity`，非 `MaxCapacity`）均正确。

发现 2 个警告（逻辑正确性问题）和 3 个信息条目（代码质量）。无阻断级问题。

---

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: `chargeStateText` 在"优化充电暂停"场景下显示"已充满"标签有误

**File:** `MacStatus/MacStatus/UI/Views/DashboardView.swift:203-207`
**Issue:** `chargeStateText` 的三态逻辑为：`isCharging=true` → `充电中`；`isCharging=false && isOnAC=true` → `已充满`；否则 → `使用电池`。

"已充满"在中文语义上等同于"100% charged"。然而 macOS 的优化电池充电功能（Battery Health Management）会在 80% 时暂停充电：此时 `kIOPSIsChargingKey = false`、`kIOPSPowerSourceStateKey = "AC Power"`，而 `chargePercent = 80`。结果界面显示 **"80% · 已充满"**，标签与实际电量完全矛盾，会对用户造成误导。

此问题不由 `kIOPSIsChargedKey` 引入（代码已正确回避该键），而是"AC 非充电"状态的标签选择问题。

**Fix:** 对 AC 非充电且未达满电的情形使用中性标签，例如 `电源接入`（或 `充电暂停`），将"已充满"限定于 `chargePercent >= 99`：

```swift
private var chargeStateText: String {
    if snapshot.isCharging { return "充电中" }
    if snapshot.isOnAC {
        // 优化充电可能在 80% 暂停，不能直接用"已充满"
        return snapshot.chargePercent >= 99 ? "已充满" : "电源接入"
    }
    return "使用电池"
}
```

---

### WR-02: `postWakeSkipCount` 存在跨线程数据竞争（与 NetworkReader 同模式）

**File:** `MacStatus/MacStatus/Readers/BatteryReader.swift:76-83`
**Issue:** `NSWorkspace.didWakeNotification` 观察者以 `queue: nil` 注册，通知回调在**未指定线程**（通常是后台线程）执行，直接写入 `self?.postWakeSkipCount`。而 `readValue()` 由 `@MainActor` 的 tick 调用，在主线程读写同一属性。`BatteryReader` 无任何 actor 隔离，`postWakeSkipCount` 是普通 `var Int`，这在 Swift 6（`SWIFT_STRICT_CONCURRENCY = complete`）下构成可检测的数据竞争。

```swift
// 写入：任意后台线程
self?.postWakeSkipCount = self?.postWakeSkipTotal ?? 3

// 读写：@MainActor 主线程
if postWakeSkipCount > 0 {
    postWakeSkipCount -= 1
```

项目已确认以 Swift 6 + `SWIFT_STRICT_CONCURRENCY = complete` 编译，`NetworkReader` 中存在相同模式（`previousBytes`/`previousTime` 在 wake 回调写入，在 `.utility` 后台 queue 读写，竞争更严重），均在 v1.0 中随同发布。本条目记录该风险，供后续修正参考。

**Fix（可选，与 NetworkReader 对齐修复）：** 将 wake 观察者 `queue` 改为 `.main`，消除跨线程写入：

```swift
wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification,
    object: nil,
    queue: .main   // <-- 确保与 readValue() 在同一队列
) { [weak self] _ in
    self?.postWakeSkipCount = self?.postWakeSkipTotal ?? 3
}
```

---

## Info

### IN-01: `hasBattery` 是冗余的 `@Published` 属性

**File:** `MacStatus/MacStatus/UI/Views/DashboardView.swift:62-64` 及 `DashboardState:282,362`
**Issue:** `DashboardState` 维护两个并行属性 `battery: BatterySnapshot?` 和 `hasBattery: Bool`，`updateBattery(_:)` 将两者同步赋值。`DashboardView` 使用双重条件 `if state.hasBattery, let battery = state.battery`。

`hasBattery` 完全派生自 `battery != nil`，不提供任何独立信息，却引入了两个 `@Published` 更新（两次 `objectWillChange` 触发两次可能的 SwiftUI 重渲染）和视图中冗余的双重判断。

**Fix:** 移除 `hasBattery`，视图直接使用 `if let battery = state.battery`：

```swift
// DashboardView.swift
if let battery = state.battery {
    BatterySectionView(snapshot: battery)
}

// DashboardState.swift — 删除 hasBattery 属性和对应赋值
func updateBattery(_ snapshot: BatterySnapshot?) {
    battery = snapshot
}
```

---

### IN-02: `timeLabel` 在 AC 待机状态下显示"剩余时间"行语义歧义

**File:** `MacStatus/MacStatus/UI/Views/DashboardView.swift:210-222`
**Issue:** `timeLabel` 的计算逻辑为 `snapshot.isCharging ? "距充满" : "剩余时间"`，未处理 AC 待机（`isOnAC=true`，`!isCharging`）情形。在"已充满/电源接入"状态下，界面展示一行 `"剩余时间 ···  —"`。该行既没有实际意义（WR-01 的场景下更是与 "已充满" 标签同时可见），不如在 AC 待机时完全隐藏此行。

**Fix:** AC 待机时不渲染时间行：

```swift
// 仅在"使用电池"或"充电中"时显示时间行
if snapshot.isCharging || !snapshot.isOnAC {
    row(timeLabel, timeText)
}
```

---

### IN-03: `updateUI` 中 `NetworkStats` 对象重复构造

**File:** `MacStatus/MacStatus/Collectors/MetricCollector.swift:196-199,222-225`
**Issue:** `updateUI(sample:)` 方法内，`netStats`（用于 `dashboard.updateNetwork`）和 `netStats2`（用于 `StatusBarManager.shared.updateTitle`）使用完全相同的逻辑分别构造，是重复代码。此问题存在于本次 Phase 前，但 battery 集成未修复它，留存于本次 diff 范围内。

**Fix:**

```swift
let netStats: NetworkStats? = (sample.networkUploadBps != nil || sample.networkDownloadBps != nil)
    ? NetworkStats(downloadBytesPerSec: sample.networkDownloadBps ?? 0,
                   uploadBytesPerSec: sample.networkUploadBps ?? 0)
    : nil

dashboard.updateNetwork(netStats)
// ...
StatusBarManager.shared.updateTitle(
    cpuUsage: sample.cpuUsage,
    memoryStats: memStats,
    networkStats: netStats,   // 复用同一实例
    gpuStats: sample.gpuUsage.map { GPUStats(utilizationPercent: $0, pressureLevel: nil) }
)
```

---

_Reviewed: 2026-06-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
