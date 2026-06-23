# Phase 9: Settings Window UI + Customization — Research

**Researched:** 2026-06-17
**Domain:** SwiftUI macOS 14, @Observable binding patterns, Form/List drag-reorder, ColorPicker
**Confidence:** HIGH (SDK interface files verified directly)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- 扩展现有 `SettingsView`（`@Bindable var settings = SettingsManager.shared`，`formStyle(.grouped)`），不新开窗口，不用 TabView。
- "状态栏指标"组：SwiftUI `List { ForEach(settings.metricOrder) }.onMove`，每行含指标名 + Toggle（enabledMetrics）+ 拖动柄。
- "弹窗区块"组：新增 `showBatterySection`/`showProcessSection` bool 键控制弹窗区块显隐；独立于 enabledMetrics。
- 阈值编辑器仅 cpu/memory/gpu；warning 30–90，critical 50–95，step 5；warning < critical 约束在 UI 层执行。
- 配色：每 (指标, 等级) 一个 `ColorPicker`，通过 NSColor+Hex 双向转换 customColors。
- displayMode Picker 迁移为独立 section "状态栏文字模式"。
- 窗口宽度扩展至 420pt，Form 内容可滚动，不设高度上限。
- 即时生效（SET-06）：所有控件经 SettingsManager → postChange → .settingsDidChange → applyNow/reconfigure。
- 不引入裸 @AppStorage。无保存按钮。

### Claude's Discretion

- DashboardView 如何响应弹窗区块可见性键（直接读 @Observable SettingsManager 还是镜像进 DashboardState）。
- showBatterySection/showProcessSection 是否纳入 .settingsDidChange cosmetic 分支触发 applyNow。
- "状态栏指标"List 行内 Toggle + onMove 的具体 SwiftUI 实现（EditMode、拖动柄样式）。
- 新键迁移：schemaVersion bump 还是 loadAll getter 缺省。
- ColorPicker supportsOpacity（建议关闭）。

### Deferred Ideas (OUT OF SCOPE)

- 窗内实时预览面板。
- TabView 分页设置。
- 每指标独立刷新间隔（SET-F1）。
- 自定义通知/告警规则。
- 导入/导出/配置档案。
- network 阈值着色。
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SET-01 | 用户能从右键菜单打开独立设置窗口 | SettingsWindowManager.showSettings() 已存在；无新工作 |
| SET-02 | 用户能逐个开关每个指标在状态栏的显示 | enabledMetrics Toggle binding 模式；showBattery/showProcess 新键 |
| SET-03 | 用户能拖动调整状态栏各指标的显示顺序 | List { ForEach.onMove } macOS 14 确认模式；EditMode 不可用（SDK 验证） |
| SET-04 | 用户能自定义各指标的警告/危险阈值 | Binding<Double> 嵌套字典模式；warning<critical 约束 |
| SET-05 | 用户能自定义各指标的着色 | Binding<Color> ↔ customColors hex 往返模式；NSColor 桥接 SDK 验证 |
| SET-06 | 用户能在紧凑/详细两种状态栏文本模式间切换 | displayMode Picker 已有；迁入独立 section |
</phase_requirements>

---

## Summary

Phase 9 将五个已完成后端能力（Phase 6 SettingsManager 接缝、Phase 7 电池、Phase 8 进程）暴露为一个完整的设置控制面。所有工作集中在三个文件的改造上：`SettingsView.swift`（新增四个 section，泛化两个旧 section）、`SettingsManager.swift`（新增两个 bool 键）、`DashboardView.swift`（新增可见性门控）。

**主要发现（SDK 级验证）：**

1. **`EditMode` 在 macOS 上不可用**（`@available(macOS, unavailable)`）。UI-SPEC 中的 `.environment(\.editMode, .constant(.active))` 在 macOS 目标上**无法编译**。正确方案：macOS 上 `List.onMove` 无需 EditMode；拖动柄通过 `.onMove` 自动激活，行为类似 iOS 的 `.active` 状态，但不需要显式设置。使用 `moveDisabled()/onHover()` 模式实现"仅在悬停区域可拖动"（见 Q1）。

2. **Color ↔ NSColor 桥接已有官方 API**（SDK 验证）：`Color(nsColor:)` 可用 macOS 12+；`NSColor(_ color: Color)` 可用 macOS 11+。两个方向均可直接使用，无需第三方库。

3. **@Observable 单例在 view body 内直接读取即可建立 Observation 追踪**，无需 @State 或 @EnvironmentObject 包装。`DashboardView` 直接读 `SettingsManager.shared.showBatterySection` 是正确且最简的方案。

4. **新 bool 键无需 schemaVersion bump**；在 `loadAll()` 中用 `defaults.object(forKey:) == nil` 判断 nil 时回退 `true` 默认值即可，符合现有迁移梯子模式。

**Primary recommendation:** 三文件改造，无新文件，内嵌子视图 struct 于 SettingsView.swift，避免 pbxproj 变更风险。

---

## Architectural Responsibility Map

