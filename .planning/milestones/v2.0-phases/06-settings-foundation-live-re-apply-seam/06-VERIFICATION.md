---
phase: "06-settings-foundation-live-re-apply-seam"
verified: "2026-06-17T00:00:00Z"
status: passed
score: 4/4
human_validated: "2026-06-17 — 全部 5 项运行时/系统级行为经用户在真机 debug 构建上手动验证通过"
overrides_applied: 0
human_verification:
  - test: "启动 debug 构建，确认状态栏显示格式与 v1.0 一致"
    expected: "compact 模式下显示 'C:xx% G:xx% M:xx% N:↑xx↓xx' 格式，字段间空格分隔，无多余分隔符"
    why_human: "状态栏文字渲染效果（字体、颜色、间距）及实际展示宽度只能视觉确认；代码路径已静态验证"
  - test: "在设置窗口拖动「刷新间隔」Picker 更改为 1s，确认状态栏在约 1s 内自动更新"
    expected: "MetricCollector.reconfigure() 被调用，新 Timer 以 1s 间隔触发，状态栏随即以更快频率刷新"
    why_human: "Timer 重调度为实时行为，静态检查只能验证代码路径存在；实际生效需要在运行中观察"
  - test: "更改 CPU 警告阈值（Slider）后立即观察状态栏颜色是否随之变化"
    expected: "colorForUsage 实时读取新阈值，高于新阈值的数值立刻变为橙色/红色，无需重启"
    why_human: "颜色变化为运行时视觉结果，依赖 applyNow() → updateTitle 调用链在 live app 中端到端生效"
  - test: "退出并重启应用，确认上次设置的刷新间隔和显示模式已恢复"
    expected: "偏好设置与退出前一致（UserDefaults 持久化），schemaVersion=1 写入"
    why_human: "持久化验证需要实际 quit-relaunch 生命周期，无法通过单次运行或静态分析确认"
  - test: "开启「登录时启动」Toggle，在系统偏好「登录项」中确认 MacStatus 已注册"
    expected: "SMAppService.mainApp.register() 成功，系统登录项列表出现 MacStatus"
    why_human: "SMAppService 注册为系统级副作用，需要在真实 macOS 环境中核查系统设置"
---

# Phase 06: Settings Foundation + Live Re-apply Seam 验证报告

**Phase Goal:** A single typed `SettingsManager` becomes the one source of truth, preferences survive restart, and changing a preference takes effect immediately without relaunch — establishing the plumbing every customizable feature depends on.
**Verified:** 2026-06-17T00:00:00Z
**Status:** passed（4/4 静态验证 + 5/5 人工运行时验证，用户 2026-06-17 确认全部正常）
**Re-verification:** 否——初次验证

---

## Goal Achievement

### Observable Truths（可观测真值）

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | 所有设置读写经过单一 SettingsManager；SettingsView 零 @AppStorage；MetricCollector 和 StatusBarManager 读同一 SettingsManager | ✓ VERIFIED | SettingsView.swift 中无任何 `@AppStorage`；含 `@Bindable var settings = SettingsManager.shared`；StatusBarManager.updateTitle 第 90 行 `let settings = SettingsManager.shared` |
| 2 | 所有偏好（含 metricOrder、enabledMetrics、customThresholds、customColors、launchAtLogin）经版本化 UserDefaults 持久化；schemaVersion 键 + 迁移阶梯存在 | ✓ VERIFIED | SettingsManager.swift 第 76 行 `Keys.schemaVersion`；第 279–328 行 `runMigrations()` + `migrateToV1()`；loadAll() 完整从 UserDefaults 还原所有 backing var |
| 3 | 设置变更实时生效：.settingsDidChange → MetricCollector.applyNow()（外观变更）或 reconfigure()（timing 变更）；reconfigure() 不重置 reader baseline | ✓ VERIFIED | MetricCollector.swift 第 117–133 行闭包 observer；第 127 行 `changedKeys.contains("refreshInterval")` 分支；reconfigure() 第 97–106 行仅 invalidate + 重建 Timer，不调用任何 reader 方法 |
| 4 | StatusBarManager.updateTitle 按 enabledMetrics + metricOrder 条件组合 segment；colorForUsage 实时读取 customThresholds/customColors；只有单一 NSStatusItem，从不增删 | ✓ VERIFIED | StatusBarManager.swift 第 25 行单一 `statusItem` 创建；第 91–120 行 metricOrder/enabledMetrics 过滤循环；第 269–285 行 colorForUsage 读 customThresholds/customColors |

