---
phase: 06-settings-foundation-live-re-apply-seam
reviewed: 2026-06-17T08:00:00Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - MacStatus/MacStatus/Utils/Metric.swift
  - MacStatus/MacStatus/Utils/SettingsManager.swift
  - MacStatus/MacStatus/Utils/NSColor+Hex.swift
  - MacStatus/MacStatus/Collectors/MetricCollector.swift
  - MacStatus/MacStatus/UI/Views/SettingsView.swift
  - MacStatus/MacStatus/UI/StatusBarManager.swift
  - MacStatus/MacStatus/Readers/CPUReader.swift
findings:
  critical: 0
  warning: 1
  info: 3
  total: 4
status: issues_found
---

# Phase 06: Code Review Report（第二轮，迭代 2）

**Reviewed:** 2026-06-17
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

本轮为第一轮修复后的重审（re-review）。首轮 6 个 in-scope findings（CR-01、CR-02、WR-01、WR-02、WR-03、WR-04）**全部已正确修复**，均为实质性修复而非表面应付：

- **CR-01**：`setupSettingsObserver()` 观察者闭包现已包裹 `Task { @MainActor [weak self] in ... }`，Swift 6 隔离违规已消除。`changedKeys`（`Set<String>: Sendable`）的捕获方式正确；`[weak self]` 在内外两层均存在，不产生 retain cycle。
- **CR-02**：`firstSegmentWritten` 标志正确替代了原先基于 index 的无条件分隔符追加逻辑，`case .battery: segment = nil` 路径不写入任何内容（含分隔符）；all-disabled 路径由第 96 行的 `active.isEmpty` guard 覆盖；单 metric 路径不产生前置分隔符。
- **WR-01**：四个阈值均已改用 `defaults.object(forKey:) as? Double`，合法的 `0.0` 值不再被误判为"未设置"并静默重置。
- **WR-02**：`SMAppService.register()` / `unregister()` 现在在 UserDefaults 写入之前调用，`catch` 分支不写入任何状态，`@Observable` 的 SwiftUI 绑定可自动回弹到旧值。
- **WR-03**：`hexString` 已用 `min(255, max(0, Int(...)))` 对 r/g/b 分量截断，Display P3 宽色域颜色不再产生超过 7 字符的非法输出。
- **WR-04**：`loadAll()` 中的 `_customColors` 赋值路径已复用 setter 的 `hasPrefix("#") && count == 7` 过滤逻辑。

本轮发现 1 个新 **WARNING** 级问题（CR-02 修复引入的残余边界案例）和 3 个延续自首轮的 **INFO** 级问题（IN-01、IN-02、IN-03）。

---

## Warnings

### WR-01: `updateTitle()` 在所有 active metric 均产生 nil segment 时输出空字符串而非占位符

**File:** `MacStatus/MacStatus/UI/StatusBarManager.swift:96-121`

**Issue:**

`active.isEmpty` 保护（第 96 行）检查的是"启用列表为空"，而非"所有启用 metric 的 segment 均为 nil"。目前只有 `.battery` case 返回 `segment = nil`；若 `enabledMetrics` 被设置为仅含 `.battery`（`[.battery]`），则：

1. `active = [.battery]`，不为空，第 96 行 guard 不触发
2. 循环运行一次，`.battery` → `segment = nil` → `if let segment` 跳过
3. `result` 仍为空 `NSMutableAttributedString`
4. `button.attributedTitle = result` → 菜单栏显示空白，违反注释中"never leaves the status bar blank"的约束

虽然 UI（`SettingsView`）目前不提供直接将 `enabledMetrics` 设置为仅含 `.battery` 的操作路径，但 `enabledMetrics` setter（第 203-209 行）接受任意 `[Metric]` 数组，且 Phase 7 激活 `.battery` 后该场景概率增大。

此问题由 CR-02 修复引入：原始代码在进入循环体之前追加分隔符，行为不同，但 `firstSegmentWritten` 方案未将"result 最终为空"纳入防护。

**Fix:**
在 `button.attributedTitle = result` 之前增加空串检测，回退到占位符：

```swift
if result.length == 0 {
    button.title = "◆"
} else {
    button.attributedTitle = result
}
```

或者更防御性地，将占位符逻辑移至 `active.isEmpty` 检查处改为检查最终 result：

```swift
// 将现有 if active.isEmpty { button.title = "◆"; return } 保留，
// 并在循环结束后增加：
if result.length == 0 {
    button.title = "◆"
    return
}
button.attributedTitle = result
```

---

## Info

### IN-01: `CPUReader.setup()` 重置 `previousInfo` 但不重置 `hasPrevious`（延续自首轮）

**File:** `MacStatus/MacStatus/Readers/CPUReader.swift:40-42`

**Issue:**
```swift
override func setup() {
    previousInfo = host_cpu_load_info()
    // hasPrevious 未重置
}
```
若 `MetricCollector` 将来在 stop/restart 循环中再次调用 `cpuReader.setup()`，`hasPrevious` 仍为 `true`，首次 `readValue()` 将以归零的 `previousInfo` 计算 delta，产生虚高的 CPU 读数（接近 100%）。当前只调用一次，暂无实际影响。

**Fix:**
```swift
override func setup() {
    previousInfo = host_cpu_load_info()
    hasPrevious = false
}
```

---

### IN-02: `SettingsView` 版本号硬编码 + "清除历史"按钮未完成（延续自首轮）

**File:** `MacStatus/MacStatus/UI/Views/SettingsView.swift:69-73, 80`

**Issue:**
- `"v1.0 (M002)"` 硬编码，每次版本更新需人工同步
- "清除历史"按钮永久 `.disabled(true)` 且附有 `// TODO` 注释，向用户暴露未完成的功能入口

**Fix:**
```swift
// 版本号
Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")

// 清除历史：隐藏直到 MetricCollector.purgeAll() 实现
// 使用 .hidden() 或直接移除该 Button
```

---

### IN-03: `defaultWarning(for:)` / `defaultCritical(for:)` 中的 `default` 分支为死代码（延续自首轮）

**File:** `MacStatus/MacStatus/UI/StatusBarManager.swift:289-305`

**Issue:**
`colorForUsage(_:metric:)` 仅由 `cpuSegment`、`memSegment`、`gpuSegment` 调用；`netSegment` 固定返回 `.labelColor`，`.battery` 返回 `nil` segment 从不进入该方法。`default` 分支（覆盖 `.network` 和 `.battery`）永远无法到达，且会屏蔽未来新增 metric 时编译器的穷举警告。

**Fix:**
将 `default` 替换为具名 case：
```swift
private func defaultWarning(for metric: Metric) -> Double {
    switch metric {
    case .cpu:     return SettingsManager.shared.cpuWarningThreshold
    case .memory:  return SettingsManager.shared.memoryWarningThreshold
    case .gpu:     return 80.0
    case .network: return 80.0  // 当前不使用；明确列出以便 Phase 7 检查
    case .battery: return 80.0  // 同上
    }
}
```

---

_Reviewed: 2026-06-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
