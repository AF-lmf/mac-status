---
phase: 08-per-process-top-n-cpu-memory
fixed_at: 2026-06-17T11:45:00Z
review_path: .planning/phases/08-per-process-top-n-cpu-memory/08-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 08: Code Review Fix Report

**Fixed at:** 2026-06-17T11:45:00Z
**Source review:** `.planning/phases/08-per-process-top-n-cpu-memory/08-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 5（CR-01、CR-02、WR-01、WR-02、WR-03）
- Fixed: 5
- Skipped: 0

构建结果：**BUILD SUCCEEDED**，无 Swift 6 并发错误。

---

## Fixed Issues

### CR-01 + CR-02 + WR-02 + IN-02: 将 ProcessResourceReader 转换为 actor

**Files modified:** `MacStatus/MacStatus/Readers/ProcessResourceReader.swift`, `MacStatus/MacStatus/UI/PopoverManager.swift`
**Commit:** `e7ef0e1`
**Applied fix:**

将 `ProcessResourceReader` 从 `final class ... @unchecked Sendable` 改为 `actor`。

- **CR-01**（clearSnapshot 与飞行中 sample() 的数据竞争）：在 `popoverDidClose()` 中将 `resourceReader.clearSnapshot()` 改为 `Task { await self?.resourceReader.clearSnapshot() }`。actor 的串行 executor 保证该调用在任何进行中的 `sample()` 完成后才执行，消除无同步并发读写。
- **CR-02**（快速重开弹窗时两个 sample() 并发读写 prevSnapshot）：actor 串行化所有方法调用，新旧两个 sample() 不可能同时执行，竞争窗口从根本上关闭。
- **WR-02**（wallNow 在枚举开始前统一采样导致末尾进程 CPU% 系统性偏高）：将 `let wallNow = mach_absolute_time()` 从 PID 枚举开始前移至每个进程 `proc_pid_rusage` 调用之后，紧贴各自的 rusage 读取时刻，`deltaWall` 与 `deltaCPU` 的读取窗口对齐。
- **IN-02**（文档注释虚假描述）：更新类注释，删除"单任务独占访问"的不实声明，改为准确描述 actor 隔离机制；删除 `@unchecked Sendable`。

`PopoverManager.startResourceSampling()` 改为直接 `await self.resourceReader.sample()`——actor 方法调用自动跳转到其 executor（离开 MainActor），无需额外 `Task.detached` 包装。采样循环在 actor executor 上执行完毕后跳回 `Task` 上下文更新 `dashboardState`（MainActor isolated 属性，Task 继承 MainActor 隔离）。PROC-03（关闭时停止所有 CPU 工作）保持不变：`resourceSampleTask?.cancel()` 取消外层 Task，循环检测 `Task.isCancelled` 退出；actor 的 `clearSnapshot()` 异步执行但不阻塞关闭路径。

---

### WR-01: 移除未使用的 resourceError 字段

**Files modified:** `MacStatus/MacStatus/UI/Views/DashboardView.swift`
**Commit:** `1b1ddcd`
**Applied fix:**

从 `DashboardState` 中删除 `@Published var resourceError: String? = nil`。`ProcessResourceReader.sample()` 通过返回空数组来表达失败，`PopoverManager` 的采样循环没有任何路径设置该字段，保留它只会产生死状态和误导性的 API 面。

---

### WR-03: ForEach 改用稳定进程身份标识

**Files modified:** `MacStatus/MacStatus/UI/Views/DashboardView.swift`, `MacStatus/MacStatus/UI/Views/ProcessListView.swift`, `MacStatus/MacStatus/Readers/ProcessNetworkReader.swift`
**Commit:** `d31be49`
**Applied fix:**

- `ProcessResourceSectionView`（CPU/内存列表）：`ForEach(Array(items.prefix(5).enumerated()), id: \.offset)` 改为 `ForEach(items.prefix(5), id: \.pid)`。`ProcessResourceUsage.pid` 是非 Optional 的 `Int32`，可直接用作稳定 id。
- `ProcessListView`（网络列表）：`processIdentifier` 为 `Int32?`，在 `ProcessNetworkUsage` 中新增 `var stableID: String { "\(processIdentifier ?? -1)-\(processName)" }` 计算属性，`ForEach` 改用 `id: \.stableID`。
- 进程列表重排时 SwiftUI 现在正确识别行身份，执行动画交换而非就地更新文本，并消除未来 `ProcessMetricRow` 持有局部状态时可能出现的状态复用 bug。

---

## Skipped Issues

（无跳过的问题，所有 in-scope findings 均已修复。）

---

_Fixed: 2026-06-17T11:45:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
