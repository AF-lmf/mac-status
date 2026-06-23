---
phase: 08-per-process-top-n-cpu-memory
plan: "01"
subsystem: ProcessResourceReader (libproc sampler)
tags: [libproc, swift6, concurrency, cpu-sampling, memory-sampling, pbxproj]
dependency_graph:
  requires: []
  provides:
    - ProcessResourceUsage (Sendable struct)
    - ProcessResourceReader (final class, sample() + clearSnapshot())
  affects:
    - MacStatus/MacStatus/Readers/ProcessResourceReader.swift
    - MacStatus/MacStatus.xcodeproj/project.pbxproj
tech_stack:
  added: []
  patterns:
    - proc_listpids two-call buffer dance (+10% headroom)
    - proc_pid_rusage(RUSAGE_INFO_V4) with withMemoryRebound to UnsafeMutableRawPointer?
    - (pid, ri_proc_start_abstime) composite key for PID-reuse safety
    - mach_absolute_time() wall clock — same Mach tick unit as ri_user/system_time, units cancel
    - proc_name(pid, buf, 256) for process names with PID fallback
key_files:
  created:
    - MacStatus/MacStatus/Readers/ProcessResourceReader.swift
  modified:
    - MacStatus/MacStatus.xcodeproj/project.pbxproj
decisions:
  - "proc_pid_rusage Swift binding requires withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self) — UnsafeMutableRawPointer($0) alone does not satisfy rusage_info_t * (void **) parameter type"
  - "UUID A80000000000000000000001/002 used for ProcessResourceReader pbxproj entries"
metrics:
  duration: "~3 minutes"
  completed: "2026-06-17"
  tasks_completed: 2
  files_created: 1
  files_modified: 1
requirements_covered: [PROC-01, PROC-02, PROC-03]
---

# Phase 08 Plan 01: ProcessResourceReader (libproc 采样引擎) Summary

**一句话概述：** 新建 ProcessResourceReader.swift（libproc CPU/内存 Top-N 采样引擎），使用 proc_pid_rusage(RUSAGE_INFO_V4) + mach_absolute_time() delta 算法 + (pid, ri_proc_start_abstime) PID 复用安全键，并完成 project.pbxproj 四条目注册，xcodebuild BUILD SUCCEEDED。

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | 新建 ProcessResourceReader.swift（libproc 采样引擎）| f5654df, 2269e70 | Readers/ProcessResourceReader.swift |
| 2 | 在 project.pbxproj 注册 ProcessResourceReader.swift（4 条目）| 2269e70 | MacStatus.xcodeproj/project.pbxproj |

---

## 实际使用的 UUID

| 条目 | UUID | 类型 |
|------|------|------|
| PBXFileReference | A80000000000000000000001 | ProcessResourceReader.swift |
| PBXBuildFile | A80000000000000000000002 | ProcessResourceReader.swift in Sources |

---

## 导出的符号列表

### ProcessResourceUsage (struct)
```swift
struct ProcessResourceUsage: Sendable, Equatable {
    let processName: String      // proc_name() 获取；失败 fallback 为 "PID \(pid)"
    let pid: Int32               // 进程 ID
    let cpuPercent: Double?      // nil = 首帧（无前值），UI 显示"—"
    let memoryBytes: UInt64      // ri_phys_footprint（应用独占物理内存）
}
```

### ProcessResourceReader (final class)
```swift
final class ProcessResourceReader {
    func clearSnapshot()                                  // popoverDidClose 时调用，清空快照 map
    func sample() -> ([ProcessResourceUsage], [ProcessResourceUsage])  // (cpuTop5, memTop5)
}
```

---

## 构建验证

```
** BUILD SUCCEEDED **
```

验收检查结果：

| 检查项 | 结果 |
|--------|------|
| 文件存在 | ✅ MacStatus/MacStatus/Readers/ProcessResourceReader.swift |
| ri_phys_footprint 出现次数 | ✅ 2（字段读取 + 赋值注释） |
| ri_proc_start_abstime 出现次数 | ✅ 3（struct 注释 + 字段提取 + key 构造） |
| mach_absolute_time 出现次数 | ✅ 3（文档注释 + wallNow + SnapshotEntry 注释） |
| task_for_pid 出现次数 | ✅ 0（禁用 API 缺席） |
| mach_timebase_info 出现次数 | ✅ 0（无不必要单位转换） |
| pbxproj "in Sources" 匹配数 | ✅ 2（PBXBuildFile 行 + Sources 阶段引用） |
| pbxproj 总匹配数 | ✅ 4（PBXBuildFile + PBXFileReference + Readers 组 + Sources 阶段） |
| xcodebuild BUILD SUCCEEDED | ✅ 无 Swift 6 并发错误，无 error: |

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] proc_pid_rusage Swift 调用类型修正**

- **发现于：** Task 2（注册后首次 xcodebuild 时暴露编译错误）
- **问题：** RESEARCH.md 建议写法 `UnsafeMutableRawPointer($0)` 实际触发类型错误：
  `cannot convert value of type 'UnsafeMutableRawPointer?' to expected argument type 'UnsafeMutablePointer<rusage_info_t?>'`
  原因：`proc_pid_rusage` 第三参数在 Swift 中的类型绑定为 `UnsafeMutablePointer<rusage_info_t?>?`（即 `void **`），而非 `UnsafeMutableRawPointer`（`void *`）。
- **修复：** 改用 `withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1)` 模式，通过 rebound 将 `UnsafeMutablePointer<rusage_info_v4>` 视图转换为 `UnsafeMutablePointer<rusage_info_t?>`，满足参数类型约束。
- **修改文件：** MacStatus/MacStatus/Readers/ProcessResourceReader.swift（第 102-108 行）
- **提交：** 2269e70（与 Task 2 pbxproj 注册合并提交）

与 RESEARCH.md 蓝图的其余部分完全一致：CPU 公式、字段选择、排序逻辑、clearSnapshot() 签名均按蓝图实现。

---

## 威胁模型合规性

| Threat ID | 处置 | 实现 |
|-----------|------|------|
| T-08-01 | mitigate | (pid, ri_proc_start_abstime) 复合键 + max(Δcpu,0) ✅ |
| T-08-02 | mitigate | max(Δcpu,0) + min(result, 999.9) clamp ✅ |
| T-08-03 | accept | guard ret == 0（probe-and-skip，不暴露错误细节）✅ |
| T-08-04 | mitigate | +10% headroom 分配，第二次返回值计算 pidCount ✅ |
| T-08-05 | mitigate | 无 task_for_pid，libproc only ✅ |

---

## Known Stubs

无。ProcessResourceReader.swift 是纯数据层，无 UI stub。Plan 02 将在此基础上直接引用 ProcessResourceUsage 和 ProcessResourceReader 类型，无需做任何 C-interop 工作。

---

## Threat Flags

无新增安全相关表面（libproc syscall 由内核已有访问控制管理，无新端点/新权限）。

---

## Self-Check: PASSED

| 检查项 | 结果 |
|--------|------|
| MacStatus/MacStatus/Readers/ProcessResourceReader.swift 存在 | ✅ |
| MacStatus/MacStatus.xcodeproj/project.pbxproj 已修改（4条目）| ✅ |
| commit f5654df 存在 | ✅ |
| commit 2269e70 存在 | ✅ |
| BUILD SUCCEEDED（xcodebuild exit 0）| ✅ |
