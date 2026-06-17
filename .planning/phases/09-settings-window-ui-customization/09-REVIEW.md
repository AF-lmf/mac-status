---
phase: 09-settings-window-ui-customization
reviewed: 2026-06-17T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - MacStatus/MacStatus/Utils/SettingsManager.swift
  - MacStatus/MacStatus/UI/Views/SettingsView.swift
  - MacStatus/MacStatus/UI/Views/DashboardView.swift
findings:
  critical: 0
  warning: 4
  info: 6
  total: 10
status: issues_found
---

# Phase 09: Code Review Report

**Reviewed:** 2026-06-17
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

本次审查涵盖 Phase 9 设置窗口 UI 定制化的三个核心文件：`SettingsManager.swift`（新增 `showBatterySection` / `showProcessSection` 两个可观察属性）、`SettingsView.swift`（`ThresholdSubsection` / `ColorSubsection` / `MetricOrderRow` 子组件，以及 `SettingsWindowManager`），以及 `DashboardView.swift`（利用新开关门控电池和进程区块）。

整体架构正确：`@ObservationIgnored` 背后的计算属性 setter 模式（无 `didSet`）、`@Bindable` 绑定方式、computed Binding 定义为 struct 计算属性（而非 body 内局部 Binding）、List.onMove 无 EditMode 等均符合 Swift 6 + SwiftUI / macOS 14 的规范。

**关键正面确认：**
- `enabledBinding` 的 add/remove 逻辑无重复、无顺序丢失。
- `thresholdBinding` 的 `onChange` warning↔critical 约束逻辑：经过边界值全路径追踪，确认不会产生死循环或震荡（warning 推高 critical / critical 拉低 warning 的单向推拉机制，终止条件明确）。
- `DashboardView` 在 body 中直接读取 `SettingsManager.shared` 是正确的 `@Observable` 追踪模式，`showBatterySection`/`showProcessSection` 改动可正确触发重渲染。
- `showBatterySection`/`showProcessSection` 的默认值逻辑（`object(forKey:)==nil → true`）对新安装和现有用户均正确，无需写入 `migrateToV1()`。
- `ColorPicker(supportsOpacity: false)` 正确；`NSColor(hex:)` 解析容错；`NSColor(hex: defaultHex)!` 强制解包安全（对硬编码合法字符串）。

发现 0 个 BLOCKER，4 个 WARNING，6 个 INFO。

---

## Warnings

### WR-01: ThresholdSubsection 初始加载时可能显示 warning > critical 的倒置状态

**File:** `MacStatus/MacStatus/UI/Views/SettingsView.swift:183-199`

**Issue:** `ThresholdSubsection` 的 `defaultWarning` / `defaultCritical` 读取旧全局键（`settings.cpuWarningThreshold` / `settings.cpuCriticalThreshold`）作为"迁移种子"回退值。如果旧版用户将这两个全局键设置为 `warning > critical` 的非法组合（例如 `cpuWarning=80, cpuCritical=70`），而 `customThresholds["cpu"]` 尚不存在（用户从未打开过新版设置面板），则 `warningBinding.wrappedValue = 80`、`criticalBinding.wrappedValue = 70`，Slider 会显示 80% 警告 / 70% 严重的视觉矛盾状态。`onChange` 约束只在用户主动拖动 Slider 时才触发，不会在视图出现时自动修复这一初始状态。

**Fix:** 在 `ThresholdSubsection.body` 的 `.onAppear` 中校正初始倒置状态：

```swift
.onAppear {
    let w = warningBinding.wrappedValue
    let c = criticalBinding.wrappedValue
    if w >= c {
        // 强制写入 customThresholds 以建立有效初始状态
        criticalBinding.wrappedValue = min(w + 5, 95)
    }
}
```

---

### WR-02: SettingsWindowManager 未将 NSWindow.isReleasedWhenClosed 设为 false