| 能力 | Primary Tier | Secondary Tier | 说明 |
|------|-------------|----------------|------|
| 设置窗口生命周期 | Frontend (NSWindow/AppKit) | — | SettingsWindowManager 已就绪 |
| 设置控件 UI | Frontend (SwiftUI Form) | — | SettingsView + 子 struct |
| 设置持久化与广播 | SettingsManager singleton | UserDefaults | 已就绪（Phase 6） |
| 状态栏即时刷新 | MetricCollector/StatusBarManager | — | 经 .settingsDidChange（Phase 6 接缝） |
| 弹窗区块显隐 | DashboardView (SwiftUI @Observable) | SettingsManager | 直接读 @Observable 响应 |
| 阈值/配色运行时应用 | StatusBarManager.colorForUsage | SettingsManager | 已实现，无需改动 |

---

## Standard Stack

### Core（无新依赖）

| 组件 | 版本/来源 | 用途 |
|------|---------|------|
| SwiftUI `Form` / `Section` | macOS 11+ | 设置面板容器，现有 |
| SwiftUI `List` + `ForEach.onMove` | macOS 10.15+ | 可拖动重排列表 |
| SwiftUI `ColorPicker` | macOS 11+ | 颜色选择，绑定 `Binding<Color>` |
| SwiftUI `Slider` | macOS 11+ | 阈值滑块 |
| SwiftUI `Toggle` | macOS 11+ | 指标开关/区块开关 |
| `NSColor(hex:)` / `hexString` | 项目已有 | customColors 往返转换 |
| `NSColor(_ color: Color)` | macOS 11+（SDK 验证）| Color → NSColor 转换 |
| `Color(nsColor:)` | macOS 12+（SDK 验证）| NSColor → Color 转换 |
| `@Observable` + `@Bindable` | macOS 14+ | SettingsManager 绑定（现有） |

### 无新包安装

本阶段零外部依赖新增。所有能力均来自 Apple SDK 或项目已有代码。

---

## Package Legitimacy Audit

> 本阶段不安装任何外部包。跳过。

---

## Architecture Patterns

### System Architecture Diagram

```
用户操作控件
     │
     ▼
SettingsView (SwiftUI, @Bindable settings)
     │  computed Binding helpers
     │  (thresholdBinding / colorBinding / enabledBinding)
     ▼
SettingsManager.shared (@Observable @MainActor singleton)
     │  setter → UserDefaults.set + postChange(keys:)
     ▼
NotificationCenter .settingsDidChange
     │
     ├─► MetricCollector.setupSettingsObserver
     │        │
     │        ├─ refreshInterval changed → reconfigure()
     │        └─ other keys → applyNow()
     │              │
     │              └─► StatusBarManager.updateTitle(...)
     │                       └─ colorForUsage reads SettingsManager live
     │
     └─► DashboardView.body (SwiftUI @Observable 自动追踪)
              │ reads showBatterySection / showProcessSection
              └─ 条件渲染 BatterySectionView / ProcessResourceSectionView
```

### Recommended Project Structure

```
MacStatus/UI/Views/
└── SettingsView.swift          ← 全部改造在此（含内嵌子 struct）
MacStatus/Utils/
└── SettingsManager.swift       ← 新增两个 bool 键
MacStatus/UI/Views/
└── DashboardView.swift         ← 新增可见性门控
```

> 优先将 `MetricOrderRow`、`ThresholdSubsection`、`ColorSubsection` 内嵌为私有 struct，
> 避免 pbxproj 注册风险（Phase 7/8 教训）。

---

## Q1: macOS 14 List 拖动重排（含 Toggle 行）

### 关键发现：EditMode 在 macOS 上不可用

**SDK 验证来源：** `/Applications/Xcode.app/.../MacOSX.sdk/.../SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface` 第 16682–16707 行。

```swift
@available(iOS 13.0, tvOS 13.0, *)
@available(macOS, unavailable)    // ← CONFIRMED: EditMode 对 macOS 目标不存在
@available(watchOS, unavailable)
public enum EditMode : Swift.Sendable { ... }

@available(macOS, unavailable)
public var editMode: Binding<EditMode>? { ... }
```

`UI-SPEC.md` 第 89 行的 `.environment(\.editMode, .constant(.active))` **在 macOS 14 目标上无法编译**。须删除。

### macOS 上的正确拖动重排模式

在 macOS 上，`List { ForEach(...).onMove }` 不需要 EditMode。当 `.onMove` 被提供时，macOS 行为如下：

- **没有固定可见的"三横线"拖动柄**（macOS 的原生列表拖动行为）：用户选中行后可直接拖动。
- 若需要显式拖动柄图标，使用 `moveDisabled/onHover` 模式（见下）。

### 推荐实现模式（macOS 14，含 Toggle 行）

```swift
// MARK: - 状态栏指标 section（内嵌于 SettingsView.body 的 Form 中）

Section("状态栏指标") {
    List {
        ForEach(settings.metricOrder) { metric in
            MetricOrderRow(metric: metric, settings: settings)
        }
        .onMove { from, to in
            // settings.metricOrder setter 写 UserDefaults + 发 .settingsDidChange
            settings.metricOrder.move(fromOffsets: from, toOffset: to)
        }
    }
    .frame(height: CGFloat(settings.metricOrder.count) * 36)
    // ↑ List 内嵌于 Form 时必须给固定高度，否则折叠为零高（已知 macOS 行为）
    .listStyle(.plain)          // Form 内的 List 用 plain 样式避免双重 grouped 外观
}
```

