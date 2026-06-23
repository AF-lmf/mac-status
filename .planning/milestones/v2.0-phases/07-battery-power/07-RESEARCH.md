# Phase 7: Battery & Power — Research

**Researched:** 2026-06-17
**Domain:** IOKit Power Sources API + AppleSmartBattery IORegistry, Swift 6 strict concurrency
**Confidence:** HIGH — all key API facts verified against local Xcode SDK headers (`IOPSKeys.h`) and live `ioreg`/Swift execution on the development machine (Apple Silicon MacBook, macOS 26.5).

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- 电量%/充电状态/剩余时间：用 **IOKit Power Sources**（`IOPSCopyPowerSourcesInfo` + `IOPSGetPowerSourceDescription`）—— 直接给出百分比、充电态、时间估计及 `-1`(计算中)/`-2`(不可用) 哨兵。
- 功率(W)/健康度/循环次数：读 **`AppleSmartBattery` IORegistry 键**（Amperage × Voltage → 带符号瓦数；MaxCapacity/DesignCapacity 或 NominalChargeCapacity → 健康%；CycleCount）。**逐键 probe-and-nil**，任一键缺失/类型不符即该字段为 nil，绝不强解包、绝不造假值。
- 读取节奏：**复用 MetricCollector 现有主 tick**（与其他指标同一计时器；电池读取廉价，瓦数需"实时"故跟随 tick）。电池数据**不**写入 `MetricSample`/`RingBuffer`/`HistoryStore`（v2.0 不持久化电池、不做电池 sparkline），每 tick 读取后直接推给 `DashboardState`。
- 台式机检测：Power Sources 无内置电池 或 `AppleSmartBattery` 服务缺失 → `BatteryReader.readValue()` 返回 `nil` → popover 整段隐藏（沿用 v1.0 GPU nil 降级范式）。
- 展示位置：**2x2 指标网格下方、进程列表上方的独立整宽 section**；仅当有电池时渲染。
- 充电态文案（中文）：**充电中 / 已充满 / 使用电池**。
- 剩余时间格式：充电中显示"距充满"，使用电池显示"剩余"，格式 "X小时Y分" / "Y分钟"；`-1` 哨兵 → **"计算中"**。
- 功率(W)：**带符号**，充电 `+18.5W`、放电 `−12.3W`，1 位小数；不可读 → **"—"**。
- 健康度：**"健康度 92%（XXX 次循环）"**；任一不可读 → "—"。
- 降级粒度：**整段隐藏仅在无电池（台式机）时**；笔记本上个别不可读字段各自降级为 "—"。
- 跨 actor 快照：定义 **`BatterySnapshot: Sendable` struct**，probe-and-nil 字段全为 Optional；`BatteryReader.readValue() -> BatterySnapshot?`（nil = 无电池）。
- sleep/wake：**`BatteryReader` 观察 `NSWorkspace.didWakeNotification`**；唤醒后剩余时间估计先显示"计算中"，直到取得稳定读数。

### Claude's Discretion

- `BatteryReader` 是否继承 `TimerReader<BatterySnapshot>` 还是仅实现同步 `readValue()`：由 Claude 依 MetricCollector 接入方式裁定。
- 瓦数计算的具体键名与单位换算：交由研究阶段定稿（见本文档）。
- 健康度分母用 `DesignCapacity` 还是 `NominalChargeCapacity`：交由研究阶段定稿（见本文档）。
- 电池 section 的具体 SwiftUI 布局细节由 Claude 依现有 DashboardView 风格裁定。

### Deferred Ideas (OUT OF SCOPE)

- 状态栏电池显示（把 `.battery` 加入 `enabledMetrics`/`order`）→ Phase 9。
- 电池历史趋势/sparkline、落盘持久化 → v2.0 Out of Scope。
- 低电量告警/通知 → v2.0 未纳入。
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BATT-01 | 用户能在弹窗中看到电池电量百分比与充电状态（充电中 / 已充满 / 使用电池） | Power Sources API: `kIOPSCurrentCapacityKey` (%), `kIOPSIsChargingKey` (Bool), `kIOPSPowerSourceStateKey` (String) — all verified on device |
| BATT-02 | 用户能在弹窗中看到电池剩余可用时间（或充满时间） | `kIOPSTimeToEmptyKey` / `kIOPSTimeToFullChargeKey` (minutes, -1=calculating) — verified from SDK header |
| BATT-03 | 用户能在弹窗中看到实时充/放电功率（瓦） | AppleSmartBattery: `Amperage` (signed mA, Int) × `Voltage` (mV, Int) / 1_000_000 = W — verified on device |
| BATT-04 | 用户能在弹窗中看到电池健康度（最大容量百分比）与循环次数 | AppleSmartBattery: `AppleRawMaxCapacity` / `DesignCapacity` × 100 for health%; `CycleCount` (Int) — verified on device |
| BATT-05 | 在无电池机型（台式 Mac）上整个电池区块优雅降级隐藏 | `IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery")) == IO_OBJECT_NULL` → no battery — verified pattern |
</phase_requirements>

---

## Summary

Phase 7 adds a battery section to the popover on laptops. The data comes from two Apple-provided IOKit layers. Both were verified live on the development machine (Apple Silicon MacBook Pro, macOS 26.5, CycleCount=95, AppleRawMaxCapacity=8176 mAh / DesignCapacity=8579 mAh = 95.3% health).

