---
phase: 9
slug: settings-window-ui-customization
status: draft
platform: macOS-native (Swift 6 + AppKit/SwiftUI)
design_system: SwiftUI native controls (Form/Section/Picker/Slider/Toggle/ColorPicker/List)
created: 2026-06-17
---

# Phase 9 — UI 设计契约：Settings Window UI + Customization

> 这是一个原生 macOS 菜单栏应用的设计契约，不是 Web 应用。不使用 CSS 令牌、breakpoint 或组件库。
> 所有控件均为 SwiftUI 原生控件，运行于 macOS 14+。
> 本契约由 gsd-ui-researcher 生成，供 gsd-planner / gsd-executor 消费。

---

## 设计系统

| 属性 | 值 |
|------|---|
| 平台 | macOS 14+ (Sonoma) |
| UI 框架 | SwiftUI + AppKit |
| 窗口宿主 | `NSWindow` + `NSHostingView`（`SettingsWindowManager`，已存在） |
| 表单样式 | `.formStyle(.grouped)`（与现有 `SettingsView` 一致） |
| 控件集 | `Form` / `Section` / `Picker` / `Slider` / `Toggle` / `ColorPicker` / `List` |
| 图标库 | SF Symbols（系统内置） |
| 设计令牌 | 不使用自定义令牌；使用系统语义颜色（`.primary`、`.secondary`、`.accentColor`） |
| 三方注册表 | 不适用 |

---

## 窗口尺寸

| 属性 | 值 | 说明 |
|------|---|------|
| 宽度 | 420pt | 从现有 380 适当加宽，为 `ColorPicker` 行留出空间 |
| 高度 | 可滚动 | `Form` 内容超出时自然滚动；不设固定高度上限 |
| 内边距 | `.padding()`（系统默认） | 与现有 `SettingsView` 一致 |
| 窗口标题 | `"MacStatus 偏好设置"` | 不变 |
| 样式掩码 | `.titled`, `.closable` | 不变 |

---

## Section 清单与排列顺序

`SettingsView` 中唯一 `Form` 内的 section，按从上到下的最终顺序：

| # | Section 标题 | 内容摘要 | 需求覆盖 |
|---|-------------|---------|---------|
| 1 | `通用` | 刷新间隔 Picker、登录时启动 Toggle（保留原样） | SET-07/08（已完成） |
| 2 | `状态栏指标` | 可拖动重排 + 启用开关 List（新增） | SET-01, SET-02, SET-03 |
| 3 | `弹窗区块` | 电池区块 Toggle、进程区块 Toggle（新增） | SET-02 弹窗分支 |
| 4 | `状态栏文字模式` | `displayMode` Picker，三选一（重标题，移出通用） | SET-06 |
| 5 | `告警阈值` | 按指标（cpu/memory/gpu）分组的 warning + critical 滑块（泛化原有全局滑块） | SET-04 |
| 6 | `配色` | 按指标（cpu/memory/gpu）分组的 ColorPicker + 恢复默认（新增） | SET-05 |
| 7 | `数据` | 已存采样点计数 + 清除历史按钮（保留原样） | — |
| 8 | `关于` | MacStatus 版本 + macOS 版本（保留原样） | — |

> **现有 `通用` section 的"显示模式"行**：从 `通用` 移出，单独成为第 4 号 section `状态栏文字模式`，以便界面语义清晰。原 `告警阈值` section（CPU/MEM 全局滑块）被第 5 号 section 完全替换。

---

## Section 详细规格

### 1. 通用（保留）

无变化。刷新间隔 `Picker` + 登录时启动 `Toggle`。`显示模式`行从此处移除。

---

### 2. 状态栏指标（新增）——SET-01 / SET-02 / SET-03

**绑定：** `settings.metricOrder`（排序）、`settings.enabledMetrics`（启用集合）

**控件实现：**

