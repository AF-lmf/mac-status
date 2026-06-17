---
phase: "09-settings-window-ui-customization"
plan: "01"
subsystem: "SettingsManager"
tags: [settings, bool-keys, observable, userdefaults, phase9]
dependency_graph:
  requires: []
  provides:
    - "SettingsManager.showBatterySection (Bool, default true)"
    - "SettingsManager.showProcessSection (Bool, default true)"
  affects:
    - "Plan 02: SettingsView Toggle 绑定"
    - "Plan 03: DashboardView 区块门控"
tech_stack:
  added: []
  patterns:
    - "@ObservationIgnored private backing var + computed get/set + postChange"
    - "loadAll nil-check (object(forKey:) == nil) 防止 UserDefaults.bool 零值陷阱"
key_files:
  created: []
  modified:
    - path: "MacStatus/MacStatus/Utils/SettingsManager.swift"
      description: "新增 showBatterySection / showProcessSection 两个 Bool 键（Keys + backing + computed + loadAll）"
decisions:
  - "showBatterySection/showProcessSection 通过 loadAll nil-check 补默认值，不新增 schemaVersion/migrateToV1 条目（与 customThresholds/customColors 同模式）"
  - "backing 变量初始值为 true，实际运行值由 loadAll() 决定（init 顺序安全）"
metrics:
  duration: "~5m"
  completed: "2026-06-17"
  tasks_completed: 1
  files_modified: 1
requirements_satisfied:
  - SET-02
  - SET-06
---

# Phase 09 Plan 01: SettingsManager 新增 showBatterySection / showProcessSection

**一句话摘要：** 为 SettingsManager 添加两个弹窗区块可见性 Bool 键（默认 true），采用与 showIcons 完全一致的 @ObservationIgnored backing + computed get/set + loadAll nil-check 模式。

## 完成情况

| 任务 | 名称 | Commit | 文件 |
|------|------|--------|------|
| 1 | SettingsManager 新增 showBatterySection / showProcessSection | a24df0c | MacStatus/MacStatus/Utils/SettingsManager.swift |

## 实现细节

### 变更位置（共 4 处，均为纯新增，不改任何现有代码）

**位置 1 — Keys enum（第 75–77 行）：**
在 `launchAtLogin` 之后新增两个 Phase 9 键注释块和两个 `static let`。

**位置 2 — Backing Storage 区块：**
在 `_customColors` 之后新增：
```swift
@ObservationIgnored private var _showBatterySection: Bool = true
@ObservationIgnored private var _showProcessSection: Bool = true
```

**位置 3 — Public Properties（新 MARK 区块）：**
在 `launchAtLogin` 与 `// MARK: - Custom Thresholds & Colors` 之间新增 `// MARK: - Popover Section Visibility` 块，包含两个计算属性，形状与 `showIcons` 完全一致：
```swift
var showBatterySection: Bool {
    get { _showBatterySection }
    set {
        _showBatterySection = newValue
        defaults.set(newValue, forKey: Keys.showBatterySection)
        postChange(keys: [Keys.showBatterySection])
    }
}
```

**位置 4 — loadAll()：**
在 `_launchAtLogin = defaults.bool(...)` 之后新增两个 nil-check 块，避免 `UserDefaults.bool(forKey:)` 在 key 不存在时返回 false 零值（默认应为 true）。

### 正确性保证

- `migrateToV1()` 未触碰（新键无需加入迁移 ladder）
- `schemaVersion` 未 bump
- 两个新键的 postChange 各自传递自身 key，与所有其他属性一致
- 无新 import，无新文件，无 pbxproj 变更

## 验收结果

| 断言 | 结果 |
|------|------|
| grep -c "showBatterySection" SettingsManager.swift | 10 ✅ (>= 6) |
| grep -c "showProcessSection" SettingsManager.swift | 10 ✅ (>= 6) |
| grep -c "_showBatterySection: Bool = true" | 1 ✅ |
| grep -c "_showProcessSection: Bool = true" | 1 ✅ |
| object(forKey: Keys.showBatterySection) nil-check | 1 ✅ |
| object(forKey: Keys.showProcessSection) nil-check | 1 ✅ |
| migrateToV1 count 不变 | 2 ✅ |
| xcodebuild Build Succeeded | ✅ exit 0 |

## 计划偏差

无 — 计划完全按预定步骤执行。

## Known Stubs

无。

## Threat Flags

无新安全面引入（仅添加两个 Bool 偏好键，局限于本进程 UserDefaults）。

## Self-Check: PASSED

- 文件存在: MacStatus/MacStatus/Utils/SettingsManager.swift ✅
- 提交存在: a24df0c ✅
- 构建: BUILD SUCCEEDED ✅