**Score:** 4/4 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `MacStatus/MacStatus/Utils/Metric.swift` | Metric 枚举，String rawValue，CaseIterable，Sendable | ✓ VERIFIED | 第 12 行 `enum Metric: String, CaseIterable, Sendable`；五个 case（cpu/memory/network/gpu/battery） |
| `MacStatus/MacStatus/Utils/SettingsManager.swift` | @MainActor @Observable 单一真源 | ✓ VERIFIED | 第 48 行 `@MainActor @Observable final class SettingsManager`；无 @unchecked Sendable |
| `MacStatus/MacStatus/Utils/NSColor+Hex.swift` | NSColor ↔ #RRGGBB 互转扩展 | ✓ VERIFIED | 第 11 行 `convenience init?(hex:)`；第 25 行 `var hexString: String`；用 `colorSpace: .sRGB` 初始化 |
| `MacStatus/MacStatus/Collectors/MetricCollector.swift` | reconfigure/applyNow/lastSample/settingsObserver | ✓ VERIFIED | 第 42 行 lastSample；第 45 行 settingsObserver；第 97 行 reconfigure()；第 110 行 applyNow()；第 117 行 setupSettingsObserver() |
| `MacStatus/MacStatus/UI/Views/SettingsView.swift` | @Bindable 绑定，零 @AppStorage | ✓ VERIFIED | 第 8 行 `@Bindable var settings = SettingsManager.shared`；全文无 @AppStorage |
| `MacStatus/MacStatus/UI/StatusBarManager.swift` | 启用集+顺序条件组合 updateTitle，实时 colorForUsage | ✓ VERIFIED | 第 91–120 行 updateTitle 新实现；无 buildFullTitle/buildCompactTitle/buildPercentageTitle；无 private enum MetricType；无 settingsObserver |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| SettingsManager setter | NotificationCenter.post(.settingsDidChange) | postChange(keys:) | ✓ WIRED | 第 386–392 行 postChange；每个 setter 均调用 postChange |
| MetricCollector.setupSettingsObserver() | reconfigure() 或 applyNow() | changedKeys.contains("refreshInterval") | ✓ WIRED | 第 127–130 行 — refreshInterval 变更走 reconfigure()，其他走 applyNow() |
| MetricCollector.tick() | lastSample | `lastSample = sample`（ringBuffer.append 之前） | ✓ WIRED | 第 155 行；顺序：构造 sample → lastSample = sample → ringBuffer.append → updateUI |
| MetricCollector.applyNow() | StatusBarManager.updateTitle | updateUI(sample:) | ✓ WIRED | applyNow() 第 111–113 行调用 updateUI；updateUI 第 211–216 行调用 StatusBarManager.shared.updateTitle |
| StatusBarManager.updateTitle | SettingsManager.metricOrder / enabledMetrics | `let active = order.filter { enabled.contains($0) }` | ✓ WIRED | 第 91–95 行 |
| StatusBarManager.colorForUsage | SettingsManager.customThresholds / customColors | `settings.customThresholds[metric.rawValue]?["warning"]` | ✓ WIRED | 第 272–273、276–280 行 |

---