> ⚠️ **研究阶段更正（以 09-RESEARCH.md 为准）**：`EditMode` 在 macOS 上**不可用**（`@available(macOS, unavailable)`，SDK 接口文件确认）。下方 `.environment(\.editMode, .constant(.active))` 在 macOS 目标**无法编译**——必须删除。macOS 的 `List { ForEach.onMove }` 本身即支持拖动重排，**无需** EditMode；拖动柄由系统在 List 行上提供（必要时配合悬停）。`List` 嵌入 grouped `Form` 时需显式 `.frame(height:)`（约 4 行 × 36pt），否则折叠为零高。执行以 RESEARCH.md 的可编译模式为准。

```swift
// 注意：macOS 无 EditMode；List.onMove 直接可拖动重排（见 RESEARCH.md）
List {
    ForEach(settings.metricOrder) { metric in
        MetricOrderRow(metric: metric, settings: settings)
    }
    .onMove { from, to in
        settings.metricOrder.move(fromOffsets: from, toOffset: to)
    }
}
.frame(height: CGFloat(settings.metricOrder.count) * 36)   // List in Form 需显式高度
```

**行解剖（`MetricOrderRow`）：**

```
[ 拖动柄 ]  [ 指标中文名 ]              [ Toggle ]
```

- **拖动柄**：macOS `List` 在 `.onMove` 存在时即允许拖动整行重排（**无 EditMode**，见上方更正）；拖动行即可重排，无需进入编辑模式。
- **指标中文名**：见下表

| `Metric` rawValue | 显示名 |
|-------------------|--------|
| `cpu` | CPU |
| `memory` | 内存 |
| `network` | 网络 |
| `gpu` | GPU |

- **Toggle**：`isOn` 绑定计算属性（`enabledMetrics.contains(metric)` → set 时 append/remove）；即时写回 `settings.enabledMetrics`。

**禁用行外观：**  
已关闭的指标行：指标名使用 `.foregroundStyle(.secondary)`（灰显），`Toggle` 为 off 状态。行仍可拖动——排序与启用状态相互独立。

**全部关闭时（空状态）：**  
允许所有指标均关闭。此时状态栏将显示 Phase 6 定义的 `◆` 占位符（`StatusBarManager` 已实现）。Form 中不显示额外警告文字——行为符合预期，无需提示。

**仅含状态栏指标：** cpu / memory / network / gpu（共 4 项）。`battery` 不在此列表中（popover-only）。

---

### 3. 弹窗区块（新增）——SET-02 弹窗分支

**绑定：** `settings.showBatterySection`（新键）、`settings.showProcessSection`（新键）

**控件：**

```swift
Section("弹窗区块") {
    Toggle("电池区块", isOn: $settings.showBatterySection)
    Toggle("进程区块", isOn: $settings.showProcessSection)
}
```

- 两个 `Toggle`，各自独立控制弹窗中对应区块的显隐。
- 即时生效：`DashboardView` 直接读取 `@Observable SettingsManager.shared`（`body` 内访问自动建立 Observation 依赖），无需 `applyNow`/经状态栏重绘路径。
- `showBatterySection` 的硬件降级：`DashboardView` 现有的 `if state.hasBattery` 硬件门控保留，`showBatterySection` 叠加在其外层：`if settings.showBatterySection && state.hasBattery`。在无电池机型上，toggle 仍然可操作（用户可提前配置），但弹窗始终不显示电池区块。
- **新键迁移策略**：`SettingsManager` 中直接在 `loadAll()` 的 getter 提供 `true` 缺省，不额外推进 `schemaVersion`（与 Phase 6 migration ladder 的"nil 时用默认值"模式一致；这两个键从不存在时读 `false` 会造成错误行为，故在 `loadAll` 中明确 `defaults.bool(forKey:)` 返回 `false` 时需检查 `object(forKey:) == nil` 决定是否采用 `true` 默认值）。

---

### 4. 状态栏文字模式（重标题移入独立 Section）——SET-06

**绑定：** `settings.displayMode`

**控件：**

