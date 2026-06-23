---
phase: "06-settings-foundation-live-re-apply-seam"
plan: "03"
subsystem: "status-bar-seam"
tags: ["statusbar", "nscolor", "hex", "metric-order", "enabled-metrics", "refactor"]
dependency_graph:
  requires:
    - "06-01 (Metric enum, SettingsManager.metricOrder/enabledMetrics/customThresholds/customColors)"
    - "06-02 (MetricCollector.applyNow() drives repaint)"
  provides:
    - "NSColor.init?(hex:) — optional #RRGGBB → NSColor (sRGB), nil on malformed"
    - "NSColor.hexString — NSColor → #RRGGBB string"
    - "StatusBarManager.updateTitle — enabled-set+order conditional segment composition"
    - "StatusBarManager.colorForUsage(_:metric:Metric) — real-time custom thresholds/colors"
    - "StatusBarManager.cpuSegment/memSegment/netSegment/gpuSegment — per-metric helpers"
    - "StatusBarManager.defaultWarning/defaultCritical — fallback threshold helpers"
    - "StatusBarManager.compactSeparator() — space separator for compact mode"
  affects:
    - "MacStatus/MacStatus/UI/StatusBarManager.swift"
    - "MacStatus/MacStatus/Utils/NSColor+Hex.swift"
tech_stack:
  added: []
  patterns:
    - "NSColor(colorSpace:.sRGB components:count:) for hex → NSColor (avoids ambiguous overload)"
    - "Scanner.scanHexInt64 for validated hex parsing (returns nil on failure)"
    - "metricOrder.filter { enabledSet.contains } — O(n) ordered active list"
    - "index > 0 separator guard — no leading/trailing separators"
    - "per-metric segment helpers accepting DisplayMode — replaces 3 mode-specific build*Title methods"
key_files:
  created:
    - "MacStatus/MacStatus/Utils/NSColor+Hex.swift"
  modified:
    - "MacStatus/MacStatus/UI/StatusBarManager.swift"
    - "MacStatus/MacStatus.xcodeproj/project.pbxproj"
decisions:
  - "NSColor(colorSpace:.sRGB components:count:) used instead of NSColor(sRed:green:blue:alpha:) — the latter is not a valid Swift NSColor initializer spelling; colorSpace:components:count: is the correct sRGB constructor"
  - "Compact separator is a plain space with monospacedDigitSystemFont — matches v1.0 buildCompactTitle behavior exactly"
  - "defaultWarning/defaultCritical for .network/.battery return 80.0/90.0 — network has no threshold coloring; battery is Phase 7"
  - "No settingsObserver in StatusBarManager — repaint driven by MetricCollector.applyNow() via 06-02 seam"
metrics:
  duration: "~3 minutes"
  completed: "2026-06-16T17:00:00Z"
  tasks_completed: 2
  files_changed: 3
---

# Phase 06 Plan 03: StatusBarManager Enabled-Set/Order Seam + NSColor+Hex Summary

**一句话总结：** 新建 `NSColor+Hex.swift`（#RRGGBB ↔ NSColor sRGB 互转，nil 容错）并将 `StatusBarManager.updateTitle` 重构为按 `metricOrder+enabledMetrics` 条件循环组合 segment，`colorForUsage` 实时读取 `customThresholds/customColors`，完成 Phase 9 设置 UI 将驱动的外观接缝（SET-07/SET-08）。

## Tasks Completed

| # | Task | Commit | Key Files |
|---|------|--------|-----------|
| 1 | 新建 NSColor+Hex.swift（#RRGGBB ↔ NSColor 互转） | fc39151 | MacStatus/Utils/NSColor+Hex.swift (new), project.pbxproj |
| 2 | StatusBarManager — updateTitle 顺序/启用集接缝 + colorForUsage 实时阈值/配色 | 84657bb | MacStatus/UI/StatusBarManager.swift |

## What Was Built

### Task 1: NSColor+Hex.swift

新建 `MacStatus/MacStatus/Utils/NSColor+Hex.swift`（约 35 行）：