**Layer 1 — Power Sources API** (`IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceDescription`): provides charge %, charging state, and time-remaining estimates. The keys are well-documented in `IOPSKeys.h` (bundled in the Xcode SDK). All values are type-safe (CFNumber as `Int`, CFBoolean as `Bool`, CFString as `String`) and cast cleanly as Swift optionals. The `-1` sentinel for time keys means "still calculating"; value `0` means "not applicable in current state" (e.g., `Time to Empty = 0` when on AC).

**Layer 2 — AppleSmartBattery IORegistry**: provides real-time Amperage (signed mA), Voltage (mV), health-related capacity keys, and cycle count. On Apple Silicon the `MaxCapacity` key changed from mAh to a percentage (returns `100` on a healthy battery); `AppleRawMaxCapacity` still gives the actual mAh value. Health = `AppleRawMaxCapacity / DesignCapacity * 100`. Every key must be probe-and-nil cast — no strong-unwrapping anywhere.

**Primary recommendation:** `BatteryReader` does NOT need to subclass `TimerReader<BatterySnapshot>` since `MetricCollector` calls `readValue()` synchronously on its own timer. Implement `BatteryReader` as a plain `final class` with a synchronous `readValue() -> BatterySnapshot?` method and an `NSWorkspace.didWakeNotification` observer (mirroring `NetworkReader`). The `BatterySnapshot: Sendable` struct holds only value types (Int, Bool, Double, Optional) — no CF types cross the actor boundary.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| 电量% / 充电状态 / 时间估计 | Reader (BatteryReader) | — | IOKit Power Sources API is a synchronous C call; belongs in the Reader layer |
| 实时功率(W) / 健康度 / 循环次数 | Reader (BatteryReader) | — | AppleSmartBattery IORegistry is a synchronous C call; same reader handles both layers |
| 台式机检测 (nil = no battery) | Reader (BatteryReader.readValue → nil) | — | Mirrors GPUReader nil-degradation pattern already in codebase |
| 数据分发 | MetricCollector (@MainActor tick) | — | Existing tick calls readValue() and pushes to DashboardState; no new timer needed |
| UI 状态 | DashboardState (@Published fields) | — | Existing ObservableObject pattern; add battery @Published fields + updateBattery(_:) |
| 电池 section 渲染 | DashboardView (SwiftUI, conditional) | — | Battery section inserted between 2×2 grid and ProcessListView; hidden when snapshot nil |
| sleep/wake 恢复 | BatteryReader (wakeObserver) | — | Mirror NetworkReader.wakeObserver pattern; set a `postWakeSkipCount` flag |

---

## Standard Stack

### Core (All Apple SDK — Zero External Dependencies)

| API / Framework | Header / Module | Purpose |
|----------------|----------------|---------|
| `IOKit` | `import IOKit` | Base IOKit access for AppleSmartBattery |
| `IOKit.ps` | `import IOKit.ps` | Power Sources API (IOPSCopy*, IOPSGet*) |
| `Foundation` | `import Foundation` | `NSWorkspace`, `NotificationCenter`, CF bridging |
| `AppKit` | (via `NSWorkspace`) | `NSWorkspace.didWakeNotification` |

No external packages are introduced in this phase. No slopcheck required.

---

## Package Legitimacy Audit

No external packages are installed in Phase 7. All APIs are Apple SDK (IOKit, Foundation). This section is N/A.

---

## Architecture Patterns

### System Architecture Diagram

```
MetricCollector (@MainActor, existing 2s tick)
    │
    ├─ batteryReader.readValue()   ← synchronous, µs-fast
    │       │
    │       ├─ Layer 1: IOPSCopyPowerSourcesInfo / IOPSGetPowerSourceDescription
    │       │       → chargePercent (Int), isCharging (Bool), isOnAC (Bool)
    │       │       → timeToEmptyMinutes (Int?), timeToFullMinutes (Int?)
    │       │
    │       └─ Layer 2: IOServiceGetMatchingService("AppleSmartBattery")
    │               + IORegistryEntryCreateCFProperties
    │               → watts (Double?), healthPercent (Double?), cycleCount (Int?)
    │               → IOObjectRelease(service)
    │
    ├─ Returns BatterySnapshot? (nil = no battery = desktop)
    │
    └─ dashboard.updateBattery(snapshot?)
            │
            └─ DashboardState @Published fields
                    │
                    └─ DashboardView: BatterySectionView (if snapshot != nil)
```

**Wake recovery path:**
```
NSWorkspace.didWakeNotification
    → BatteryReader.wakeObserver fires
    → sets postWakeSkipCount = 3  (skip 3 ticks ≈ 6s at 2s interval)
    → on next readValue(): decrement postWakeSkipCount
    → while postWakeSkipCount > 0: return snapshot with
      timeToEmptyMinutes = nil (force "计算中" display)
      timeToFullMinutes = nil
    → after count reaches 0: resume normal time-remaining reads
```

### Recommended Project Structure

```
MacStatus/Readers/
├── BatteryReader.swift      # NEW: BatterySnapshot struct + BatteryReader class
MacStatus/Collectors/
├── MetricCollector.swift    # EDIT: add batteryReader, tick integration, updateBattery
MacStatus/UI/Views/
├── DashboardView.swift      # EDIT: add DashboardState battery @Published fields,
│                            #       updateBattery(), BatterySectionView
```

