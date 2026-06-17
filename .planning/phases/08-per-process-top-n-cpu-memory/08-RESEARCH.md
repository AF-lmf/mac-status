# Phase 8: Per-Process Top-N CPU & Memory - Research

**Researched:** 2026-06-17
**Domain:** macOS libproc C-interop, Swift 6 strict concurrency, popover-gated sampling
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **采样 API**：`proc_listpids(PROC_ALL_PIDS, …)` 枚举 PID；`proc_pid_rusage(pid, RUSAGE_INFO_V4, …)` 取累计 CPU 时间（`ri_user_time + ri_system_time`）与内存。**无 `task_for_pid`、无新 entitlement**。
- **CPU% 算法**：`(pid, 启动时间)` → (上次 cpu_ticks, 上次壁钟 ticks) 快照 map；`CPU% = max(Δcpu_ticks, 0) / Δwall_ticks × 100`。首帧"—"。`max(delta,0)` 处理计数器异常。
- **采样节奏**：popover 打开时 ~1.5s 循环（`Task` 循环 + sleep）；popover 关闭立即 cancel。
- **内存指标**：`proc_pid_rusage` 的物理内存字段（具体字段研究定稿）。
- **数据模型**：`ProcessResourceUsage: Sendable`（`processName`, `pid`, `cpuPercent: Double?`, `memoryBytes: UInt64`）。独立于 `ProcessNetworkUsage`。
- **reader 形态**：`ProcessResourceReader` class，持有上次快照 map。由 `PopoverManager` 的门控 Task 循环驱动；`Task.detached(.utility)` 做 libproc 调用，结果回 `MainActor`。
- **启停**：`toggle()` 打开 → 启动资源采样循环；`popoverDidClose` → cancel + **清空快照 map**。关闭后零后台开销（可验证成功标准 #3）。
- **Top-N**：两份独立列表 —— CPU% Top 5 与内存 Top 5（同一进程可同时出现）。降序，相等时进程名 tie-break，`prefix(5)`。
- **UI**：popover 新增两个区块"CPU 占用 Top 5"与"内存占用 Top 5"，紧邻"Top Processes (by network)"，沿用卡片背景风格。抽通用 `ProcessMetricRow` 供三处复用。首帧"—"；加载 spinner "Sampling…"；空 "无数据"。

### Claude's Discretion

- **libproc vs /bin/ps fallback**：研究阶段定稿——研究结论见下文（libproc 完全可行，推荐 libproc，不需要 ps fallback）。
- `proc_pid_rusage` 的具体 `RUSAGE_INFO` 版本与内存字段（`ri_resident_size` vs `ri_phys_footprint`）：研究定稿见下文。
- 进程名获取：`proc_name` vs `proc_pidpath` basename，研究定稿见下文。
- `ProcessMetricRow` 尾部内容如何同时容纳网络（↑↓ 双值）与 CPU/内存（单值）：由 Claude 设计。

### Deferred Ideas (OUT OF SCOPE)

- 全进程可排序列表 / 完整活动监视器
- 逐进程 GPU 占用
- 进程级历史趋势 / 持久化
- 状态栏内显示 Top 进程
- 点击进程行查看详情 / 终止进程
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PROC-01 | 用户能在弹窗中看到 CPU 占用最高的 3-5 个进程（进程名 + CPU%） | `proc_listpids` + `proc_pid_rusage` delta；CPU% 公式；首帧"—"处理 |
| PROC-02 | 用户能在弹窗中看到常驻内存占用最高的 3-5 个进程（进程名 + 内存） | `ri_phys_footprint` 即时读取；`ByteFormatting` 复用；泛化 `ProcessMetricRow` |
| PROC-03 | 逐进程数据仅在弹窗打开时采样，关闭弹窗即停止，不增加后台常驻开销 | Task loop 启停模式；`popoverDidClose` cancel + 清空 map；成功标准可验证 |
</phase_requirements>

---

## Summary

Phase 8 新增基于 `libproc` 的 per-process CPU/内存采样，在 popover 内展示 Top 5 进程的两个独立区块。研究的核心贡献是解决三个 C-interop 精度问题：（1）时间单位，（2）内存字段选择，（3）进程复用安全键。

**关键发现**：`rusage_info_v4.ri_user_time` 和 `ri_system_time` 是 **Mach absolute time ticks，不是纳秒**。在 Apple Silicon 上，一个 tick ≠ 1 ns（换算比例约为 3/125，即一个 tick ≈ 41.7 ns）。然而，`mach_absolute_time()` 也以完全相同的 Mach tick 单位为壁钟计时，因此 CPU% 公式 `Δcpu_ticks / Δwall_ticks × 100` 中**单位天然抵消**，无需调用 `mach_timebase_info`。`ri_proc_start_abstime`（也在 `rusage_info_v4`）同样是 Mach ticks，可直接用作 PID 复用安全键，**不需要单独的 sysctl `kinfo_proc` 调用**。

**内存字段**：选 `ri_phys_footprint`（物理内存占用，对应活动监视器"内存"列）。`ri_resident_size` 是 RSS（包含共享库映射），`ri_phys_footprint` 才是应用实际独占的物理内存，与 Activity Monitor 一致。

