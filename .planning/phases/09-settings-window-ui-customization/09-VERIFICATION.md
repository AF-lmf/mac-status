---
phase: "09-settings-window-ui-customization"
verified: "2026-06-17T00:00:00Z"
status: human_needed
score: 12/12
overrides_applied: 0
human_verification:
  - test: "右键点击状态栏图标，选择「偏好设置…」，确认独立设置窗口打开（SET-01）"
    expected: "NSWindow 标题为「MacStatus 偏好设置」，Form 宽度约 420pt，包含 8 个 Section"
    why_human: "窗口弹出是运行时行为，无法由 grep 或构建验证"
  - test: "在「状态栏指标」Section 关闭 CPU Toggle，观察状态栏（SET-02）"
    expected: "状态栏 CPU 段立即消失；重新开启后立即恢复"
    why_human: "enabledMetrics → StatusBarManager.updateTitle 的即时响应是运行时视觉行为"
  - test: "在「状态栏指标」Section 将鼠标悬停在某指标的「≡」图标上，拖动到新位置（SET-03）"
    expected: "状态栏指标顺序立即按新排列更新"
    why_human: "List.onMove 拖动排序的即时视觉响应只能在实际运行中验证"
  - test: "在「弹窗区块」Section 关闭「进程区块」Toggle，打开弹窗（SET-02 进程子项）"
    expected: "弹窗中 ProcessListView、CPU Top 5、内存 Top 5 三个区块整体消失"
    why_human: "运行时 UI 门控行为"
  - test: "在「弹窗区块」Section 关闭「电池区块」Toggle（笔记本），打开弹窗（SET-02 电池子项）"
    expected: "弹窗中 BatterySectionView 立即隐藏；台式机（无电池）上 hasBattery=false 原有行为不变"
    why_human: "运行时 UI 门控行为，台式机需独立验证降级逻辑"
  - test: "在「告警阈值」Section 将 CPU 警告 Slider 拖低至 30%（低于当前 CPU 使用率），观察状态栏（SET-04）"
    expected: "状态栏 CPU 数值颜色立即变为橙色（warning 区间）"
    why_human: "阈值变化→状态栏颜色即时响应是运行时视觉行为"
  - test: "将 CPU warning Slider 上移到接近 critical 值，确认 warning<critical 约束生效（SET-04）"
    expected: "warning 值 >= critical 时，critical 自动上推；critical 值 <= warning 时，warning 自动下拉"
    why_human: ".onChange 双向约束的 UI 交互体验"
  - test: "点击告警阈值「恢复默认」按钮，观察 Slider 位置和状态栏颜色（SET-04）"
    expected: "Slider 回到 defaultWarning/defaultCritical 值（CPU: 60/80，Memory: 60/80，GPU: 60/80）；状态栏颜色回到内置默认"
    why_human: "resetThresholds() 的视觉反馈只能运行时确认"
  - test: "在「配色」Section 用 ColorPicker 将 CPU 警告色改为蓝色，观察状态栏（SET-05）"
    expected: "状态栏 CPU 值在 warning 区间时立即显示蓝色"
    why_human: "ColorPicker 颜色选择 UI 及状态栏即时着色是运行时视觉行为"
  - test: "点击配色「恢复默认」按钮（SET-05）"
    expected: "状态栏 CPU 警告色恢复橙色（#FF9500），严重色恢复红色（#FF3B30）"
    why_human: "resetColors() 的视觉反馈"
  - test: "在「状态栏文字模式」Section 切换「详细/紧凑/百分比」segmented Picker（SET-06）"
    expected: "状态栏文字格式立即切换：详细→「CPU: 23% | MEM: 67%...」紧凑→「C:23% M:67%...」百分比→「23% | 67%...」"
    why_human: "displayMode 切换的即时视觉响应是运行时行为"
  - test: "修改若干设置，退出 MacStatus，重新启动，检查设置是否保持（SET-07 持久化）"
    expected: "阈值、颜色、指标顺序、开关状态、文字模式均保持重启前的值"
    why_human: "持久化跨进程生命周期，须实际重启验证"
---

# Phase 09: Settings Window UI + Customization 验证报告