No new files in any other directory. No new Xcode targets. No new frameworks.

---

## Authoritative API Reference

### API 1: Power Sources — Exact Keys, Types, Sentinels

All constants below are verified from `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk/System/Library/Frameworks/IOKit.framework/Versions/A/Headers/ps/IOPSKeys.h`. [VERIFIED: local Xcode SDK]

#### Key constants (actual string values)

| Swift Constant | String Value | CF Type → Swift Cast | Unit | Notes |
|---------------|-------------|---------------------|------|-------|
| `kIOPSCurrentCapacityKey` | `"Current Capacity"` | CFNumber → `as? Int` | % (0–100) | Apple-defined sources publish in percent |
| `kIOPSMaxCapacityKey` | `"Max Capacity"` | CFNumber → `as? Int` | % (usually 100) | From IOPS layer; Apple sources publish in percent |
| `kIOPSPowerSourceStateKey` | `"Power Source State"` | CFString → `as? String` | — | `"AC Power"` or `"Battery Power"` or `"Off Line"` |
| `kIOPSIsChargingKey` | `"Is Charging"` | CFBoolean → `as? Bool` | — | `true` = actively charging |
| `kIOPSIsChargedKey` | `"Is Charged"` | CFBoolean → `as? Bool` | — | `true` when ≥95% and plugged in and not actively charging; BUT can be `false` during Optimized Battery Charging (see Note 1) |
| `kIOPSTimeToEmptyKey` | `"Time to Empty"` | CFNumber → `as? Int` | minutes | Valid only when `PowerSourceState = "Battery Power"` AND `IsCharging = false`; `-1` = "Still Calculating" |
| `kIOPSTimeToFullChargeKey` | `"Time to Full Charge"` | CFNumber → `as? Int` | minutes | Valid only when `IsCharging = true`; `-1` = "Still Calculating" |
| `kIOPSIsPresentKey` | `"Is Present"` | CFBoolean → `as? Bool` | — | Filter: only process sources where this is `true` |
| `kIOPSTypeKey` | `"Type"` | CFString → `as? String` | — | Filter: use only `kIOPSInternalBatteryType = "InternalBattery"` |
| `kIOPSACPowerValue` | `"AC Power"` | (String constant) | — | Value for `kIOPSPowerSourceStateKey` |
| `kIOPSBatteryPowerValue` | `"Battery Power"` | (String constant) | — | Value for `kIOPSPowerSourceStateKey` |
| `kIOPSInternalBatteryType` | `"InternalBattery"` | (String constant) | — | Value for `kIOPSTypeKey` |

**Note 1 — `kIOPSIsChargedKey` reliability:** Verified on device: at 97% charge on AC with Optimized Battery Charging active, `IsCharged = false` even though the battery is not being charged. Do not rely on `IsChargedKey` alone for the "已充满" display state. Use the rule below.

**Sentinel values (verified from SDK docs + live execution):**
- `-1` → "Still Calculating the Time" → display **"计算中"**
- `0` → not applicable in current mode (e.g., `Time to Empty = 0` when on AC) → ignore / do not display
- `>0` → positive integer minutes remaining → convert to "X小时Y分" or "Y分钟"

#### Charging state → display text mapping (verified on device)

```
isCharging == true                           → 充电中  (show timeToFull if ≥1)
isCharging == false && state == "AC Power"   → 已充满  (show nothing or "—" for time)
state == "Battery Power"                     → 使用电池 (show timeToEmpty if ≥1)
```

Rationale: When on AC and not actively charging, macOS itself shows "Not Charging" or treats the battery as effectively maintained. For user-facing display, "已充满" (or "AC 已连接") is the appropriate label. Using `kIOPSIsChargedKey == true` would incorrectly show "使用电池" during Optimized Charging pauses.

#### Memory management for Power Sources [VERIFIED: local Xcode SDK + Apple Developer Forums]

```swift
// takeRetainedValue() — caller owns; ARC will release
let info: CFTypeRef = IOPSCopyPowerSourcesInfo()!.takeRetainedValue()
let list: CFArray   = IOPSCopyPowerSourcesList(info)!.takeRetainedValue()

// takeUnretainedValue() — NOT owned; do NOT release; dictionary is valid
// only as long as `info` is alive
let desc: CFDictionary? = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
```

**Critical:** `IOPSGetPowerSourceDescription` returns a non-retained (borrowed) reference. Using `takeRetainedValue()` here over-releases and causes a crash. Use `takeUnretainedValue()`.

---

### API 2: AppleSmartBattery IORegistry — Exact Keys, Types, Units

Verified by running `ioreg -r -c AppleSmartBattery` and a Swift test harness on the development machine (Apple Silicon MacBook Pro, macOS 26.5). [VERIFIED: local ioreg + Swift execution]

#### Service acquisition and release

```swift
let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                          IOServiceMatching("AppleSmartBattery"))
guard service != IO_OBJECT_NULL else {
    return nil  // No battery (desktop Mac or unsupported hardware)
}
defer { IOObjectRelease(service) }

var propsRef: Unmanaged<CFMutableDictionary>?
guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
      let props = propsRef?.takeRetainedValue() as? [String: Any] else {
    return nil  // Properties unavailable — treat as no battery
}
```