**Swift 6 并发**：libproc 函数是纯 C syscall，任意线程安全。推荐 `ProcessResourceReader` 为**普通 class（非 actor）**，实例始终由同一个 `Task.detached(.utility)` 循环持有并访问——无多线程竞争，符合 Swift 6 严格并发要求。结果以 `[ProcessResourceUsage]` Sendable 数组回 `MainActor`。

**Primary recommendation:** 使用 `proc_pid_rusage(pid, RUSAGE_INFO_V4, …)` + `mach_absolute_time()` 实现 CPU delta；`ri_phys_footprint` 取内存；`ri_proc_start_abstime` 作为 PID 复用键。无需 `mach_timebase_info` 转换，无需 `/bin/ps` fallback，无需 `sysctl kinfo_proc`。

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| PID 枚举与 rusage 读取 | Off-main Task.detached(.utility) | — | libproc 是 syscall，任意线程安全；避免在 MainActor 上阻塞 |
| CPU/内存 Top-N 排序 | Off-main Task.detached(.utility) | — | 纯计算，留在同一后台 Task，减少 MainActor 切换 |
| 快照 map（prev → delta）状态 | ProcessResourceReader class | — | 持有跨采样状态；class 实例由单一 Task 独占访问，无竞争 |
| Top-N 结果发布 | MainActor (DashboardState) | — | @Published 字段驱动 SwiftUI 重渲染，必须在 MainActor |
| 采样循环启停 | @MainActor PopoverManager | — | popover 生命周期在 MainActor 管理 |
| UI 渲染（进程行） | SwiftUI View (@MainActor) | — | 消费 DashboardState @Published 字段 |

---

## Standard Stack

### Core — 已在项目中（无新依赖）

| 符号 / 模块 | 来源 | 用途 | 访问方式 |
|-------------|------|------|----------|
| `proc_listpids` | `<libproc.h>` (libSystem) | 枚举所有 PID | `import Darwin`（libproc 是 Darwin 子模块） |
| `proc_pid_rusage` | `<libproc.h>` | 取累计 CPU ticks + 内存 | `import Darwin` |
| `rusage_info_v4` | `<sys/resource.h>` | 精确结构体，含 ri_proc_start_abstime | 随 `import Darwin` 自动可见 |
| `RUSAGE_INFO_V4` | `<sys/resource.h>` | flavor 常量 = 4 | 随 `import Darwin` 可见 |
| `proc_name` | `<libproc.h>` | 短进程名（最多 MAXCOMLEN = 16 字符）| `import Darwin` |
| `proc_pidpath` | `<libproc.h>` | 可执行路径（最多 PROC_PIDPATHINFO_MAXSIZE = 4096 字节）| `import Darwin`，仅对 Top-N 调用 |
| `mach_absolute_time` | `<mach/mach_time.h>` | 壁钟 Mach ticks（与 ri_user_time 同单位）| `import Darwin` |
| `ByteFormatting` | 项目内 | 内存字节格式化 | 直接复用 |
| `DashboardState` | 项目内 | 新增两个 @Published 字段 | 直接扩展 |
| `PopoverManager` | 项目内 | 新增采样循环启停逻辑 | 直接扩展 |

**安装命令**：无 —— 全部系统 SDK，零外部依赖。在新 `ProcessResourceReader.swift` 文件顶部写 `import Darwin` 即可。

---

## Package Legitimacy Audit

> 本 phase 无外部 package 安装。所有 API 均来自系统 SDK (`import Darwin`)。跳过此节。

---

## Architecture Patterns

### System Architecture Diagram

```
[PopoverManager @MainActor]
    .toggle() → popover.show()
         │
         ▼
    startResourceSampling()
         │
         ▼
    resourceSampleTask = Task { ← 1.5s loop
         │
         ▼
     Task.detached(.utility) {
          │
          ├── proc_listpids(PROC_ALL_PIDS) → [pid32]
          │
          ├── for each pid:
          │     proc_pid_rusage(pid, RUSAGE_INFO_V4, &info)
          │     → (ri_user_time, ri_system_time, ri_phys_footprint, ri_proc_start_abstime)
          │
          ├── ProcessResourceReader.sample(pids, wallNow)
          │     ├── diff against prevSnapshot[(pid, startAbstime)]
          │     ├── CPU% = max(Δcpu, 0) / Δwall * 100
          │     └── → [ProcessResourceUsage] (Sendable)
          │
          └── await MainActor.run {
                dashboardState.topCPUProcesses = cpuTop5
                dashboardState.topMemoryProcesses = memTop5
              }
     }
         │
         ▼
    try? await Task.sleep(nanoseconds: 1_500_000_000)
    }  // while !Task.isCancelled
         │
    popoverDidClose()
         │
         ▼
    resourceSampleTask?.cancel()
    resourceReader.clearSnapshot()

[DashboardState @MainActor]
    @Published topCPUProcesses: [ProcessResourceUsage]
    @Published topMemoryProcesses: [ProcessResourceUsage]
    @Published resourceLoading: Bool
    @Published resourceError: String?

[DashboardView SwiftUI]
    ProcessListSectionView(title: "CPU 占用 Top 5",  items: state.topCPUProcesses,  ...)
    ProcessListSectionView(title: "内存占用 Top 5", items: state.topMemoryProcesses, ...)
    → ProcessMetricRow (泛化，网络/CPU/内存三处复用)
```