**Phase Goal:** 从右键菜单打开真实设置窗口，可开关指标、拖动重排、设定自定义阈值与颜色、切换紧凑/详细状态栏模式——每项变更即时生效。
**Verified:** 2026-06-17
**Status:** human_needed
**Re-verification:** No — 初次验证

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | SET-01：右键菜单项「偏好设置…」调用 SettingsWindowManager.shared.showSettings()，打开包含 SettingsView 的 NSWindow | ✓ VERIFIED | StatusBarManager.setupRightClickMenu() 创建 NSMenuItem title=「偏好设置…」action=#selector(showPreferences)；showPreferences() 调用 SettingsWindowManager.shared.showSettings()；showSettings() 构造 NSHostingController(rootView: SettingsView()) 并呈现 NSWindow。三级链完整。 |
| 2 | SET-02：各指标 Toggle 绑定 enabledMetrics（通过 MetricOrderRow.enabledBinding 计算属性）；电池/进程区块 Toggle 绑定 showBatterySection/showProcessSection | ✓ VERIFIED | MetricOrderRow.enabledBinding 是 struct 计算属性（非 body 内局部），读 settings.enabledMetrics.contains(metric)，写 append/removeAll；Section("弹窗区块") 直接绑定 $settings.showBatterySection 和 $settings.showProcessSection。enabledMetrics setter 写 UserDefaults + postChange。 |
| 3 | SET-03：List { ForEach(settings.metricOrder, id: \.rawValue).onMove } 实现拖动重排；零 EditMode/editMode 引用 | ✓ VERIFIED | SettingsView.swift 第 31–41 行：List + ForEach + .onMove closure 调用 settings.metricOrder.move(fromOffsets:toOffset:)；grep -ic "editMode" = 0；.frame(height: CGFloat(count)*36) + .listStyle(.plain) 均存在 |
| 4 | SET-04：ThresholdSubsection 提供按指标（cpu/memory/gpu）warning/critical Slider，通过 customThresholds[metric.rawValue] 读写，warning<critical 约束通过 .onChange { _, new in } 双参数签名实现 | ✓ VERIFIED | ThresholdSubsection 第 174–265 行：warningBinding/criticalBinding 是计算属性，thresholdBinding(for:default:) 读写 settings.customThresholds[metric.rawValue]；.onChange 双参数签名确认（第 209、219 行）；resetThresholds() 调用 removeValue(forKey: metric.rawValue) |
| 5 | SET-05：ColorSubsection 提供按指标 warning/critical ColorPicker，supportsOpacity: false，经 NSColor(hex:)/Color(nsColor:) 双向转换写 customColors；resetColors() 清除条目 | ✓ VERIFIED | ColorSubsection 第 272–347 行：ColorPicker 2 处均有 supportsOpacity: false；colorBinding 读 customColors[metric.rawValue]?[level]；NSColor(hex:) = 2，Color(nsColor:) = 2；removeValue(forKey: metric.rawValue) = 2 |
| 6 | SET-06：独立 Section("状态栏文字模式") 含 .pickerStyle(.segmented)，三 tag：.full/.compact/.percentage，绑定 $settings.displayMode | ✓ VERIFIED | SettingsView.swift 第 50–59 行：LabeledContent("文字模式") 包裹 Picker 绑定 $settings.displayMode，三 tag 均含，.pickerStyle(.segmented) 确认 |
| 7 | 零 EditMode/editMode 引用（macOS 不可用，会导致编译失败） | ✓ VERIFIED | grep -ic "editmode\|EditMode" SettingsView.swift = 0 |
| 8 | 零 @AppStorage 重新引入（SET-06 硬约束：不得引入第二数据源） | ✓ VERIFIED | grep -c "@AppStorage" SettingsView.swift = 0；grep -c "@AppStorage" SettingsManager.swift = 0 |
| 9 | 所有计算 Binding 定义在 struct 计算属性中（非 body 内局部，防无限重渲染） | ✓ VERIFIED | MetricOrderRow.enabledBinding（第 155–167 行）、ThresholdSubsection.warningBinding/criticalBinding（第 239–245 行）、ColorSubsection.warningColorBinding/criticalColorBinding（第 315–321 行）均为 private var 计算属性，不在 body 内构造 |
| 10 | showBatterySection/showProcessSection 在 SettingsManager 以 object(forKey:)==nil nil-check 保证首次安装默认 true | ✓ VERIFIED | SettingsManager.swift 第 414–424 行：两个 key 各有一个 if defaults.object(forKey:) == nil { = true } else { defaults.bool } 块 |
| 11 | DashboardView 电池区块门控为 settings.showBatterySection && state.hasBattery；进程三区块被 if settings.showProcessSection 整体包裹 | ✓ VERIFIED | DashboardView.swift 第 65 行：if settings.showBatterySection && state.hasBattery, let battery = state.battery；第 70–97 行：if settings.showProcessSection 包裹三个进程区块；let settings = SettingsManager.shared 在 body 内建立 @Observable 追踪 |
| 12 | StatusBarManager.colorForUsage 实时读取 customThresholds/customColors，阈值/颜色变更即时反映到状态栏着色 | ✓ VERIFIED | StatusBarManager.swift colorForUsage(_:metric:) 第 276–292 行：直接读 settings.customThresholds[metric.rawValue]?["warning"]/"critical"] 和 settings.customColors[metric.rawValue]?["critical"]/"warning"]；SettingsManager 通过 @Observable 追踪，每次读取均获最新值 |

