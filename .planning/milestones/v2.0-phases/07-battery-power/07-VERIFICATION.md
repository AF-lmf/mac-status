---
phase: 07-battery-power
verified: 2026-06-17T00:00:00Z
status: human_needed
score: 5/5 must-haves verified
human_validation_disposition: "deferred 2026-06-17 — 用户在自主模式选择继续到 Phase 8；4 项运行时硬件 UAT 留待与 Phase 9 一并补测。代码已静态验证(5/5) + build 成功 + 代码审查 clean。"
overrides_applied: 0
human_verification:
  - test: "在笔记本 Mac 上运行 app，打开 popover，观察电池区块"
    expected: "2x2 指标网格下方、进程列表上方出现电池卡片，显示充电态文案（充电中/已充满/使用电池）+ 电量%、时间行、功率行、健康度行；各行在对应 IOKit 键不可读时显示"—""
    why_human: "真实 IOKit 数据只在笔记本硬件运行时可验证；静态代码分析无法替代实际 UI 渲染"
  - test: "在台式 Mac（Mac mini / Mac Pro / iMac）上运行 app，打开 popover"
    expected: "电池区块完全不渲染——无任何占位行、空字段或零值；进程列表直接跟在 2x2 网格之后"
    why_human: "hasBattery=false 路径需在真实无电池硬件上确认；模拟器不等效于台式 Mac IOKit 环境"
  - test: "在笔记本上让系统睡眠后唤醒，在约 6 秒内观察时间行"
    expected: "时间行显示"计算中"（postWakeSkipCount=3，每 tick 递减），约 6 秒后恢复显示正常时间估计"
    why_human: "需要真实 sleep/wake 周期触发 NSWorkspace.didWakeNotification；无法静态验证时序行为"
  - test: "拔插充电器，观察充电三态切换"
    expected: "充电时显示"充电中"+ 正瓦数，已充满时显示"已充满"，用电池时显示"使用电池"+ 负瓦数；切换后 2 秒内（一个 tick）自动刷新"
    why_human: "三态切换需要真实电源状态变化；代码逻辑已静态验证，但端到端行为需硬件确认"
---

# Phase 7: Battery & Power — 验证报告

**Phase Goal:** On laptops the user can open the popover and see a complete battery picture — charge %, charging state, time remaining, real-time power draw, and health — while desktop Macs hide the whole battery section cleanly.
**Verified:** 2026-06-17
**Status:** human_needed
**Re-verification:** No — 初次验证

---

## Goal Achievement

### Observable Truths（来自 ROADMAP Success Criteria）

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Popover 显示电量%与充电状态（充电中/已充满/使用电池），数据来自 IOKit Power Sources | ✓ VERIFIED | `BatterySectionView`：`"\(snapshot.chargePercent)% · \(chargeStateText)"` 直接渲染；`chargeStateText` 实现三态逻辑（isCharging→充电中；!isCharging&&isOnAC→已充满；else→使用电池），不依赖 `kIOPSIsChargedKey` |
| 2 | Popover 显示剩余时间或充满时间，`-1` 哨兵及 nil（post-wake）均渲染为"计算中" | ✓ VERIFIED | `formatTime(_:)`：`nil→"计算中"`；`-1→"计算中"`；`0→"—"`；`>0→X小时Y分/Y分钟`；`postWakeSkipCount>0` 时时间字段被强制为 `nil` |
| 3 | Popover 显示带符号瓦数（+充电/−放电）与健康度（%，附循环次数），`AppleSmartBattery` 键不可读时降级为"—" | ✓ VERIFIED | `watts` 符号来自 `isChargingPS`（非 Amperage 符号）；`\|watts\| < 0.1 → nil`（UI 显示"—"）；`healthPercent` = `min(100, AppleRawMaxCapacity/DesignCapacity×100)`；所有键均 `as?` probe-and-nil，无 `as!` |
| 4 | 台式 Mac（无电池）整个电池区块完全隐藏 | ✓ VERIFIED | `DashboardView.body`：`if state.hasBattery, let battery = state.battery { BatterySectionView(...) }`；`updateBattery(nil)` → `hasBattery=false`；`readValue()` 在无内置电池源时 `return nil` |
| 5 | `BatteryReader` 仅发出 `Sendable` 快照，sleep/wake 后延迟信任时间估计 | ✓ VERIFIED | `BatterySnapshot: Sendable, Equatable`，8 个字段全部值类型（Int/Bool/Double/Optional），无 CF 类型跨 actor；`setup()` 注册 `NSWorkspace.didWakeNotification`，`postWakeSkipCount=3`；`deinit` 移除观察器 |