### Recommended Project Structure

```
MacStatus/MacStatus/
├── Readers/
│   ├── ProcessNetworkReader.swift    # 现有，不改
│   └── ProcessResourceReader.swift  # NEW — proc_listpids + proc_pid_rusage + snapshot map
├── UI/
│   ├── PopoverManager.swift          # 修改：新增 resourceSampleTask 启停
│   └── Views/
│       ├── DashboardView.swift       # 修改：新增两个 Top-N 区块 + DashboardState 新字段
│       └── ProcessListView.swift     # 修改：抽出 ProcessMetricRow，网络行改用之
```

**新文件 `ProcessResourceReader.swift` 必须手动加入 `MacStatus.xcodeproj` pbxproj（Phase 7 教训）。**

---

## Critical API Reference: 精确字段与单位

### rusage_info_v4 字段（来自 `<sys/resource.h>`，macOS 15.4 SDK）

[VERIFIED: /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk/usr/include/sys/resource.h]

```c
struct rusage_info_v4 {
    uint8_t  ri_uuid[16];
    uint64_t ri_user_time;          // Mach absolute time ticks（非纳秒）
    uint64_t ri_system_time;        // Mach absolute time ticks（非纳秒）
    // ... (其他字段略)
    uint64_t ri_resident_size;      // 字节，RSS（含共享库映射）
    uint64_t ri_phys_footprint;     // 字节，物理内存独占占用 = Activity Monitor "内存"列
    uint64_t ri_proc_start_abstime; // Mach absolute time ticks（进程启动时刻，用于 PID 复用键）
    uint64_t ri_proc_exit_abstime;  // Mach absolute time ticks（已退出进程 > 0）
    // ... (其他字段略)
    uint64_t ri_runnable_time;
};
```

**时间单位关键结论** [VERIFIED via osquery/htop 开源 PR + Apple forums]:
- `ri_user_time`、`ri_system_time`、`ri_proc_start_abstime` 均为 **Mach absolute time ticks**。
- 在 Intel 上 1 tick = 1 ns；在 Apple Silicon 上 1 tick ≈ 41.7 ns（比例 3/125，随硬件变化）。
- **正确 CPU% 公式**：用 `mach_absolute_time()` 作壁钟，两者同单位，units 抵消，**无需 `mach_timebase_info` 转换**。

**内存字段选择** [VERIFIED: Apple 头文件字段语义 + exelban/stats 内存列对齐 Activity Monitor]:
- `ri_phys_footprint`：应用实际独占的物理内存页（不含未映射的共享库），对应活动监视器"内存"列。✅ **使用此字段**。
- `ri_resident_size`：RSS，包含共享映射（如 dyld、系统框架），比实际内存占用虚高。❌ 不用。

### proc_pid_rusage Swift 调用模式

[VERIFIED: libproc.h 签名 `int proc_pid_rusage(int pid, int flavor, rusage_info_t *buffer)`]

`rusage_info_t` 定义为 `void *`，因此需要 unsafe pointer 体操：

```swift
import Darwin

// Swift 6 兼容调用方式（参考 MemoryReader.swift 的 withUnsafeMutablePointer 模式）
func readRusage(pid: Int32) -> rusage_info_v4? {
    var info = rusage_info_v4()
    let ret = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { typedPtr in
            // rusage_info_t 是 void*；proc_pid_rusage 第三参数要求 rusage_info_t *
            // 但 Swift 不允许直接传 *rusage_info_v4 → 用 UnsafeMutableRawPointer
            proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutableRawPointer(ptr))
        }
    }
    return ret == 0 ? info : nil
}
```

**更简洁的写法**（推荐，省去二次 rebound）：

```swift
func readRusage(pid: Int32) -> rusage_info_v4? {
    var info = rusage_info_v4()
    let ret = withUnsafeMutablePointer(to: &info) {
        proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutableRawPointer($0))
    }
    return ret == 0 ? info : nil
}
```

`proc_pid_rusage` 的第三个参数类型是 `rusage_info_t *`（即 `void **`），而 `rusage_info_v4` 的指针是 `UnsafeMutablePointer<rusage_info_v4>`，通过 `UnsafeMutableRawPointer($0)` 擦除类型即可合法传递。返回值 0 = 成功，-1 = 失败（EPERM / ESRCH / 进程已退出），**失败直接 skip，不 crash**。

### proc_listpids 缓冲区大小舞蹈

[VERIFIED: libproc.h + 标准 macOS 惯用法]