```swift
// MARK: - MetricOrderRow（内嵌私有 struct）

private struct MetricOrderRow: View {
    let metric: Metric
    @Bindable var settings: SettingsManager

    // 是否悬停在拖动柄区域
    @State private var isHoveringHandle = false

    var body: some View {
        HStack(spacing: 8) {
            // 显式拖动柄图标（仅在悬停时激活拖动）
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .onHover { hovering in
                    isHoveringHandle = hovering
                }

            // 指标中文名（已禁用时灰显）
            Text(metric.displayName)
                .foregroundStyle(
                    enabledBinding.wrappedValue ? .primary : .secondary
                )

            Spacer()

            // 启用开关
            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .moveDisabled(!isHoveringHandle)
        // ↑ 仅当鼠标悬停在拖动柄上时才允许拖动，其他区域点击不会误触发拖动手势
    }

    /// 计算 Binding<Bool>：enabledMetrics.contains(metric) ↔ append/remove
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

extension Metric {
    var displayName: String {
        switch self {
        case .cpu:     return "CPU"
        case .memory:  return "内存"
        case .network: return "网络"
        case .gpu:     return "GPU"
        case .battery: return "电池"  // 不会出现在此列表中
        }
    }
}
```

### List 高度与 Form 的已知问题

**已知 macOS 行为（多源证实）：** `List` 嵌入 `Form`（或任何非 `ScrollView` 的父容器）时，SwiftUI **不会自动计算内容高度**，列表折叠为零高。解法：必须提供 `.frame(height:)` 或 `.frame(minHeight:)`。

**推荐高度计算：**

```swift
// 4 行 × 36pt/行（macOS 默认 List 行高约 32–36pt）
.frame(height: CGFloat(settings.metricOrder.count) * 36)
```

如果 executor 发现行高有偏差，可用 `preferredRowHeight` 或实测值调整。固定行数（始终 4 行）使计算简单。

### macOS 与 popover 的 onMove Bug（不影响本项目）

Apple Forums thread/742462 记录了 Mac Catalyst popover 中 `List.onMove` 在 macOS Sonoma 上存在 bug（onMove 回调不触发）。**本项目的设置窗口使用 NSWindow（非 popover）**，不受此 bug 影响。

---

## Q2: ColorPicker ↔ customColors hex 往返 Binding

### SDK 验证的官方 API

```
// 来源：MacOSX.sdk SwiftUI.swiftinterface 第 18565–18592 行

// NSColor → SwiftUI Color（macOS 12+）
Color(nsColor: NSColor)

// 旧式：NSColor → SwiftUI Color（macOS 10.15+，已废弃，编译警告）
// @available(macOS, introduced: 10.15, deprecated: 100000.0)
Color(_ color: NSColor)   // 建议用 Color(nsColor:) 代替

// SwiftUI Color → NSColor（macOS 11+）
NSColor(_ color: Color)   // [VERIFIED: MacOSX.sdk SwiftUI.swiftinterface]
```

**所有版本均满足 macOS 14 部署目标。**

### ColorPicker API（SDK 验证）

```swift
// ColorPicker 可用 macOS 11+，本项目目标 macOS 14+ 完全满足
ColorPicker("警告色", selection: $boundColor, supportsOpacity: false)
// supportsOpacity: false ← 颜色不需要 alpha 通道，关闭透明度控制
```

### 计算 Binding<Color> 的完整实现

**关键约束：** 不要在 `body` 内动态创建 `Binding`（会导致无限重渲染）。将计算 Binding 定义为子 struct 的计算属性。

```swift
private struct ColorSubsection: View {
    let metric: Metric
    @Bindable var settings: SettingsManager

    // ── 颜色默认值（与 StatusBarManager.colorForUsage 内置默认色对齐）
    private let defaultWarningHex = "#FF9500"   // 系统橙
    private let defaultCriticalHex = "#FF3B30"  // 系统红

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("警告色")
                Spacer()
                ColorPicker("警告色", selection: warningColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44)
            }

            HStack {
                Text("严重色")
                Spacer()
                ColorPicker("严重色", selection: criticalColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44)
            }

            HStack {
                Spacer()
                Button("恢复默认") {
                    resetColors()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.accentColor)
            }
        }
    }

    // MARK: - Computed Bindings（定义为计算属性，不在 body 内构造，避免无限重渲染）

    private var warningColorBinding: Binding<Color> {
        colorBinding(for: "warning", defaultHex: defaultWarningHex)
    }

    private var criticalColorBinding: Binding<Color> {
        colorBinding(for: "critical", defaultHex: defaultCriticalHex)
    }

    private func colorBinding(for level: String, defaultHex: String) -> Binding<Color> {
        Binding {
            // 读：hex string → NSColor → SwiftUI Color
            let hex = settings.customColors[metric.rawValue]?[level] ?? defaultHex
            let ns = NSColor(hex: hex) ?? NSColor(hex: defaultHex)!
            return Color(nsColor: ns)           // Color(nsColor:) 可用 macOS 12+
        } set: { newColor in
            // 写：SwiftUI Color → NSColor → hex string → customColors
            let ns = NSColor(newColor)          // NSColor(_ color: Color) 可用 macOS 11+
            let hex = ns.hexString              // 项目已有 NSColor+Hex 扩展
            var updated = settings.customColors
            var levels = updated[metric.rawValue] ?? [:]
            levels[level] = hex
            updated[metric.rawValue] = levels
            settings.customColors = updated     // setter 写 UserDefaults + 发 .settingsDidChange
        }
    }

    private func resetColors() {
        var updated = settings.customColors
        updated.removeValue(forKey: metric.rawValue)
        settings.customColors = updated         // 清除 → colorForUsage 自动回退内置默认色
    }
}
```

