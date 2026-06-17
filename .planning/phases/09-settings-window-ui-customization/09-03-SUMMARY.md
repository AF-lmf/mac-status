---
phase: "09-settings-window-ui-customization"
plan: "03"
subsystem: "SettingsView + DashboardView"
tags: [settings-ui, swiftui, colorpicker, slider, observable, bindable, phase9, v2.0-final]
dependency_graph:
  requires:
    - "09-02: SettingsView 8-section Form 框架（含 Section 5/6 占位）"
    - "Phase 6: SettingsManager.customThresholds / customColors (@Bindable, setter, postChange)"
    - "Phase 6: SettingsManager.showBatterySection / showProcessSection (Plan 01 添加)"
    - "NSColor+Hex.swift: NSColor(hex:) / hexString 扩展"
  provides:
    - "ThresholdSubsection 内嵌私有 struct：per-metric warning/critical Slider + 约束 + 恢复默认"
    - "ColorSubsection 内嵌私有 struct：per-metric warning/critical ColorPicker + 恢复默认"
    - "DashboardView 电池区块 showBatterySection 门控"
    - "DashboardView 进程三区块 showProcessSection 门控"
  affects:
    - "StatusBarManager.colorForUsage: customThresholds/customColors 读取路径（无需改动）"
    - "BatterySectionView: 被 showBatterySection 门控（视图本身不变）"
    - "ProcessListView / ProcessResourceSectionView: 被 showProcessSection 门控（视图本身不变）"
tech_stack:
  added: []
  patterns:
    - "private struct ThresholdSubsection / ColorSubsection 内嵌于 SettingsView.swift（零 pbxproj 变更）"
    - "Binding<Double> 计算属性读写 customThresholds[metric.rawValue][level]（防无限重渲染）"
    - "Binding<Color> 计算属性：NSColor(hex:) → Color(nsColor:) / NSColor(_ color:) → hexString（双向转换）"
    - ".onChange(of:) { _, newValue in } 双参数签名（Swift 6 / macOS 14）实现 warning < critical 约束"
    - "ColorPicker(supportsOpacity: false) + .labelsHidden() + .frame(width: 44)（HStack 布局）"
    - "let settings = SettingsManager.shared 在 body 内建立 @Observable 追踪（无 @State/@EnvironmentObject）"
key_files:
  created: []
  modified:
    - path: "MacStatus/MacStatus/UI/Views/SettingsView.swift"
      description: "替换 Section 5 告警阈值占位 + Section 6 配色占位；内嵌 ThresholdSubsection + ColorSubsection 私有 struct"
    - path: "MacStatus/MacStatus/UI/Views/DashboardView.swift"
      description: "电池区块加 settings.showBatterySection 外层门控；进程三区块加 settings.showProcessSection 整体门控"
decisions:
  - ".foregroundStyle(.accentColor) 在 Swift 6 / macOS 14 编译失败，改用 .foregroundColor(.accentColor)（Rule 1 自动修复）"
  - "all computed Bindings 定义为 struct 计算属性（非 body 局部），防无限重渲染（Research 陷阱 3）"
  - "cpu/memory 旧全局键（cpuWarningThreshold 等）作为迁移种子只读取初始值，写入走 customThresholds"
  - "warning < critical 约束通过 .onChange 单向推送，不在 Binding setter 内互锁（防递归）"
metrics:
  duration: "~20m"
  completed: "2026-06-17"
  tasks_completed: 2
  files_modified: 2
requirements_satisfied:
  - SET-02
  - SET-04
  - SET-05
---

# Phase 09 Plan 03: SettingsView 告警阈值 + 配色 Section + DashboardView 区块门控

**一句话摘要：** 用 ThresholdSubsection（per-metric Slider + warning<critical 约束）替换 Section 5 占位，用 ColorSubsection（per-metric ColorPicker + NSColor/hex 双向转换）替换 Section 6 占位，并为 DashboardView 电池/进程区块添加 settings 可见性门控——v2.0 里程碑 Phase 9 终态。

## 完成情况

| 任务 | 名称 | Commit | 文件 |
|------|------|--------|------|
| 1 | SettingsView 告警阈值 + 配色 Section | 30d4c92 | MacStatus/MacStatus/UI/Views/SettingsView.swift |
| 2 | DashboardView 弹窗区块可见性门控 | 7ccc958 | MacStatus/MacStatus/UI/Views/DashboardView.swift |

## 实现细节

### Task 1：ThresholdSubsection（Section 5）

```swift
private struct ThresholdSubsection: View {
    let metric: Metric
    @Bindable var settings: SettingsManager

    // 旧全局键作迁移种子（只读，写入走 customThresholds[metric]）
    private var defaultWarning: Double { ... }
    private var defaultCritical: Double { ... }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.displayName).font(.caption.weight(.semibold))
            Text("\(metric.displayName) 警告：\(Int(warningBinding.wrappedValue))%")
            Slider(value: warningBinding, in: 30...90, step: 5)
                .onChange(of: warningBinding.wrappedValue) { _, newWarning in
                    if newWarning >= criticalBinding.wrappedValue {
                        criticalBinding.wrappedValue = min(newWarning + 5, 95)
                    }
                }
            // ... critical Slider + 恢复默认 ...
        }
    }

    // Binding 定义为计算属性（非 body 局部）
    private var warningBinding: Binding<Double> { thresholdBinding(for: "warning", ...) }
    private func thresholdBinding(for level: String, default defaultValue: Double) -> Binding<Double> {
        Binding {
            settings.customThresholds[metric.rawValue]?[level] ?? defaultValue
        } set: { newValue in
            var updated = settings.customThresholds
            var levels = updated[metric.rawValue] ?? [:]
            levels[level] = newValue
            updated[metric.rawValue] = levels
            settings.customThresholds = updated
        }
    }
}
```