```swift
Section("状态栏文字模式") {
    Picker("", selection: $settings.displayMode) {
        Text("详细").tag(DisplayMode.full)
        Text("紧凑").tag(DisplayMode.compact)
        Text("百分比").tag(DisplayMode.percentage)
    }
    .pickerStyle(.segmented)  // 三选一，segmented 直观
}
```

- 选项标签：`full` → `"详细"`，`compact` → `"紧凑"`，`percentage` → `"百分比"`。
- 即时生效：Phase 6 接缝（`postChange` → `.settingsDidChange` → `applyNow()`）已就绪。

---

### 5. 告警阈值（泛化原有全局滑块）——SET-04

**绑定：** `settings.customThresholds[metric.rawValue]["warning" / "critical"]`

**适用指标：** cpu、memory、gpu（共 3 个指标；network 无阈值着色，不出现在此 section）。

**每指标子块结构：**

```
[ 指标名标题行（粗体 caption） ]
CPU 警告：60%         ←── live label，Int(value)%
[====|====|====] Slider(in: 30...90, step: 5)
CPU 严重：80%
[====|====|====] Slider(in: 50...95, step: 5)
[恢复默认]            ←── Button，right-aligned
────────────────      ←── Divider（各指标间分隔）
```

**警告 < 严重约束：**  
在 `Slider` 的 `onChange` 处理中强制：
- 调整 warning 时：若 `newWarning >= critical`，则 `critical = min(newWarning + 5, 95)`。
- 调整 critical 时：若 `newCritical <= warning`，则 `warning = max(newCritical - 5, 30)`。
- 此约束在 UI 层执行；`SettingsManager` setter 已提供 0...100 clamp 兜底。

**读取逻辑（各指标默认值）：**

| 指标 | 警告默认值 | 严重默认值 | 备注 |
|------|----------|----------|------|
| cpu | 60% | 80% | 从 `customThresholds["cpu"]` 读，缺失时读旧键 `cpuWarningThreshold`/`cpuCriticalThreshold` |
| memory | 60% | 80% | 从 `customThresholds["memory"]` 读，缺失时读旧键 `memoryWarningThreshold`/`memoryCriticalThreshold` |
| gpu | 60% | 80% | 从 `customThresholds["gpu"]` 读，缺失时使用硬编码默认值 |

> 旧全局键（`cpuWarningThreshold` 等）仍存在于 `SettingsManager`，读取时作为 cpu/memory 的迁移源；写入统一走 `customThresholds`。

**恢复默认（每指标）：**  
点击后清除 `customThresholds[metric.rawValue]`（将该 key 从 dict 移除）→ UI 自动回退到上表默认值。按钮使用 `.buttonStyle(.borderless)`，`.foregroundStyle(.accentColor)`，位于该指标子块右下角。

**SwiftUI 结构：**

```swift
Section("告警阈值") {
    ForEach([Metric.cpu, .memory, .gpu], id: \.rawValue) { metric in
        ThresholdSubsection(metric: metric, settings: settings)
    }
}
```

---

### 6. 配色（新增）——SET-05

**绑定：** `settings.customColors[metric.rawValue]["warning" / "critical"]`

**适用指标：** cpu、memory、gpu（同告警阈值，network 无值级着色）。

**每指标子块结构：**

```
[ 指标名标题行（粗体 caption） ]
警告色    [ColorSwatch]  ColorPicker(...)
严重色    [ColorSwatch]  ColorPicker(...)
[恢复默认]               ←── Button，right-aligned
────────────────         ←── Divider（各指标间分隔）
```

**`ColorPicker` 参数：**

```swift
ColorPicker(
    selection: $boundColor,
    supportsOpacity: false   // 颜色不需要 alpha 通道
)
```

**Color ↔ String 互转：**  
使用已有 `NSColor+Hex`：
- 读取：`NSColor(hex: settings.customColors[metric.rawValue]?["warning"] ?? defaultHex)` → `Color(nsColor:)`
- 写入：`ColorPicker` binding 为 `Color`；在 `onChange` 中通过 `NSColor(color).hexString` 写回 `customColors`。

