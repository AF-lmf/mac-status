---
phase: 09-settings-window-ui-customization
fixed_at: 2026-06-17T13:30:00Z
review_path: .planning/phases/09-settings-window-ui-customization/09-REVIEW.md
iteration: 2
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 09：代码审查修复报告

**修复时间：** 2026-06-17
**源审查文件：** `.planning/phases/09-settings-window-ui-customization/09-REVIEW.md`
**迭代轮次：** 2

**概要：**
- 范围内发现：5（WR-01 ~ WR-04 + WR-02-REGR，不含 Info 级别）
- 已修复：5（迭代 1：4 项；迭代 2：1 项）
- 已跳过：0

构建验证：两轮修复完成后执行 `xcodebuild` 构建，结果均为 **BUILD SUCCEEDED**，无编译错误，无因本次修改新增的 deprecated 警告。

---

## 已修复问题

### WR-01：ThresholdSubsection 初始加载时可能显示 warning >= critical 的倒置状态

**修改文件：** `MacStatus/MacStatus/UI/Views/SettingsView.swift`
**提交：** `f524aa2`（迭代 1）
**修复内容：**
在 `ThresholdSubsection.body` 的 `VStack` 末尾添加 `.onAppear` 修正器。视图首次出现时读取 `warningBinding` 和 `criticalBinding` 的当前值，若检测到 `w >= c`（倒置状态），将 `criticalBinding.wrappedValue` 推高到 `min(w + 5, 95)`，建立有效的 warning < critical 关系。该操作通过 `criticalBinding` 的 setter 写入 `customThresholds`，因此仅在实际需要纠正时才写入，不影响已有合法阈值条目（非破坏性）。`onChange` 约束仅在用户主动拖动时触发，本 `.onAppear` 补全了视图初始化路径的防护。

---

### WR-02：SettingsWindowManager 未将 NSWindow.isReleasedWhenClosed 设为 false

**修改文件：** `MacStatus/MacStatus/UI/Views/SettingsView.swift`
**提交：** `0c03256`（迭代 1）
**修复内容：**
在 `showSettings()` 中 `NSWindow(contentViewController:)` 初始化之后、设置 `title` 之前，插入 `window.isReleasedWhenClosed = false`。编程创建的 `NSWindow` 默认值为 `true`，AppKit 关闭时会额外发送 `-release`；`SettingsWindowManager` 通过 `var window: NSWindow?` 持有强引用并在下次打开时复用，若未设置此属性则处于未定义行为区域，在特定 macOS 版本或内存压力下可能导致 use-after-release。

---

### WR-02-REGR：showSettings() 窗口复用逻辑与 isReleasedWhenClosed=false 不兼容，导致每次重新打开都泄漏 NSWindow

**修改文件：** `MacStatus/MacStatus/UI/Views/SettingsView.swift`
**提交：** `52722fb`（迭代 2）
**修复内容：**
将 `showSettings()` 的复用判断条件由 `if let window, window.isVisible` 改为 `if let window`，彻底移除 `.isVisible` 检查。

**问题根源：** `isReleasedWhenClosed = false` 后，用户关闭设置窗口时 `self.window != nil` 但 `window.isVisible == false`。旧代码因此跳过复用分支，继续执行创建路径，生成全新的 `NSWindow + NSHostingController` 并用 `self.window = window`（新窗口局部变量）覆写 `self.window`（旧窗口强引用）。旧窗口从未被显式 `close()`，以"已关闭但未从窗口系统注销"的状态永久残留在 `NSApp.windows`，每次关闭→重新打开循环累积一个泄漏对象。

**修复后行为：** 只要 `self.window` 持有实例（无论窗口是否可见），均直接调用 `makeKeyAndOrderFront` 重新显示，实现 `isReleasedWhenClosed = false` 的正确复用语义——整个应用生命周期共享同一个 NSWindow 实例。

---

### WR-03：两处 `.foregroundColor(.accentColor)` 使用已废弃 API

**修改文件：** `MacStatus/MacStatus/UI/Views/SettingsView.swift`
**提交：** `8866552`（迭代 1）
**修复内容：**
将文件中全部两处 `.foregroundColor(.accentColor)` 替换为 `.foregroundStyle(Color.accentColor)`：
- 第 232 行（`ThresholdSubsection` 的"恢复默认"按钮）
- 第 318 行（`ColorSubsection` 的"恢复默认"按钮）

`.foregroundColor(_:)` 在 macOS 14（项目 target）中已标记为 deprecated。`Color` 符合 `ShapeStyle` 协议，`Color.accentColor` 写法在 macOS 14 上可正常编译，无需降级回已废弃 API。使用 `replace_all` 一次性替换两处，确保一致性。

---

### WR-04：List 固定行高 36pt 可能导致行内容被裁切

**修改文件：** `MacStatus/MacStatus/UI/Views/SettingsView.swift`
**提交：** `70de3da`（迭代 1）
**修复内容：**
将第 39 行 List 高度乘数从 `36` 提高到 `44`，并添加注释说明此为 Dynamic Type 适配。`MetricOrderRow` 包含 `Image + Text + Spacer + Toggle`，在辅助功能大字体设置下行高可超过 36pt，末行会被裁切或出现不必要的内部滚动。44pt 对应 Apple 人机界面指南推荐的最小触摸目标高度，可容纳更大字体。List 仍保持显式 `frame(height:)` 约束，不会折叠。

---

_修复时间：2026-06-17_
_修复工具：Claude (gsd-code-fixer)_
_迭代轮次：2_
