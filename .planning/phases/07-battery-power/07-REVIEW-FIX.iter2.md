---
phase: 07-battery-power
fixed_at: 2026-06-17T01:17:00Z
review_path: .planning/phases/07-battery-power/07-REVIEW.md
iteration: 1
findings_in_scope: 2
fixed: 2
skipped: 0
status: all_fixed
---

# Phase 07: Code Review Fix Report

**Fixed at:** 2026-06-17  
**Source review:** `.planning/phases/07-battery-power/07-REVIEW.md`  
**Iteration:** 1

**Summary:**
- Findings in scope: 2（WR-01、WR-02；Info 条目 IN-01~03 超出本次范围）
- Fixed: 2
- Skipped: 0

## Fixed Issues

### WR-01: `chargeStateText` 优化充电暂停场景下显示"已充满"标签有误

**Files modified:** `MacStatus/MacStatus/UI/Views/DashboardView.swift`  
**Commit:** `0126e5b`  
**Applied fix:** 将"AC 非充电"分支由无条件返回"已充满"改为按 `chargePercent >= 99` 分支：
- `chargePercent >= 99` → `"已充满"`（真正满电）
- `chargePercent < 99` → `"电源接入"`（包含优化充电在 80% 暂停的场景）

同时更新了 `chargeStateText` 上方的注释以准确反映新的三态逻辑。`timeText` 的 AC 待机分支（已返回 `"—"`）未修改，符合评审说明。

---

### WR-02: `postWakeSkipCount` 跨线程数据竞争

**Files modified:** `MacStatus/MacStatus/Readers/BatteryReader.swift`  
**Commit:** `cad9428`  
**Applied fix:** 将 `NSWorkspace.didWakeNotification` 观察者的 `queue: nil` 改为 `queue: .main`，确保 `postWakeSkipCount` 的写入与 `readValue()`（由 `@MainActor` tick 调用，运行于主线程）始终在同一队列执行，消除 Swift 6 strict concurrency 下的跨线程数据竞争。保留了 `[weak self]` 捕获。`NetworkReader` 的 wake 处理未修改，符合评审指示。

构建验证：两个修改均已通过 `xcodebuild` Debug 构建，**BUILD SUCCEEDED**，无新增编译错误或警告。

---

_Fixed: 2026-06-17_  
_Fixer: Claude (gsd-code-fixer)_  
_Iteration: 1_