### NSColor(newColor) 的颜色空间注意事项

`NSColor(_ color: Color)` 初始化后，颜色空间由 SwiftUI Color 的内部表示决定（通常为 sRGB 或 Display P3）。项目已有的 `hexString` 在转换时通过 `.usingColorSpace(.sRGB)` 统一到 sRGB 并截断到 0–255，已处理 Display P3 宽色域分量可能超过 1.0 的边界情况，无需额外处理。

---

## Q3: 嵌套字典 customThresholds 的 Binding<Double>

### 计算 Binding 模式（防无限重渲染）

与 ColorPicker 相同：将计算 Binding 定义为计算属性，不在 `body` 内动态构造。

```swift
private struct ThresholdSubsection: View {
    let metric: Metric
    @Bindable var settings: SettingsManager

    // 各指标的默认阈值（与 StatusBarManager.defaultWarning/Critical 对齐）
    private var defaultWarning: Double {
        switch metric {
        case .cpu:    return settings.cpuWarningThreshold
        case .memory: return settings.memoryWarningThreshold
        case .gpu:    return 60.0
        default:      return 60.0
        }
    }
    private var defaultCritical: Double {
        switch metric {
        case .cpu:    return settings.cpuCriticalThreshold
        case .memory: return settings.memoryCriticalThreshold
        case .gpu:    return 80.0
        default:      return 80.0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.displayName)
                .font(.caption.weight(.semibold))

            // Warning Slider
            Text("\(metric.displayName) 警告：\(Int(warningBinding.wrappedValue))%")
            Slider(value: warningBinding, in: 30...90, step: 5)
                .onChange(of: warningBinding.wrappedValue) { _, newWarning in
                    // 约束：warning < critical
                    let crit = criticalBinding.wrappedValue
                    if newWarning >= crit {
                        criticalBinding.wrappedValue = min(newWarning + 5, 95)
                    }
                }

            // Critical Slider
            Text("\(metric.displayName) 严重：\(Int(criticalBinding.wrappedValue))%")
            Slider(value: criticalBinding, in: 50...95, step: 5)
                .onChange(of: criticalBinding.wrappedValue) { _, newCritical in
                    // 约束：critical > warning
                    let warn = warningBinding.wrappedValue
                    if newCritical <= warn {
                        warningBinding.wrappedValue = max(newCritical - 5, 30)
                    }
                }

            HStack {
                Spacer()
                Button("恢复默认") {
                    resetThresholds()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.accentColor)
            }
        }
    }

    // MARK: - Computed Bindings

    private var warningBinding: Binding<Double> {
        thresholdBinding(for: "warning", default: defaultWarning)
    }
    private var criticalBinding: Binding<Double> {
        thresholdBinding(for: "critical", default: defaultCritical)
    }

    private func thresholdBinding(for level: String, default defaultValue: Double) -> Binding<Double> {
        Binding {
            settings.customThresholds[metric.rawValue]?[level] ?? defaultValue
        } set: { newValue in
            var updated = settings.customThresholds
            var levels = updated[metric.rawValue] ?? [:]
            levels[level] = newValue
            updated[metric.rawValue] = levels
            settings.customThresholds = updated  // setter clamp 0...100 + postChange
        }
    }

    private func resetThresholds() {
        var updated = settings.customThresholds
        updated.removeValue(forKey: metric.rawValue)
        settings.customThresholds = updated
    }
}
```

### warning < critical 约束的实现策略

约束在 UI 层通过 `.onChange` 执行，分两方向：

| 调整方向 | 触发条件 | 行为 |
|---------|---------|------|
| 调高 warning | `newWarning >= critical` | `critical = min(newWarning + 5, 95)` |
| 调低 critical | `newCritical <= warning` | `warning = max(newCritical - 5, 30)` |

SettingsManager setter 已对所有值做 0...100 clamp，UI 层再加 warning<critical 约束是双重保障。**不**在 Binding setter 里直接修改另一个字段（会导致 onChange 递归），而是在 `.onChange` 修饰符中单独处理。

---

## Q4: SettingsManager 新增 showBatterySection/showProcessSection

### 新增模式（完全复用既有 @ObservationIgnored + 计算 getter/setter 模式）

