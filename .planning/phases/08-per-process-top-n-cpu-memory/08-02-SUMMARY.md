---
phase: 08-per-process-top-n-cpu-memory
plan: "02"
subsystem: UI — PopoverManager + DashboardView + ProcessListView
tags: [swift6, concurrency, libproc, ui, popover-gating, generics]
dependency_graph:
  requires:
    - 08-01 (ProcessResourceReader.sample() + clearSnapshot() + ProcessResourceUsage)
  provides:
    - PopoverManager.startResourceSampling() — 1.5s popover-gated sampling loop
    - ProcessMetricRow<Trailing: View> — generic process row component
    - DashboardView CPU占用Top5 + 内存占用Top5 sections
  affects:
    - MacStatus/MacStatus/UI/PopoverManager.swift
    - MacStatus/MacStatus/UI/Views/DashboardView.swift
    - MacStatus/MacStatus/UI/Views/ProcessListView.swift
    - MacStatus/MacStatus/Readers/ProcessResourceReader.swift (minor: @unchecked Sendable)
tech_stack:
  added: []
  patterns:
    - Task.detached(.utility) + MainActor.run result delivery (sampling loop)
    - @unchecked Sendable for exclusive-access final class
    - ProcessMetricRow<Trailing: View> @ViewBuilder generic trailing slot
    - ProcessResourceSectionView reusable loading/empty/data card
decisions:
  - "ProcessResourceReader marked @unchecked Sendable to satisfy Swift 6 Task.detached capture — exclusive-access invariant enforced by PopoverManager (single resourceSampleTask at a time)"
key_files:
  created: []
  modified:
    - MacStatus/MacStatus/UI/PopoverManager.swift
    - MacStatus/MacStatus/UI/Views/DashboardView.swift
    - MacStatus/MacStatus/UI/Views/ProcessListView.swift
    - MacStatus/MacStatus/Readers/ProcessResourceReader.swift
metrics:
  duration: "~5 minutes"
  completed: "2026-06-17"
  tasks_completed: 2
  files_created: 0
  files_modified: 4
requirements_covered: [PROC-01, PROC-02, PROC-03]
---

# Phase 08 Plan 02: UI 接入 ProcessResourceReader — CPU/内存 Top-5 Summary

**一句话概述：** PopoverManager 添加 1.5s 采样循环（PROC-03 关闭停止）；DashboardState 添加四个 @Published 字段；ProcessListView 抽出 ProcessMetricRow 泛型组件；DashboardView 插入 CPU/内存 Top-5 两个新区块，xcodebuild BUILD SUCCEEDED，Swift 6 无并发错误。

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | PopoverManager — resourceSampleTask 采样循环启停（PROC-03）| 31a4825 | PopoverManager.swift |
| 2+3 | DashboardState 新字段 + ProcessMetricRow + CPU/内存 Top-5 区块（PROC-01/02）| 0c25529 | DashboardView.swift, ProcessListView.swift, ProcessResourceReader.swift |

---

## PopoverManager 实际修改

### 新增属性（紧接 processRefreshTask 之后）
```swift
private var resourceSampleTask: Task<Void, Never>?
private let resourceReader = ProcessResourceReader()
```

### startResourceSampling() 实现（行 118–143）
- `resourceSampleTask?.cancel()` — 防重叠
- `Task { [weak self] in while !Task.isCancelled { ... } }`
- 内层 `Task.detached(priority: .utility) { [reader = self.resourceReader] in reader.sample() }`
- guard `!Task.isCancelled` 后 `await MainActor.run` 更新三个 DashboardState 字段
- `try? await Task.sleep(nanoseconds: 1_500_000_000)` — 1.5s 间隔

### toggle() 调用点（popover 打开后）
```swift
refreshProcessList()       // 现有，保留
startResourceSampling()    // 新增，紧随其后
```

### popoverDidClose() 扩展（PROC-03 门控）
```swift
stopOutsideClickMonitor()      // 现有
resourceSampleTask?.cancel()   // 新增
resourceSampleTask = nil       // 新增
resourceReader.clearSnapshot() // 新增 — 下次打开首帧重新"—"
dashboardState.resourceLoading = true  // 新增 — 重置 spinner
```

---

## DashboardState 新字段列表

```swift
@Published var topCPUProcesses: [ProcessResourceUsage] = []
@Published var topMemoryProcesses: [ProcessResourceUsage] = []
@Published var resourceLoading: Bool = true
@Published var resourceError: String? = nil
```

位置：`// Processes` 区块现有三字段之后。

---

## DashboardView 两个新区块结构摘要

```swift
// CPU Top 5 (PROC-01)
ProcessResourceSectionView(
    title: "CPU 占用 Top 5",
    items: state.topCPUProcesses,
    isLoading: state.resourceLoading,
    trailingText: { proc in
        proc.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—"
    }
)

// 内存 Top 5 (PROC-02)
ProcessResourceSectionView(
    title: "内存占用 Top 5",
    items: state.topMemoryProcesses,
    isLoading: state.resourceLoading,
    trailingText: { proc in
        ByteFormatting.format(Double(proc.memoryBytes))
    }
)
```

位置：`ProcessListView(...)` 之后，Footer HStack 之前。

### ProcessResourceSectionView 结构（新增于 DashboardView.swift）
- 状态分支：`isLoading` → spinner + "Sampling…"；`items.isEmpty` → "无数据"；否则 ForEach
- ForEach 使用 `ProcessMetricRow(processName:pid:) { Text(trailingText(proc))... }`
- `.padding(10)` + `RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04))` 背景

