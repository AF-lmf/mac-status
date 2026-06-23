---
phase: 08-per-process-top-n-cpu-memory
reviewed: 2026-06-17T11:47:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - MacStatus/MacStatus/Readers/ProcessResourceReader.swift
  - MacStatus/MacStatus/UI/PopoverManager.swift
  - MacStatus/MacStatus/UI/Views/DashboardView.swift
  - MacStatus/MacStatus/UI/Views/ProcessListView.swift
  - MacStatus/MacStatus/Readers/ProcessNetworkReader.swift
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: clean
---

# Phase 08: Code Review Report (Iteration 2 Re-Review)

**Reviewed:** 2026-06-17T11:47:00Z
**Depth:** standard
**Files Reviewed:** 5
**Status:** clean

---

## Summary

本轮为迭代 2 复审（re-review），验证针对 CR-01、CR-02、WR-01、WR-02、WR-03 的全部修复是否真实有效，并确认未引入回归。构建结果：**BUILD SUCCEEDED**，零 Swift 6 并发警告，零编译警告（仅有 xcodebuild 目标选择提示，非 Swift 编译器输出）。

经全文件精读及跨文件调用链分析，未发现新的 BLOCKER 或 WARNING 级问题。info 级别问题（IN-01 redundant prefix(5)、IN-03 resourceLoading 耦合）在本轮范围外，不影响 status。

**All reviewed files meet quality standards. No new or remaining critical/warning issues found.**

---

## Structural Findings (fallow)

无结构分析预传入（本轮未提供 `structural_findings` block）。

---

## Narrative Findings (AI reviewer)

### CR-01 + CR-02：actor 转换验证

**修复确认有效。**

`ProcessResourceReader` 已从 `final class @unchecked Sendable` 正确转换为 `actor`（ProcessResourceReader.swift:31）。`prevSnapshot` 现为 actor 私有状态，Swift 6 编译器静态保证对其的互斥访问，原有的两个数据竞争从语言层面被彻底消除。`sample()` 与 `clearSnapshot()` 均为 actor 隔离方法，编译器强制调用方使用 `await`，无法绕过。

`sample()` 是同步 actor 函数（非 `async`）——这是合法的 Swift 并发模式：同步 actor 方法仍需从 actor 外部 `await`，并在 actor 的串行执行器上运行，**不占用 MainActor**。PopoverManager 中 `await self.resourceReader.sample()` 正确发起 actor hop，调用期间 MainActor 不被阻塞。

### clearSnapshot() 与 in-flight sample() 的竞争分析

**设计安全，无数据竞争。**

`popoverDidClose`（PopoverManager.swift:107-117）的执行顺序：

1. `resourceSampleTask?.cancel()` — 向 Task 发送取消信号。
2. `Task { await self?.resourceReader.clearSnapshot() }` — 将 `clearSnapshot()` 排入 actor 队列。

Actor 的串行执行器保证：若 `sample()` 此刻正在 actor 上运行，`clearSnapshot()` 排在其后，等 `sample()` 完整返回后才执行。若 `sample()` 尚未开始（Task 已取消未调用），`clearSnapshot()` 直接运行。两条路径下 `prevSnapshot` 均无并发读写。

**快速重开边界情况**（open→close→open）：新 Task B 的首次 `sample()` 与旧 close 触发的 `clearSnapshot()` 在 actor 队列上的顺序不确定，但均受 actor 串行化约束——两者不可能并发执行。结果：
- `clearSnapshot()` 先执行：Task B 首帧看到空 `prevSnapshot`，正确显示"—"。
- Task B 的 `sample()` 先执行：记录新快照，随后 `clearSnapshot()` 清空，下一帧再次显示"—"，多延迟一个采样周期（1.5s）。可接受，非数据损坏。

### 采样循环停止性验证

**验证通过：取消后不再有任何 CPU 工作。**

```swift
// PopoverManager.swift:132-145
resourceSampleTask = Task { [weak self] in
    while !Task.isCancelled {
        guard let self else { return }
        let (cpuTop, memTop) = await self.resourceReader.sample()
        guard !Task.isCancelled else { return }   // ← 取消后不写 dashboardState
        self.dashboardState.topCPUProcesses = cpuTop
        ...
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        // ← CancellationError 被 try? 吞掉，while 条件重检为 false，退出
    }
}
```

取消路径：
- sleep 期间取消：`Task.sleep` 抛 `CancellationError`，`try?` 吞掉；`while !Task.isCancelled` 为 false，循环退出，不再调用 `sample()`。
- `sample()` 运行期间取消：actor 同步函数不提前中断，执行完毕后返回；`guard !Task.isCancelled` 阻止写入 `dashboardState`，循环终止。

去掉 `Task.detached` 包装器后，Task 继承 `@MainActor PopoverManager` 的上下文，loop 控制流在 MainActor；`await sample()` hop 到 actor executor；`dashboardState` 写入回到 MainActor——符合 Swift 6 隔离规则，编译器零警告验证。

双重取消防护（PopoverManager.swift:131：`resourceSampleTask?.cancel()` 在 `startResourceSampling` 开头）确保快速重开时旧循环被取消后才创建新循环，无双重采样。

### WR-01：resourceError 字段移除

**修复确认：** 全项目范围内未找到任何 `resourceError` 引用（grep 无输出）。

### WR-02：per-process 壁钟时间戳对齐

**修复确认正确，无跨进程错位。**

```swift
// ProcessResourceReader.swift:110, 124, 133
let wallNow = mach_absolute_time()           // 紧跟 proc_pid_rusage 之后，每进程独立采样
...
let deltaWall = wallNow > prev.wallTicks ? wallNow - prev.wallTicks : 0
newSnapshot[key] = SnapshotEntry(cpuTicks: cpuTicks, wallTicks: wallNow)
```

每个进程的 `wallNow` 在其 `proc_pid_rusage` 调用之后立即采集，存入该进程专属的 `SnapshotEntry.wallTicks`。delta 计算使用"本帧该进程采样时刻 − 上帧该进程采样时刻"——配对完全对应，无跨进程错位。CPU ticks 与壁钟 ticks 同为 Mach absolute time 单位，无需单位转换。修复为真实有效。

### WR-03：ForEach 稳定 ID

**修复确认，无回归。**

- **CPU/内存 Top 5**（DashboardView.swift:315）：`id: \.pid`（`Int32`，非 optional）。`proc_listpids` 返回唯一 PID 集，经 `guard pid > 0` 过滤，Top-5 子集内 pid 不重复，身份唯一。
- **网络进程列表**（ProcessListView.swift:42）：`id: \.stableID`。`ProcessNetworkUsage.stableID` computed property 已正确添加至 ProcessNetworkReader.swift:17，值为 `"\(processIdentifier ?? -1)-\(processName)"`，组合键在实践中唯一（nettop 总以 `name.pid` 格式输出）。

两处 `ForEach` 均已使用稳定身份标识，无数组偏移量作 id 的回归。

---

_Reviewed: 2026-06-17T11:47:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
