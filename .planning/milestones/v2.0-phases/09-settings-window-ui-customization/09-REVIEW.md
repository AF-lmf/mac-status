---
phase: 09-settings-window-ui-customization
reviewed: 2026-06-17T13:02:30Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - MacStatus/MacStatus/UI/Views/SettingsView.swift
  - MacStatus/MacStatus/Utils/SettingsManager.swift
  - MacStatus/MacStatus/UI/Views/DashboardView.swift
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: clean
---

# Phase 09: Code Review Report (Iteration 3 — Final)

**Reviewed:** 2026-06-17T13:02:30Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** clean

## Summary

本次为第 3 轮（--auto 循环最终轮）复审，聚焦两个问题：

1. **WR-02-REGR 窗口复用修复的正确性**
2. **5 次累计修复是否引入新回归**

同时执行了 `xcodebuild` 全量构建验证（BUILD SUCCEEDED，零编译警告）。

---

## 窗口复用修复验证（WR-02-REGR）

`SettingsWindowManager.showSettings()`（SettingsView.swift 第 371–393 行）的逻辑路径分析：

**首次调用（`self.window == nil`）：**
`if let window` 绑定失败，进入创建路径。新建 `NSWindow`，设置 `isReleasedWhenClosed = false`，调用 `makeKeyAndOrderFront` + `NSApp.activate`，最后赋值 `self.window = window`。路径正确，无问题。

**后续调用（窗口存在，无论是否可见）：**
`if let window` 绑定成功，直接调用 `window.makeKeyAndOrderFront(nil)` + `NSApp.activate`，然后 `return`。`makeKeyAndOrderFront` 在窗口已显示时为 no-op，在窗口已关闭（orderOut）但未释放时会重新显示该窗口——这正是 `isReleasedWhenClosed = false` 所保证的：AppKit 关闭时不会调用额外的 `release`，manager 的强引用保持有效，`self.window` 指针始终指向同一个 `NSWindow` 实例。

**关键不变量验证：**
- `isReleasedWhenClosed = false`（第 385 行）：确保 NSWindow 关闭后不被 AppKit 释放，`self.window` 不会成为悬垂引用。
- 不再有 `.isVisible` 分支：旧版在 `isVisible == false` 时会跳过 `return`、进入创建路径，导致旧窗口泄漏进 `NSApp.windows`。此路径已完全消除。
- 无 use-after-free 风险：`self.window` 是强引用，`isReleasedWhenClosed = false` 保证引用计数不会在 close 时被 AppKit 额外递减。
- `NSApp.windows` 泄漏：整个生命周期只创建一个 `NSWindow` 实例，无泄漏。

**结论：WR-02-REGR 修复逻辑正确。**

---

## 其余 4 项修复的回归检查

**WR-01（ThresholdSubsection.onAppear 阈值规范化）：**
SettingsView.swift 第 235–244 行，`onAppear` 正确读取 `warningBinding`/`criticalBinding` 的当前值，在 `w >= c` 时将 `critical` 推高到 `min(w + 5, 95)`，不影响已有有效阈值。无回归。

**WR-03（foregroundStyle 替换 foregroundColor）：**
全文检查显示所有颜色修饰符均使用 `foregroundStyle`，无遗留 `foregroundColor` 调用。无回归。

**WR-04（List 行高 44pt）：**
SettingsView.swift 第 39 行，`CGFloat(settings.metricOrder.count) * 44`，动态行高计算正确。无回归。

**SettingsManager 累计修复：**
`customThresholds` setter 的 `max(0.0, min(100.0, $0))` 钳位（第 275 行）、`customColors` setter 的 `#RRGGBB` 格式过滤（第 294–299 行）、`loadAll()` 在启动时同步应用相同过滤逻辑（第 437–441 行）均正常。`launchAtLogin` setter 在 SMAppService 调用失败时不写入 UserDefaults 也不更新 backing var（第 236–239 行），UI 自动回弹逻辑完整。无回归。

---

## 构建状态

```
** BUILD SUCCEEDED **
```

编译警告：0（不含 AppIntents 元数据处理器与本代码无关的 note 行）。

---

## 结论

三个文件在本轮复审中无新增 Critical 或 Warning 问题。已知 6 项 INFO 条目（按范围排除）不影响状态判定。所有已修复问题均已验证正确，无回归。

---

_Reviewed: 2026-06-17T13:02:30Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
