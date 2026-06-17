# Phase 8: Per-Process Top-N CPU & Memory - Context

**Gathered:** 2026-06-17
**Status:** Ready for planning

<domain>
## Phase Boundary

在 popover 内新增两个"Top-N 进程"区块：当前 CPU 占用最高的 3-5 个进程（进程名 + CPU%）与常驻内存占用最高的 3-5 个进程（进程名 + 内存）。采样仅在 popover 可见时进行，关闭即停（无 24/7 后台开销）。新增基于 `libproc` 的 `ProcessResourceReader`（无 `task_for_pid`、无新权限），仅产出 `Sendable` 快照。复用并泛化 v1.0 已有的进程列表 UI 与 popover 门控基础设施。覆盖 PROC-01..03。

不做：全进程可排序列表（保持轻量 Top-N，不与 Activity Monitor 重叠）、逐进程 GPU、持久化。
</domain>

<decisions>
## Implementation Decisions

### 采样引擎 (libproc CPU/内存)
- API：**libproc** —— `proc_listpids(PROC_ALL_PIDS, …)` 枚举 PID，`proc_pid_rusage(pid, RUSAGE_INFO_V4, …)` 取累计 CPU 时间（`ri_user_time + ri_system_time`，纳秒）与内存。**无 `task_for_pid`、无新 entitlement**。
- CPU% 算法：保存一份 `(pid, 启动时间)` → (上次 cpu_time, 上次时间戳) 的快照 map；`CPU% = max(Δcpu_ns, 0) / Δwall_ns × 100`。首帧（无前值）→ **"—"**（非累计 rusage 百分比）。**启动时间纳入键**以正确处理 PID 消失/复用。`max(delta,0)` 处理计数器异常。
- 采样节奏：popover 打开时以 **~1.5s 间隔循环采样**（Task 循环 + sleep），使 CPU 差实时更新；popover 关闭立即 cancel 该循环。
- 内存指标：`proc_pid_rusage` 的**物理内存占用**（`ri_resident_size` 或 `ri_phys_footprint`，具体字段由研究阶段定）；`ByteFormatting` 格式化。

### 数据模型与门控 (Data Model & Gating)
- 快照类型：新增 **`ProcessResourceUsage: Sendable`**（`processName: String`、`pid: Int32?`、`cpuPercent: Double?`（nil = 首帧"—"）、`memoryBytes: UInt64`）。独立于既有 `ProcessNetworkUsage`，不混用。
- reader 形态：**`ProcessResourceReader` class**（持有上次快照 map，CPU 差需要跨采样状态）。由 PopoverManager 的门控 Task 循环驱动；在 `Task.detached(.utility)` 上做 libproc 调用，结果回 MainActor。
- 启停位置：`PopoverManager.toggle` 打开 → 启动资源采样循环；`popoverDidClose` → cancel 循环并**清空快照 map**（重开首帧重新显示"—"），保证关闭后零后台 CPU 开销（成功标准 #3 可验证）。既有网络 Top-N 的一次性刷新保持不变。
- Top-N 选取：**两份独立列表** —— CPU% Top 5 与 内存 Top 5（同一进程可同时出现在两表）。降序排序，CPU 相等/内存相等时按进程名 tie-break。limit 5。

### 展示 (Popover 区块)
- 布局：popover 新增**两个区块**"CPU 占用 Top 5"与"内存占用 Top 5"，紧邻既有"Top Processes (by network)"。沿用卡片背景风格（RoundedRectangle cornerRadius 8 / Color.primary.opacity(0.04)）。
- 进程行泛化：抽出通用 **`ProcessMetricRow`**（进程名 + 可选 pid + 尾部值文本/可选色），供网络/CPU/内存三处复用；保留现有网络行的 ↑↓ 行为（可通过尾部内容定制）。
- 状态：CPU% 首帧显示 **"—"**（尚无差值）随后转实时%；加载用现有 `ProgressView` spinner（"Sampling…"）；空 → "无数据"。内存即时可得（无需差值）。
- 条数：各 **Top 5**（匹配既有 `prefix(5)` 与"3-5"需求；少于 5 则显示实际数量）。

### 研究阶段澄清 (resolved post-research, HIGH 置信度 — 直读 macOS SDK 头文件)
- **CPU 时间单位修正**：`ri_user_time`/`ri_system_time` 是 **Mach absolute time ticks，不是纳秒**（AS 上 1 tick≈41.7ns，Intel 上=1ns——历史 bug 根源）。正确做法：用 `mach_absolute_time()` 取壁钟时间戳作为 Δwall，与 cpu ticks **同单位**，`CPU% = max(Δcpu_ticks,0)/Δwall_ticks×100` 中单位天然抵消，**无需 `mach_timebase_info` 转换**。
- **启动时间键免 sysctl**：`rusage_info_v4` 已含 `ri_proc_start_abstime`（Mach ticks）。`(pid, ri_proc_start_abstime)` 作复合键即可 PID 复用安全——**一次 `proc_pid_rusage` 调用取齐 CPU ticks、内存、启动时间三者**，无需单独 `sysctl(KERN_PROC_PID)`。
- **内存字段定为 `ri_phys_footprint`**（应用独占物理内存，对应活动监视器"内存"列）；**不用** `ri_resident_size`（RSS 含共享库映射、虚高）。
- **/bin/ps fallback 不实现**：libproc 是纯 C syscall、任意线程安全，`rusage_info_v4` 全值类型满足 Swift 6 Sendable；`ProcessResourceReader` 作普通 class 由单一 `Task.detached` 独占访问即无数据竞争，编译器不报错。STATE 的 ps fallback 关切已消解——直接用 libproc。
- **`import Darwin` 足够**（libproc 在 Darwin.modulemap 内），无需 bridging header（与现有 MemoryReader/GPUReader 一致）。
- 进程名用 `proc_name(pid,…)`（或 `proc_pidpath` basename，PROC_PIDPATHINFO_MAXSIZE 缓冲）；`proc_pid_rusage` 返回 -1/errno 的 PID（权限/已退出）静默跳过（probe-and-skip）。