**Score:** 12/12 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|---------|--------|---------|
| `MacStatus/MacStatus/UI/Views/SettingsView.swift` | 8-section Form + MetricOrderRow + ThresholdSubsection + ColorSubsection 内嵌 struct | ✓ VERIFIED | 396 行，包含全部 8 个 Section 及三个内嵌私有 struct |
| `MacStatus/MacStatus/Utils/SettingsManager.swift` | showBatterySection + showProcessSection Bool 属性（Keys + backing + computed + loadAll） | ✓ VERIFIED | 459 行，10 处 showBatterySection / showProcessSection 引用，nil-check loadAll 模式正确 |
| `MacStatus/MacStatus/UI/Views/DashboardView.swift` | showBatterySection + showProcessSection 门控逻辑 | ✓ VERIFIED | 电池门控（showBatterySection && hasBattery）+ 进程三区块整体门控均存在 |
| `MacStatus/MacStatus/UI/StatusBarManager.swift` | colorForUsage 实时读 customThresholds/customColors | ✓ VERIFIED | colorForUsage 实现正确；偏好设置右键菜单项已连接 SettingsWindowManager.shared.showSettings() |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| NSMenuItem「偏好设置…」 | SettingsView NSWindow | StatusBarManager.showPreferences() → SettingsWindowManager.shared.showSettings() | ✓ WIRED | 三级链完整；showSettings() 构造 NSHostingController(rootView: SettingsView()) |
| MetricOrderRow.enabledBinding | settings.enabledMetrics | Binding(get: contains / set: append/removeAll) 计算属性 | ✓ WIRED | enabledBinding 第 155–167 行，读 .contains，写 .append/.removeAll；setter 写 UserDefaults + postChange |
| ForEach.onMove | settings.metricOrder | metricOrder.move(fromOffsets:toOffset:) | ✓ WIRED | SettingsView.swift 第 35–37 行，onMove closure 直接调用 move；metricOrder setter postChange(keys: [Keys.metricOrder]) |
| ThresholdSubsection.thresholdBinding | settings.customThresholds | Binding(get:set:) 计算属性读写 customThresholds[metric.rawValue][level] | ✓ WIRED | 第 247–257 行；setter 赋回 settings.customThresholds 触发 postChange + applyNow |
| ColorSubsection.colorBinding | settings.customColors | NSColor(hex:)/Color(nsColor:)/NSColor(_ color:)/.hexString 双向转换 | ✓ WIRED | 第 323–338 行；setter 赋回 settings.customColors 触发 postChange |
| DashboardView.showBatterySection gate | SettingsManager.shared.showBatterySection | let settings = SettingsManager.shared (@Observable 追踪) | ✓ WIRED | DashboardView.swift 第 11、65 行 |
| DashboardView.showProcessSection gate | SettingsManager.shared.showProcessSection | let settings = SettingsManager.shared (@Observable 追踪) | ✓ WIRED | DashboardView.swift 第 11、70 行 |
| StatusBarManager.colorForUsage | settings.customThresholds / customColors | 直接读 SettingsManager.shared (@Observable) | ✓ WIRED | StatusBarManager.swift 第 277–291 行 |