**默认颜色（`customColors` 中无对应键时的展示值）：**

| 指标 | 警告色（默认） | 严重色（默认） |
|------|-------------|-------------|
| cpu | `#FF9500`（橙） | `#FF3B30`（红） |
| memory | `#FF9500`（橙） | `#FF3B30`（红） |
| gpu | `#FF9500`（橙） | `#FF3B30`（红） |

> 默认色与 `StatusBarManager.colorForUsage` 现有硬编码默认色保持一致（executor 实现时以实际代码为准）。

**恢复默认（每指标）：**  
清除 `customColors[metric.rawValue]`（移除该 key）→ `StatusBarManager.colorForUsage` 自动回退到内置默认色。按钮样式同告警阈值的"恢复默认"。

**SwiftUI 结构：**

```swift
Section("配色") {
    ForEach([Metric.cpu, .memory, .gpu], id: \.rawValue) { metric in
        ColorSubsection(metric: metric, settings: settings)
    }
}
```

---

### 7. 数据（保留）

无变化。

---

### 8. 关于（保留）

无变化。版本号更新为 v2.0（Phase 9 完成时）由 executor 按实际 build 号填写。

---

## 即时生效契约（SET-08）

| 控件变化 | 传播路径 | 效果 |
|---------|---------|------|
| 指标 Toggle on/off | `settings.enabledMetrics` setter → `postChange` → `.settingsDidChange` → `StatusBarManager.applyNow()` | 状态栏立即增减指标段 |
| 指标拖动重排 | `settings.metricOrder` setter → `postChange` → `.settingsDidChange` → `StatusBarManager.applyNow()` | 状态栏段顺序立即更新 |
| 弹窗区块 Toggle | `settings.showBatterySection`/`showProcessSection` setter → `@Observable` 响应式 | `DashboardView` 下次刷新时条件渲染区块（SwiftUI @Observable 自动追踪，无需 applyNow） |
| displayMode Picker | `settings.displayMode` setter → `postChange` → `.settingsDidChange` → `applyNow()` | 状态栏文字格式立即切换 |
| 阈值 Slider | `settings.customThresholds` setter → `postChange` → `.settingsDidChange` → `applyNow()` | 状态栏着色立即更新 |
| 配色 ColorPicker | `settings.customColors` setter → `postChange` → `.settingsDidChange` → `applyNow()` | 状态栏着色立即更新 |

**无保存按钮。** 状态栏与弹窗即为实时预览，无窗内预览面板。

---

## 持久化契约（SET-07）

所有控件绑定 `SettingsManager`（@Observable 单一真源）。`SettingsManager` setter 每次写 `UserDefaults` + 发通知。不得引入裸 `@AppStorage`。

---

## 本地化（文案）

所有 UI 标签使用中文，与现有 `SettingsView` 风格一致。

### Section 标题

| Section | 标题字符串 |
|---------|----------|
| 1 | `"通用"` |
| 2 | `"状态栏指标"` |
| 3 | `"弹窗区块"` |
| 4 | `"状态栏文字模式"` |
| 5 | `"告警阈值"` |
| 6 | `"配色"` |
| 7 | `"数据"` |
| 8 | `"关于"` |

### 控件标签

| 控件 | 标签文字 |
|------|---------|
| 电池区块 Toggle | `"电池区块"` |
| 进程区块 Toggle | `"进程区块"` |
| displayMode .full | `"详细"` |
| displayMode .compact | `"紧凑"` |
| displayMode .percentage | `"百分比"` |
| 告警阈值 warning 行标签 | `"{指标名} 警告：{N}%"`（如 `"CPU 警告：60%"`） |
| 告警阈值 critical 行标签 | `"{指标名} 严重：{N}%"`（如 `"内存 严重：80%"`） |
| 配色 warning 行标签 | `"警告色"` |
| 配色 critical 行标签 | `"严重色"` |
| 恢复默认按钮 | `"恢复默认"` |