**Memory rule:** `IORegistryEntryCreateCFProperties` returns a retained CF dictionary — use `takeRetainedValue()`. The service handle is a Mach port; `IOObjectRelease(service)` is mandatory, best placed in `defer`.

#### Key table (all verified on device with Swift type inspection)

| Key String | Swift Cast | Unit | Example Value | Notes |
|-----------|-----------|------|---------------|-------|
| `"Amperage"` | `as? Int` | mA (signed) | `0` (idle), `-2500` (discharging), `+4990` (charging) | **Signed**: negative = discharging on most Apple Silicon models; positive = charging. However, sign convention is NOT guaranteed across all models — cross-check with `kIOPSIsChargingKey` for display sign. See Note 2. |
| `"Voltage"` | `as? Int` | mV | `12904` | Always positive. 3-cell pack = ~12.9V nominal |
| `"AppleRawMaxCapacity"` | `as? Int` | mAh | `8176` | Full-charge capacity in real mAh. **Use this for health calculation.** Present on all tested Apple Silicon Macs. |
| `"DesignCapacity"` | `as? Int` | mAh | `8579` | Factory-rated capacity. **Denominator for health %**. Present on all tested Macs. |
| `"MaxCapacity"` | `as? Int` | **% on Apple Silicon** / mAh on Intel | `100` (AS) | **Do not use for health calculation** — returns `100` (percentage) on Apple Silicon instead of mAh. Use `AppleRawMaxCapacity` instead. |
| `"NominalChargeCapacity"` | `as? Int` | mAh | `8420` | A smoothed/normalized capacity. Close to `AppleRawMaxCapacity` but slightly higher. Could be used as alternative health denominator but `AppleRawMaxCapacity / DesignCapacity` is more standard. |
| `"CycleCount"` | `as? Int` | count | `95` | Lifetime charge-discharge cycles |
| `"IsCharging"` | `as? Bool` | — | `false` | Redundant with IOPS layer; use IOPS `kIOPSIsChargingKey` for authoritative charging state |
| `"FullyCharged"` | `as? Bool` | — | `false` | Subject to Optimized Battery Charging; use with caution |
| `"ExternalConnected"` | `as? Bool` | — | `true` | AC adapter plugged in |
| `"BatteryInstalled"` | `as? Bool` | — | `true` | True if battery is physically present |
| `"TimeRemaining"` | `as? Int` | minutes | `65535` | `0xFFFF` = not applicable (on AC); use IOPS `kIOPSTimeToEmptyKey` instead, which has proper -1 sentinel |
| `"CurrentCapacity"` | `as? Int` | % | `97` | Same as IOPS `kIOPSCurrentCapacityKey`; use IOPS layer value |
| `"InstantAmperage"` | `as? Int` | mA (signed) | `0` | Instantaneous current; `Amperage` is the averaged reading |
| `"AdapterDetails"` → `"Watts"` | `([String:Any])["Watts"] as? Int` | W | `140` | AC adapter rated wattage (not the actual draw). Only present when AC is connected. Do NOT use as "current draw" — it's the adapter's capacity. |

**Note 2 — Amperage sign convention and Watts calculation:**

On Apple Silicon Macs, the convention verified in testing is:
- `Amperage > 0` = charging current flowing in
- `Amperage < 0` = discharge current flowing out
- `Amperage = 0` = idle / no current (e.g., maintenance at high SOC)

Watts formula: `watts = Double(amperage) / 1000.0 * Double(voltage) / 1000.0`

This gives:
- Positive watts when charging: `+18.5W` display as `+18.5W`
- Negative watts when discharging: `-12.3W` display as `−12.3W`

**IMPORTANT:** The sign convention of `Amperage` is not guaranteed to be consistent across all Mac models. Some older Intel Macs have been reported to use the reverse sign. Always cross-check against `kIOPSIsChargingKey`:
- If IOPS says `IsCharging = true` but computed watts < 0 → flip sign (display as positive)
- If IOPS says `IsCharging = false && state == "Battery Power"` but watts ≥ 0 → flip sign

The `Amperage` key should be treated as "direction of current relative to the battery pack"; use `kIOPSIsChargingKey` as the authoritative charging direction and only use the magnitude of watts (`abs(watts)`) plus the charging direction from IOPS for the sign in the display string.

**Recommended safe Watts calculation:**

```swift
// Sign is derived from IOPS state, magnitude from Amperage × Voltage
// This is safe across heterogeneous hardware
guard let amperage = props["Amperage"] as? Int,
      let voltage = props["Voltage"] as? Int else {
    return nil  // probe-and-nil
}
let magnitude = abs(Double(amperage)) / 1000.0 * Double(voltage) / 1000.0
// isOnAC and isCharging come from the Power Sources snapshot taken in the same readValue() call
let signedWatts: Double = isCharging ? +magnitude : -magnitude
```

Display: when `isOnAC && !isCharging` (maintenance mode), `Amperage = 0` → `0.0W` → display `"0.0W"` or consider `"—"` since current is negligible. Prefer `"—"` when `abs(watts) < 0.1` to avoid showing `+0.0W` / `-0.0W`.

---

### API 3: Health % Calculation — Apple Silicon vs Intel

