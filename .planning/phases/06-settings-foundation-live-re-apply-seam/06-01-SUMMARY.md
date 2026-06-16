---
phase: "06-settings-foundation-live-re-apply-seam"
plan: "01"
subsystem: "settings-foundation"
tags: ["settings", "observable", "migration", "notification", "metric-enum"]
dependency_graph:
  requires: []
  provides:
    - "Metric enum (cpu/memory/network/gpu/battery) with String rawValue"
    - "SettingsManager @MainActor @Observable singleton"
    - "Notification.Name.settingsDidChange + changedKeysUserInfoKey"
    - "SettingsManager.runMigrations() + migrateToV1() versioned migration"
    - "SettingsManager.loadAll() backing var population without notifications"
    - "SettingsManager.postChange(keys:) broadcast helper"
  affects:
    - "MacStatus/MacStatus/Readers/CPUReader.swift (nonisolated init fix)"
tech_stack:
  added: []
  patterns:
    - "@ObservationIgnored private _backing + public computed get/set (SE-0395)"
    - "UserDefaults versioned migration ladder (schemaVersion integer key)"
    - "JSONEncoder/JSONDecoder for nested dictionary persistence"
    - "SMAppService side-effect in setter (launchAtLogin)"
key_files:
  created:
    - "MacStatus/MacStatus/Utils/Metric.swift"
  modified:
    - "MacStatus/MacStatus/Utils/SettingsManager.swift"
    - "MacStatus/MacStatus/Readers/CPUReader.swift"
    - "MacStatus/MacStatus.xcodeproj/project.pbxproj"
decisions:
  - "Default metricOrder = [cpu, gpu, memory, network] — matches v1.0 compact mode layout (C G M N) for zero-behavior-change upgrade guarantee"
  - "enabledMetrics stored as [Metric] (not Set) to preserve ordering; consumers convert to Set<Metric> for O(1) contains queries"
  - "migrateToV1() writes directly to UserDefaults.standard.set — never through property setters, prevents notification storm during init"
  - "loadAll() populates _backing vars directly — never through setters, prevents notifications during init"
  - "customColors setter filters entries where hex is not '#' + 6 chars; invalid entries silently dropped"
  - "threshold setters clamp to max(0, min(100, newValue)) per threat model T-06-01"
  - "CPUReader.init() uses hardcoded 2.0 instead of SettingsManager.shared — MetricCollector owns the unified tick timer"
metrics:
  duration: "~20 minutes"
  completed: "2026-06-16T15:48:00Z"
  tasks_completed: 2
  files_changed: 4
---

# Phase 06 Plan 01: Settings Foundation (Metric + SettingsManager) Summary

**一句话总结：** 建立 `@MainActor @Observable SettingsManager` 单一偏好真源，含版本化 UserDefaults 迁移阶梯、六个新键（metricOrder/enabledMetrics/customThresholds/customColors/launchAtLogin/schemaVersion）、完整变更广播机制，并新增 `Metric` 枚举作为所有指标的稳定 id。

## Tasks Completed

| # | Task | Commit | Key Files |
|---|------|--------|-----------|
| 1 | 创建 Metric 枚举（Metric.swift） | 669b202 | MacStatus/Utils/Metric.swift (new), project.pbxproj |
| 2 | 全面重构 SettingsManager | d20d1f9 | MacStatus/Utils/SettingsManager.swift, MacStatus/Readers/CPUReader.swift |

## What Was Built

### Task 1: Metric.swift

新建 `MacStatus/MacStatus/Utils/Metric.swift`，声明 `Metric` 枚举：

- 遵循 `String, CaseIterable, Sendable`
- 五个 case：`cpu = "cpu"`, `memory = "memory"`, `network = "network"`, `gpu = "gpu"`, `battery = "battery"`
- `battery` 预留，Phase 7 激活；所有 switch 应含此 case 并 break
- rawValue 作为 metricOrder/enabledMetrics/customThresholds/customColors 的键组件
- 已添加至 Xcode project（PBXFileReference + Utils group + Sources build phase）

### Task 2: SettingsManager 全面重构

**类声明改造：**
- `final class SettingsManager: @unchecked Sendable` → `@MainActor @Observable final class SettingsManager`
- 移除 `@unchecked Sendable`；所有访问路径均已在 @MainActor 上（经代码库审计确认）