```swift
// MARK: - Keys（在 Keys enum 中新增）
static let showBatterySection  = "showBatterySection"
static let showProcessSection  = "showProcessSection"

// MARK: - Backing Storage（新增）
@ObservationIgnored private var _showBatterySection: Bool = true
@ObservationIgnored private var _showProcessSection: Bool = true

// MARK: - Public Properties（新增）
var showBatterySection: Bool {
    get { _showBatterySection }
    set {
        _showBatterySection = newValue
        defaults.set(newValue, forKey: Keys.showBatterySection)
        postChange(keys: [Keys.showBatterySection])
    }
}

var showProcessSection: Bool {
    get { _showProcessSection }
    set {
        _showProcessSection = newValue
        defaults.set(newValue, forKey: Keys.showProcessSection)
        postChange(keys: [Keys.showProcessSection])
    }
}
```

### 迁移策略：不新增 schemaVersion

**裁定：不 bump schemaVersion。** 理由：

1. `UserDefaults.bool(forKey:)` 在 key 不存在时返回 `false`，但我们期望默认值 `true`。
2. 现有 `loadAll()` 对数值型 key 已有 `object(forKey:) == nil` 判断模式。
3. 新增两个 bool key 无破坏性，直接在 `loadAll()` 添加 nil 检查即可。

```swift
// 在 loadAll() 中新增（紧接现有 _launchAtLogin 之后）：
if defaults.object(forKey: Keys.showBatterySection) == nil {
    _showBatterySection = true      // 默认 true（弹窗显示区块）
} else {
    _showBatterySection = defaults.bool(forKey: Keys.showBatterySection)
}

if defaults.object(forKey: Keys.showProcessSection) == nil {
    _showProcessSection = true
} else {
    _showProcessSection = defaults.bool(forKey: Keys.showProcessSection)
}
```

这符合 Phase 6 既有迁移模式，schemaVersion 保持 v1，无需 `migrateToV1()` 或新 migration 函数。

### 是否触发 applyNow？

**裁定：postChange 可以发送，但 applyNow 路径对弹窗区块无实际效果。**

`applyNow()` 调用 `StatusBarManager.updateTitle()`，与弹窗区块可见性无关。DashboardView 通过 @Observable 自动追踪 `showBatterySection`/`showProcessSection` 的变化，无需 applyNow。

`postChange` 仍应调用（保持接缝完整性，未来扩展用），MetricCollector 的 `settingsObserver` 会触发 `applyNow()`，代价极小（仅重新推送已缓存数据），且无害。

---

## Q5: DashboardView 响应 showBatterySection/showProcessSection

### 裁定：直接读 @Observable SettingsManager.shared

**理由（多源证实）：**

- Swift Observation 框架：`body` 内读取 `@Observable` 对象的属性，SwiftUI 自动建立追踪依赖，无需 @State/@EnvironmentObject。
- `SettingsManager.shared` 是 `@Observable @MainActor` singleton，`DashboardView` 已在 `@MainActor` 上下文中运行。
- 直接读取是最简路径，避免在 DashboardState 增加冗余镜像字段和同步逻辑。

**DashboardView 改造（仅相关部分）：**

```swift
// DashboardView.body 内（body 开头声明 settings 引用，建立追踪）
var body: some View {
    let settings = SettingsManager.shared  // 在 body 内读取，建立 Observation 依赖
    VStack(spacing: 8) {
        // ... 现有 metric cards 网格 ...

        // 电池区块：硬件门控（hasBattery）叠加设置门控（showBatterySection）
        if settings.showBatterySection && state.hasBattery, let battery = state.battery {
            BatterySectionView(snapshot: battery)
        }

        // 进程区块：仅设置门控（无硬件条件）
        if settings.showProcessSection {
            // ... 现有 ProcessListView + ProcessResourceSectionView ...
        }

        // ... footer ...
    }
}
```

**注意：** 直接在 `body` 内用 `let settings = SettingsManager.shared` 而非声明为 `@State`，因为 singleton 的生命周期由 SettingsManager 自己管理，SwiftUI Observation 会在 body 访问时自动追踪。

---

## Q6: "恢复默认"语义

### customThresholds 恢复默认

```swift
// 移除整个 metric key → colorForUsage/StatusBarManager 自动回退到内置默认值
var updated = settings.customThresholds
updated.removeValue(forKey: metric.rawValue)
settings.customThresholds = updated
// ↑ setter 执行：_customThresholds 更新 + UserDefaults JSON 重写 + postChange + applyNow
```

### customColors 恢复默认

```swift
var updated = settings.customColors
updated.removeValue(forKey: metric.rawValue)
settings.customColors = updated
// ↑ 同上
```

### 回退机制（已有，无需改动）

`StatusBarManager.colorForUsage(_:metric:)` 已实现：

```swift
let warning  = settings.customThresholds[metric.rawValue]?["warning"]  ?? defaultWarning(for: metric)
let critical = settings.customThresholds[metric.rawValue]?["critical"] ?? defaultCritical(for: metric)
// 当 customThresholds[metric.rawValue] == nil 时，自动回退到 defaultWarning/defaultCritical
```