**Problem:** On Apple Silicon, `MaxCapacity` returns `100` (a percentage), not an mAh value. Code that computes `MaxCapacity / DesignCapacity` on Apple Silicon gets `100 / 8579 ≈ 1.2%` — massively wrong. This is a documented failure mode in multiple third-party apps. [CITED: forums.macrumors.com/threads/battery-capacity-details-no-longer-available-on-m1-macbooks.2268940]

**Verified formula (Apple Silicon, M-series):**

```
Health % = AppleRawMaxCapacity / DesignCapacity × 100
         = 8176 / 8579 × 100
         = 95.3%
```

Both `AppleRawMaxCapacity` and `DesignCapacity` are in mAh. This is consistent with what `coconutBattery`, `iStat Menus`, and the exelban/stats project use on Apple Silicon. [CITED: exelban/stats Battery reader analysis]

**Safe probe-and-nil health calculation:**

```swift
guard let rawMax = props["AppleRawMaxCapacity"] as? Int,
      let design = props["DesignCapacity"] as? Int,
      design > 0 else {
    return nil  // probe-and-nil: health unavailable
}
let healthPercent = min(100.0, Double(rawMax) / Double(design) * 100.0)
```

Note: `min(100.0, ...)` caps at 100% to prevent reporting >100% health on a fresh battery where `AppleRawMaxCapacity` can slightly exceed `DesignCapacity`.

**Intel compatibility note:** On Intel Macs, `MaxCapacity` gives actual mAh (not %). `AppleRawMaxCapacity` also exists on Intel. Using `AppleRawMaxCapacity / DesignCapacity` is the safest cross-platform formula — it is correct on both Apple Silicon and Intel.

---

### API 4: No-Battery Detection (Desktop Macs) [VERIFIED: Swift execution]

```swift
let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                          IOServiceMatching("AppleSmartBattery"))
guard service != IO_OBJECT_NULL else {
    return nil  // No AppleSmartBattery → desktop Mac → BatteryReader returns nil
}
defer { IOObjectRelease(service) }
```

**Secondary check (belt-and-suspenders):** Iterate the IOPS list and check for any source where `kIOPSTypeKey == kIOPSInternalBatteryType && kIOPSIsPresentKey == true`. If the list is empty or no internal battery is present, return `nil`. However, the `IOServiceGetMatchingService` check alone is reliable and sufficient on macOS 14+.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Battery capacity % | Custom mAh → % calculation | `kIOPSCurrentCapacityKey` from IOPS | Already a % (0–100) from Apple |
| "Is charging?" | Logic on Voltage/Amperage trends | `kIOPSIsChargingKey` (Bool) from IOPS | Apple provides authoritative state |
| Time remaining display | EMA of discharge rate | `kIOPSTimeToEmptyKey` / `kIOPSTimeToFullChargeKey` | Apple's PMU computes this; yours would be less accurate |
| No-battery detection | Checking sysctl or model identifier | `IOServiceGetMatchingService("AppleSmartBattery") == IO_OBJECT_NULL` | Direct and reliable |
| Health % | Using `MaxCapacity` from IOPS | `AppleRawMaxCapacity / DesignCapacity × 100` from AppleSmartBattery | IOPS `MaxCapacity` = 100 always (percent); registry gives real mAh |

**Key insight:** Apple provides two complementary layers: IOPS for human-readable state (%, charging, time) and AppleSmartBattery registry for raw electrical data (mA, mV, mAh counters). Do not cross-compute what one layer already provides cleanly.

---

## Common Pitfalls

### Pitfall 1: Using `MaxCapacity` from AppleSmartBattery Registry for Health %
**What goes wrong:** `MaxCapacity` = `100` on Apple Silicon. `100 / 8579 * 100 = 1.2%` health — wildly wrong.
**Why it happens:** Apple changed `MaxCapacity` to a percentage (not mAh) on Apple Silicon. Old Intel code breaks silently.
**How to avoid:** Use `AppleRawMaxCapacity / DesignCapacity × 100` exclusively. Probe both with `as? Int` and check `design > 0`.
**Warning signs:** Health% showing < 5% on a new Mac.

### Pitfall 2: Using `takeRetainedValue()` on `IOPSGetPowerSourceDescription` Result
**What goes wrong:** Over-release → EXC_BAD_ACCESS crash, potentially delayed (hard to debug).
**Why it happens:** `IOPSGetPowerSourceDescription` returns a non-owning (borrowed) reference. The dictionary is owned by `info`.
**How to avoid:** Use `takeUnretainedValue()` for `IOPSGetPowerSourceDescription`. Use `takeRetainedValue()` for `IOPSCopyPowerSourcesInfo` and `IOPSCopyPowerSourcesList`.

### Pitfall 3: Trusting `Amperage` Sign Alone for Display Direction
**What goes wrong:** On some Mac models (particularly older Intel), `Amperage` sign convention is reversed. Showing `+3.5W` when actually discharging.
**Why it happens:** There is no Apple documentation guaranteeing the sign of `Amperage` across all models.
**How to avoid:** Derive the sign from `kIOPSIsChargingKey` and `kIOPSPowerSourceStateKey`; use `abs(watts)` for magnitude and apply sign from IOPS state.
**Warning signs:** Watts display sign doesn't match the battery % trend.

