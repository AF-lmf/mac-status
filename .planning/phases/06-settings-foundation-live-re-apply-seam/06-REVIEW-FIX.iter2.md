---
phase: 06-settings-foundation-live-re-apply-seam
fixed_at: 2026-06-17T00:00:00Z
review_path: .planning/phases/06-settings-foundation-live-re-apply-seam/06-REVIEW.md
iteration: 1
findings_in_scope: 6
fixed: 6
skipped: 0
status: all_fixed
---

# Phase 06: Code Review Fix Report

**Fixed at:** 2026-06-17
**Source review:** `.planning/phases/06-settings-foundation-live-re-apply-seam/06-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 6（CR-01、CR-02、WR-01、WR-02、WR-03、WR-04）
- Fixed: 6
- Skipped: 0

构建验证：所有修复应用后执行 `xcodebuild` **BUILD SUCCEEDED**，无编译错误。

---

## Fixed Issues

### CR-01: Swift 6 严格并发违规 — NotificationCenter 观察者闭包

**Files modified:** `MacStatus/MacStatus/Collectors/MetricCollector.swift`
**Commit:** `3216239`
**Applied fix:** 在 `setupSettingsObserver()` 的观察者闭包体内包裹 `Task { @MainActor [weak self] in ... }`，显式 hop 回 MainActor 后再调用 `reconfigure()` / `applyNow()`，与 Timer 回调的处理方式保持一致，满足 Swift 6 严格并发隔离规则。

---

### CR-02: `.battery` metric 产生双分隔符

**Files modified:** `MacStatus/MacStatus/UI/StatusBarManager.swift`
**Commit:** `0a43c79`
**Applied fix:** 将 `updateTitle()` 中的分隔符追加逻辑改为"先计算 segment，仅当 segment 非 nil 时才在前面插入分隔符"。使用 `firstSegmentWritten` 布尔标志取代基于 `index > 0` 的无条件追加，`case .battery` 产生 `nil` segment 时不写入任何内容（含分隔符）。

---

### WR-01: 阈值 `0.0` 被误判为"未设置"

**Files modified:** `MacStatus/MacStatus/Utils/SettingsManager.swift`
**Commit:** `f1b66e5`
**Applied fix:** 将 `loadAll()` 中 4 个阈值（cpuWarning/Critical、memoryWarning/Critical）的加载方式由 `rawValue > 0 ? rawValue : default` 改为 `defaults.object(forKey:) as? Double`，正确区分 key 不存在与值为 `0.0` 的情况，避免合法的零值阈值被静默重置。

---

### WR-02: `launchAtLogin` setter 在失败后不回滚状态

**Files modified:** `MacStatus/MacStatus/Utils/SettingsManager.swift`
**Commit:** `3d9e320`
**Applied fix:** 将 `SMAppService.register()` / `unregister()` 调用移至 UserDefaults 写入之前。仅在系统调用成功的 `do` 分支内才执行 `_launchAtLogin = newValue`、`defaults.set(...)` 和 `postChange(...)`；`catch` 分支只打印日志，不写入任何状态，UI 绑定自动回弹到旧值。

---

### WR-03: `hexString` 未截断超出范围的颜色分量

**Files modified:** `MacStatus/MacStatus/Utils/NSColor+Hex.swift`
**Commit:** `4ab959e`
**Applied fix:** 在 `hexString` 计算 r/g/b 整数值时，用 `min(255, max(0, Int(...)))` 将结果截断到 `0...255`，防止 Display P3 等宽色域颜色转换后分量超过 `1.0` 时输出非法的多字符十六进制字符串。

---

### WR-04: `loadAll()` 中 `customColors` 跳过格式校验

**Files modified:** `MacStatus/MacStatus/Utils/SettingsManager.swift`
**Commit:** `dde28c1`
**Applied fix:** 在 JSON 解码后复用与 `customColors` setter 相同的过滤逻辑（`hex.hasPrefix("#") && hex.count == 7`），过滤掉不符合 `#RRGGBB` 格式的条目，确保直接加载路径与通过 setter 写入的路径有相同的格式约束，消除内存与磁盘状态的不一致。

---

## Skipped Issues

无跳过项——所有 6 个 in-scope findings 均已成功修复并通过构建验证。

---

_Fixed: 2026-06-17_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
