---
phase: 09-settings-window-ui-customization
reviewed: 2026-06-17T13:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - MacStatus/MacStatus/Utils/SettingsManager.swift
  - MacStatus/MacStatus/UI/Views/SettingsView.swift
  - MacStatus/MacStatus/UI/Views/DashboardView.swift
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 09: Code Review Report（第 2 次迭代）

**Reviewed:** 2026-06-17T13:00:00Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

本次为 WR-01 ~ WR-04 四项修复的再审（iteration 2）。构建结果：`BUILD SUCCEEDED`，针对这三个文件零编译警告。

各项修复确认情况：

- **WR-01（onAppear 阈值归一化）：** 修复真实有效。`onAppear` 仅在 `w >= c` 时执行推高 critical 的操作，不破坏已有有效的 `customThresholds`（`w < c` 时条件不成立，直接跳过）。写入路径正确经过 `SettingsManager.customThresholds` setter（clamp + postChange）。不存在震荡风险：`onAppear` 写入 critical 后，`onChange(of: criticalBinding)` 的条件 `newCritical <= warningBinding` 为 false，handler 不执行；反向路径同理。`onAppear` 每次视图层级实例化只触发一次，无循环触发问题。

- **WR-03（.foregroundStyle(Color.accentColor) 替换）：** 三个文件中零残留 `.foregroundColor` SwiftUI 修饰符，完全替换正确。`StatusBarManager.swift` 中的 `.foregroundColor` 是 `NSAttributedString.Key`，属于 AppKit 用法，不适用。

- **WR-04（List 行高 44pt）：** `.frame(height: CGFloat(settings.metricOrder.count) * 44)` 及 `.listStyle(.plain)` 均存在，List 不会折叠。`metricOrder` 在正常使用路径下数量始终 >= 1，零高问题不可到达。

- **WR-02（isReleasedWhenClosed = false）：** 该行确已写入。**但引入了一个新的回归**，见下方 WR-02-REGR。

---

## Warnings

### WR-02-REGR: showSettings() 窗口复用逻辑与 isReleasedWhenClosed=false 不兼容，导致每次重新打开都泄漏 NSWindow

**File:** `MacStatus/MacStatus/UI/Views/SettingsView.swift:371-390`

**Issue:**

`showSettings()` 的复用判断条件为：

```swift
if let window, window.isVisible {
    window.makeKeyAndOrderFront(nil)
    ...
    return
}
```

当用户关闭设置窗口后：`self.window != nil`（ARC 仍持有强引用），但 `window.isVisible == false`。因此条件失败，代码继续执行并创建**全新**的 `NSWindow + NSHostingController`，然后用 `self.window = window`（局部新变量）覆盖了 `self.window`（持有旧窗口的强引用）。

**在 WR-02 修复前**（`isReleasedWhenClosed = true`，AppKit 默认值），AppKit 在用户关闭窗口时会额外发送 `release`，使窗口在 ARC 管理的强引用之外额外减一次引用计数，关闭后窗口通常已被系统内部释放——旧的 `self.window` 覆写相对无害。

**在 WR-02 修复后**（`isReleasedWhenClosed = false`），AppKit 不再在 `close()` 时额外 release，窗口的生命周期完全由 Swift ARC 管理。当 `self.window` 被新窗口覆盖，旧窗口的 Swift 强引用计数归零，但 **AppKit 的 `NSApp.windows` 窗口列表仍持有已关闭窗口的内部引用**，直到调用 `window.close()` 才会将其从列表中移除。由于旧窗口从未被显式 `close()`，它以"已关闭但未从窗口系统注销"的状态残留在 `NSApp.windows` 中。每次用户关闭并重新打开设置面板，这一资源泄漏重复发生。

**根本原因：** `isReleasedWhenClosed = false` 的正确使用模式是**复用**同一个 NSWindow 实例（每次 `makeKeyAndOrderFront` 重新显示），而不是每次创建新实例。

**Fix:** 将复用条件从 `window.isVisible` 改为仅检查窗口实例是否存在（`if let window`）；已有实例时直接唤起前台，无需重建：

```swift
func showSettings() {
    if let window {
        // 复用已有窗口：无论是否可见，直接唤起前台
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let settingsView = SettingsView()
    let hostingController = NSHostingController(rootView: settingsView)
    let window = NSWindow(contentViewController: hostingController)
    window.isReleasedWhenClosed = false
    window.title = "MacStatus 偏好设置"
    window.styleMask = [.titled, .closable]
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    self.window = window
}
```

此修复同时实现了 WR-02 的真正意图：单一 NSWindow 实例在整个应用生命周期中被复用，而非每次重新打开时重建。

---

_Reviewed: 2026-06-17T13:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