### Data-Flow Trace（Level 4）

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| StatusBarManager.updateTitle | metricOrder, enabledMetrics | SettingsManager.shared（UserDefaults 持久化） | 是 | ✓ FLOWING |
| StatusBarManager.colorForUsage | customThresholds, customColors | SettingsManager.shared（JSONDecoder 从 UserDefaults.data 解码） | 是 | ✓ FLOWING |
| MetricCollector.applyNow() | lastSample | tick() 每帧写入的真实硬件读数 | 是 | ✓ FLOWING |
| SettingsView Slider/Picker | settings.cpuWarningThreshold 等 | SettingsManager.shared._backing 变量，loadAll() 从 UserDefaults 填充 | 是 | ✓ FLOWING |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| xcodebuild 编译成功 | `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build.noindex build` | `** BUILD SUCCEEDED **`（exit 0） | ✓ PASS |
| SettingsView 零 @AppStorage | `grep "@AppStorage" SettingsView.swift` | 无输出 | ✓ PASS |
| SettingsManager 是 @MainActor @Observable，无 @unchecked Sendable | `grep "@MainActor @Observable\|@unchecked Sendable" SettingsManager.swift` | 第 48 行匹配 @MainActor @Observable；无 @unchecked Sendable | ✓ PASS |
| MetricCollector 包含全部新方法 | `grep "func reconfigure\|func applyNow\|lastSample\|settingsObserver" MetricCollector.swift` | 全部匹配 | ✓ PASS |
| reconfigure() 不调用 stop()/start()/reader 方法 | 提取 reconfigure() 函数体 | 仅含 timer?.invalidate()、SettingsManager.shared.refreshInterval、Timer.scheduledTimer；无 stop()/start()/setup() | ✓ PASS |
| 单一 NSStatusItem | `grep "statusItem(withLength" **/*.swift` | 仅 StatusBarManager.swift 第 25 行一处 | ✓ PASS |
| 无旧 buildFullTitle/buildCompactTitle/buildPercentageTitle/MetricType | `grep "buildFullTitle\|buildCompactTitle\|buildPercentageTitle\|private enum MetricType" StatusBarManager.swift` | 无输出 | ✓ PASS |
| StatusBarManager 无 settingsObserver | `grep "settingsObserver" StatusBarManager.swift` | 无输出 | ✓ PASS |
| NSColor+Hex sRGB 实现 | `grep "colorSpace: .sRGB\|hexString" NSColor+Hex.swift` | 第 19 行 colorSpace: .sRGB；第 25 行 hexString | ✓ PASS |
| migrateToV1() 直接写 UserDefaults，不经过 setter | 读取 migrateToV1() 实现（第 290–328 行） | 全部使用 `defaults.set(...)` 写 UserDefaults，无任何 `self.xxx =` 赋值 | ✓ PASS |
| launchAtLogin setter 含 SMAppService 副作用 | 读取 setter 实现（第 215–231 行） | `SMAppService.mainApp.register()/unregister()` 调用存在 | ✓ PASS |
| 默认 metricOrder = [cpu, gpu, memory, network] | `grep "cpu, .gpu, .memory, .network" SettingsManager.swift` | 第 103、293、297、360、364 行均为此顺序 | ✓ PASS |
| changedKeys 字符串字面量与 Keys.refreshInterval 值一致 | `Keys.refreshInterval = "refreshInterval"`；MetricCollector 第 127 行 `"refreshInterval"` | 完全一致 | ✓ PASS |
| NotificationCenter 使用闭包形式（非 @objc #selector） | 读取 setupSettingsObserver()（第 117–133 行） | `addObserver(forName:object:queue:using:)` 闭包形式；无 @objc #selector | ✓ PASS |

---

### High-Risk Research Item Verification

| Item | Claim | Code Evidence | Status |
|------|-------|---------------|--------|
| @ObservationIgnored backing + 计算 setter（SE-0395） | SettingsManager 所有属性用 `@ObservationIgnored private var _xxx` + 公开计算属性 | SettingsManager.swift 第 95–107 行 13 个 @ObservationIgnored backing var；每个公开属性均为 `get { _xxx } set { _xxx = newValue; defaults.set(...); postChange(...) }` | ✓ VERIFIED |
| migration 直接写 UserDefaults，不经过 setter | migrateToV1() 不调用 self 的任何属性 setter | 第 290–328 行全部为 `defaults.set(xxx, forKey: Keys.xxx)`；无 `self.xxx = xxx` | ✓ VERIFIED |
| 默认 metricOrder = [.cpu, .gpu, .memory, .network] | compact 顺序，升级零变化 | backing var 第 103 行默认值；loadAll() 回退第 360 行；migrateToV1() 第 293 行 | ✓ VERIFIED |
| NotificationCenter 闭包形式（非 @objc #selector） | setupSettingsObserver() 用 addObserver(forName:object:queue:using:) | MetricCollector.swift 第 118 行 | ✓ VERIFIED |

