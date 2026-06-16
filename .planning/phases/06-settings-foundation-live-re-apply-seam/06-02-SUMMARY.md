---
phase: "06-settings-foundation-live-re-apply-seam"
plan: "02"
subsystem: "settings-live-reapply"
tags: ["settings", "notification", "timer", "bindable", "migration"]
dependency_graph:
  requires:
    - "06-01 (SettingsManager @Observable + .settingsDidChange + changedKeysUserInfoKey)"
  provides:
    - "MetricCollector.lastSample — 每帧缓存，tick() 赋值"
    - "MetricCollector.reconfigure() — 仅重建 timer，不碰 reader"
    - "MetricCollector.applyNow() — 重推 lastSample → updateUI"
    - "MetricCollector.settingsObserver — 闭包 observer token (NSObjectProtocol?)"
    - "SettingsView @Bindable — 零 @AppStorage，单一 SettingsManager.shared 绑定"
  affects:
    - "MacStatus/MacStatus/Collectors/MetricCollector.swift"
    - "MacStatus/MacStatus/UI/Views/SettingsView.swift"
tech_stack:
  added: []
  patterns:
    - "NotificationCenter closure observer (addObserver(forName:object:queue:using:)) — Swift 6 safe, no @objc #selector"
    - "NSObjectProtocol? token storage — prevents ARC release of observer"
    - "lastSample cache pattern — re-push UI on appearance change without re-reading hardware"
    - "@Bindable var settings = SettingsManager.shared — single @Observable source replaces N @AppStorage"
key_files:
  created: []
  modified:
    - "MacStatus/MacStatus/Collectors/MetricCollector.swift"
    - "MacStatus/MacStatus/UI/Views/SettingsView.swift"
decisions:
  - "changedKeys 使用字符串字面量 'refreshInterval' 而非 SettingsManager.Keys.refreshInterval — Keys enum 是 private，外部不可见"
  - "lastSample = sample 赋值放在 ringBuffer.append 之前 — 确保 applyNow() 拿到最新 sample 而非前一帧"
  - "setupSettingsObserver() 在 start() 末尾（loadRecentHistory 之后）调用 — 保证 timer 已就绪，避免 observer 触发 reconfigure() 时 timer 为 nil"
metrics:
  duration: "~8 minutes"
  completed: "2026-06-16T16:10:00Z"
  tasks_completed: 2
  files_changed: 2
---

# Phase 06 Plan 02: Live Re-apply Seam (MetricCollector + SettingsView) Summary

**一句话总结：** 在 MetricCollector 植入 `lastSample` 缓存 + `reconfigure()`/`applyNow()` + 闭包 `.settingsDidChange` observer，同时将 SettingsView 的 9 行 `@AppStorage` 全部消除，改为单一 `@Bindable var settings = SettingsManager.shared`，彻底铲除第二真源并接通设置即时生效管道。

## Tasks Completed

| # | Task | Commit | Key Files |
|---|------|--------|-----------|
| 1 | MetricCollector — lastSample 缓存 + reconfigure() + applyNow() + settingsObserver | 357d279 | MacStatus/Collectors/MetricCollector.swift |
| 2 | SettingsView — 消除所有 @AppStorage，改用 @Bindable 绑定 | 865a609 | MacStatus/UI/Views/SettingsView.swift |

## What Was Built

### Task 1: MetricCollector 实时重应用管道

**新增属性（tickCount 声明之后）：**
- `private var lastSample: MetricSample?` — tick() 每帧写入；applyNow() 读取
- `private var settingsObserver: NSObjectProtocol?` — 持有 observer token，防止 ARC 释放

**tick() 修改：**
- 在 `MetricSample(...)` 构造后、`ringBuffer.append(sample)` 前插入 `lastSample = sample`

**新 `// MARK: - Live Re-apply` 区块（stop() 之后）：**

`reconfigure()`:
- `timer?.invalidate(); timer = nil`
- 读取 `SettingsManager.shared.refreshInterval`
- 用 `Timer.scheduledTimer(withTimeInterval:repeats:)` 重建 timer（与 start() 中完全相同的模式）
- **绝不调用** `stop()`、`start()`、`reader.setup()`、`reader.readValue()` — 保留 NetworkReader delta baseline

`applyNow()`:
- `guard let sample = lastSample else { return }`
- `updateUI(sample: sample)` — 重推 UI，不触发新的硬件读取