```swift
// 1. 先 probe 大小（buffer=NULL，size=0）
let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
guard needed > 0 else { return [] }

// 2. 分配 + 再次调用（可能在两次调用之间多了新进程，略多分配 10%）
let count = Int(needed) / MemoryLayout<Int32>.size
var pids = [Int32](repeating: 0, count: count + count / 10)
let actual = pids.withUnsafeMutableBytes { buf in
    proc_listpids(UInt32(PROC_ALL_PIDS), 0, buf.baseAddress, Int32(buf.count))
}
guard actual > 0 else { return [] }

let pidCount = Int(actual) / MemoryLayout<Int32>.size
// pids[0..<pidCount] 包含有效 PID 列表（包括 pid 0，需过滤）
```

**过滤规则**：跳过 `pid == 0`（kernel_task，无法采样）。

### proc_name vs proc_pidpath 进程名获取

[VERIFIED: libproc.h 函数签名 + proc_info.h MAXCOMLEN/PROC_PIDPATHINFO_MAXSIZE 常量]

| 函数 | 缓冲区大小 | 返回名称 | 适用场景 |
|------|-----------|---------|---------|
| `proc_name(pid, buf, 256)` | 建议 256（MAXCOMLEN=16 太短；实际最多约 64 字符） | 短名（如 "Safari Web Content"）| **首选**，对全部 PID 调用成本低 |
| `proc_pidpath(pid, buf, PROC_PIDPATHINFO_MAXSIZE)` | 4096 (PROC_PIDPATHINFO_MAXSIZE) | 完整路径 | 仅对最终 Top-N 调用（5 个），获取 `.lastPathComponent` 作更可读名称 |

**推荐做法**：
1. 对所有 PID 调用 `proc_name` 获取短名（开销小）。
2. 完成排序取出 Top-N 后，对这 5 个进程可选地再调用 `proc_pidpath` 取 basename 以获得更可读的名称（例如 "Safari" 而非 "com.apple.Safari"）。对于被拒绝（EPERM）的 PID，`proc_name` 返回 0 字节或空字符串——此时用 pid 字符串作 fallback，**不 crash，不 skip 该行**（PID 存在但名称不可读是正常情况）。

### sysctl kinfo_proc 不再需要

由于 `rusage_info_v4.ri_proc_start_abstime` 已经提供进程启动时间（Mach ticks），**不需要** 通过 `sysctl(KERN_PROC_PID)` + `kinfo_proc.kp_proc.p_starttime` 获取启动时间。这简化了实现：一次 `proc_pid_rusage` 调用即可同时获得 CPU ticks、内存和进程启动时间，构成完整的快照条目。

（如需参考 sysctl 路径：`mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]` → `kinfo_proc.kp_proc.p_starttime: timeval`，精度为微秒。两个方法都可做键，但 `ri_proc_start_abstime` 更直接。）

---

## Code Examples

### ProcessResourceUsage Sendable 快照结构

```swift
// Source: CONTEXT.md locked decision + Swift 6 Sendable 约定
struct ProcessResourceUsage: Sendable, Equatable {
    let processName: String
    let pid: Int32
    let cpuPercent: Double?   // nil = 首帧（无前值），显示"—"
    let memoryBytes: UInt64   // ri_phys_footprint，无需 delta
}
```

### ProcessResourceReader.sample() 核心逻辑