**`NSColor.init?(hex:)`**
- 接受 `"#RRGGBB"` 格式字符串（含或不含 `#` 前缀）
- 去掉前导 `#` 后验证剩余长度 == 6，否则 `return nil`
- `Scanner.scanHexInt64` 解析 `UInt64`，失败时 `return nil`（T-06-06：不 crash）
- `NSColor(colorSpace: .sRGB, components: [r, g, b, 1.0], count: 4)` 初始化（sRGB 色彩空间）
  - 注：`NSColor(sRed:green:blue:alpha:)` 拼写在 Swift/AppKit 不可用；正确 API 是 `colorSpace:components:count:`

**`NSColor.hexString: String`**
- `usingColorSpace(.sRGB)` 转换，失败回退 `"#000000"`
- 读 `redComponent/greenComponent/blueComponent`，格式化为 `"#%02X%02X%02X"`

已添加至 Xcode project（PBXFileReference + Utils group + Sources build phase）。

### Task 2: StatusBarManager 重构

**删除的方法和类型：**
- `private func buildFullTitle(...)` — 已删除
- `private func buildCompactTitle(...)` — 已删除
- `private func buildPercentageTitle(...)` — 已删除
- `private enum MetricType { case cpu, memory, gpu }` — 已删除

**新 `updateTitle` 逻辑：**

```swift
let order   = settings.metricOrder           // [Metric]
let enabled = Set(settings.enabledMetrics)   // Set<Metric> O(1)
let active  = order.filter { enabled.contains($0) }

if active.isEmpty { button.title = "◆"; return }

let sep = mode == .compact ? compactSeparator() : separator()
for (index, metric) in active.enumerated() {
    if index > 0 { result.append(sep) }
    switch metric {
    case .cpu:     result.append(cpuSegment(...))
    case .memory:  result.append(memSegment(...))
    case .network: result.append(netSegment(...))
    case .gpu:     result.append(gpuSegment(...))
    case .battery: break   // Phase 7
    }
}
```

**Per-metric helpers (private)：**
- `cpuSegment(_:mode:)` — "CPU: X%" / "C:X%" / "X%" 三模式
- `memSegment(_:mode:)` — 含 pressure 标签（full 模式）
- `netSegment(_:mode:)` — 网络无阈值着色；percentage 模式显示总吞吐量/s
- `gpuSegment(_:mode:)` — "GPU: X%"/"GPU: N/A" / "G:X%"/"G:--" / "X%"/"--"

**分隔符逻辑：**
- compact 模式：单空格（`monospacedDigitSystemFont`，匹配 v1.0 `buildCompactTitle` 行为）
- full/percentage 模式：`" | "`（与 v1.0 一致）

**新 `colorForUsage` 实现：**

```swift
private func colorForUsage(_ percent: Double, metric: Metric) -> NSColor {
    let settings = SettingsManager.shared
    let warning  = settings.customThresholds[metric.rawValue]?["warning"]  ?? defaultWarning(for: metric)
    let critical = settings.customThresholds[metric.rawValue]?["critical"] ?? defaultCritical(for: metric)
    if percent >= critical {
        if let hex = settings.customColors[metric.rawValue]?["critical"],
           let color = NSColor(hex: hex) { return color }
        return .systemRed
    } else if percent >= warning {
        if let hex = settings.customColors[metric.rawValue]?["warning"],
           let color = NSColor(hex: hex) { return color }
        return .systemOrange
    }
    return .labelColor   // semantic; dark/light 自适应
}
```

**`defaultWarning(for:)` / `defaultCritical(for:)：**`
- `.cpu` → `SettingsManager.shared.cpuWarningThreshold` / `cpuCriticalThreshold`
- `.memory` → `SettingsManager.shared.memoryWarningThreshold` / `memoryCriticalThreshold`
- `.gpu`, others → 80.0 / 90.0