`setupSettingsObserver()` (private):
- 闭包形式 `NotificationCenter.default.addObserver(forName: .settingsDidChange, object: nil, queue: .main)`
- 解包 `userInfo?[SettingsManager.changedKeysUserInfoKey] as? Set<String>`
- `changedKeys.contains("refreshInterval")` → `reconfigure()`；否则 → `applyNow()`
- 返回 token 存入 `self.settingsObserver`

**start() 末尾：**
- `setupSettingsObserver()` 调用（在 loadRecentHistory() 之后）

### Task 2: SettingsView @Bindable 迁移

**删除：**
- 9 行 `@AppStorage` 声明（refreshInterval, displayMode, displayUnit, showIcons, cpuWarning, cpuCritical, memWarning, memCritical, launchAtLogin）
- `import ServiceManagement`（SMAppService 已移至 SettingsManager）
- `Toggle.onChange(of: launchAtLogin)` modifier
- `private func setLaunchAtLogin(_:)` 方法及 `// MARK: - Launch at Login` 注释

**新增：**
- `@Bindable var settings = SettingsManager.shared`（结构体第一行）

**绑定更新：**
- `$refreshInterval` → `$settings.refreshInterval`
- `$displayModeRaw`（String）→ `$settings.displayMode`（DisplayMode enum）；tag 去掉 `.rawValue`
- `$launchAtLogin` → `$settings.launchAtLogin`
- `$cpuWarning` → `$settings.cpuWarningThreshold`；标签用 `settings.cpuWarningThreshold`
- `$cpuCritical` → `$settings.cpuCriticalThreshold`
- `$memWarning` → `$settings.memoryWarningThreshold`
- `$memCritical` → `$settings.memoryCriticalThreshold`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] changedKeys 键名使用字符串字面量**
- **Found during:** Task 1 实现时分析 SettingsManager.Keys 可见性
- **Issue:** `06-PATTERNS.md` 示例代码中用 `SettingsManager.Keys.refreshInterval` 引用 refreshInterval 键，但 `Keys` 枚举声明为 `private enum Keys`，MetricCollector 无法访问
- **Fix:** 改用字符串字面量 `"refreshInterval"`（与 SettingsManager.Keys.refreshInterval 的实际值完全一致）
- **Files modified:** `MacStatus/MacStatus/Collectors/MetricCollector.swift`
- **Commit:** 357d279

## Verification Results

```
xcodebuild BUILD SUCCEEDED (exit 0) — Task 1 后 ✓
xcodebuild BUILD SUCCEEDED (exit 0) — Task 2 后 ✓
grep "@AppStorage" SettingsView.swift → 无输出 ✓
grep "@Bindable" SettingsView.swift → line 8 ✓
grep "setLaunchAtLogin" SettingsView.swift → 无输出 ✓
grep "onChange" SettingsView.swift → 无输出 ✓
grep ".rawValue" SettingsView.swift (Picker tag) → 无输出 ✓
grep "func reconfigure\|func applyNow\|lastSample\|settingsObserver" MetricCollector.swift → 全部匹配 ✓
reconfigure() 函数体内无 stop()/start() 调用 ✓
```

## Known Stubs

None. MetricCollector 管道全部接通真实逻辑；SettingsView 所有控件绑定到 SettingsManager 真实属性。

## Threat Flags

No new security-relevant surface beyond plan's threat model.

| Flag | File | Description |
|------|------|-------------|
| (none) | — | T-06-04 (observer 回调 changedKeys cast 失败 guard return) 和 T-06-05 (reconfigure 低代价) 均按计划实现 |

## Self-Check: PASSED

- [x] `MacStatus/MacStatus/Collectors/MetricCollector.swift` 包含 `private var lastSample: MetricSample?`
- [x] 包含 `func reconfigure()`
- [x] 包含 `func applyNow()`
- [x] 包含 `settingsObserver`
- [x] 包含 `setupSettingsObserver`
- [x] `reconfigure()` 体内含 `timer?.invalidate()`，不含 `stop()` 或 `start()` 调用
- [x] `MacStatus/MacStatus/UI/Views/SettingsView.swift` 不含任何 `@AppStorage`
- [x] 含 `@Bindable var settings = SettingsManager.shared`
- [x] 不含 `setLaunchAtLogin`
- [x] 不含 `.onChange(of: launchAtLogin)`
- [x] displayMode Picker tag 为 `DisplayMode.full/compact/percentage`（无 `.rawValue`）
- [x] Commit 357d279 存在 (Task 1)
- [x] Commit 865a609 存在 (Task 2)
- [x] xcodebuild BUILD SUCCEEDED (两次验证均通过)