### Task 1：ColorSubsection（Section 6）

```swift
private struct ColorSubsection: View {
    let metric: Metric
    @Bindable var settings: SettingsManager

    private let defaultWarningHex = "#FF9500"   // 系统橙
    private let defaultCriticalHex = "#FF3B30"  // 系统红

    // ColorPicker 使用 supportsOpacity: false，颜色经 NSColor+Hex 双向转换
    private func colorBinding(for level: String, defaultHex: String) -> Binding<Color> {
        Binding {
            let hex = settings.customColors[metric.rawValue]?[level] ?? defaultHex
            let ns = NSColor(hex: hex) ?? NSColor(hex: defaultHex)!
            return Color(nsColor: ns)           // macOS 12+
        } set: { newColor in
            let ns = NSColor(newColor)          // macOS 11+
            let hex = ns.hexString
            // ... 更新 settings.customColors[metric][level] ...
        }
    }
}
```

### Task 2：DashboardView 门控

```swift
var body: some View {
    let settings = SettingsManager.shared  // @Observable 自动追踪
    VStack(spacing: 8) {
        // 电池：设置门控（外层）+ 硬件门控（内层）
        if settings.showBatterySection && state.hasBattery, let battery = state.battery {
            BatterySectionView(snapshot: battery)
        }
        // 进程三区块：整体门控
        if settings.showProcessSection {
            ProcessListView(...)
            ProcessResourceSectionView("CPU 占用 Top 5", ...)
            ProcessResourceSectionView("内存占用 Top 5", ...)
        }
    }
}
```

## 验收结果

| 断言 | 结果 |
|------|------|
| grep -c "ColorPicker" SettingsView | 3 ✅ (>= 2) |
| grep -c "supportsOpacity: false" SettingsView | 2 ✅ |
| grep -c "ThresholdSubsection" SettingsView | 4 ✅ (>= 2) |
| grep -c "ColorSubsection" SettingsView | 4 ✅ (>= 2) |
| grep -c "customThresholds\[metric" SettingsView | 2 ✅ |
| grep -c "customColors\[metric" SettingsView | 1 ✅ |
| grep -c "恢复默认" SettingsView | 4 ✅ (>= 2) |
| grep -c "removeValue(forKey: metric.rawValue)" SettingsView | 2 ✅ |
| grep -c "NSColor(hex:" SettingsView | 2 ✅ |
| grep -c "Color(nsColor:" SettingsView | 2 ✅ |
| 占位文字已移除 "由 Plan 03 实现" | 0 ✅ |
| grep -c "showBatterySection" DashboardView | 2 ✅ |
| grep -c "showProcessSection" DashboardView | 2 ✅ |
| grep -c "SettingsManager.shared" DashboardView | 1 ✅ |
| grep -c "state.hasBattery" DashboardView | 1 ✅ |
| grep -c "ProcessListView" DashboardView | 1 ✅ |
| grep -ic "editMode" SettingsView | 0 ✅ |
| grep -c ".onMove" SettingsView | 1 ✅ |
| xcodebuild BUILD SUCCEEDED | ✅ exit 0 |

## 计划偏差

### 自动修正

**1. [Rule 1 - Bug] .foregroundStyle(.accentColor) 编译失败**
- **发现于：** 首次 xcodebuild 编译
- **问题：** Swift 6 / macOS 14 中 `.foregroundStyle(.accentColor)` 报错 "type 'ShapeStyle' has no member 'accentColor'"——`ShapeStyle` 协议没有静态 `.accentColor` 成员，只有 `Color` 有。
- **修复：** 改为 `.foregroundColor(.accentColor)`，该 API 在 macOS 14 上仍可用，语义等价。
- **文件：** MacStatus/MacStatus/UI/Views/SettingsView.swift（ThresholdSubsection + ColorSubsection 各一处，共 2 处）
- **Commit：** 30d4c92（含修复）

## Known Stubs

无。Plan 03 已替换 Plan 02 的两处占位文字（Section 5 告警阈值、Section 6 配色），所有 Section 均已实现真实功能。

## Threat Flags

无新安全面引入。

- ColorPicker 输入经 `NSColor.hexString` 输出，`.usingColorSpace(.sRGB)` 截断到 0–255，符合 T-09-03-T 缓解措施。
- Slider 输入经 SettingsManager.customThresholds setter 的 `clamp(0...100)` 处理，UI 层再加 warning<critical 约束，双重保障符合 T-09-03-T。
- DashboardView 只读访问 SettingsManager.shared，无副作用，符合 T-09-03-I。

## Self-Check: PASSED

- 文件存在: MacStatus/MacStatus/UI/Views/SettingsView.swift ✅
- 文件存在: MacStatus/MacStatus/UI/Views/DashboardView.swift ✅
- 提交存在: 30d4c92 ✅
- 提交存在: 7ccc958 ✅
- 构建: BUILD SUCCEEDED ✅
- 占位文字已移除: 0 ✅
- editMode 引用: 0 ✅