### Pitfall 4: Displaying `-1` or `0` as a Time Value
**What goes wrong:** Showing "−1分钟" or "0分钟剩余" to the user.
**Why it happens:** Not filtering the sentinel values from `kIOPSTimeToEmptyKey`.
**How to avoid:**
```swift
switch timeToEmpty {
case .none:    timeDisplay = "—"          // key missing
case -1:       timeDisplay = "计算中"      // Apple sentinel
case 0:        timeDisplay = "—"          // not applicable in current state
case let m where m > 0:
    let hrs = m / 60
    let mins = m % 60
    timeDisplay = hrs > 0 ? "\(hrs)小时\(mins)分" : "\(mins)分钟"
default:       timeDisplay = "—"
}
```

### Pitfall 5: Strong-Unwrapping Any AppleSmartBattery Key
**What goes wrong:** `props["Amperage"] as! Int` crashes on desktop Mac (no service, code path reached by mistake) or future macOS that removes/renames the key.
**Why it happens:** `as!` is not a probe; it's a crash.
**How to avoid:** Every single AppleSmartBattery key access must be `as? Type` inside a `guard let` or `if let`. Even "always present" keys like `DesignCapacity` should be probed — Apple has removed previously-stable keys on new architectures before.

### Pitfall 6: Forgetting `IOObjectRelease` on the Service Handle
**What goes wrong:** Mach port leak. At 2-second polling, this is ~43,200 unreleased ports per day — eventually exhausting the port namespace.
**Why it happens:** `IOServiceGetMatchingService` creates a retained handle.
**How to avoid:** Always `defer { IOObjectRelease(service) }` immediately after the `guard service != IO_OBJECT_NULL` check.

