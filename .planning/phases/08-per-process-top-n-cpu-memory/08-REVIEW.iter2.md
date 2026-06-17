---
phase: 08-per-process-top-n-cpu-memory
reviewed: 2026-06-17T00:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - MacStatus/MacStatus/Readers/ProcessResourceReader.swift
  - MacStatus/MacStatus/UI/PopoverManager.swift
  - MacStatus/MacStatus/UI/Views/DashboardView.swift
  - MacStatus/MacStatus/UI/Views/ProcessListView.swift
findings:
  critical: 2
  warning: 3
  info: 3
  total: 8
status: issues_found
---

# Phase 08: Code Review Report

**Reviewed:** 2026-06-17
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

---

## Summary

本次评审覆盖了 Phase 08 新增的进程资源采样模块（`ProcessResourceReader`）及其与 `PopoverManager`、`DashboardView`、`ProcessListView` 的集成代码。整体实现质量较高——libproc 调用流程、CPU% 数学、首帧哨兵值、内存格式化等主要逻辑均正确。**但并发安全存在两处可证明的数据竞争（CR-01、CR-02），均指向同一根因：`@unchecked Sendable` 的"单任务独占访问"不变量在代码中并未真正被强制执行。**此外发现 3 项警告（WR）和 3 项信息级别（IN）问题。

---

## Critical Issues

### CR-01: `clearSnapshot()` 与飞行中的 `sample()` 存在数据竞争

**File:** `MacStatus/MacStatus/UI/PopoverManager.swift:107–113` 与 `MacStatus/MacStatus/Readers/ProcessResourceReader.swift:64–66`

**Issue:**

`popoverDidClose()` 在 `@MainActor` 上依次执行：

```swift
resourceSampleTask?.cancel()   // 行 110：仅向外层 Task 发出取消信号
resourceSampleTask = nil
resourceReader.clearSnapshot() // 行 112：在 MainActor 上执行 prevSnapshot.removeAll()
```

问题在于：内层 `Task.detached(priority: .utility) { reader.sample() }`（`startResourceSampling()` 第 126–129 行）是**独立分离任务**，它不继承外层 `resourceSampleTask` 的取消令牌。当外层循环被 `.cancel()` 中断时，正在 background 线程执行的 `sample()` 调用不会被中断——它会跑完整个 PID 枚举循环，在此期间持续读写 `prevSnapshot`（第 124、136、149 行）。与此同时，`clearSnapshot()` 在 MainActor 上向同一 map 写入 `removeAll()`。这是一次**无同步的并发读写**，在 Swift 6 严格并发下属于未定义行为（`@unchecked Sendable` 绕过了编译器检查）。

**真实触发场景：** 系统加载较高时 `sample()` 可能耗时 50–200ms。用户打开弹窗后快速关闭，极易命中此窗口。

**Fix:**

最简修复是将 `clearSnapshot()` 的调用移入采样任务内部，在取消检测点之后执行，确保 `sample()` 已完成再清空 map：

```swift
// PopoverManager.startResourceSampling() 内部
resourceSampleTask = Task { [weak self] in
    defer {
        // 任务退出时（无论因取消还是正常结束）清空快照
        // 此时 sample() 已不再运行，无竞争
        self?.resourceReader.clearSnapshot()
        Task { @MainActor [weak self] in
            self?.dashboardState.resourceLoading = true
        }
    }
    while !Task.isCancelled {
        guard let self else { return }
        let (cpuTop, memTop) = await Task.detached(priority: .utility) {
            [reader = self.resourceReader] in
            reader.sample()
        }.value
        guard !Task.isCancelled else { return }
        // ... 更新 dashboardState ...
        try? await Task.sleep(nanoseconds: 1_500_000_000)
    }
}
```

在 `popoverDidClose()` 中删除对 `clearSnapshot()` 和 `dashboardState.resourceLoading = true` 的直接调用（两者均由 `defer` 块接管）。

根本解法（更安全）：将 `ProcessResourceReader` 改为 `actor`，Swift 6 编译器即可静态保证互斥访问，无需文档约定。

---

### CR-02: 快速重开弹窗时两个 `sample()` 调用并发读写 `prevSnapshot`

**File:** `MacStatus/MacStatus/UI/PopoverManager.swift:121–143`

**Issue:**

`startResourceSampling()` 在开始前取消旧任务：

```swift
func startResourceSampling() {
    resourceSampleTask?.cancel()   // 行 122：取消外层 Task
    resourceSampleTask = Task { ... }
}
```

