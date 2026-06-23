---
phase: 08-per-process-top-n-cpu-memory
verified: 2026-06-17T00:00:00Z
status: human_needed
score: 4/4 must-haves verified
verifier: inline (orchestrator — verifier subagent socket dropped mid-run; verification completed inline via grep + source read + build)
human_validation_disposition: "deferred 2026-06-17 — 用户在自主模式选择继续到 Phase 9；3 项运行时 UAT 与 Phase 7/9 一并补测。代码静态验证(4/4) + build + 审查 clean（2 并发 bug 已 actor 修复）。"
overrides_applied: 0
human_verification:
  - test: "打开 popover，观察 'CPU 占用 Top 5' 与 '内存占用 Top 5' 两个区块"
    expected: "首次打开 CPU% 短暂显示 '—'（无前值），约 1.5s 后转为实时百分比；内存即时显示（如 '512MB'）；各 Top 5 行有进程名"
    why_human: "实时 CPU 差值与内存数据只在运行中可见；静态分析无法替代实际渲染"
  - test: "关闭 popover 后，用活动监视器观察 MacStatus 自身 CPU 占用"
    expected: "popover 关闭后 MacStatus 无可测后台 CPU 开销（采样循环已 cancel + clearSnapshot），重新打开首帧重新显示 '—'"
    why_human: "'关闭即停、零后台开销' 是 PROC-03 的运行时可验证标准，需实际测量"
  - test: "连续开关 popover 多次 / 让某进程在采样间退出"
    expected: "不崩溃；退出/权限不足的进程被静默跳过；PID 复用不串数据（(pid, 启动时间) 复合键）"
    why_human: "PID 消失/复用与 probe-and-skip 的鲁棒性需真实进程动态触发"
---

# Phase 08: Per-Process Top-N CPU & Memory 验证报告

**Phase Goal:** When the user opens the popover they see the top 3-5 processes by CPU and by memory right now, and sampling stops the moment the popover closes (no 24/7 background cost).
**Verified:** 2026-06-17（编排器内联验证 —— 验证子代理 socket 中途断开，已用 grep + 源码阅读 + 构建完成等效验证）
**Status:** human_needed（4/4 静态验证通过；3 项运行时行为需人工确认）

---

## Goal Achievement — 4 ROADMAP 成功标准

| # | 标准 | 状态 | 证据 |
|---|------|------|------|
| 1 | CPU Top 3-5（名+CPU%），CPU% 为两次 libproc 快照壁钟差，首帧"—"，非累计 rusage | ✓ VERIFIED | `ProcessResourceReader.swift`：`cpuPercent = min(Double(deltaCPU)/Double(deltaWall)*100, 999.9)`，`deltaCPU = max(Δ,0)`；首帧无前值 `cpuPercent = nil`。`DashboardView`：`proc.cpuPercent.map{ "%.1f%%" } ?? "—"`；区块 "CPU 占用 Top 5" |
| 2 | 内存 Top 3-5（名+内存），复用泛化行，与网络 Top-N 并列 | ✓ VERIFIED | `DashboardView` 区块 "内存占用 Top 5"；`ProcessMetricRow<Trailing: View>` 泛型行三处复用（网络/CPU/内存）；旧 `struct ProcessRow` 已删除（grep=0） |
| 3 | 采样仅在 popover 可见时（off-main Task.detached），关闭即 cancel —— 关闭后无可测 CPU 开销 | ✓ VERIFIED（静态） | `PopoverManager`：`resourceSampleTask` 1.5s 循环，`toggle()` 打开启动；`popoverDidClose()` 调 `resourceSampleTask?.cancel()` + `= nil` + `resourceReader.clearSnapshot()`。采样在 `Task.detached(.utility)` 上。运行时"零开销"需人工测量 |
| 4 | task_for_pid-free（libproc only，无新权限），PID 消失/复用经 (pid, 启动时间) 键 + max(delta,0)，仅 Sendable 快照 | ✓ VERIFIED | 源码 `task_for_pid` 计数=0；`proc_listpids`+`proc_pid_rusage(RUSAGE_INFO_V4)`+`proc_name`；键 `ProcessKey(pid, ri_proc_start_abstime)`；`max(Δcpu,0)`；`ProcessResourceUsage: Sendable`；无 .entitlements 文件、Info.plist 无任务端口键 |

**Score:** 4/4 truths verified

---

## 高风险研究项核对

| 检查 | 结果 |
|------|------|
| CPU% 用 Mach-tick 差不转换（`mach_absolute_time` 在、`mach_timebase_info` 计数=0） | ✓ |
| 内存 = `ri_phys_footprint`（`ri_resident_size` 计数=0） | ✓ |
| 首帧 cpuPercent nil → "—" | ✓ |
| libproc-only，零 `task_for_pid`，无新 entitlement | ✓ |
| probe-and-skip（`proc_pid_rusage` 返回非 0 跳过，无强解包） | ✓ |
| ProcessResourceReader.swift 已登记 xcodeproj Sources（grep=2） | ✓ |
| ProcessMetricRow 泛化后网络列表保留 | ✓ |
| `xcodebuild ... build` → **BUILD SUCCEEDED** | ✓ |

---

## Findings（交由代码审查核查）

- **`ProcessResourceReader: @unchecked Sendable`（并发警示）**：执行阶段为通过 `Task.detached` 的 Sendable 边界检查给 reader 加了 `@unchecked Sendable`。其可变状态是 `prevSnapshot` map。访问模型：PopoverManager 单一 `resourceSampleTask` 串行调用 `sample()`（detached）。但 `popoverDidClose()` 在 MainActor 调 `clearSnapshot()`（`prevSnapshot.removeAll()`）——由于 `Task.cancel()` 是**协作式**，关闭瞬间可能有一次在途 `sample()` 仍在 detached 线程读写 `prevSnapshot`，与 `clearSnapshot()` 形成**潜在数据竞争**。功能不受影响（窄窗口、最坏是一次脏读/丢失快照），但属真实并发瑕疵。**建议代码审查评估**：让 `clearSnapshot` 也在采样 Task 内完成（cancel 后于 task 收尾清理），或将 reader 改为 actor / 加锁。不阻塞目标达成。

## 人工验证（3 项，见 frontmatter human_verification）

运行时行为（实时 CPU%/内存渲染、关闭后零后台开销测量、PID 动态鲁棒性）需真机确认。