**属性模式（SE-0395 推荐实现）：**
- 每个属性均有 `@ObservationIgnored private var _backing` + 公开计算属性
- setter 写 UserDefaults 后调用 `postChange(keys:)` 发出 `.settingsDidChange`

**新增键（Keys 枚举）：**
- `schemaVersion`、`metricOrder`、`enabledMetrics`、`customThresholds`、`customColors`、`launchAtLogin`

**版本化迁移阶梯：**
- `runMigrations()` 读取 `schemaVersion`（absent = 0 = 新安装），调用 `migrateToV1()`，写入版本 1
- `migrateToV1()` 为所有键补默认值，直接写 `UserDefaults.standard.set()`，**不经过属性 setter**

**init 顺序：**
```
private init() {
    runMigrations()   // 直接写 UserDefaults，无通知
    loadAll()         // 填充 _backing，无通知
}
```

**输入验证（威胁模型 T-06-01 / T-06-02 / T-06-03）：**
- threshold setters：`max(0, min(100, newValue))`
- `customThresholds` setter：每个 Double 值 clamp 到 0...100
- `customColors` setter：过滤非 `"#RRGGBB"` 格式的条目（`hasPrefix("#") && count == 7`）
- `customThresholds`/`customColors` loadAll()：decode 失败回退到 `[:]`，不 crash

**launchAtLogin 副作用 setter：**
```swift
do {
    if newValue { try SMAppService.mainApp.register() }
    else        { try SMAppService.mainApp.unregister() }
} catch { print("[Settings] launchAtLogin toggle failed: \(error)") }
```

**广播机制：**
- `Notification.Name.settingsDidChange` 定义在 `extension Notification.Name`
- `SettingsManager.changedKeysUserInfoKey = "changedKeys"` 供消费者解包 userInfo
- `postChange(keys:)` 携带 `Set<String>` 变更键集合

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] CPUReader.init() 中的 @MainActor 隔离错误**
- **Found during:** Task 2 build verification
- **Issue:** `CPUReader.init()` 调用了 `SettingsManager.shared.refreshInterval`；在 SettingsManager 成为 `@MainActor` 后，nonisolated 的 `CPUReader.init()` 无法访问 main actor 隔离的属性，Swift 6 严格并发报错：`main actor-isolated property 'refreshInterval' can not be referenced from a nonisolated context`
- **Fix:** 将 `super.init(interval: SettingsManager.shared.refreshInterval)` 改为 `super.init(interval: 2.0)`（与 MemoryReader/GPUReader/NetworkReader 一致的硬编码默认值）。MetricCollector 在 `start()` 中通过 `SettingsManager.shared.refreshInterval` 管理统一的 tick Timer，CPUReader 的内部 Timer 不参与主采样循环。
- **Files modified:** `MacStatus/MacStatus/Readers/CPUReader.swift`
- **Commit:** d20d1f9

## Verification Results

```
xcodebuild BUILD SUCCEEDED (exit 0)
grep "@MainActor @Observable" SettingsManager.swift → line 48 ✓
grep "@unchecked Sendable" SettingsManager.swift → no match ✓
grep "runMigrations|loadAll|postChange|settingsDidChange|changedKeysUserInfoKey" → all present ✓
grep "metricOrder|enabledMetrics|customThresholds|customColors|launchAtLogin" → all present ✓
grep "enum Metric" Metric.swift → line 12 ✓
```

## Known Stubs

None. All properties are fully wired with real UserDefaults read/write paths. No placeholder data flows to UI.

## Threat Flags

No new security-relevant surface introduced beyond what is specified in the plan's threat model.

| Flag | File | Description |
|------|------|-------------|
| (none) | — | All trust boundaries documented in plan's threat model; mitigations applied (T-06-01, T-06-02, T-06-03) |

## Self-Check: PASSED

- [x] `MacStatus/MacStatus/Utils/Metric.swift` exists
- [x] `MacStatus/MacStatus/Utils/SettingsManager.swift` contains `@MainActor @Observable`
- [x] `MacStatus/MacStatus/Utils/SettingsManager.swift` does NOT contain `@unchecked Sendable`
- [x] Commit 669b202 exists (Metric.swift)
- [x] Commit d20d1f9 exists (SettingsManager refactor + CPUReader fix)
- [x] xcodebuild BUILD SUCCEEDED (verified twice)
