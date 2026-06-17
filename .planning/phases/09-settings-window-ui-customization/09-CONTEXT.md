# Phase 9: Settings Window UI + Customization - Context

**Gathered:** 2026-06-17
**Status:** Ready for planning

<domain>
## Phase Boundary

把前序阶段建立的能力暴露为一个完整的设置窗口控制面：从右键菜单打开独立设置窗口，可直接（即时生效）——开关哪些指标显示、拖动重排序、按指标设自定义阈值与配色、切换状态栏紧凑/详细文字模式。所有控件绑定 Phase 6 的 `SettingsManager`，改动即时反映到真实状态栏与弹窗，且跨重启持久化。覆盖 SET-01..06。这是 v2.0 的最后一个阶段（控制面，建立在 Phase 6 接缝 + Phase 7 电池 + Phase 8 进程之上）。

不做：窗内预览面板、TabView 分页、独立通知设置、新增非本阶段功能。
</domain>

<decisions>
## Implementation Decisions

### 窗口结构与指标列表 (Window Structure & Metrics List)
- 扩展现有 `SettingsView`（Phase 6 已重构为 `@Bindable var settings = SettingsManager.shared`、已能经 `SettingsWindowManager.showSettings()` 从右键菜单打开），在其单一可滚动 `Form` 中新增 section。**不**用 TabView、**不**开新窗口。
- "状态栏指标"组：SwiftUI `List { ForEach(settings.metricOrder) }.onMove`，每行 = 指标名 + 启用 `Toggle`（驱动 `enabledMetrics`）+ 拖动柄；拖动写回 `metricOrder`（SET-01 开关、SET-02 排序）。仅含状态栏指标：cpu/gpu/memory/network。
- "弹窗区块"组：电池区与进程区是 popover-only（不进状态栏组合），用**新增 bool 键** `showBatterySection`、`showProcessSection`（默认 true）控制其在弹窗中的显隐——独立于 enabledMetrics/metricOrder。SC2 "battery and process toggles included" 由此满足。
- 即时生效：所有控件绑定 `SettingsManager` → 属性 setter 写 UserDefaults + 发 `.settingsDidChange`（Phase 6 接缝）→ 状态栏 `applyNow()`（外观）/`reconfigure()`（计时）实时刷新；弹窗区块由 `DashboardView` 读取新可见性键条件渲染（SET-06 即时反映）。

### 阈值与配色定制 (Thresholds & Colors)
- 阈值编辑器仅 **cpu / memory / gpu**（有值级着色；network 无阈值色）。各指标 warning + critical 两个滑块，写 `customThresholds[metric.rawValue]["warning"/"critical"]`（Phase 6 已建该 JSON 键）。把现有全局 CPU/MEM 滑块**泛化为按指标**。范围 warning 30–90、critical 50–95、step 5；保证 warning < critical（Phase 6 setter 已 clamp 到 0...100，UI 侧再加 warning<critical 约束）。（SET-03）
- 配色：每 (指标, 等级) 一个 SwiftUI `ColorPicker`（warning 色 + critical 色），通过 `NSColor.hexString`（Phase 6 的 NSColor+Hex）写 `customColors[metric.rawValue][level]` 十六进制；读取时 `NSColor(hex:)`。（SET-04）
- 每组（阈值/配色）带"恢复默认"按钮：清除对应 metric 的 customThresholds/customColors 键 → 回退内置默认色与 `colorForUsage` 默认阈值。

### 紧凑/详细模式与窗口 (Mode & Window)
- 复用现有 `displayMode` Picker（full/compact/percentage），标为"状态栏文字模式"，选项 详细=full / 紧凑=compact / 百分比=percentage，绑定 `settings.displayMode` 即时生效（Phase 6 接缝）。（SET-05 切换、SET-06 即时+持久）。**不**新增独立 verboseMode 键。
- 窗口沿用 `SettingsWindowManager`（NSWindow + NSHostingView；LSUIElement 应用不能用 SwiftUI `Settings` scene——SC1 已满足）。仅改 SettingsView 内容。
- 现有 380×440 frame 随 section 增多**增高或让 Form 可滚动**（必要时加宽至 ~420）。菜单栏/弹窗即真实预览，**无**窗内预览面板。