```swift
// Source: Apple headers + osquery/htop CPU% 研究结论 + CONTEXT.md 算法
import Darwin

final class ProcessResourceReader {

    // (pid, start_abstime) → (cpuTicks, wallTicks)
    private var prevSnapshot: [ProcessKey: SnapshotEntry] = [:]

    struct ProcessKey: Hashable {
        let pid: Int32
        let startAbstime: UInt64   // ri_proc_start_abstime，Mach ticks
    }

    struct SnapshotEntry {
        let cpuTicks: UInt64       // ri_user_time + ri_system_time
        let wallTicks: UInt64      // mach_absolute_time() at sample time
    }

    func clearSnapshot() {
        prevSnapshot.removeAll()
    }

    /// 同步采样，从后台 Task.detached 调用。
    /// 返回 (cpuTop5, memoryTop5)。
    func sample() -> ([ProcessResourceUsage], [ProcessResourceUsage]) {
        let wallNow = mach_absolute_time()

        // 1. 枚举 PID
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return ([], []) }
        let count = Int(needed) / MemoryLayout<Int32>.size
        var pids = [Int32](repeating: 0, count: count + count / 10)
        let actual = pids.withUnsafeMutableBytes { buf in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buf.baseAddress, Int32(buf.count))
        }
        guard actual > 0 else { return ([], []) }
        let pidCount = Int(actual) / MemoryLayout<Int32>.size

        // 2. 采集每个 PID 的 rusage
        var newSnapshot: [ProcessKey: SnapshotEntry] = [:]
        var candidates: [(name: String, pid: Int32, cpuPercent: Double?, memBytes: UInt64)] = []

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }  // 过滤 pid 0

            var info = rusage_info_v4()
            let ret = withUnsafeMutablePointer(to: &info) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutableRawPointer($0))
            }
            guard ret == 0 else { continue }  // EPERM/ESRCH → skip

            let cpuTicks = info.ri_user_time + info.ri_system_time
            let startAbstime = info.ri_proc_start_abstime
            let memBytes = info.ri_phys_footprint
            let key = ProcessKey(pid: pid, startAbstime: startAbstime)

            // 计算 CPU%
            var cpuPercent: Double? = nil
            if let prev = prevSnapshot[key] {
                let deltaCPU = cpuTicks >= prev.cpuTicks
                    ? cpuTicks - prev.cpuTicks
                    : 0  // max(delta, 0)
                let deltaWall = wallNow > prev.wallTicks
                    ? wallNow - prev.wallTicks
                    : 0
                if deltaWall > 0 {
                    cpuPercent = min(Double(deltaCPU) / Double(deltaWall) * 100.0, 999.9)
                    // 注：上限 999.9 仅防止异常值，正常单核不超过 100
                }
            }
            // 首帧：cpuPercent = nil（显示"—"）

            newSnapshot[key] = SnapshotEntry(cpuTicks: cpuTicks, wallTicks: wallNow)

            // 进程名：先 proc_name，失败 fallback to PID string
            var nameBuf = [CChar](repeating: 0, count: 256)
            let nameLen = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let name: String = nameLen > 0
                ? String(cString: nameBuf)
                : "PID \(pid)"

            candidates.append((name: name, pid: pid, cpuPercent: cpuPercent, memBytes: memBytes))
        }

        prevSnapshot = newSnapshot

        // 3. Top-5 CPU（nil cpuPercent 的首帧进程排到末尾）
        let cpuSorted = candidates.sorted {
            let a = $0.cpuPercent ?? -1
            let b = $1.cpuPercent ?? -1
            if a == b { return $0.name < $1.name }
            return a > b
        }
        let cpuTop5 = Array(cpuSorted.prefix(5)).map {
            ProcessResourceUsage(processName: $0.name, pid: $0.pid,
                                 cpuPercent: $0.cpuPercent, memoryBytes: $0.memBytes)
        }

        // 4. Top-5 内存
        let memSorted = candidates.sorted {
            if $0.memBytes == $1.memBytes { return $0.name < $1.name }
            return $0.memBytes > $1.memBytes
        }
        let memTop5 = Array(memSorted.prefix(5)).map {
            ProcessResourceUsage(processName: $0.name, pid: $0.pid,
                                 cpuPercent: $0.cpuPercent, memoryBytes: $0.memBytes)
        }

        return (cpuTop5, memTop5)
    }
}
```

### PopoverManager 采样循环启停模式

```swift
// Source: CONTEXT.md locked decision + 参照现有 processRefreshTask 模式
// 在 PopoverManager 内新增：

private var resourceSampleTask: Task<Void, Never>?
private let resourceReader = ProcessResourceReader()

func startResourceSampling() {
    resourceSampleTask?.cancel()
    resourceSampleTask = Task { [weak self] in
        while !Task.isCancelled {
            guard let self else { return }

            let (cpuTop, memTop) = await Task.detached(priority: .utility) { [reader = self.resourceReader] in
                reader.sample()
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.dashboardState.topCPUProcesses = cpuTop
                self.dashboardState.topMemoryProcesses = memTop
                self.dashboardState.resourceLoading = false
            }

            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
        }
    }
}

// toggle() 打开 popover 后调用：
// startResourceSampling()
// （现有 refreshProcessList() 保持不变）

// popoverDidClose() 新增：
func popoverDidClose(_ notification: Notification) {
    stopOutsideClickMonitor()
    // Phase 8 新增：
    resourceSampleTask?.cancel()
    resourceSampleTask = nil
    resourceReader.clearSnapshot()
    // DashboardState 的 resourceLoading 重置为 true 供下次打开显示 spinner
    dashboardState.resourceLoading = true
}
```

### ProcessMetricRow 泛化设计

```swift
// 通用进程行：尾部通过 trailing: AnyView 或枚举注入，容纳：
// - 网络：↑x /s  ↓x /s（双 Label）
// - CPU：  12.3%（单 Text）
// - 内存：  1.2G（单 Text）

struct ProcessMetricRow<Trailing: View>: View {
    let processName: String
    let pid: Int32?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(processName)
                .font(.caption2).lineLimit(1).truncationMode(.tail)
            if let pid { Text("(\(pid))").font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary) }
            Spacer()
            trailing()
        }
        .padding(.vertical, 1)
    }
}

// 网络行（现有 ProcessRow 替换为）：
ProcessMetricRow(processName: proc.processName, pid: proc.processIdentifier) {
    Label(ByteFormatting.format(proc.uploadBytesPerSec) + "/s", systemImage: "arrow.up")
        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.orange)
    Label(ByteFormatting.format(proc.downloadBytesPerSec) + "/s", systemImage: "arrow.down")
        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.blue)
}

// CPU 行：
ProcessMetricRow(processName: proc.processName, pid: proc.pid) {
    Text(proc.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—")
        .font(.system(.caption2, design: .monospaced))
}

// 内存行：
ProcessMetricRow(processName: proc.processName, pid: proc.pid) {
    Text(ByteFormatting.format(Double(proc.memoryBytes)))
        .font(.system(.caption2, design: .monospaced))
}
```

---

## Don't Hand-Roll