色值同理。`removeValue(forKey:)` 清除 key 后，`?["warning"]` 返回 `nil`，fallback 到内置默认值。

---

## Q7: macOS 14 Form 滚动与 ColorPicker 布局

### Form 可滚动策略

当 section 数量增加导致内容超出窗口时，macOS 上的 `Form.formStyle(.grouped)` **已自动带滚动条**（Form 内部使用 List，List 自带滚动）。

**窗口高度策略：**

```swift
// SettingsWindowManager.showSettings() 中，移除固定高度，改为最小高度约束：
// 原：.frame(width: 380, height: 440)
// 改：
.frame(width: 420)       // 宽度从 380 增至 420（为 ColorPicker 行留空间）
.frame(minHeight: 400)   // 最小高度保证初始显示合理，内容超出时自动滚动
```

**如果 Form 不自动滚动（macOS 版本差异）：** 在 Form 外包一层 ScrollView（如需）。但 macOS 14 的 `.formStyle(.grouped)` 已内含滚动，通常无需额外 ScrollView。

### ColorPicker 在 Form 行内的布局

`ColorPicker` 在 Form 行内默认占满宽度并显示标签+色块+展开箭头。要控制尺寸：

```swift
HStack {
    Text("警告色")
    Spacer()
    ColorPicker("", selection: $warningColor, supportsOpacity: false)
        .labelsHidden()    // 隐藏内置标签（已由 HStack 左侧 Text 提供）
        .frame(width: 44)  // 仅显示色块圆形按钮，点击展开系统颜色面板
}
```

`.labelsHidden()` 仅隐藏 ColorPicker 的内置文字标签，色块本身仍可见可点击。`.frame(width: 44)` 使色块不撑满行宽。

---

## Don't Hand-Roll

| 问题 | 不要自建 | 用内置方案 | 原因 |
|------|---------|---------|------|
| Color ↔ NSColor 转换 | 自定义 CGColor 组件解析 | `Color(nsColor:)` + `NSColor(_ color:)` | SDK 官方 API，已验证可用 macOS 11+/12+ |
| hex ↔ NSColor 转换 | 新写扩展 | 项目已有 `NSColor+Hex.swift` | 已经过测试，满足需求 |
| 列表拖动柄 | 自定义 drag gesture | `List.onMove` + `moveDisabled/onHover` | 系统原生，VoiceOver 自动可用 |
| 嵌套字典 Binding | @AppStorage 裸存储 | `Binding(get:set:)` 计算属性 | 保持 SettingsManager 单一真源 |
| warning<critical 约束 | SettingsManager setter 互锁 | UI 层 `.onChange` 单向推送 | 防止 setter 递归调用 |

---

## Common Pitfalls

### 陷阱 1：EditMode 在 macOS 编译失败

**什么会出错：** 使用 `.environment(\.editMode, .constant(.active))` 会产生编译错误："'editMode' is unavailable in macOS"。
**根本原因：** `EditMode` 枚举及 `editMode` 环境值均标记为 `@available(macOS, unavailable)`（SDK 验证）。
**如何避免：** 直接使用 `List { ForEach.onMove }` 加 `moveDisabled/onHover` 模式，不设置 editMode。
**检测信号：** Xcode 编译器立即报错，不会是运行时问题。

### 陷阱 2：List 嵌入 Form 时高度折叠为零

**什么会出错：** List 在 Form/Section 内不提供 `.frame(height:)` 时，可能渲染为零高。
**根本原因：** SwiftUI 对嵌套滚动视图的高度推断不完整，List 内嵌于 Form（本身也是 List）时高度协商失效。
**如何避免：** 明确指定 `.frame(height: count * rowHeight)`，例如 4 行 × 36pt。
**检测信号：** 运行后看不到列表行，但 Form 其他 section 正常显示。

### 陷阱 3：在 body 内动态构造 Binding 导致无限重渲染

**什么会出错：** 在 `var body` 内写 `let binding = Binding { ... } set: { ... }` 然后传给控件。每次 body 重渲染都创建新 Binding 对象，SwiftUI 检测到 Binding"变化"后再次重渲染，无限循环。
**根本原因：** Binding 对象标识不稳定。
**如何避免：** 将 `Binding(get:set:)` 定义为子 struct 的**计算属性**，不在 body 内局部变量构造。
**检测信号：** CPU 飙升至 100%，控件不响应；打印日志会看到 body 无限被调用。

### 陷阱 4：Bool 键默认值错误（UserDefaults.bool 返回 false）

**什么会出错：** 首次安装时 `showBatterySection` 和 `showProcessSection` 不存在，`defaults.bool(forKey:)` 返回 `false`，弹窗的电池和进程区块默认隐藏。
**根本原因：** `UserDefaults.bool(forKey:)` 在 key 缺失时返回 Swift 零值 `false`，非我们期望的 `true`。
**如何避免：** 在 `loadAll()` 中用 `defaults.object(forKey:) == nil` 判断后赋默认 `true`（见 Q4 代码）。
**检测信号：** 新安装后打开弹窗，电池/进程区块消失，但设置窗口的 Toggle 显示 off。

### 陷阱 5：`$settings.showBatterySection` binding 在 @Bindable 内嵌套字典的用法