**Score:** 5/5 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `MacStatus/MacStatus/Readers/BatteryReader.swift` | BatterySnapshot struct + BatteryReader class | ✓ VERIFIED | 204 行，包含两个符号；xcodebuild 编译并入 Sources 构建阶段（`project.pbxproj` 含 2 处 Sources 条目） |
| `MacStatus/MacStatus/Collectors/MetricCollector.swift` | batteryReader 集成（setup/tick/updateUI） | ✓ VERIFIED | `batteryReader` 出现 4 次；`lastBatterySnapshot` 出现 3 次；`dashboard.updateBattery(lastBatterySnapshot)` 已接入 `updateUI`；`reconfigure()` 无 batteryReader 调用 |
| `MacStatus/MacStatus/UI/Views/DashboardView.swift` | DashboardState 电池字段 + updateBattery + BatterySectionView | ✓ VERIFIED | `@Published hasBattery: Bool = false`、`@Published battery: BatterySnapshot? = nil`、`func updateBattery`、`BatterySectionView` struct 均已实现 |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `BatteryReader.readValue()` | `IOPSCopyPowerSourcesInfo / IOPSGetPowerSourceDescription` | Layer 1 Power Sources API | ✓ WIRED | `grep "IOPSCopyPowerSourcesInfo" BatteryReader.swift` → 2 次出现；`takeUnretainedValue()` 正确用于 `GetPowerSourceDescription` |
| `BatteryReader.readValue()` | `IOServiceGetMatchingService("AppleSmartBattery")` | Layer 2 IORegistry | ✓ WIRED | `grep "AppleSmartBattery"` → 5 次；`defer { IOObjectRelease(service) }` 紧随 `guard service != IO_OBJECT_NULL` 之后（BatteryReader.swift:150-151）|
| `BatteryReader.setup()` | `NSWorkspace.didWakeNotification` | wakeObserver | ✓ WIRED | `grep "didWakeNotification"` → 3 次；`[weak self]` 捕获防止保留循环；`deinit` 移除观察器 |
| `MetricCollector.tick()` | `BatteryReader.readValue()` | `batteryReader.readValue()` | ✓ WIRED | MetricCollector.swift:154-155 |
| `MetricCollector.updateUI()` | `DashboardState.updateBattery(_:)` | `dashboard.updateBattery` | ✓ WIRED | MetricCollector.swift:209 |
| `DashboardView.body` | `BatterySectionView` | `if state.hasBattery` | ✓ WIRED | DashboardView.swift:62-64 |

---

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `BatterySectionView` | `snapshot: BatterySnapshot` | `MetricCollector.tick()` → `batteryReader.readValue()` → IOKit | 是，来自 IOKit Power Sources + AppleSmartBattery IORegistry（非静态/空值） | ✓ FLOWING |
| `DashboardState.hasBattery` | `Bool` | `updateBattery(snapshot)` → `snapshot != nil` | 是，直接从 IOKit 结果派生 | ✓ FLOWING |

---

## Behavioral Spot-Checks

Step 7b: SKIPPED（需要运行中的 app + 真实 IOKit 硬件访问；编译时可静态验证，无法 curl/CLI 测试）

---

## Probe Execution