### Claude's Discretion
- **DashboardView 如何响应弹窗区块可见性键**：可让 `DashboardView` 直接读取 `SettingsManager.shared`（@Observable，body 内读取自动建立 Observation 依赖），或把 `showBatterySection`/`showProcessSection` 镜像进 `DashboardState`（经 MetricCollector/PopoverManager 的设置 observer 更新）。由 Claude 依 SwiftUI 响应式最简路径裁定；优先直接读 @Observable SettingsManager（避免冗余镜像）。
- `showBatterySection`/`showProcessSection` 是否纳入 `.settingsDidChange` 的 cosmetic 分支触发 applyNow：弹窗区块显隐是 SwiftUI 响应式（@Observable），可能无需经状态栏 applyNow；由 Claude 裁定。但务必保证开关后弹窗即时反映（必要时 applyNow 也无害）。
- "状态栏指标"List 行内 Toggle + onMove 的具体 SwiftUI 实现（EditMode、拖动柄样式、List vs ForEach-in-VStack）由 Claude 设计；macOS 14 List.onMove 行为以实际为准。
- 新键的迁移：Phase 6 有 schemaVersion + migration ladder；为 showBatterySection/showProcessSection 增加默认值迁移（v?→next）或直接在 loadAll/getter 提供默认 true，由 Claude 依 Phase 6 既有模式裁定。
- ColorPicker 的 supportsOpacity（建议关闭，颜色不需 alpha）与默认值展示由 Claude 裁定。
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MacStatus/UI/Views/SettingsView.swift` — **核心改造对象**：Phase 6 已重构为 `@Bindable var settings = SettingsManager.shared`，含 通用(刷新间隔 Picker、显示模式 Picker、登录时启动 Toggle)、告警阈值(CPU/MEM 全局滑块)、数据、关于 五个 section。Phase 9 在此新增/泛化 section。`formStyle(.grouped)`、380×440 frame。
- `MacStatus/UI/Views/SettingsView.swift` 内 `SettingsWindowManager`（@MainActor 单例，NSWindow+NSHostingView，showSettings()）——已满足 SC1，无需改。
- `MacStatus/Utils/SettingsManager.swift` — @MainActor @Observable 单一真源：已有 `metricOrder [Metric]`、`enabledMetrics [Metric]`、`customThresholds [String:[String:Double]]`、`customColors [String:[String:String]]`、`displayMode`、`launchAtLogin`、schemaVersion + migration ladder + `.settingsDidChange` 广播 + `postChange(keys:)`。Phase 9 加 `showBatterySection`/`showProcessSection` 两个 bool 键。
- `MacStatus/Utils/Metric.swift` — `Metric` enum（cpu/memory/network/gpu/battery）稳定 rawValue id，CaseIterable。
- `MacStatus/Utils/NSColor+Hex.swift` — `NSColor(hex:)` / `hexString` 供 ColorPicker ↔ customColors 互转。
- `MacStatus/UI/StatusBarManager.swift` — `colorForUsage` 已实时读 customThresholds/customColors（Phase 6）；`updateTitle` 已按 enabledMetrics/metricOrder 条件组合。Phase 9 的开关/排序/阈值/配色控件经 SettingsManager → applyNow 直接驱动它，**无需改 StatusBarManager**。
- `MacStatus/UI/Views/DashboardView.swift` — 电池区块 `if state.hasBattery`、进程区块；Phase 9 追加 `showBatterySection`/`showProcessSection` 可见性门控。
- `MacStatus/Collectors/MetricCollector.swift` — `.settingsDidChange` observer → applyNow/reconfigure（Phase 6）。新键若需触发状态栏重绘走此路。

### Established Patterns
- 单一 @Observable SettingsManager 真源；@Bindable 绑定控件；didSet→UserDefaults+通知；状态栏 applyNow/reconfigure 实时重应用（Phase 6）。
- SwiftUI Form/Section/Picker/Slider/Toggle（SettingsView 现有）；ColorPicker 为本阶段新增控件。
- 值级着色读 SettingsManager 实时阈值/配色（StatusBarManager.colorForUsage）。

### Integration Points
- `SettingsManager`：+ `showBatterySection`/`showProcessSection`（bool，默认 true，computed getter/setter + backing + postChange，迁移补默认）。
- `SettingsView`：+ "状态栏指标"(List.onMove+Toggle)、"弹窗区块"(2 toggle)、按指标"阈值"(cpu/memory/gpu warning/critical 滑块)、按指标"配色"(ColorPicker + 恢复默认) section；现有全局 CPU/MEM 阈值滑块泛化/替换。
- `DashboardView`：电池/进程区块包一层 `if settings.showBatterySection`/`if settings.showProcessSection`（读 @Observable SettingsManager 或 DashboardState 镜像）。
- 无新文件预期（全部改 SettingsView/SettingsManager/DashboardView）——**若拆出新视图文件务必登记 pbxproj**（Phase 7/8 教训）。
</code_context>

<specifics>
## Specific Ideas

- 即时生效是硬约束（SET-06）：每个控件改动必须立刻反映到真实状态栏/弹窗，无保存按钮、无重启。依赖 Phase 6 接缝（已验证）。
- 持久化是硬约束：不得重新引入裸 `@AppStorage`，所有控件绑定 SettingsManager（Phase 6 单一真源）。
- 电池/进程是 popover-only：其开关控弹窗区块显隐，不混入状态栏 enabledMetrics。
- 复用 Phase 6 已建的 customThresholds/customColors/metricOrder/enabledMetrics 键与 NSColor+Hex；Phase 9 主要是"UI 控件 + 两个新可见性键"。
- 用户三个灰区全部接受推荐方案。
- 新视图文件（若有）务必登记 pbxproj。

</specifics>

<deferred>
## Deferred Ideas

- 窗内实时预览面板 → 不做（菜单栏即预览）。
- TabView 分页设置 → 不做（单表单）。
- 每指标独立刷新间隔（SET-F1）→ v2.0 已 CUT（见 STATE 横切约束）。
- 自定义通知/告警规则 → v2.0 Out of Scope。
- 导入/导出设置、配置文件同步 → 未纳入 v2.0。
- network 阈值着色 → network 无阈值色（不做）。
</deferred>