**File:** `MacStatus/MacStatus/UI/Views/SettingsView.swift:371-378`

**Issue:** `SettingsWindowManager.showSettings()` 用编程方式创建 `NSWindow`，未设置 `window.isReleasedWhenClosed = false`。根据 Apple 文档，编程创建的 `NSWindow` 默认 `isReleasedWhenClosed = true`，即关闭窗口时 AppKit 会对其发送额外的 `-release` 消息。尽管 Swift ARC 通过 `var window: NSWindow?` 持有强引用通常能防止实际崩溃，但这违反了 `NSWindow` 的文档约定，属于未定义行为区域，在某些 macOS 版本或系统内存压力下可能导致 use-after-release。

**Fix:**

```swift
let window = NSWindow(contentViewController: hostingController)
window.isReleasedWhenClosed = false   // 添加此行
window.title = "MacStatus 偏好设置"
window.styleMask = [.titled, .closable]
```

---

### WR-03: 两处 `.foregroundColor(.accentColor)` 使用已废弃 API

**File:** `MacStatus/MacStatus/UI/Views/SettingsView.swift:232, 308`

**Issue:** `ThresholdSubsection` 和 `ColorSubsection` 的"恢复默认"按钮均使用 `.foregroundColor(.accentColor)`。`.foregroundColor(_:)` 在 macOS 14（项目 target）中已被标记为 deprecated，正确替代为 `.foregroundStyle(Color.accentColor)`。审查提示说明此处是为修复编译错误而将 `.foregroundStyle(.accentColor)` 改回了 `.foregroundColor(.accentColor)`——但原始修复方向错了：`.foregroundStyle(Color.accentColor)` 在 macOS 14 上可以正常编译，因为 `Color` 符合 `ShapeStyle`。

**Fix:**

```swift
// 两处均替换为：
.foregroundStyle(Color.accentColor)
```

如仍遇编译问题，需确认导入了 `SwiftUI`（`Color.accentColor` 需完整限定名）。

---

### WR-04: List 固定行高 36pt 可能导致行内容被裁切

**File:** `MacStatus/MacStatus/UI/Views/SettingsView.swift:39`

**Issue:** `.frame(height: CGFloat(settings.metricOrder.count) * 36)` 假定每行高度恰好为 36pt。`MetricOrderRow` 包含 `Image` + `Text` + `Spacer` + `Toggle`（switchStyle），在不同系统字体缩放或辅助功能大字体设置下，行高可能超过 36pt，导致 List 容器高度不足，末行被裁切或出现不必要的内部滚动。

**Fix:** 将固定乘数适当加大，或改用动态高度方案：

```swift
// 方案 A：适当加大安全余量
.frame(height: CGFloat(settings.metricOrder.count) * 44)

// 方案 B：不限高度，让 Form Section 自然撑开（需配合 .fixedSize() 或 GeometryReader）
```

---

## Info

### IN-01: "清除历史"按钮为永久禁用的 TODO 占位，含幽灵注释

**File:** `MacStatus/MacStatus/UI/Views/SettingsView.swift:87-90`

**Issue:** Section "数据" 中的 `Button("清除历史")` 始终 `.disabled(true)` 且注释为 `// TODO: Implement via MetricCollector.purgeAll()`。经验证，`MetricCollector` 中不存在 `purgeAll()` 方法。这是一处未实现功能的 dead UI，会给用户带来困惑。

**Fix:** 若此功能不在 Phase 9 范围内，应将该按钮及其 Section 从 UI 中移除，或在 backlog 中创建对应 issue 跟踪实现。

---

### IN-02: NSApp.activate(ignoringOtherApps:) 在 macOS 14 已废弃

**File:** `MacStatus/MacStatus/UI/Views/SettingsView.swift:364, 376`

**Issue:** 两处调用了 `NSApp.activate(ignoringOtherApps: true)`，该 API 在 macOS 14 中已废弃，且使用 `ignoringOtherApps: true` 会强行抢占焦点，行为过于激进。