### Claude's Discretion
- **libproc vs /bin/ps fallback**（STATE Phase 8 关切）：优先 libproc。若 Swift 6 严格并发下 libproc 的 C struct/handle 跨 actor 边界过于棘手，已记录的 fallback 是仿 `ProcessNetworkReader` spawn `/bin/ps` 解析。由研究/执行阶段依实际并发可行性裁定，但务必先尝试 libproc。
- `proc_pid_rusage` 的具体 `RUSAGE_INFO` 版本与内存字段（`ri_resident_size` vs `ri_phys_footprint`，后者更接近活动监视器"内存"）由研究阶段核实定稿。
- 进程名获取：`proc_name(pid, …)` 或 `proc_pidpath` basename；零权限。被拒绝读取的 PID（权限/已退出）静默跳过（probe-and-skip），绝不崩溃。
- `ProcessMetricRow` 的尾部内容如何同时容纳网络（↑↓ 双值）与 CPU/内存（单值）：由 Claude 设计（可用泛型尾部 view 或枚举式 trailing）。
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MacStatus/Readers/ProcessNetworkReader.swift` — v1.0 按需进程采样范式（enum + `Task.detached` 调用、Sendable 结果、`.processes/.idle/.unavailable` 枚举、超时处理）。Phase 8 的 reader 借鉴其门控/线程模型，但需 class 持状态（CPU 差）。`ProcessNetworkUsage: Sendable` 是快照范式样板。
- `MacStatus/UI/Views/ProcessListView.swift` — `ProcessListView` + 私有 `ProcessRow`（进程名 + pid + 尾部 Label）。Phase 8 泛化出 `ProcessMetricRow`，三处复用。
- `MacStatus/UI/PopoverManager.swift` — **门控核心**：`toggle()` 打开调 `refreshProcessList()`（`Task.detached(.utility)` + 取消旧任务 + MainActor 更新）；`popoverDidClose` 当前只清 outside-click monitor。Phase 8 在此加资源采样循环的启动(open)/取消(close)。`dashboardState` 是 UI 真源。
- `MacStatus/UI/Views/DashboardView.swift` — `DashboardState: @MainActor ObservableObject`；已有 `topProcesses/processesLoading/processError`。新增 CPU/内存 Top-N 的 `@Published` 字段 + 加载/错误态。body 在网络列表附近插入两个新区块。
- `MacStatus/Utils/ByteFormatting.swift` — 内存字节格式化复用。

### Established Patterns
- 按需采样：popover 打开触发，`Task.detached(.utility)` 跑重活，`await MainActor.run` 更新 `@Published`，取消旧任务防叠加。
- Sendable 快照跨 actor；reader 不直接碰 UI。
- probe-and-skip：不可读的进程静默跳过（类比 v1.0 各 reader 的 nil 降级）。

### Integration Points
- 新建 `MacStatus/Readers/ProcessResourceReader.swift`（+ `ProcessResourceUsage` Sendable struct）。
- `PopoverManager`：新增 `resourceSampleTask: Task<Void,Never>?` + 启动/取消逻辑（open→start loop, close→cancel+clear）。
- `DashboardState`：新增 `topCPUProcesses`/`topMemoryProcesses`（[ProcessResourceUsage]）+ 加载/错误态 + update 方法。
- `DashboardView`：插入两个新区块（CPU/内存 Top 5），用泛化 `ProcessMetricRow`。
- 泛化 `ProcessListView`/`ProcessRow` → 通用 `ProcessMetricRow`（网络列表改用之）。
- **新文件需手动加入 `MacStatus.xcodeproj` 编译源**（参 Phase 7 教训：内联/新文件易漏登记 pbxproj，仿 Readers 组现有条目）。
</code_context>

<specifics>
## Specific Ideas

- 关闭即停是硬约束（成功标准 #3）：采样循环必须随 popover 关闭被 cancel，且可验证关闭后无可测 CPU 开销。
- 零权限/零新 entitlement 是硬约束：libproc only，禁用 `task_for_pid`。
- PID 复用安全：`(pid, 启动时间)` 键 + `max(delta,0)`。
- 用户三个灰区全部接受推荐方案。
- 新文件务必登记 pbxproj（Phase 7 曾因内联创建漏登记导致假阳性 BUILD SUCCEEDED）。

</specifics>

<deferred>
## Deferred Ideas

- 全进程可排序列表 / 完整活动监视器 → v2.0 Out of Scope（保持轻量 Top-N）。
- 逐进程 GPU 占用 → macOS 无公开 API（Out of Scope）。
- 进程级历史趋势/持久化 → Out of Scope。
- 状态栏内显示 Top 进程 → 非本阶段（popover-only）。
- 点击进程行查看详情/终止进程 → 未纳入 v2.0。
</deferred>