| 问题 | 不要自己实现 | 直接用 | 原因 |
|------|------------|--------|------|
| 字节格式化 | 自定义格式器 | `ByteFormatting.format()` | 项目已有，已测试 |
| 壁钟纳秒转换 | `mach_timebase_info` 手动转换 | **直接用 Mach ticks 计算 delta**（units cancel）| Mach ticks 与 ri_user_time 同单位，无需转换 |
| 进程名获取 | 自行 parse `/proc` 或调用 ps | `proc_name(pid, buf, size)` | 零权限，零进程 spawn |
| 内存格式化 | 自定义 ByteFormatter | `ByteFormatting.format(Double(proc.memoryBytes))` | 项目已有 |
| 采样超时处理 | 手动 Timer + dispatch | `Task.sleep(nanoseconds:)` + `Task.isCancelled` | Swift 6 结构化并发，自动取消传播 |

---

## Common Pitfalls

### Pitfall 1: 假设 ri_user_time 是纳秒
**问题**：直接用 `ri_user_time` 除以 `Date().timeIntervalSince1970 * 1e9` 或 `DispatchTime.now()`。
**根因**：在 Apple Silicon 上 `ri_user_time` 是 Mach ticks，1 tick ≈ 41.7 ns（非 1 ns）；而 `DispatchTime`/`Date` 是真实纳秒。分母分子单位不同 → CPU% 在 Apple Silicon 上偏高约 41×。
**避免**：壁钟也用 `mach_absolute_time()`——两者同单位，units cancel，无需 `mach_timebase_info`。

### Pitfall 2: 仅用 pid 作快照键（PID 复用）
**问题**：进程 A 退出，新进程 B 拿到同一 pid，delta 计算出离谱的 CPU%（ri_user_time 从 0 开始）。
**根因**：pid 在内核中复用，两次采样之间可能换人。
**避免**：用 `(pid, ri_proc_start_abstime)` 作复合键。新进程的 `startAbstime` 不同，prev 查找失败 → cpuPercent = nil（首帧"—"），下一帧正常显示。

### Pitfall 3: 在 Main Actor 上直接调用 proc_pid_rusage
**问题**：枚举全系统进程 + syscall 约需 10-50ms，在 MainActor 上会卡顿 UI。
**根因**：libproc 逐进程 syscall，百个进程需要百次系统调用。
**避免**：在 `Task.detached(priority: .utility)` 内执行，通过 `await MainActor.run {}` 回传结果。

### Pitfall 4: resourceSampleTask 未在 popoverDidClose 取消
**问题**：用户关闭 popover 后 Task 仍在 1.5s 循环，持续采样，造成不可见的后台 CPU 开销。
**根因**：漏掉 `resourceSampleTask?.cancel()`。
**避免**：在 `popoverDidClose` 中 cancel + nil + clearSnapshot，并将 resourceLoading 重置为 true（下次打开会显示 spinner）。

### Pitfall 5: proc_pid_rusage 返回 -1 时未跳过
**问题**：对 root-owned 进程（如 `kernel_task`，大量系统守护进程）调用 `proc_pid_rusage` 返回 -1 / EPERM，若强解包数据则取到全零结构，将这些进程误入 Top-N 列表。
**根因**：忘记检查返回值。
**避免**：`guard ret == 0 else { continue }`。被拒绝的进程在 Top-N 视角不重要——用户关心的是自己的应用。

### Pitfall 6: proc_listpids 缓冲区竞争
**问题**：第一次 probe 返回 N，分配 N/4 字节，第二次调用时进程数已增至 N+10，截断 PID 列表。
**根因**：两次调用之间系统进程数可能变化。
**避免**：分配时额外加 10%（`count + count / 10`）。最终有效数量从第二次返回值计算，不用 count。

### Pitfall 7: 忘记在 pbxproj 中登记新文件
**问题**：新建 `ProcessResourceReader.swift` 后 Xcode 提示 BUILD SUCCEEDED，但运行时类型缺失（或根本未编译到 target）。
**根因**：Phase 7 教训：在 Finder/CLI 创建的文件不会自动加入编译 target，必须手动在 pbxproj 中添加 `PBXBuildFile` 和 `PBXFileReference` 条目。
**避免**：在 Xcode 内通过 File → New File 创建，或执行后验证 pbxproj 包含该文件。

---

## State of the Art

| 旧做法 | 当前推荐做法 | 变更时间 | 影响 |
|--------|------------|---------|------|
| 假设 ri_user_time 是纳秒（Intel 时代正确）| 用 mach_absolute_time 作壁钟（units cancel）| Apple Silicon 发布（M1, 2020）| Intel 代码在 ARM 上偏高 ~41×，必须修正 |
| 仅用 pid 作快照键 | (pid, ri_proc_start_abstime) 复合键 | 一直是最佳实践，M1 后更重要 | 避免 PID 复用导致异常首帧 CPU% |
| 用 sysctl kinfo_proc 获取 startTime | 直接读 ri_proc_start_abstime（已在 rusage_info_v4）| macOS 10.9（RUSAGE_INFO_V4 引入）| 减少一次 sysctl 调用 |
| proc_pidinfo(PROC_PIDTASKINFO)（旧版 STACK.md 建议）| proc_pid_rusage(RUSAGE_INFO_V4)（CONTEXT.md 锁定）| CONTEXT.md 决策 | 两者均可行，V4 多了 ri_proc_start_abstime 在同一调用中 |