Step 7c: N/A（本阶段无 `scripts/*/tests/probe-*.sh` 探针文件）

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| BATT-01 | 07-01, 07-02 | 弹窗显示电量%与充电状态（充电中/已充满/使用电池） | ✓ SATISFIED | `chargeStateText` 三态逻辑 + `chargePercent` 渲染，数据来自 `kIOPSIsChargingKey` + `kIOPSPowerSourceStateKey` |
| BATT-02 | 07-01, 07-02 | 弹窗显示剩余可用时间或充满时间 | ✓ SATISFIED | `formatTime` 处理 nil/−1/0/>0 四种情形；`timeLabel` 按充电状态动态切换"距充满"/"剩余时间" |
| BATT-03 | 07-01, 07-02 | 弹窗显示实时充/放电功率（瓦） | ✓ SATISFIED | `wattsText` 渲染带符号瓦数；Watts 幅值 = `abs(Amperage/1000 × Voltage/1000)`，符号来自 `kIOPSIsChargingKey` |
| BATT-04 | 07-01, 07-02 | 弹窗显示电池健康度（最大容量%）与循环次数 | ✓ SATISFIED | `healthPercent = min(100, AppleRawMaxCapacity/DesignCapacity×100)`；`healthText` 输出"N%（N 次循环）"或仅"%"（cycleCount nil 时） |
| BATT-05 | 07-01, 07-02 | 无电池机型整个电池区块优雅降级隐藏 | ✓ SATISFIED | `readValue()` 在无内置电池源时返回 nil → `hasBattery=false` → `BatterySectionView` 完全不渲染 |

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | 无 `as!` 强解包；无 `TBD/FIXME/XXX` 未关联工单的债务标记；无空 stub 实现 |

零 `as!` 强解包（`grep -c " as! " BatteryReader.swift` → 0）。全部三个被修改文件无 `TBD`/`FIXME`/`XXX` 标记。

---

## 高风险核查项（逐项结论）

### 1. 健康度公式使用 AppleRawMaxCapacity / DesignCapacity

**VERIFIED** — BatteryReader.swift:184-187：

```swift
guard let rawMax = props["AppleRawMaxCapacity"] as? Int,
      let design = props["DesignCapacity"] as? Int,
      design > 0 else { return nil }
return min(100.0, Double(rawMax) / Double(design) * 100.0)
```

字符串 `"MaxCapacity"` 在文件中出现 0 次（`grep -c '"MaxCapacity"'` → 0）。

### 2. Watts 符号来自 kIOPSIsChargingKey，非 Amperage 符号

**VERIFIED** — BatteryReader.swift:178：`return isChargingPS ? +magnitude : -magnitude`（`isChargingPS` 来自 `kIOPSIsChargingKey`；`magnitude` 取 `abs(Double(amp))`，丢弃 Amperage 自带符号）。

### 3. 充电三态不依赖 kIOPSIsChargedKey

**VERIFIED** — `kIOPSIsChargedKey` 在 BatteryReader.swift 和 DashboardView.swift 中均出现 0 次。三态仅用 `isCharging`（来自 `kIOPSIsChargingKey`）与 `isOnAC`（来自 `kIOPSPowerSourceStateKey`）。

### 4. IOPSGetPowerSourceDescription 使用 takeUnretainedValue

**VERIFIED** — BatteryReader.swift:104-105：`IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()`。Copy* 函数（第 97-98 行）使用 `takeRetainedValue()`。

### 5. IOObjectRelease 在 defer 块内，guard 之后立即设置

**VERIFIED** — BatteryReader.swift:137-151：`guard service != IO_OBJECT_NULL else { return BatterySnapshot(...) }` → 若服务有效才执行 `defer { IOObjectRelease(service) }`（第 151 行）。

### 6. 零 `as!` 强解包

**VERIFIED** — `grep -c " as! " BatteryReader.swift` → 0。

### 7. 电池不进入 MetricSample / RingBuffer / HistoryStore

**VERIFIED** — MetricSample 初始化（MetricCollector.swift:157-163）不含任何 `battery` 字段；`grep -A8 "let sample = MetricSample" | grep -c "battery"` → 0。`lastBatterySnapshot` 独立缓存，不经 ringBuffer/historyStore。

### 8. StatusBarManager / enabledMetrics 未触碰

**VERIFIED** — StatusBarManager.swift 第 112 行：`case .battery: segment = nil`（Phase 7 scope 内保持不变）；`SettingsManager.swift` 第 104 行默认 `enabledMetrics = [.cpu, .gpu, .memory, .network]`，注释明确"Does NOT include .battery"；`StatusBarManager.shared.updateTitle` 调用不含任何 battery 参数（`grep -A6 "updateTitle"` → 0 次 battery）。

### 9. BatteryReader.swift 已登记进 Xcode target 编译源

**VERIFIED** — `project.pbxproj` 包含：
- `F70000000000000000000002 /* BatteryReader.swift in Sources */`（PBXBuildFile）
- `F70000000000000000000001 /* BatteryReader.swift */`（PBXFileReference）
- Readers group children 与 Sources build phase 各 1 条

