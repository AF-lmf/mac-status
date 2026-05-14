---
status: complete
phase: 03-gpu-monitoring
source:
  - 03-01-SUMMARY.md
  - 03-02-SUMMARY.md
started: 2026-05-14T13:17:08Z
updated: 2026-05-14T13:22:10Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing complete]

## Tests

### 1. 组合菜单栏 GPU 段
expected: 启动 Debug 版 MacStatus。在 macOS 菜单栏里，可见的组合状态项应该包含 GPU 段，并且 GPU 紧跟在 CPU 后面，顺序和短标签为 `C ...% | G ...% | M ... | ↓... ↑...`。如果当前机器能读取 GPU 占用率，GPU 段应显示成类似 `G 34%`。
result: pass

### 2. GPU 不可用降级
expected: 如果当前机器读取不到 GPU 数据，或 GPU 数据暂时不可用，组合菜单栏项仍然应该保留 GPU 段，显示为 `G --`。同时，CPU、内存和网络段应该继续更新，不应该消失或导致应用崩溃。
result: pass

### 3. GPU 压力颜色
expected: 在 Apple Silicon 上，`G ...%` 这一段应根据 GPU 压力显示颜色。CPU、内存、网络和分隔符应保持普通菜单栏文字颜色，不应该一起变色。
result: pass

## Summary

total: 3
passed: 3
issues: 0
pending: 0
skipped: 0

## Gaps

[none yet]
