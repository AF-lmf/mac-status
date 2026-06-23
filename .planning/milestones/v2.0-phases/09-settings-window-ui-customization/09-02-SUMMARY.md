---
phase: "09-settings-window-ui-customization"
plan: "02"
subsystem: "SettingsView"
tags: [settings-ui, swiftui, list-reorder, observable, bindable, phase9]
dependency_graph:
  requires:
    - "09-01: SettingsManager.showBatterySection / showProcessSection"
    - "Phase 6: SettingsManager.metricOrder / enabledMetrics / displayMode (@Bindable)"
  provides:
    - "SettingsView 8-section Form（通用/状态栏指标/弹窗区块/状态栏文字模式/告警阈值占位/配色占位/数据/关于）"
    - "MetricOrderRow 内嵌 struct（List.onMove 拖动重排 + enabledMetrics Toggle）"
    - "displayMode segmented Picker（独立 section）"
    - "showBatterySection / showProcessSection Toggle 绑定"
  affects:
    - "Plan 03: ThresholdSubsection / ColorSubsection 替换占位 Section 5/6"
tech_stack:
  added: []
  patterns:
    - "List { ForEach(id: \\.rawValue).onMove } + .frame(height: count*36) + .listStyle(.plain)（macOS 14 拖动重排，无 EditMode）"
    - "private var enabledBinding: Binding<Bool>（struct 计算属性，防止 body 内局部 Binding 无限重渲染）"
    - "moveDisabled(!isHoveringHandle) + .onHover（悬停拖动柄才激活拖动）"
    - "LabeledContent 包裹 segmented Picker（避免 grouped Form 空标签空白列）"
    - "@Bindable SettingsManager 传入内嵌私有 struct"
key_files:
  created: []
  modified:
    - path: "MacStatus/MacStatus/UI/Views/SettingsView.swift"
      description: "完整重写：8-section Form + 内嵌 MetricOrderRow + Metric.displayName 扩展 + Form 宽度 420"
decisions:
  - "ForEach 使用 id: \\.rawValue 而非 Identifiable conformance（Metric 无需 Identifiable，rawValue 稳定唯一）"
  - "MetricOrderRow.enabledBinding 定义为 struct 计算属性而非 body 内局部 Binding（防无限重渲染，Research 陷阱 3）"
  - "Section 告警阈值和配色均以占位 Text 实现，保留 Plan 03 扩展点（不引入旧全局滑块冗余）"
  - "Metric.displayName 扩展放在文件末尾 extension 而非 SettingsView 内部，避免 private 可见性限制"
metrics:
  duration: "~15m"
  completed: "2026-06-17"
  tasks_completed: 1
  files_modified: 1
requirements_satisfied:
  - SET-01
  - SET-02
  - SET-03
  - SET-06
---

# Phase 09 Plan 02: SettingsView 重构 — 8-Section Form + 拖动重排

**一句话摘要：** 完整重写 SettingsView，新增状态栏指标拖动重排列表（MetricOrderRow + List.onMove，零 EditMode 引用）、弹窗区块开关、独立文字模式 segmented Picker，窗口宽度扩展至 420pt。

## 完成情况

| 任务 | 名称 | Commit | 文件 |
|------|------|--------|------|
| 1 | Section 框架重构 + 状态栏指标 List + 弹窗区块 Toggles + 文字模式 Picker | 97b8e74 | MacStatus/MacStatus/UI/Views/SettingsView.swift |

## 实现细节

### 8-Section Form 结构（最终顺序）

| # | Section | 内容 |
|---|---------|------|
| 1 | 通用 | 刷新间隔 Picker + 登录时启动 Toggle（移除了旧的显示模式行） |
| 2 | 状态栏指标 | List { ForEach(id: \.rawValue).onMove } + MetricOrderRow（拖动重排 + Toggle） |
| 3 | 弹窗区块 | Toggle 电池区块 / Toggle 进程区块（绑定 showBatterySection / showProcessSection） |
| 4 | 状态栏文字模式 | LabeledContent + segmented Picker（详细/紧凑/百分比） |
| 5 | 告警阈值 | 占位 Text，由 Plan 03 替换 |
| 6 | 配色 | 占位 Text，由 Plan 03 替换 |
| 7 | 数据 | 已存采样点 + 清除历史（原样保留） |
| 8 | 关于 | v2.0 (M009)（版本号更新） |