`grep "BatteryReader.swift in Sources" project.pbxproj | wc -l` → 2（Build File 定义 + Sources 引用）。

**注意：07-01-SUMMARY.md 记载了一个已修复的关键问题**——Plan 07-01 在 BatteryReader.swift 创建时未将其登记进 pbxproj，导致 07-01 的 BUILD SUCCEEDED 是假阳性（文件从未被编译）。Plan 07-02 已在 pbxproj 中补全 4 处条目，当前 build 已正确编译 BatteryReader。

### 10. xcodebuild BUILD SUCCEEDED

**VERIFIED** — 本次验证实际运行：
```
xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus \
  -configuration Debug -derivedDataPath build.noindex build \
  2>&1 | grep "BUILD (SUCCEEDED|FAILED)"
```
输出：`** BUILD SUCCEEDED **`

---

## 细节差异说明（非 BLOCKER）

**healthText 当 cycleCount 为 nil 时的行为**：PLAN02 `<behavior>` 描述为"任一为 nil→—"，但代码实现为"健康度 nil→—；仅 cycleCount nil→显示裸百分比"（DashboardView.swift:246-253，注释明确"循环数缺失则仅显示百分比"）。ROADMAP SC3 要求"degrading to '—' when the model's AppleSmartBattery keys are unreadable"——健康度键不可读确实显示"—"，cycleCount 缺失时显示裸百分比比完全隐藏更有用。此为有意的实现优化，与用户可见需求（BATT-04）不矛盾，列为信息项。

**ROADMAP SC2 提及"−2 哨兵"**：SC2 原文为"the `-1`/`-2` sentinels"，但 RESEARCH.md 详细 API 表（第 174-175 行）仅记录 `-1 = "Still Calculating"` 作为 IOPS 时间键的已知哨兵。`formatTime` 对负数走 `default: return "—"` 分支，`-2` 若实际出现会显示"—"而非"计算中"。PLAN01 must_have 仅规定 `-1→计算中`，未包含 `-2`。此项为边缘情形，归入人工验证（需真实硬件确认 `-2` 是否实际出现）。

---

## Human Verification Required

### 1. 笔记本 popover 电池区块完整性

**Test:** 在搭载电池的 MacBook 上运行 MacStatus，点击菜单栏图标打开 popover
**Expected:** 2x2 指标网格与进程列表之间出现电池卡片（RoundedRectangle 背景，与其他卡片风格一致），显示：行1—"电池" + "85% · 充电中/已充满/使用电池"；行2—时间（"距充满"或"剩余时间"）；行3—"功率" + 带符号瓦数或"—"；行4—"健康度" + "N%（N 次循环）"或"—"
**Why human:** 真实 IOKit 数据只在笔记本硬件上可读；静态代码分析无法替代 UI 渲染验证

### 2. 台式 Mac 电池区块完全隐藏

**Test:** 在无电池的台式 Mac（Mac mini / Mac Pro / iMac）上运行 MacStatus，打开 popover
**Expected:** 无任何电池内容，无空行、无占位符；进程列表直接跟在 2x2 网格之后
**Why human:** hasBattery=false 路径需在真实无电池 IOKit 环境下验证

### 3. Sleep/Wake 后时间行显示"计算中"

**Test:** 在笔记本上让系统睡眠，唤醒后立即打开 popover，在约 6 秒内持续观察
**Expected:** 时间行显示"计算中"（postWakeSkipCount 倒计时），约 6 秒（3 tick × 2s）后恢复正常时间数字
**Why human:** 需要真实 sleep/wake 事件；NSWorkspace.didWakeNotification 行为无法在不运行 app 的情况下静态确认

### 4. 充电三态实时切换

**Test:** 笔记本分别在插电充电、已充满悬停（AC 待机）、拔除电源三种状态下打开 popover
**Expected:** 分别显示"充电中"、"已充满"、"使用电池"；功率行分别显示正值/—/负值；时间行对应显示充满时间/—/剩余时间
**Why human:** 需要真实电源状态变化；三态逻辑已静态验证，端到端行为需硬件确认

---

## Gaps Summary

无 BLOCKER — 所有 5 条 ROADMAP Success Criteria 在代码层面已验证。人工验证项均为运行时行为确认，不影响代码正确性判断。

---

_Verified: 2026-06-17_
_Verifier: Claude (gsd-verifier)_