但与 CR-01 同理，旧循环内飞行中的 `Task.detached { reader.sample() }` 不会被取消——它继续在 background 运行直到完成。新循环立即启动，也会很快发出新的 `Task.detached { reader.sample() }`。在短暂的重叠窗口内，**两个 `sample()` 调用在不同线程上同时读写同一个 `prevSnapshot` map**，这同样是未受保护的数据竞争。

**触发场景：** 用户在 1.5s 采样间隔内连续两次点击状态栏图标（先关后开）。这在实际使用中相当常见。

**Fix:**

在 `startResourceSampling()` 中，通过引入一个"generation"计数器或利用 `actor` 来让旧的 detached task 自然失效后再启动新任务。最简单的正确修复仍然是将 `ProcessResourceReader` 改为 `actor`：

```swift
actor ProcessResourceReader {
    private var prevSnapshot: [ProcessKey: SnapshotEntry] = [:]

    func clearSnapshot() {
        prevSnapshot.removeAll()
    }

    func sample() -> ([ProcessResourceUsage], [ProcessResourceUsage]) {
        // 同原实现，actor 隔离自动序列化所有访问
    }
}
```

使用方改为 `await reader.sample()` 和 `await reader.clearSnapshot()`。`@MainActor` 的 `startResourceSampling()` 调用 `await Task.detached { await reader.sample() }` 是合法的（actor 跨隔离域调用）。这是最符合 Swift 6 并发模型的解法，也彻底消除 CR-01 和 CR-02。

---

## Warnings

### WR-01: `resourceError` 字段声明但从未被写入

**File:** `MacStatus/MacStatus/UI/Views/DashboardView.swift:368`

**Issue:**

```swift
@Published var resourceError: String? = nil
```

该字段在 `DashboardState` 中声明，但 `startResourceSampling()` 的采样循环（`PopoverManager.swift:123–143`）没有任何路径会设置它。`ProcessResourceReader.sample()` 通过返回空数组来表达失败（`proc_listpids` 失败时返回 `([], [])` ），调用方也从未将此映射到错误状态。结果是 `ProcessResourceSectionView` 永远不会向用户展示采样失败的原因——只会静默显示 spinner 或"无数据"，用户无从区分"正在加载"与"系统拒绝了权限"。

**Fix:** 要么删除 `resourceError`（如果确实不需要错误状态），要么在 `startResourceSampling()` 中检测空结果并设置它：

```swift
if cpuTop.isEmpty && memTop.isEmpty {
    self.dashboardState.resourceError = "无法读取进程数据（权限不足？）"
}
```

---

### WR-02: `wallNow` 在 PID 枚举开始前采样，导致系统负载高时 CPU% 系统性偏低

**File:** `MacStatus/MacStatus/Readers/ProcessResourceReader.swift:76`

**Issue:**

```swift
let wallNow = mach_absolute_time()  // 行 76：在所有 syscall 之前采样一次
// ...随后是 proc_listpids（可能 1–10ms）
// ...随后对每个 PID 调用 proc_pid_rusage（可能再 10–50ms）
for i in 0..<pidCount {
    // ...
    newSnapshot[key] = SnapshotEntry(cpuTicks: cpuTicks, wallTicks: wallNow) // 行 136
}
```

`wallNow` 是在枚举开始前的时刻，而 `prevSnapshot` 中每个条目的 `wallTicks` 也是该进程被写入时的"枚举开始时刻"。在系统负载高的情况下，`proc_listpids` + 数百个 `proc_pid_rusage` 调用的累积耗时可能达到 50ms 以上。此时 `deltaWall`（本帧 `wallNow` − 上帧 `wallNow`）能正确反映两帧间的挂钟时间，因此 CPU% 计算总体上是正确的——但所有进程使用同一个 `wallNow` 作为本帧时间戳，而每个进程的 `ri_user_time` 是在不同时刻读取的。对于排在 PID 列表末尾的进程，其 CPU ticks 读取时刻比 `wallNow` 晚了数十毫秒，使得 `deltaCPU` 包含了这段时间的 CPU 消耗但 `deltaWall` 没有，导致该进程 CPU% 略微偏高（而非偏低）。这对 Top-5 排名的影响微小，但与注释的直觉相反。

**Fix:** 对精度要求不高的状态监控，此误差可接受。如需改善，可在每次 `proc_pid_rusage` 调用后立即采一次 `wallNow`（每进程独立时间戳）并存入 `SnapshotEntry`：