**已废弃/避免**：
- `task_for_pid`：entitlement-gated，对他人进程失败，CONTEXT.md 明确禁止。
- `/bin/ps` fallback：不需要 —— libproc 在 Swift 6 下完全可行（见并发分析），无须 subprocess。

---

## Swift 6 并发分析：libproc + actor 边界

[VERIFIED via Swift 6 language model + C struct Sendable rules + project existing patterns]

### 结论：libproc 在 Swift 6 下完全可行，推荐使用，不需要 /bin/ps fallback

**逐点分析**：

1. **libproc 函数线程安全性**：`proc_listpids`、`proc_pid_rusage`、`proc_name`、`proc_pidpath` 均为内核 syscall，无全局可变状态，在任意线程并发调用安全。[ASSUMED from syscall semantics，但业界实践（osquery、htop、exelban/stats）均从后台线程调用]

2. **rusage_info_v4 的 Sendable**：C 结构体 `rusage_info_v4` 仅含 `uint64_t` 和 `uint8_t[16]` 值类型字段，Swift 编译器对此类 C 结构体自动合成 `@unchecked Sendable` 或允许隐式 Sendable conformance（同 `vm_statistics64_data_t` 在现有 MemoryReader 中的用法）。

3. **ProcessResourceReader 的并发形态选择**：

   | 选项 | 评估 |
   |------|------|
   | **普通 class，Task 独占访问**（推荐）| `ProcessResourceReader` 实例由 `resourceSampleTask` 中的单一 `Task.detached` 在循环中持续访问；不存在并发读写 `prevSnapshot`。Swift 6 不报错，因为没有跨 actor boundary 的可变状态共享。 |
   | actor ProcessResourceReader | 过设计：`sample()` 是同步的重 syscall，放在 actor 会让 actor 执行器在每次 sample 期间被占用，其他等待该 actor 的代码会排队。且仅一个 Task 访问它。 |
   | @MainActor class | 错误：会把重 syscall 带到 MainActor，卡顿 UI。 |

4. **跨 actor 传递结果**：`[ProcessResourceUsage]` 数组 —— `ProcessResourceUsage` 是 `Sendable` struct（值类型，所有字段值类型）—— 可安全跨 actor boundary 传递。

5. **Task.detached 与 weak self 安全**：`PopoverManager` 是 `@MainActor` 单例，生命周期与 App 相同，实际上不会销毁，但仍保留 `[weak self]` 作防御。

6. **为何不需要 /bin/ps fallback**：Swift 6 的严格并发检查关注的是数据竞争，不关注 C syscall 本身。`proc_pid_rusage` 是无副作用的 C 函数调用，在 `nonisolated` 或 `Task.detached` 上下文中调用完全合法。唯一需要处理的是 `rusage_info_v4` 的 Sendable——全值类型结构体，编译器接受。

---

## Environment Availability

| 依赖 | 要求方 | 可用 | 版本 | 备注 |
|------|--------|------|------|------|
| `proc_listpids` (libproc) | ProcessResourceReader | ✓ | macOS 10.5+，项目最低 macOS 14 | 长期稳定 |
| `proc_pid_rusage` (libproc) | ProcessResourceReader | ✓ | macOS 10.9+（RUSAGE_INFO_V4: macOS 10.10+）| RUSAGE_INFO_V4 在 macOS 14 上完全可用 |
| `mach_absolute_time` | ProcessResourceReader | ✓ | macOS 全版本 | 标准 Mach 接口 |
| Non-sandboxed entitlement | 整个 App | ✓ | 项目已配置，v1.0 nettop 依赖同条件 | 无需新增 entitlement |
| `import Darwin` | Swift 文件 | ✓ | 当前项目已用（MemoryReader、GPUReader）| libproc 是 Darwin 子模块 |

**无阻塞依赖。**

---

## Validation Architecture

> 跳过此节：`.planning/config.json` 无 `workflow.nyquist_validation` 配置，且本 Phase 核心是 C-interop syscall + popover-gated UI，无适合 unit-test 的纯逻辑边界（采样函数依赖运行中进程列表，UI 依赖 popover 打开状态）。验收通过人工 UAT（见 CONTEXT.md 成功标准 #3：可验证关闭后零 CPU 开销）。

---

## Security Domain