---

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| SettingsView（告警阈值 Section） | warningBinding / criticalBinding | settings.customThresholds[metric.rawValue][level]（Binding 计算属性读写 SettingsManager） | ✓（SettingsManager 从 UserDefaults JSON 解码，setter 写回 JSON + postChange） | ✓ FLOWING |
| SettingsView（配色 Section） | warningColorBinding / criticalColorBinding | settings.customColors[metric.rawValue][level]（NSColor+Hex 双向转换） | ✓（同上） | ✓ FLOWING |
| MetricOrderRow | enabledBinding | settings.enabledMetrics（@Observable 实时追踪） | ✓（UserDefaults stringArray 加载） | ✓ FLOWING |
| StatusBarManager.colorForUsage | warning/critical / 颜色 hex | SettingsManager.shared.customThresholds/customColors（每次调用时读取） | ✓（无缓存，读 @Observable 实时值） | ✓ FLOWING |
| DashboardView 区块门控 | settings.showBatterySection / showProcessSection | SettingsManager.shared（@Observable body 内追踪） | ✓（UserDefaults bool + nil-check loadAll） | ✓ FLOWING |

---

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| xcodebuild 编译成功 | xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug build | BUILD SUCCEEDED, exit 0 | ✓ PASS |
| EditMode/editMode = 0（macOS 不可用） | grep -ic "editMode" SettingsView.swift | 0 | ✓ PASS |
| @AppStorage = 0（无第二数据源） | grep -c "@AppStorage" SettingsView.swift + SettingsManager.swift | 0 + 0 = 0 | ✓ PASS |
| .onMove 存在 | grep -c "\.onMove" SettingsView.swift | 1 | ✓ PASS |
| supportsOpacity: false（ColorPicker 无透明度） | grep -c "supportsOpacity: false" SettingsView.swift | 2 | ✓ PASS |
| 占位文字已清除 | grep -c "由 Plan 03 实现" SettingsView.swift | 0 | ✓ PASS |

---

## Probe Execution

阶段无声明 probe 脚本，跳过（项目无 scripts/\*/tests/probe-\*.sh）。

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| SET-01 | Plan 02, 03 | 从右键菜单打开独立设置窗口 | ✓ SATISFIED | StatusBarManager 右键菜单 → SettingsWindowManager.shared.showSettings() → SettingsView NSWindow |
| SET-02 | Plan 01, 02, 03 | 逐个开关每个指标在状态栏的显示；电池/进程区块可关闭 | ✓ SATISFIED | MetricOrderRow.enabledBinding + Section("弹窗区块") Toggle + DashboardView 门控 |
| SET-03 | Plan 02 | 拖动调整状态栏各指标显示顺序 | ✓ SATISFIED | List.onMove → settings.metricOrder.move；零 EditMode 引用 |
| SET-04 | Plan 03 | 自定义各指标警告/危险阈值 | ✓ SATISFIED | ThresholdSubsection per-metric Slider + warning<critical 约束 + 恢复默认；customThresholds → StatusBarManager.colorForUsage |
| SET-05 | Plan 03 | 自定义各指标着色 | ✓ SATISFIED | ColorSubsection per-metric ColorPicker (supportsOpacity:false) + NSColor+Hex 双向转换 + 恢复默认；customColors → StatusBarManager.colorForUsage |
| SET-06 | Plan 02 | 在紧凑/详细两种状态栏文本模式间切换 | ✓ SATISFIED | Section("状态栏文字模式") + .pickerStyle(.segmented) + 三 tag(.full/.compact/.percentage)，绑定 $settings.displayMode |

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| SettingsView.swift | 88 | `// TODO: Implement via MetricCollector.purgeAll()` | ℹ️ Info | Section "数据" 的「清除历史」按钮未实现（`.disabled(true)`）。此 Section 为 Phase 9 前已有，非本阶段引入，且按钮处于禁用状态（不影响任何 SET-01..06 需求）。无参考 issue 编号——但此项目在本里程碑中未声明该 Button 为交付目标，不构成 Phase 9 阻断项。 |

**债务标记裁定：** TODO 在 Section "数据"，与 Phase 9 SET-01..06 目标无关；按钮被 `.disabled(true)` 明确标记为未激活。不构成 BLOCKER。

---

## Human Verification Required