**Fix:**

```swift
// macOS 14+ 替代
if #available(macOS 14.0, *) {
    NSApp.activate()
} else {
    NSApp.activate(ignoringOtherApps: true)
}
```

或由于项目 target 已为 macOS 14，可直接使用 `NSApp.activate()`。

---

### IN-03: 第 255 行注释含虚构方法名 "applyNow"

**File:** `MacStatus/MacStatus/UI/Views/SettingsView.swift:255`

**Issue:** 注释 `// setter: clamp 0...100 + postChange + applyNow` 中的 `applyNow` 并不存在于 `SettingsManager` 中。`postChange` 会发出通知，接收方负责响应；但没有名为 `applyNow` 的方法。该注释会误导后续读者。

**Fix:** 将注释修改为准确描述：

```swift
settings.customThresholds = updated  // setter: clamp 0...100, persist to UserDefaults, post .settingsDidChange
```

---

### IN-04: NSColor.hexString 使用截断（Int()）而非四舍五入，存在 1 位精度损失风险

**File:** `MacStatus/MacStatus/Utils/NSColor+Hex.swift:29-31`（由 `SettingsView.swift` 调用路径引入）

**Issue:** `hexString` 使用 `Int(rgb.redComponent * 255)` 进行截断。当浮点分量由于 FP 精度误差略低于精确的 `n/255` 倍数时（例如 `128/255.0` 在 FP 表示中可能为 `127.9999…`），截断会产生 off-by-1 结果（127 而非 128）。这导致颜色经 ColorPicker → 保存 → 重新加载的往返可能有 1 个 8 位通道单位的偏差，ColorPicker 显示轻微色偏。

**Fix:**

```swift
let r = min(255, max(0, Int(rgb.redComponent   * 255 + 0.5)))  // 或使用 lround()
let g = min(255, max(0, Int(rgb.greenComponent * 255 + 0.5)))
let b = min(255, max(0, Int(rgb.blueComponent  * 255 + 0.5)))
```

注：`NSColor+Hex.swift` 不在本次 Phase 9 的 review scope 文件列表中，此处通过调用链交叉发现，供参考。

---

### IN-05: 告警阈值和配色区块不包含网络（Network）指标，未有注释说明

**File:** `MacStatus/MacStatus/UI/Views/SettingsView.swift:63, 71`

**Issue:** "告警阈值"和"配色"两个 Section 的 `ForEach` 仅包含 `[.cpu, .memory, .gpu]`，跳过了 `.network`。网络指标使用字节速率（非百分比），不适合百分比阈值，这一排除可能是有意为之，但代码中缺少注释解释原因。

**Fix:** 添加注释说明原因：

```swift
// .network 不支持百分比阈值（使用字节速率），故排除
ForEach([Metric.cpu, .memory, .gpu], id: \.rawValue) { metric in
```

---

### IN-06: schemaVersion 硬编码为 1，未预留未来迁移空间

**File:** `MacStatus/MacStatus/Utils/SettingsManager.swift:317`

**Issue:** `runMigrations()` 最后无条件写入 `defaults.set(1, forKey: Keys.schemaVersion)`，无论迁移路径如何。若未来 Phase 10+ 需要 `migrateToV2()`，当前模式需要修改 `runMigrations()` 中的版本号逻辑才能正确区分已迁移和未迁移用户。这不是当前 bug，但是技术债。

**Fix:** 将版本号写入改为仅在实际执行迁移后才更新，或将当前 `set(1, ...)` 的位置保留并在未来添加条件判断：

```swift
// 在 runMigrations() 末尾已正确设置为 1。
// 下次添加 V2 迁移时，应改为：
if current < 2 {
    migrateToV2()
    defaults.set(2, forKey: Keys.schemaVersion)
}
```

当前代码应为未来迁移添加注释标记，而非让版本号无条件覆盖。

---

_Reviewed: 2026-06-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