**什么会出错：** `customThresholds`/`customColors` 是 `[String:[String:Double]]` 类型，`$settings.customThresholds["cpu"]["warning"]` 返回 `Binding<Double?>` 而非 `Binding<Double>`，Slider 无法直接绑定可选型。
**如何避免：** 使用 Q3/Q2 所示的 `Binding(get:set:)` 计算属性，在 get 中提供默认值展开可选型。

### 陷阱 6：`onChange(of:)` 的签名（Swift 6 / macOS 14）

**什么会出错：** macOS 14 + Swift 6 使用新签名 `onChange(of:) { oldValue, newValue in }` 而非旧式 `onChange(of:) { newValue in }`（旧式已废弃但可用，编译器会警告）。
**如何避免：** 使用双参数版本 `.onChange(of: warningBinding.wrappedValue) { _, newWarning in ... }`。

---

## Code Examples

### 完整的 SettingsView Section 骨架（展示集成方式）

```swift
// Source: 本项目 SettingsView.swift 改造目标
struct SettingsView: View {
    @Bindable var settings = SettingsManager.shared

    var body: some View {
        Form {
            // ── Section 1: 通用（保留，移除"显示模式"行）
            Section("通用") {
                // 刷新间隔 Picker + 登录时启动 Toggle（现有代码保留）
            }

            // ── Section 2: 状态栏指标（新增）
            Section("状态栏指标") {
                List {
                    ForEach(settings.metricOrder) { metric in
                        MetricOrderRow(metric: metric, settings: settings)
                    }
                    .onMove { from, to in
                        settings.metricOrder.move(fromOffsets: from, toOffset: to)
                    }
                }
                .frame(height: CGFloat(settings.metricOrder.count) * 36)
                .listStyle(.plain)
            }

            // ── Section 3: 弹窗区块（新增）
            Section("弹窗区块") {
                Toggle("电池区块", isOn: $settings.showBatterySection)
                Toggle("进程区块", isOn: $settings.showProcessSection)
            }

            // ── Section 4: 状态栏文字模式（从通用移出）
            Section("状态栏文字模式") {
                Picker("", selection: $settings.displayMode) {
                    Text("详细").tag(DisplayMode.full)
                    Text("紧凑").tag(DisplayMode.compact)
                    Text("百分比").tag(DisplayMode.percentage)
                }
                .pickerStyle(.segmented)
            }

            // ── Section 5: 告警阈值（泛化原有全局滑块）
            Section("告警阈值") {
                ForEach([Metric.cpu, .memory, .gpu], id: \.rawValue) { metric in
                    ThresholdSubsection(metric: metric, settings: settings)
                    if metric != .gpu { Divider() }
                }
            }

            // ── Section 6: 配色（新增）
            Section("配色") {
                ForEach([Metric.cpu, .memory, .gpu], id: \.rawValue) { metric in
                    ColorSubsection(metric: metric, settings: settings)
                    if metric != .gpu { Divider() }
                }
            }

            // ── Section 7: 数据（保留）
            // ── Section 8: 关于（保留，版本号更新为 v2.0）
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .frame(minHeight: 400)
        .padding()
    }
}
```

---

## Assumptions Log

> 以下为 `[ASSUMED]` 标记的声明，执行阶段前需关注。

| # | 声明 | 所在节 | 出错风险 |
|---|------|--------|---------|
| A1 | macOS 14 List 行高约为 36pt | Q1 List 高度 | 实际行高受系统字体大小设置影响；建议 executor 实测并微调倍数（32–40pt 均合理） |
| A2 | DashboardView 直接读 SettingsManager.shared 可在 body 中建立 Observation 追踪 | Q5 | Observation 框架保证；如发现追踪失效，备选方案是在 PopoverManager 中监听 .settingsDidChange 并更新 DashboardState |
| A3 | Form.formStyle(.grouped) 在 macOS 14 内容超出时自动滚动 | Q7 | 若不滚动，在 Form 外包 ScrollView 作为备选 |

**高置信度声明（SDK 验证，无 ASSUMED）：**
- EditMode @available(macOS, unavailable) — SDK 接口文件直接验证
- NSColor(_ color: Color) 可用 macOS 11+ — SDK 接口文件直接验证
- Color(nsColor:) 可用 macOS 12+ — SDK 接口文件直接验证
- ColorPicker 可用 macOS 11+，接受 Binding<Color>，支持 supportsOpacity:false — SDK 接口文件直接验证
- List.onMove 可用 macOS 10.15+ — SDK 接口文件直接验证

---

## Open Questions (RESOLVED)

所有关键技术问题均已解决。

1. **EditMode 在 macOS 上的可用性** → 已解决：不可用（`@available(macOS, unavailable)`，SDK 验证）。正确模式：`onMove` + `moveDisabled/onHover`，无需 EditMode。

2. **Color ↔ NSColor 官方桥接 API** → 已解决：`Color(nsColor:)` macOS 12+，`NSColor(_ color: Color)` macOS 11+，均满足目标 macOS 14。

3. **嵌套字典 Binding 是否会导致无限重渲染** → 已解决：在 `body` 外以计算属性定义 Binding 即可避免。