```swift
let wallNow = mach_absolute_time()
newSnapshot[key] = SnapshotEntry(cpuTicks: cpuTicks, wallTicks: wallNow)
```

将 `mach_absolute_time()` 移到 `proc_pid_rusage` 调用之后、`newSnapshot` 写入之前即可。

---

### WR-03: `ForEach` 使用数组偏移量（`id: \.offset`）作为身份标识，可能导致视图状态错位

**File:** `MacStatus/MacStatus/UI/Views/DashboardView.swift:315` 与 `MacStatus/MacStatus/UI/Views/ProcessListView.swift:42`

**Issue:**

```swift
ForEach(Array(items.prefix(5).enumerated()), id: \.offset) { _, proc in
    ProcessMetricRow(...)
}
```

以数组下标（offset）为 `id` 意味着：当进程列表因新采样而重排时（例如第 2 名进程跃升到第 1 名），SwiftUI 认为"id=0 的行内容变了"而不是"两行交换了顺序"——它会就地更新文本内容而不是动画交换行。虽然不会崩溃，但会导致列表刷新时的动画不正确，以及若 `ProcessMetricRow` 未来持有局部状态时可能出现状态复用到错误进程的 bug。

**Fix:** 使用 `ProcessResourceUsage.pid` 作为稳定 id（对于网络列表则用 `processIdentifier`）：

```swift
ForEach(items.prefix(5), id: \.pid) { proc in
    ProcessMetricRow(...)
}
```

`ProcessResourceUsage` 已经 `Sendable` 且 `Equatable`，只需补充 `Identifiable` conformance 或直接使用 `id: \.pid` keyPath。

---

## Info

### IN-01: `ProcessResourceSectionView` 内多余的 `.prefix(5)` 截断

**File:** `MacStatus/MacStatus/UI/Views/DashboardView.swift:315`

**Issue:**

`ProcessResourceSectionView` 在 `ForEach` 中对 `items` 再次 `.prefix(5)`，而调用方已经传入了 `state.topCPUProcesses` / `state.topMemoryProcesses`——这两个数组在 `ProcessResourceReader.sample()` 中已被截断为 5 项。双重截断不会出错，但增加了认知负担，也掩盖了"section 最多显示多少条"这一约定实际由 `Reader` 还是 `View` 控制。

**Fix:** 删除 `ForEach` 中的 `.prefix(5)`，让 section view 直接迭代 `items`；在 `ProcessResourceSectionView` 的文档注释中说明调用方应保证传入不超过 N 项。

---

### IN-02: `@unchecked Sendable` 的类注释与实际代码契约不符

**File:** `MacStatus/MacStatus/Readers/ProcessResourceReader.swift:22–35`

**Issue:**

类的文档注释声称：

> "实例由单一 Task.detached(.utility) 循环独占访问，Swift 6 严格并发无需 actor 包装。"

但如 CR-01 和 CR-02 所示，这一契约在实现中并未被强制执行——`clearSnapshot()` 可以被 MainActor 并发调用，`startResourceSampling()` 可以在旧 detached task 仍在运行时启动新的。注释制造了虚假的安全感，使得未来的维护者更容易引入同类问题。

**Fix:** 在修复 CR-01/CR-02 后（建议改为 `actor`），删除或更新此注释以准确描述实际的线程安全机制。

---

### IN-03: `resourceLoading` 在 `popoverDidClose` 中重置，但在 `startResourceSampling` 开始时未重置为 `true`

**File:** `MacStatus/MacStatus/UI/PopoverManager.swift:113` 与 `MacStatus/MacStatus/UI/Views/DashboardView.swift:367`

**Issue:**

```swift
// popoverDidClose:
dashboardState.resourceLoading = true  // 行 113

// startResourceSampling 中无对应的重置
```

如果 `startResourceSampling()` 被直接调用（例如未来的"手动刷新"功能），`resourceLoading` 不会被重置为 `true`，UI 不会显示加载 spinner。当前代码中弹窗关闭时重置、打开时启动，两者顺序正确，但将"打开时应显示 spinner"的职责隐式依赖于"关闭时重置"，而不是"打开时主动设置"，属于隐蔽的顺序耦合。

**Fix:** 在 `startResourceSampling()` 开头显式设置：

```swift
func startResourceSampling() {
    resourceSampleTask?.cancel()
    dashboardState.resourceLoading = true  // 主动重置，不依赖关闭时的副作用
    resourceSampleTask = Task { [weak self] in
        // ...
    }
}
```

---

_Reviewed: 2026-06-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
