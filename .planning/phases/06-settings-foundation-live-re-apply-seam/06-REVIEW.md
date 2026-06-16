---
phase: 06-settings-foundation-live-re-apply-seam
reviewed: 2026-06-17T00:00:00Z
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
  warning: 0
  info: 3
  total: 3
status: clean
---

# Phase 06: Code Review Report（迭代 3，最终轮）

**Reviewed:** 2026-06-17
**Depth:** standard
**Files Reviewed:** 7
**Status:** clean（仅剩 3 个 INFO 条目，无 Critical/Warning）

## Summary

本轮为第三次迭代复审（--auto 循环最终轮），重点验证第二轮 WR-01 修复（`updateTitle()` 中所有 active segment 均为 nil 时菜单栏留白）是否正确实现，以及是否引入回归。

**WR-01 修复验证（通过）**

`StatusBarManager.updateTitle()` 第 123-126 行新增的 guard：

```swift
// 所有 active metrics 均返回 nil segment（例如仅含 .battery 时）——
// 回退到占位符，保持"菜单栏永不为空"的不变量。
if result.length == 0 {
    button.title = "◆"
    return
}
button.attributedTitle = result
```

逐项验证：

1. **触发条件正确**：`result.length == 0` 仅在循环体中没有任何 `if let segment` 分支写入内容时成立。当前唯一走此路径的场景是 `active` 全部由 `.battery` 组成（`.battery` case 显式返回 `segment = nil`，不触发 `if let segment`）。条件与意图一致。

2. **不存在回归**：`updateTitle(_:)` 是纯渲染函数，无可变状态副作用（不修改 `lastSample`、`tickCount`、`pendingSamples` 等），early return 在任何路径下均安全。

3. **双重防护覆盖全部空输出路径**：
   - 第 96-99 行：`active.isEmpty` guard — 覆盖"enabledMetrics 为空，或所有启用项均不在 metricOrder 中"的场景
   - 第 123-126 行：`result.length == 0` guard — 覆盖"active 不为空但所有 segment 均为 nil"的场景（当前为仅含 `.battery`）
   二者共同确保"菜单栏永不为空"不变量在所有可达路径下成立。

4. **Phase 7 就绪**：当 `.battery` 在 Phase 7 实现真实 segment 后，`result.length == 0` guard 自然失效（不会执行），行为正确退化。

**其余先前修复保持正确（核查未发现退化）**

- CR-01（Swift 6 MainActor 隔离）：`setupSettingsObserver` 闭包内的 `Task { @MainActor [weak self] in }` 包裹健在，`[weak self]` 内外层均存在。
- CR-02（分隔符逻辑 `firstSegmentWritten`）：标志逻辑未被新 guard 影响。
- WR-02（SMAppService 先调用后持久化）：`launchAtLogin` setter 结构未变。
- WR-03（hexString 分量截断）：`NSColor+Hex.swift` 的 `min/max` 截断逻辑完好。
- WR-04（loadAll 过滤 customColors）：`loadAll()` 中的过滤路径未被改动。

本轮全部 7 个文件未发现任何 Critical 或 Warning 级别新问题。

---

## Info

以下三个 INFO 条目延续自第一轮审查，属于已记录的已知项，不阻塞本阶段交付。

### IN-01: `CPUReader.setup()` 重置 `previousInfo` 但未重置 `hasPrevious`

**File:** `MacStatus/MacStatus/Readers/CPUReader.swift:40-42`

**Issue:**
```swift
override func setup() {
    previousInfo = host_cpu_load_info()
    // hasPrevious 未重置为 false
}
```
若 `MetricCollector` 未来在 stop/restart 循环中再次调用 `cpuReader.setup()`，`hasPrevious` 仍为 `true`，首次 `readValue()` 将以归零的 `previousInfo` 计算 delta，产生虚高读数（接近 100%）。当前代码路径仅调用一次 `setup()`，暂无实际影响。

**Fix:**
```swift
override func setup() {
    previousInfo = host_cpu_load_info()
    hasPrevious = false
}
```

---

### IN-02: `SettingsView` 版本号硬编码 + "清除历史"按钮永久禁用

**File:** `MacStatus/MacStatus/UI/Views/SettingsView.swift:69-73, 80`

**Issue:**
- `"v1.0 (M002)"` 硬编码，每次版本升级需人工同步，易遗漏
- "清除历史"按钮永久 `.disabled(true)` 并附有 `// TODO` 注释，向用户暴露未完成的功能入口

**Fix:**
```swift
// 版本号改为读取 Bundle
Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")

// 清除历史：隐藏直到 MetricCollector.purgeAll() 实现
// 可使用 .hidden() 或直接移除该 Button，待对应 Phase 实现后再恢复
```

---

### IN-03: `defaultWarning(for:)` / `defaultCritical(for:)` 中的 `default` 分支为死代码

**File:** `MacStatus/MacStatus/UI/StatusBarManager.swift:295-310`

**Issue:**
`colorForUsage(_:metric:)` 仅由 `cpuSegment`、`memSegment`、`gpuSegment` 调用；`netSegment` 固定返回 `.labelColor`，`.battery` 返回 `nil` segment 不进入此方法。`default` 分支（覆盖 `.network` 和 `.battery`）永远不可达，且会屏蔽编译器对未来新增 metric 的穷举警告（exhaustiveness warning）。

**Fix:**
将 `default` 替换为具名 case：
```swift
private func defaultWarning(for metric: Metric) -> Double {
    switch metric {
    case .cpu:     return SettingsManager.shared.cpuWarningThreshold
    case .memory:  return SettingsManager.shared.memoryWarningThreshold
    case .gpu:     return 80.0
    case .network: return 80.0  // 当前不被调用；明确列出以便 Phase 7 检查
    case .battery: return 80.0  // 同上
    }
}
```

---

_Reviewed: 2026-06-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