> `security_enforcement` 未明确设置，按启用处理。

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | 否 | — |
| V3 Session Management | 否 | — |
| V4 Access Control | 部分 | proc_pid_rusage 对非本用户进程返回 EPERM，kernel-enforced，probe-and-skip |
| V5 Input Validation | 是 | proc_pid_rusage 返回值校验（`guard ret == 0`）；进程名截断防止 buffer overflow |
| V6 Cryptography | 否 | — |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| 读取其他用户敏感进程名 | Info Disclosure | 内核已拦截（EPERM）；probe-and-skip 不向 UI 暴露错误细节 |
| PID 复用导致冒名顶替 | Spoofing | (pid, ri_proc_start_abstime) 复合键 + max(delta,0) |
| 异常大 CPU% 值（计数器翻转）| Tampering | `max(Δcpu, 0)` + `min(result, 999.9)` clamp |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | libproc 函数（proc_listpids, proc_pid_rusage）为线程安全 syscall | Swift 6 并发分析 | 极低风险：业界工具（osquery, htop, stats）均从后台线程调用，未见竞争报告 |
| A2 | ri_phys_footprint 对应 Activity Monitor"内存"列 | 内存字段选择 | MEDIUM：Apple 未在头文件注释中明确说明；但 exelban/stats 和社区实践均用 phys_footprint 对齐 AM |

**验证建议**：A2 可在真机上用 `ioreg` 或 Activity Monitor 对照验证（运行自测代码，比较 phys_footprint 值与 AM 显示）。

---

## Open Questions

1. **`ri_phys_footprint` vs Activity Monitor "内存"列的精确对应**
   - 已知：`ri_phys_footprint` 是内核 `ledger` 跟踪的 phys footprint，比 RSS 更接近 AM 内存列
   - 未知：AM 内存列是否等于 `phys_footprint` 还是有细微差异（如含 IOKit dirty pages）
   - 建议：在第一个采样帧后，开发者对照 Activity Monitor 目测验证 Top 5 顺序与值是否吻合；差异通常 <5%，不影响 Top-N 排序结果

2. **proc_name 缓冲区大小**
   - 已知：`MAXCOMLEN = 16`，但实际上许多进程名更长（如 "Safari Web Content"）
   - 建议：使用 256 字节缓冲区（`var nameBuf = [CChar](repeating: 0, count: 256)`）
   - `proc_name` 在内部会截断到 PROC_PIDPATHINFO_SIZE，256 字节绰绰有余

---

## Sources

### Primary (HIGH confidence)

- `/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk/usr/include/libproc.h` — `proc_listpids`、`proc_pid_rusage`、`proc_name`、`proc_pidpath` 函数签名；`rusage_info_t` 类型；`PROC_PIDPATHINFO_MAXSIZE` 常量
- `/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk/usr/include/sys/resource.h` — `rusage_info_v4` 完整结构体字段；`RUSAGE_INFO_V4` 常量
- `/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk/usr/include/sys/proc.h` — `extern_proc.p_starttime`（sysctl 备用路径，本阶段未用）
- `/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk/usr/include/sys/proc_info.h` — `PROC_ALL_PIDS`、`proc_taskinfo`（参考）
- `/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk/usr/include/Darwin.modulemap` — 确认 libproc 是 Darwin 子模块，`import Darwin` 即可访问
- `.planning/phases/08-per-process-top-n-cpu-memory/08-CONTEXT.md` — 锁定决策（libproc 路径、算法、数据模型）

### Secondary (MEDIUM-HIGH confidence)

- [osquery PR #7473 — Fix ri_user_time unit on M1](https://github.com/osquery/osquery/pull/7473) — 确认 ri_user_time 是 Mach ticks，非纳秒；mach_timebase_info 转换公式；Apple Silicon vs Intel 差异
- [htop PR #752 — Fix macOS CPU time calculations](https://github.com/htop-dev/htop/pull/752) — 独立验证 pti_total_user 单位问题；units-cancel 方法有效性
- [osquery Issue #7459](https://github.com/osquery/osquery/issues/7459) — Apple Silicon 上每 tick ≈ 40ns 的数值证据
- [Medium: Decoding Mach — Advanced CPU Metrics](https://medium.com/@federicosauter/decoding-mach-investigating-macoss-kernel-for-advanced-cpu-metrics-6627bf5429a4) — 内核源码级调查；ri_user_time 单位来自 `recount_usage._time_mach`；units-cancel 方法原理
- `.planning/research/STACK.md` (v2.0 研究) — 确认 libproc 无 task_for_pid、非沙盒要求、proc_pidpath 使用模式

### Tertiary (LOW confidence)

- [Apple Developer Forums Thread 655349](https://developer.apple.com/forums/thread/655349) — 确认 proc_pidinfo/proc_pid_rusage 无需 task_for_pid，但无精确时间单位说明

---

## Metadata

**Confidence breakdown:**
- libproc API 调用方式：HIGH — 直接读头文件，字段/签名 100% 确定
- ri_user_time 时间单位 = Mach ticks：HIGH — 多个独立开源 PR/Issue 交叉验证
- ri_phys_footprint = Activity Monitor 内存：MEDIUM — 业界惯例，未见官方明确声明
- Swift 6 并发方案：HIGH — 基于现有项目模式 + Swift 6 类型系统推论
- proc_name 256 字节缓冲安全：HIGH — MAXCOMLEN=16，头文件确认；256 绰绰有余

**Research date:** 2026-06-17
**Valid until:** 2026-12-17（libproc 接口极稳定，RUSAGE_INFO_V4 自 macOS 10.10 起不变）

---

## RESEARCH COMPLETE