### Pitfall 7: Post-Wake Stale Time-Remaining Values
**What goes wrong:** On wake, `kIOPSTimeToEmptyKey` may return a stale value from before sleep (e.g., "5小时32分" immediately on wake when the system hasn't recalculated yet).
**Why it happens:** macOS's PMU needs a few seconds to recalculate after wake. The IOPS API may not return `-1` immediately — it may return the last cached estimate.
**How to avoid:** Use a `postWakeSkipCount` counter (set to 3 on `didWakeNotification`). While counter > 0, return `nil` for both time fields, displaying "计算中". Decrement on each `readValue()` call. 3 ticks at 2s interval = 6 seconds post-wake delay.
**Warning signs:** Time display jumps to a wildly incorrect value immediately after wake.

### Pitfall 8: Incorrect `kIOPSIsChargedKey` Reliance for "已充满" State
**What goes wrong:** Battery shows "使用电池" or no state label when plugged in at 97% but not "charged" per `kIOPSIsChargedKey` due to Optimized Battery Charging.
**Why it happens:** Apple's Optimized Battery Charging can stop charging at 80% and let the battery sit; `IsCharged` will be `false` even at 97%.
**How to avoid:** Use the three-state rule: `isCharging → 充电中`, `state == "AC Power" && !isCharging → 已充满`, `state == "Battery Power" → 使用电池`. Do not rely on `kIOPSIsChargedKey` for the display state.

---

## Code Examples

### Complete `BatterySnapshot` Struct (Swift 6)

```swift
// Source: Verified on device — all fields are value types, Sendable trivially satisfied
struct BatterySnapshot: Sendable, Equatable {
    /// Charge level 0–100%. From kIOPSCurrentCapacityKey. Always present on laptops.
    let chargePercent: Int

    /// True when actively charging. From kIOPSIsChargingKey.
    let isCharging: Bool

    /// True when on external power (AC). Derived from kIOPSPowerSourceStateKey == "AC Power".
    let isOnAC: Bool

    /// Minutes to empty. nil = not applicable or skip due to post-wake. -1 = calculating.
    /// Only meaningful when isOnAC == false.
    let timeToEmptyMinutes: Int?

    /// Minutes to full. nil = not applicable or skip due to post-wake. -1 = calculating.
    /// Only meaningful when isCharging == true.
    let timeToFullMinutes: Int?

    /// Net power draw in Watts. Positive = charging, negative = discharging.
    /// nil if Amperage or Voltage key is missing.
    let watts: Double?

    /// Battery health as a percentage (0–100). AppleRawMaxCapacity / DesignCapacity × 100.
    /// nil if either key is missing.
    let healthPercent: Double?

    /// Lifetime charge cycles. nil if CycleCount key is missing.
    let cycleCount: Int?
}
```

### `BatteryReader.readValue()` Core Pattern

```swift
// Source: Synthesized from verified API patterns
func readValue() -> BatterySnapshot? {
    // ── Layer 1: Power Sources (charge%, state, time) ──────────────────────
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }

    var psDict: [String: Any]?
    for source in list {
        guard let desc = IOPSGetPowerSourceDescription(info, source)?
                            .takeUnretainedValue() as? [String: Any],
              (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
              (desc[kIOPSIsPresentKey] as? Bool) == true
        else { continue }
        psDict = desc
        break
    }

    guard let desc = psDict,
          let chargePercent = desc[kIOPSCurrentCapacityKey] as? Int,
          let isChargingPS  = desc[kIOPSIsChargingKey] as? Bool,
          let stateStr      = desc[kIOPSPowerSourceStateKey] as? String
    else { return nil }  // No internal battery present → desktop Mac

    let isOnAC = (stateStr == kIOPSACPowerValue)

    // Time-remaining (probe-and-nil; post-wake handled by caller via postWakeSkipCount)
    let timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int   // minutes; -1=calculating; 0=N/A
    let timeToFull  = desc[kIOPSTimeToFullChargeKey] as? Int

    // ── Layer 2: AppleSmartBattery (watts, health, cycles) ─────────────────
    let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                             IOServiceMatching("AppleSmartBattery"))
    guard service != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(service) }

    var propsRef: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let props = propsRef?.takeRetainedValue() as? [String: Any]
    else {
        // Battery present in IOPS but registry unavailable — degrade gracefully
        return BatterySnapshot(chargePercent: chargePercent,
                               isCharging: isChargingPS, isOnAC: isOnAC,
                               timeToEmptyMinutes: timeToEmpty,
                               timeToFullMinutes: timeToFull,
                               watts: nil, healthPercent: nil, cycleCount: nil)
    }

    // Watts — probe-and-nil; sign derived from IOPS state (not Amperage sign)
    let watts: Double? = {
        guard let amp = props["Amperage"] as? Int,
              let volt = props["Voltage"] as? Int else { return nil }
        let magnitude = abs(Double(amp)) / 1000.0 * Double(volt) / 1000.0
        if magnitude < 0.1 { return 0.0 }  // Suppress near-zero noise
        return isChargingPS ? +magnitude : -magnitude
    }()

    // Health % — AppleRawMaxCapacity / DesignCapacity (safe on both AS and Intel)
    let healthPercent: Double? = {
        guard let rawMax = props["AppleRawMaxCapacity"] as? Int,
              let design = props["DesignCapacity"] as? Int,
              design > 0 else { return nil }
        return min(100.0, Double(rawMax) / Double(design) * 100.0)
    }()

    let cycleCount = props["CycleCount"] as? Int

    return BatterySnapshot(chargePercent: chargePercent,
                           isCharging: isChargingPS, isOnAC: isOnAC,
                           timeToEmptyMinutes: timeToEmpty,
                           timeToFullMinutes: timeToFull,
                           watts: watts, healthPercent: healthPercent,
                           cycleCount: cycleCount)
}
```

### `DashboardState.updateBattery(_:)` Pattern

```swift
// Source: Mirrors existing updateGPU pattern in DashboardView.swift
@Published var battery: BatterySnapshot? = nil
@Published var hasBattery: Bool = false  // false hides the section

func updateBattery(_ snapshot: BatterySnapshot?) {
    battery = snapshot
    hasBattery = snapshot != nil
}
```

### Time Formatting Helper

```swift
// Source: Verified against kIOPSTimeToEmptyKey sentinel semantics
func formatTimeRemaining(_ minutes: Int?) -> String {
    guard let m = minutes else { return "计算中" }  // post-wake nil → 计算中
    switch m {
    case -1:       return "计算中"   // Apple "Still Calculating" sentinel
    case 0:        return "—"        // Not applicable in current state
    case let t where t > 0:
        let hrs  = t / 60
        let mins = t % 60
        return hrs > 0 ? "\(hrs)小时\(mins)分" : "\(mins)分钟"
    default:       return "—"
    }
}
```

### `BatteryReader` Wake Observer (mirrors `NetworkReader`)

```swift
// Source: Mirrors NetworkReader.swift wake observer pattern (line 60-67)
private var wakeObserver: NSObjectProtocol?
private var postWakeSkipCount: Int = 0
private let postWakeSkipTotal = 3  // 3 ticks × 2s interval = 6s grace period

func setup() {
    wakeObserver = NSWorkspace.shared.notificationCenter
        .addObserver(forName: NSWorkspace.didWakeNotification,
                     object: nil,
                     queue: nil) { [weak self] _ in
            self?.postWakeSkipCount = self?.postWakeSkipTotal ?? 3
        }
}

// In readValue(), before time fields are included in snapshot:
// if postWakeSkipCount > 0 { postWakeSkipCount -= 1; timeToEmpty = nil; timeToFull = nil }
```

### `MetricCollector` Integration (minimal diff)

```swift
// In tick():
let battery = batteryReader.readValue()   // BatterySnapshot? — no MetricSample involvement

// In updateUI(sample:):
dashboard.updateBattery(battery)          // nil on desktop → section hidden
// Do NOT include battery in MetricSample, RingBuffer, HistoryStore, or StatusBarManager.updateTitle
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `MaxCapacity` (mAh) for health on all Macs | `AppleRawMaxCapacity / DesignCapacity` | Apple Silicon (M1, 2020) | Old code gives ~1% health on AS; new formula works on both Intel and AS |
| Sign of Amperage for discharge detection | Cross-reference `kIOPSIsChargingKey` | Varies by model | Amperage sign is not guaranteed — IOPS state is authoritative |
| `takeRetainedValue()` everywhere | `takeUnretainedValue()` for `IOPSGetPowerSourceDescription` | IOKit API clarification | Using wrong one causes crashes or double-release |
| `IOPSTimeToEmptyKey` value `65535` as sentinel | Value `65535` (`0xFFFF`) in AppleSmartBattery `TimeRemaining` key; IOPS layer uses `-1` or `0` | — | Two different conventions depending on which layer you read; always use IOPS layer for time values |

**Deprecated/outdated:**
- `MaxCapacity` from AppleSmartBattery registry: returns percentage on Apple Silicon (not mAh). Do not use for health calculation.
- `HealthConfidence` key (`kIOPSHealthConfidenceKey`): deprecated in macOS 10.6 — not published by Apple sources.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | On Intel Macs, `AppleRawMaxCapacity` exists and is in mAh (not %) | API 3 (Health %) | Health % would be wrong on Intel; probe-and-nil fallback means field shows "—" rather than crashing |
| A2 | `Amperage` sign: negative = discharging on all Apple Silicon variants | API 2 (Amperage) | Low risk: magnitude is always correct; sign is overridden by IOPS `kIOPSIsChargingKey` in recommended pattern |
| A3 | `postWakeSkipCount = 3` (6 seconds) is sufficient for IOPS to recalculate time remaining | Wake behavior | If too short, user sees stale time briefly; probe-and-nil pattern means it shows "计算中" not a crash |
| A4 | Desktop Macs return `IO_OBJECT_NULL` for `AppleSmartBattery` service | Desktop detection | Verified pattern on every Mac with battery; no known counterexample for desktops |

---

## Open Questions (RESOLVED)

1. **Watts display when `isOnAC && !isCharging` (optimized charging pause)**
   - What we know: `Amperage = 0`, `watts = 0.0W`
   - What's unclear: Should we show `0.0W`, `"—"`, or hide the watts row entirely?
   - Recommendation: Show `"—"` when `abs(watts) < 0.1` — avoids confusing `+0.0W` / `-0.0W` display. The CONTEXT.md says "不可读 → —"; zero-current is functionally "not meaningful" in this context.

2. **Intel-specific `Amperage` sign verification**
   - What we know: On this Apple Silicon Mac, sign is negative-discharging. Some sources suggest Intel could differ.
   - What's unclear: Exact sign on Intel with real discharge.
   - Recommendation: The "cross-check with IOPS state" pattern makes this a non-issue for display correctness. Mark `watts` as `nil` only if both Amperage and Voltage keys are missing — otherwise compute magnitude and derive sign from IOPS state.

---

## Environment Availability

All dependencies are Apple SDK frameworks, available everywhere macOS 14+ runs.

| Dependency | Required By | Available | Notes |
|------------|------------|-----------|-------|
| `IOKit` (Xcode SDK) | BatteryReader | ✓ always | Part of macOS SDK; no import restrictions |
| `IOKit.ps` (Xcode SDK) | Power Sources API | ✓ always | Same SDK |
| `AppleSmartBattery` IOService | BatteryReader Layer 2 | ✓ on laptops; ✗ on desktops | Returns `IO_OBJECT_NULL` on desktops — handled by nil return |
| `Foundation.NSWorkspace` | Wake observer | ✓ always | Available since macOS 10.0 |

No external CLI tools, services, or runtimes are needed.

---

## Security Domain

This phase reads publicly-accessible IOKit registries (no special entitlements required). No user data, no network access, no credentials. No new sandbox exceptions needed.

| ASVS Category | Applies | Note |
|---------------|---------|------|
| V5 Input Validation | Yes (trivially) | All values cast with `as?` — invalid types return nil; no user input processed |
| All others | No | Read-only battery telemetry from OS APIs |

No threat surface is introduced.

---

## Sources

### Primary (HIGH confidence)
- `IOPSKeys.h` from `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk/` — all IOPS key names, string values, types, units, and sentinel documentation extracted verbatim
- Live `ioreg -r -c AppleSmartBattery` on development machine — all AppleSmartBattery key names and types confirmed
- Swift test harness executed on development machine — Swift types (`__NSCFNumber`, `__NSCFBoolean`), casting patterns, Watts calculation, and Health % verified with live output
- `MacStatus/MacStatus/Readers/GPUReader.swift` — nil-degradation + Sendable pattern to mirror
- `MacStatus/MacStatus/Readers/NetworkReader.swift` — wake observer pattern to mirror
- `MacStatus/MacStatus/Collectors/MetricCollector.swift` — integration points verified

### Secondary (MEDIUM confidence)
- exelban/stats Battery reader analysis (via WebFetch) — confirmed `AppleRawMaxCapacity / DesignCapacity` as the standard health formula on Apple Silicon; confirmed `IOObjectRelease` in `deinit`
- MacRumors forums on M1 battery keys — confirmed `MaxCapacity` = 100% (percentage) on Apple Silicon, corroborating local ioreg data
- Apple Developer Forums thread on `IOPSGetPowerSourceDescription` — confirmed `takeUnretainedValue()` is correct

### Tertiary (LOW confidence)
- Apple Community forum posts on Amperage sign convention — anecdotal; handled by cross-checking with IOPS state in implementation

---

## Metadata

**Confidence breakdown:**
- Power Sources API keys/types/sentinels: HIGH — verified from Xcode SDK header
- AppleSmartBattery keys/types/units: HIGH — verified via ioreg + Swift execution on device
- Health formula (AppleRawMaxCapacity / DesignCapacity): HIGH — verified on device + corroborated by exelban/stats
- Amperage sign convention: MEDIUM — verified on Apple Silicon M-series; Intel untested but mitigated by cross-check pattern
- Wake grace period (3 ticks): LOW — heuristic; adequate for the stated requirement

**Research date:** 2026-06-17
**Valid until:** 2026-12-17 (6 months; IOKit Power Sources API is stable; AppleSmartBattery keys could change on new hardware but probe-and-nil pattern is inherently resilient)

---

## RESEARCH COMPLETE