### 指标中文名映射

| rawValue | 显示名（一律使用此名） |
|----------|-------------------|
| `cpu` | `"CPU"` |
| `memory` | `"内存"` |
| `network` | `"网络"` |
| `gpu` | `"GPU"` |

---

## 可访问性 / 原生 macOS 操控

| 规则 | 说明 |
|------|------|
| 拖动柄尺寸 | 使用系统 `List.onMove` 默认拖动柄；无需自定义触控目标尺寸（鼠标交互，非触摸） |
| `Toggle` | 使用系统原生 `Toggle`；自动满足 VoiceOver 访问性 |
| `Slider` | 使用系统原生 `Slider`；VoiceOver 播报 label + value；live label（`Text("CPU 警告：60%")`）提供可视反馈 |
| `ColorPicker` | 系统原生，VoiceOver 自动可用 |
| 键盘导航 | `Form` 内原生 Tab 顺序；不需额外 `.focusable()` 处理 |
| `EditMode` | ⚠️ **macOS 不可用**——删除任何 editMode 引用；`List { ForEach.onMove }` 在 macOS 上本身即可拖动重排（见 09-RESEARCH.md） |
| 最小控件间距 | `VStack(spacing: 8)` 内滑块组（与现有告警阈值 section 一致） |

---

## 新增文件登记要求

若 executor 将 `ThresholdSubsection`、`ColorSubsection`、`MetricOrderRow` 等拆为独立文件，**必须登记 `MacStatus.xcodeproj/project.pbxproj`**（Phase 7/8 教训）。优先选择将这些视图作为私有 `struct` 内嵌于 `SettingsView.swift`，避免 pbxproj 变更。

---

## 需求覆盖追溯

| 需求 | 对应 Section / 控件 |
|------|-------------------|
| SET-01（打开设置窗口） | `SettingsWindowManager.showSettings()`（已存在，无 UI 变更） |
| SET-02（逐指标开关） | Section 2（状态栏指标 Toggle）+ Section 3（弹窗区块 Toggle） |
| SET-03（拖动排序） | Section 2（List.onMove） |
| SET-04（自定义阈值） | Section 5（告警阈值滑块） |
| SET-05（自定义着色） | Section 6（配色 ColorPicker） |
| SET-06（文字模式切换） | Section 4（状态栏文字模式 Picker） |
| SET-07（持久化） | SettingsManager 全局契约（Phase 6 已完成） |
| SET-08（即时生效） | 即时生效契约表（Phase 6 接缝） |

---

## 开放事项（非阻塞）

无阻塞性开放事项。以下为实现时的微决策，由 executor 按最简路径自行裁定：

1. **`MetricOrderRow` / `ThresholdSubsection` / `ColorSubsection` 是否独立文件**：建议内嵌于 `SettingsView.swift` 以避免 pbxproj 变更；若代码行数过长（>400 行）可拆分，但需登记 pbxproj。
2. **告警阈值旧键迁移**：`customThresholds["cpu"]` 缺失时读旧 `cpuWarningThreshold` 键值作为初始 binding 值（展示层迁移，不删旧键）；写入时统一写 `customThresholds`。
3. **`ColorPicker` binding 辅助层**：`settings.customColors` 是 `[String:[String:String]]`，需封装一个计算 `Binding<Color>` 供 `ColorPicker` 使用；实现细节由 executor 裁定。

---

## Checker Sign-Off

- [ ] 维度 1 文案：PASS
- [ ] 维度 2 视觉控件：PASS
- [ ] 维度 3 颜色：PASS
- [ ] 维度 4 字体排版：PASS（使用系统默认）
- [ ] 维度 5 间距：PASS（使用系统默认）
- [ ] 维度 6 注册表安全：不适用（原生平台，无第三方注册表）

**审批：** 待定

---

<!-- UI-SPEC COMPLETE: Phase 9 — Settings Window UI + Customization -->