---

## ProcessMetricRow 最终签名

```swift
struct ProcessMetricRow<Trailing: View>: View {
    let processName: String
    let pid: Int32?
    @ViewBuilder let trailing: () -> Trailing
    // body: HStack { name | optional "(pid)" | Spacer | trailing() }
    // .padding(.vertical, 1)
}
```

网络区块（ProcessListView）用法：
```swift
ProcessMetricRow(processName: proc.processName, pid: proc.processIdentifier) {
    Label(ByteFormatting.format(proc.uploadBytesPerSec) + "/s", systemImage: "arrow.up")
        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.orange)
    Label(ByteFormatting.format(proc.downloadBytesPerSec) + "/s", systemImage: "arrow.down")
        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.blue)
}
```

---

## 行为验证预期

| 场景 | 预期 |
|------|------|
| 弹窗打开，首帧 | CPU Top 5 和内存 Top 5 均显示 spinner + "Sampling…" |
| 约 1.5s 后 | CPU Top 5：进程名 + "—"（首帧 cpuPercent nil）；内存 Top 5：进程名 + 大小（memoryBytes 立即可用）|
| 约 3s 后 | CPU Top 5：进程名 + 实时 CPU%（如 "12.3%"）|
| 弹窗关闭 | resourceSampleTask 已取消，prevSnapshot map 已清空，无后台 libproc 采样 |
| 再次打开弹窗 | 重新显示 spinner，CPU 首帧再次为"—" |

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ProcessResourceReader 缺少 @unchecked Sendable 声明**
- **发现于：** Task 2+3 完成后首次 xcodebuild（Swift 6 并发检查）
- **问题：** `Task.detached` 的 `[reader = self.resourceReader]` capture 将 `ProcessResourceReader`（final class，无 Sendable）发送到非隔离上下文，触发：`passing closure as a 'sending' parameter risks causing data races between main actor-isolated code and concurrent execution of the closure`
- **修复：** 在 ProcessResourceReader 声明添加 `: @unchecked Sendable`。合规性：类文档已说明"由单一 Task.detached 循环独占访问"，互斥访问由 PopoverManager 的 resourceSampleTask 单例保证，`@unchecked` 标注不引入实际数据竞争。
- **修改文件：** MacStatus/MacStatus/Readers/ProcessResourceReader.swift（第 32 行）
- **提交：** 0c25529（与 Task 2+3 合并提交）

与 PATTERNS.md 蓝图的其余部分完全一致：loop 结构、sleep 间隔、MainActor.run 结果回传、popoverDidClose 三步骤（cancel + nil + clearSnapshot）均按蓝图实现。

---

## 威胁模型合规性

| Threat ID | 处置 | 实现 |
|-----------|------|------|
| T-08-06 | mitigate | popoverDidClose: cancel + nil + clearSnapshot() + resourceLoading=true ✅ |
| T-08-07 | accept | nil → "—" 字符串，无注入面 ✅ |
| T-08-08 | accept | Plan 01 已处理 fallback；UI 层透明展示 ✅ |
| T-08-09 | accept | 两个 Task 独立；MainActor 串行更新 ✅ |

---

## 构建验证

```
** BUILD SUCCEEDED **
```

| 检查项 | 结果 |
|--------|------|
| resourceSampleTask 出现次数（PopoverManager）| ✅ 5（属性声明 + cancel×2 + nil + Task 创建）|
| startResourceSampling 出现次数 | ✅ 2（定义 + toggle 调用）|
| clearSnapshot 出现次数 | ✅ 1（popoverDidClose）|
| resourceLoading 出现次数（PopoverManager）| ✅ 2（= false + = true）|
| topCPUProcesses 出现次数（DashboardView）| ✅ 2（字段声明 + body 引用）|
| topMemoryProcesses 出现次数（DashboardView）| ✅ 2 |
| resourceLoading 出现次数（DashboardView）| ✅ 3（字段声明 + 两区块 isLoading 参数）|
| CPU 占用 Top 5 标题 | ✅ 1 |
| 内存占用 Top 5 标题 | ✅ 1 |
| ByteFormatting.format（DashboardView）| ✅ 3（内存区块 + 网络 updateNetwork×2）|
| ProcessMetricRow（ProcessListView）| ✅ 2（定义 + 网络 ForEach 使用）|
| ProcessRow（ProcessListView）| ✅ 0（已完全移除）|
| ProcessResourceReader.swift in Sources（pbxproj）| ✅ 2 |
| xcodebuild BUILD SUCCEEDED | ✅ 无 Swift 6 并发错误，无 error: |

---

## Known Stubs

无。所有字段均已接入真实数据源（ProcessResourceReader.sample()），无占位符文本或硬编码空数组流向 UI。

---

## Threat Flags

无新增安全相关表面。新增 UI 层仅读取 DashboardState @Published 字段，无直接 syscall、网络端点或权限提升。

---

## Self-Check: PASSED

| 检查项 | 结果 |
|--------|------|
| MacStatus/MacStatus/UI/PopoverManager.swift 修改存在 | ✅ |
| MacStatus/MacStatus/UI/Views/DashboardView.swift 修改存在 | ✅ |
| MacStatus/MacStatus/UI/Views/ProcessListView.swift 修改存在 | ✅ |
| MacStatus/MacStatus/Readers/ProcessResourceReader.swift @unchecked Sendable | ✅ |
| commit 31a4825 存在 | ✅ |
| commit 0c25529 存在 | ✅ |
| BUILD SUCCEEDED（xcodebuild exit 0）| ✅ |