**StatusBarManager 不注册 `.settingsDidChange` observer**：重绘路径为 MetricCollector（06-02）的 observer → `applyNow()` → `updateUI(sample:)` → `updateTitle(...)`。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] NSColor(sRed:green:blue:alpha:) 拼写不存在**
- **Found during:** Task 1 首次构建
- **Issue:** Plan 中描述了 `self.init(sRed:green:blue:alpha:)` 作为 sRGB 初始化器；同样，研究文档中的代码示例也使用了此拼写。但该 initializer 在 AppKit/Swift 中不存在，编译报 `no exact matches in call to initializer`
- **Fix:** 改用 `NSColor(colorSpace: .sRGB, components: [r, g, b, 1.0], count: 4)` —— 这是 AppKit 提供的正确 sRGB 构造路径
- **Files modified:** `MacStatus/MacStatus/Utils/NSColor+Hex.swift`
- **Commit:** fc39151

**2. [Rule 1 - Bug] 类型推断超时：一个复杂的嵌套 CGFloat 表达式**
- **Found during:** Task 1 首次构建
- **Issue:** 原始嵌套表达式 `CGFloat((value >> 16) & 0xFF) / 255.0` 作为参数写在 `self.init(...)` 调用中导致 Swift 编译器类型检查超时
- **Fix:** 拆分为三个独立 `let` 变量（`r`, `g`, `b`）再传入 init
- **Files modified:** `MacStatus/MacStatus/Utils/NSColor+Hex.swift`
- **Commit:** fc39151

## Verification Results

```
xcodebuild BUILD SUCCEEDED (exit 0) — Task 1 后 ✓
xcodebuild BUILD SUCCEEDED (exit 0) — Task 2 后 ✓
grep "metricOrder" StatusBarManager.swift → line 91 ✓
grep "enabledMetrics" StatusBarManager.swift → line 92 ✓
grep "active.isEmpty" StatusBarManager.swift → line 96 ✓
grep "case .battery" StatusBarManager.swift → line 115 ✓
grep "customThresholds" StatusBarManager.swift → lines 272,273 ✓
grep "customColors" StatusBarManager.swift → lines 276,280 ✓
grep "settingsObserver" StatusBarManager.swift → 无输出 ✓
grep "buildFullTitle" StatusBarManager.swift → 无输出 ✓
grep "buildCompactTitle" StatusBarManager.swift → 无输出 ✓
grep "buildPercentageTitle" StatusBarManager.swift → 无输出 ✓
grep "private enum MetricType" StatusBarManager.swift → 无输出 ✓
grep "convenience init?(hex:" NSColor+Hex.swift → line 11 ✓
grep "var hexString: String" NSColor+Hex.swift → line 25 ✓
grep "sRGB" NSColor+Hex.swift → lines 7,19,22,24,26 ✓
```

## Known Stubs

None. `colorForUsage` 完整读取 `customThresholds`/`customColors` 真实数据路径；`NSColor(hex:)` 实现完整。Phase 9 设置 UI 写入 `customThresholds`/`customColors` 后接缝立即生效，无需任何额外改动。

## Threat Flags

No new security-relevant surface beyond plan's threat model.

| Flag | File | Description |
|------|------|-------------|
| (none) | — | T-06-06 (hex 容错解析) 在 NSColor+Hex.swift 完整实现；T-06-07 (threshold clamping) 在 SettingsManager setter 侧（06-01）；T-06-08 (applyNow 幂等) 通过不注册 StatusBarManager observer 保证 |

## Self-Check: PASSED

- [x] `MacStatus/MacStatus/Utils/NSColor+Hex.swift` 存在
- [x] 包含 `convenience init?(hex:`
- [x] 包含 `var hexString: String`
- [x] 包含 `sRGB` 关键字
- [x] `MacStatus/MacStatus/UI/StatusBarManager.swift` 包含 `metricOrder`
- [x] 包含 `enabledMetrics`
- [x] 包含 `active.isEmpty`
- [x] 包含 `case .battery`（Phase 7 占位）
- [x] 包含 `customThresholds`
- [x] 包含 `customColors`
- [x] 不含 `settingsObserver`
- [x] 不含 `buildFullTitle`
- [x] 不含 `buildCompactTitle`
- [x] 不含 `buildPercentageTitle`
- [x] 不含 `private enum MetricType`
- [x] Commit fc39151 存在 (Task 1: NSColor+Hex)
- [x] Commit 84657bb 存在 (Task 2: StatusBarManager refactor)
- [x] xcodebuild BUILD SUCCEEDED（两次验证均通过）