---

### Probe Execution

Step 7c: xcodebuild 已在 Behavioral Spot-Checks 中作为主要验证手段运行并通过（BUILD SUCCEEDED，exit 0）。本项目无 `scripts/*/tests/probe-*.sh` 文件。

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SET-07 | 06-01-PLAN.md, 06-03-PLAN.md | 用户的所有偏好在重启应用后保持（持久化） | ✓ SATISFIED | SettingsManager 全套 UserDefaults 读写路径；runMigrations + loadAll；schemaVersion 迁移阶梯 |
| SET-08 | 06-02-PLAN.md, 06-03-PLAN.md | 设置更改即时生效，无需重启应用（实时重应用） | ✓ SATISFIED | .settingsDidChange 广播 → MetricCollector observer → reconfigure()/applyNow() → updateUI → updateTitle 完整链路已静态验证 |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `MacStatus/MacStatus/UI/Views/SettingsView.swift` | 70 | `// TODO: Implement via MetricCollector.purgeAll()` | ⚠️ Warning | 被禁用按钮（`.disabled(true)`）内的占位符，该 TODO 在 Phase 6 修改此文件之前已存在（commit ccd7bf4）；功能未在当前里程碑路线图或 REQUIREMENTS.md 中定义为任何阶段的目标；按钮禁用状态对用户不可见，不影响 Phase 6 目标 |

**债务标记门闸判定：** 该 TODO 属于 Warning 级（非 TBD/FIXME/XXX）；引用了具体方法名（`MetricCollector.purgeAll()`）；按钮处于 disabled 状态；Phase 6 目标不涉及历史清除功能。**不构成 BLOCKER。**

---

### Human Verification Required

以下项目为运行时/视觉/系统副作用行为，静态代码分析无法替代：

#### 1. 状态栏外观与 v1.0 一致性

**Test:** 启动 debug 构建（`build.noindex/Build/Products/Debug/MacStatus.app`），确认 compact 模式下状态栏格式
**Expected:** 显示 `C:xx% G:xx% M:xx% N:↑xx↓xx`，字段间单空格分隔，无前置/末尾多余分隔符
**Why human:** 字体渲染、颜色显示和实际布局宽度只能视觉核查

#### 2. 刷新间隔更改即时生效

**Test:** 在设置窗口将「刷新间隔」从 2s 改为 1s，观察状态栏
**Expected:** 约 1 秒后状态栏即开始以新频率更新；改回 2s 后节奏放缓
**Why human:** Timer 重调度为实时行为；observer → reconfigure() 调用链在 live run loop 中运行

#### 3. 阈值更改即时着色

**Test:** 将 CPU 警告阈值滑块拖至低于当前 CPU 使用率的值，观察状态栏 C:xx% 颜色
**Expected:** 数值立即变为橙色（warning）；继续拖至 critical 则变红
**Why human:** 颜色变化为运行时渲染结果，依赖 applyNow() 端到端生效

#### 4. 偏好持久化跨重启

**Test:** 修改显示模式为「完整」，退出应用（Cmd+Q），重新启动
**Expected:** 重启后显示模式仍为「完整」；UserDefaults 已持久化
**Why human:** 需要真实 quit-relaunch 生命周期验证 UserDefaults 写入与 loadAll() 读取

#### 5. launchAtLogin SMAppService 注册

**Test:** 在设置窗口开启「登录时启动」Toggle，打开 macOS 系统设置 → 通用 → 登录项
**Expected:** MacStatus 出现在登录项列表
**Why human:** SMAppService.mainApp.register() 为系统级副作用，需要真实 macOS 环境核查

---

## Gaps Summary

无 BLOCKER 级缺口。所有四项 ROADMAP 成功标准在代码层面均已静态验证。

唯一 Warning 级项目为预先存在的 `// TODO` 注释（禁用按钮内，Phase 6 修改文件时保留）——该功能不在本阶段或当前里程碑目标范围内，不影响 Phase 6 goal 的达成。

状态为 `human_needed`，因为五项运行时/系统级行为需要在真实应用中端到端确认后方可最终宣告阶段完成。

---

_Verified: 2026-06-17_
_Verifier: Claude (gsd-verifier)_