以下运行时视觉行为无法通过源码静态分析或构建验证确认，需在实际设备上手动验证。

### 1. SET-01：右键菜单打开设置窗口

**Test:** 右键点击状态栏 MacStatus 图标，选择「偏好设置…」
**Expected:** 弹出标题为「MacStatus 偏好设置」的独立 NSWindow，含 8 个 Section 的 Form（通用/状态栏指标/弹窗区块/状态栏文字模式/告警阈值/配色/数据/关于），宽度约 420pt
**Why human:** 窗口弹出、焦点、外观是运行时行为

### 2. SET-02 + SET-03：指标开关与拖动重排

**Test:** 在「状态栏指标」Section，(a) 关闭某指标 Toggle；(b) 悬停拖动柄「≡」拖动指标到新位置
**Expected:** (a) 状态栏对应段立即消失；重新开启立即恢复。(b) 状态栏指标顺序立即按新排列更新
**Why human:** enabledMetrics → updateTitle() 和 metricOrder.move → updateTitle() 的即时视觉响应是运行时行为；拖动手势体验只能人工确认

### 3. SET-02：弹窗区块开关

**Test:** 在「弹窗区块」Section 分别关闭「电池区块」（笔记本）和「进程区块」Toggle，然后打开弹窗
**Expected:** 对应区块立即消失；台式机（无电池）关闭「电池区块」Toggle 对弹窗无效果（hasBattery=false 硬件门控）
**Why human:** 运行时弹窗可见性响应

### 4. SET-04：自定义阈值即时着色

**Test:** 将 CPU warning Slider 拖低至低于当前 CPU 使用率；再测试 warning<critical 约束（将 warning 拖到接近 critical 时，critical 自动上推）
**Expected:** 状态栏 CPU 颜色立即变橙色；warning/critical 约束自动调整可见
**Why human:** Slider 拖动 UI 交互 + 状态栏颜色即时响应是运行时视觉行为

### 5. SET-04：阈值恢复默认

**Test:** 调整阈值后点击「恢复默认」
**Expected:** Slider 回到迁移种子值（CPU: warning=60, critical=80）；状态栏颜色恢复至默认
**Why human:** 运行时 Slider 位置视觉确认

### 6. SET-05：ColorPicker 着色即时生效

**Test:** 在「配色」Section 将 CPU warning 颜色改为蓝色（ColorPicker 不显示透明度滑块）
**Expected:** 状态栏 CPU 值在 warning 区间时立即变蓝；ColorPicker 无透明度通道
**Why human:** ColorPicker UI 外观 + 状态栏即时着色是运行时视觉行为

### 7. SET-05：配色恢复默认

**Test:** 点击配色区域「恢复默认」
**Expected:** 状态栏 warning 色恢复橙色（#FF9500），critical 色恢复红色（#FF3B30）
**Why human:** 颜色视觉确认

### 8. SET-06：状态栏文字模式切换

**Test:** 在「状态栏文字模式」Section 切换「详细/紧凑/百分比」
**Expected:** 状态栏文字格式即时切换。详细模式：「CPU: 23% | MEM: 67% OK」；紧凑模式：「C:23% M:67%」；百分比模式：「23% | 67%」
**Why human:** 状态栏 UI 即时切换是运行时视觉行为

### 9. 持久化跨重启（SET-07 / 已在 Phase 6 建立，Phase 9 不得回退）

**Test:** 修改阈值、颜色、指标顺序、开关状态、文字模式，退出 MacStatus，重新启动
**Expected:** 所有设置保持；无 @AppStorage 重新引入（已由构建验证排除），持久化经 SettingsManager → UserDefaults → loadAll()
**Why human:** 跨进程生命周期验证

---

## Gaps Summary

无阻断性差距。全部 12 条可观测真值通过代码静态验证和构建验证，SET-01..06 共 6 项需求均有代码实现支撑。状态设为 `human_needed` 是因为运行时视觉行为（拖动排序即时更新、ColorPicker 着色、阈值着色即时响应）需人工在真实设备上确认。

TODO（第 88 行，「清除历史」按钮）为 Phase 9 前已有的非交付功能，按钮处于 `.disabled(true)` 状态，不构成本阶段阻断项。

---

_Verified: 2026-06-17_
_Verifier: Claude (gsd-verifier)_