### MetricOrderRow 内嵌 struct 关键设计

```swift
private struct MetricOrderRow: View {
    let metric: Metric
    @Bindable var settings: SettingsManager
    @State private var isHoveringHandle = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .onHover { isHoveringHandle = $0 }
            Text(metric.displayName)
            Spacer()
            Toggle("", isOn: enabledBinding).labelsHidden().toggleStyle(.switch)
        }
        .moveDisabled(!isHoveringHandle)
    }

    // 关键：定义为计算属性，不在 body 内构造（防无限重渲染）
    private var enabledBinding: Binding<Bool> {
        Binding {
            settings.enabledMetrics.contains(metric)
        } set: { enabled in
            if enabled {
                if !settings.enabledMetrics.contains(metric) {
                    settings.enabledMetrics.append(metric)
                }
            } else {
                settings.enabledMetrics.removeAll { $0 == metric }
            }
        }
    }
}
```

### 编译修正（Rule 1 — Bug）

**ForEach Identifiable 约束：** `ForEach(settings.metricOrder)` 需要 `Metric: Identifiable`，但 `Metric` 是简单 enum 未采纳此协议。修正为 `ForEach(settings.metricOrder, id: \.rawValue)`，rawValue 是稳定唯一标识，语义正确，无需为 Metric 添加 Identifiable conformance。

## 验收结果

| 断言 | 结果 |
|------|------|
| grep -c ".onMove" | 1 ✅ |
| grep -ic "editMode" | 0 ✅ |
| grep -c "showBatterySection" | 1 ✅ |
| grep -c "showProcessSection" | 1 ✅ |
| grep -c "状态栏指标" | 4 ✅ |
| grep -c "弹窗区块" | 2 ✅ |
| grep -c "状态栏文字模式" | 2 ✅ |
| grep -c "pickerStyle(.segmented)" | 1 ✅ |
| grep -c "frame(width: 420)" | 1 ✅ |
| grep -c "MetricOrderRow" | 3 ✅ (>= 2) |
| grep -c "isHoveringHandle" | 3 ✅ |
| grep -c "moveDisabled" | 2 ✅ |
| grep -c "enabledBinding" | 4 ✅ (>= 2) |
| grep -c "cpuWarningThreshold\|memoryWarningThreshold" | 0 ✅ |
| 无新 .swift 文件 | ✅ |
| xcodebuild BUILD SUCCEEDED | ✅ exit 0 |

## 计划偏差

### 自动修正

**1. [Rule 1 - Bug] ForEach 需要 id 参数**
- **发现于：** 首次 xcodebuild 编译
- **问题：** `ForEach(settings.metricOrder)` 要求 `Metric: Identifiable`，编译报错 "referencing initializer 'init(_:content:)' on 'ForEach' requires that 'Metric' conform to 'Identifiable'"
- **修复：** 改为 `ForEach(settings.metricOrder, id: \.rawValue)`（rawValue 唯一且稳定，符合语义）
- **文件：** MacStatus/MacStatus/UI/Views/SettingsView.swift
- **Commit：** 97b8e74（含修复）

## Known Stubs

| 文件 | Section | 内容 | 计划解决 |
|------|---------|------|---------|
| SettingsView.swift | 告警阈值 (Section 5) | `Text("（由 Plan 03 实现按指标编辑）")` | Plan 03 替换为 ThresholdSubsection |
| SettingsView.swift | 配色 (Section 6) | `Text("（由 Plan 03 实现按指标配色）")` | Plan 03 替换为 ColorSubsection |

两处占位均为计划内设计（Plan 02 目标是 SET-01/02/03/06，阈值/配色由 Plan 03 覆盖），不影响本计划目标功能。

## Threat Flags

无新安全面引入。所有用户输入经过 @Bindable → SettingsManager setter → UserDefaults，setter 已实现类型安全（Phase 6 设计）。

## Self-Check: PASSED

- 文件存在: MacStatus/MacStatus/UI/Views/SettingsView.swift ✅
- 提交存在: 97b8e74 ✅
- 构建: BUILD SUCCEEDED ✅
- editMode 引用: 0 ✅