4. **showBatterySection/showProcessSection 迁移策略** → 已解决：不 bump schemaVersion，在 `loadAll()` 添加 nil 检查赋默认 `true`。

5. **DashboardView 追踪方式** → 已解决：直接读 `SettingsManager.shared` 属性即可建立 @Observable 追踪，无需镜像到 DashboardState。

---

## Environment Availability

> 本阶段为纯代码/UI 改造，无外部 CLI 工具或服务依赖。跳过。

所有依赖均为 Apple SDK（SwiftUI、AppKit），已在现有项目中可用。

---

## Validation Architecture

> `workflow.nyquist_validation` 在 `.planning/config.json` 中未设置（缺失键），按默认值 `true` 处理。
> 但本项目所有测试均为手动验证（无 XCTest 基础设施），故测试框架框架部分不适用。

| Req ID | 行为 | 测试类型 | 验证方式 |
|--------|------|---------|---------|
| SET-01 | 右键菜单 → 设置窗口打开 | 手动 | 右键菜单点击"偏好设置…" |
| SET-02 | 逐指标 Toggle 即时更新状态栏 | 手动 | 关闭 CPU → 状态栏消失 CPU 段 |
| SET-03 | 拖动重排即时更新状态栏顺序 | 手动 | 拖动 Memory 到第一行 → 状态栏顺序变化 |
| SET-04 | 阈值 Slider 即时更新状态栏着色 | 手动 | 调低 CPU warning 到 10% → 颜色立即变化 |
| SET-05 | ColorPicker 即时更新状态栏配色 | 手动 | 改 CPU warning 色为蓝色 → 状态栏立即变蓝 |
| SET-06 | displayMode Picker 即时切换状态栏文字格式 | 手动 | 切换"详细"→"紧凑"→"百分比" |
| 弹窗区块 | showBattery/Process Toggle 即时隐藏弹窗区块 | 手动 | 关闭"进程区块"→ 弹窗中进程列表消失 |
| 持久化 | 所有设置重启后保持 | 手动 | 改动设置 → 退出 → 重新启动 → 验证设置保留 |

---

## Security Domain

> 本阶段为纯 UI 控件层，扩展已有 SettingsManager（Phase 6 已做安全设计）。

| ASVS Category | 适用 | 标准控制 |
|---------------|------|---------|
| V5 Input Validation | 是 | SettingsManager setter：customColors 过滤非 `#RRGGBB`；customThresholds clamp 0...100；已就绪 |
| V6 Cryptography | 否 | 无加密操作 |
| V2/V3/V4 | 否 | 无认证/会话/访问控制 |

**新增威胁面：** 无。ColorPicker 输入经 NSColor.hexString 输出时已做截断（0–255），满足 T-06-06 容错解析要求。

---

## Sources

### Primary（HIGH confidence）

- `[VERIFIED: MacOSX.sdk SwiftUI.swiftinterface]` — `/Applications/Xcode.app/.../MacOSX.sdk/System/Library/Frameworks/SwiftUI.framework/.../arm64e-apple-macos.swiftinterface`
  - 第 16682–16707 行：EditMode `@available(macOS, unavailable)` 直接确认
  - 第 18565–18592 行：Color(nsColor:) macOS 12+，NSColor(_ color: Color) macOS 11+
  - 第 10816 行：onMove macOS 10.15+
  - 第 23334–23365 行：ColorPicker macOS 11+，supportsOpacity 参数
- [Apple Developer Documentation — List.onMove](https://developer.apple.com/documentation/swiftui/dynamicviewcontent/onmove(perform:))
- [Apple Developer Documentation — Color.init(nsColor:)](https://developer.apple.com/documentation/swiftui/color/init(nscolor:))

### Secondary（MEDIUM confidence）

- [nilcoalescing.com — List Reordering with TextFields on macOS](https://nilcoalescing.com/blog/ListReorderingWhileStillBeingAbleToEditTheListItems/) — moveDisabled/onHover 模式
- [fatbobman.com — Mastering Observation Framework](https://fatbobman.com/en/posts/mastering-observation/) — @Observable 体内直接读取追踪
- [Apple Developer Forums thread/742462](https://developer.apple.com/forums/thread/742462) — macOS Sonoma popover onMove bug（本项目不受影响）
- [Apple Developer Forums thread/772167](https://developer.apple.com/forums/thread/772167) — body 内动态构造 Binding 导致无限重渲染问题

### Tertiary（LOW confidence）

- 无。所有关键技术声明均已通过 SDK 接口文件或官方 Forums 验证。

---

## Metadata

**Confidence breakdown:**
- Standard Stack: HIGH — SDK 接口文件直接验证所有 API 可用性
- Architecture: HIGH — 基于现有代码深度阅读，模式完全继承 Phase 6
- Pitfalls: HIGH — EditMode 不可用为 SDK 级事实；其余均有 Apple Forums 或代码逻辑支撑

**Research date:** 2026-06-17
**Valid until:** 2026-12-17（SwiftUI macOS API 稳定，新版本可能新增 API 但不会移除）

---

## RESEARCH COMPLETE
