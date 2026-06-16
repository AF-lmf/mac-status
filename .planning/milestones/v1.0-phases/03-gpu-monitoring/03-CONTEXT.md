# Phase 3: GPU Monitoring - Context

**Gathered:** 2026-05-14
**Status:** Ready for planning

<domain>
## Phase Boundary

在 Phase 2 已有的可见组合菜单栏项基础上，新增 GPU 监控展示：用户能在菜单栏看到 GPU 使用率；Apple Silicon 上 GPU 压力通过 GPU 段颜色表达；GPU 数据不可用时必须优雅降级，不影响 CPU、网络、内存继续显示。Phase 3 聚焦把 GPU 指标接入现有显示链路，Phase 4 再处理全量组合展示 polish（固定宽度、整体配色、最终格式整理）。

</domain>

<decisions>
## Implementation Decisions

### 菜单栏 GPU 展示格式
- **D-01:** GPU 正常可用时显示为 `G 34%`，使用短标签 `G` 节省菜单栏宽度。
- **D-02:** GPU 数据不可用时显示为 `G --`，保持与现有不可用状态一致，不隐藏 GPU 段。
- **D-03:** 组合菜单栏文本使用短标签：`CPU` 改为 `C`，`MEM` 改为 `M`，GPU 使用 `G`。

### GPU 压力表达
- **D-04:** Apple Silicon 的 GPU 压力通过 `G 34%` 这一段文字颜色表达，绿色/黄色/红色表示压力状态。
- **D-05:** Phase 3 只锁定 GPU 段上色；CPU 和 MEM 也上色的想法延后到 Phase 4 的组合展示优化中处理。

### 组合项顺序
- **D-06:** GPU 段放在 CPU 后面，目标格式为 `C 12% | G 34% | M OK | ↓2.1M ↑512K`。

### Agent 的裁量空间
- GPU 数据源、IOKit/IOReport 细节、轮询间隔、压力阈值映射、Sandbox 兼容性验证方式均交给 research/planning 决定。
- 实现应优先沿用现有 `TimerReader<T>` + `StatusBarManager` 可见组合项模式，不因 GPU 不可用导致崩溃或隐藏其他指标。

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 项目定义
- `.planning/PROJECT.md` — 项目核心价值、平台约束、菜单栏应用定位。
- `.planning/REQUIREMENTS.md` — GPU-01、GPU-02、GPU-03 和 DISP-04 的需求定义。
- `.planning/ROADMAP.md` — Phase 3 成功标准和 Phase 4 展示边界。

### 技术研究
- `.planning/research/STACK.md` — IOKit `IOAccelerator` GPU utilization 方案和 graceful fallback 建议。
- `.planning/research/SUMMARY.md` — Phase 3 rationale、GPU risk notes、IOReport/pressure feasibility warning。
- `.planning/research/ARCHITECTURE.md` — Reader -> wiring -> presentation 管道、GPUReader 隔离原则。
- `.planning/research/PITFALLS.md` — Sandbox vs IOKit、sleep/wake stale data、IOKit 不应在主线程调用。
- `.planning/research/FEATURES.md` — GPU pressure 作为 Apple Silicon 差异化能力的背景。

### Prior Phase Context
- `.planning/phases/01-foundation-cpu-monitoring/01-CONTEXT.md` — ReaderProtocol、TimerReader、菜单栏文本和 redraw 策略。
- `.planning/phases/02-network-memory-monitoring/02-CONTEXT.md` — 组合状态项、网络/内存接入方式、可见 status item 决策。

### Existing Code
- `MacStatus/MacStatus/Readers/TimerReader.swift` — 新 GPUReader 应复用的后台轮询基类。
- `MacStatus/MacStatus/Readers/ReaderProtocol.swift` — 新 Reader 生命周期协议。
- `MacStatus/MacStatus/Readers/CPUReader.swift` — 百分比 reader 的参考实现。
- `MacStatus/MacStatus/Readers/MemoryReader.swift` — 压力状态 model 和 nil fallback 的参考实现。
- `MacStatus/MacStatus/App/AppDelegate.swift` — 新 GPUReader 的注册、start/stop、主线程 UI 更新 wiring。
- `MacStatus/MacStatus/UI/StatusBarManager.swift` — 组合菜单栏文本的唯一可见展示入口，需要新增 GPU text/state/color handling。

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TimerReader<T>` — 已封装后台 `DispatchSourceTimer` 轮询，GPUReader 可继承并通过 `onUpdate` 发送 `GPUStats?`。
- `StatusBarManager` — 当前可见 source of truth 是 `networkStatusItem` 组合项，已维护 `latestCPUText`、`latestMemoryText`、`latestNetworkText`。
- `MemoryPressureLevel` / `MemoryStats` 模式 — GPU pressure 可采用类似 enum + Sendable stats struct 的 typed model。

### Established Patterns
- Reader 在后台队列读取系统 API，通过 `DispatchQueue.main.async` 更新 UI。
- 指标不可用时发送 `nil`，UI 显示 `--`，不保留误导性旧值。
- 菜单栏文本使用 monospaced digit 字体和 fixed-width status item，避免数值变化造成抖动。

### Integration Points
- 新增 `MacStatus/MacStatus/Readers/GPUReader.swift`。
- 修改 `MacStatus/MacStatus/App/AppDelegate.swift`：持有 GPUReader，注册 `onUpdate`，启动/停止轮询。
- 修改 `MacStatus/MacStatus/UI/StatusBarManager.swift`：维护 `latestGPUText`、GPU 压力颜色，并按 `C | G | M | network` 顺序生成 attributed title。
- 需要更新 Xcode project 文件以纳入新增 Swift 源文件。

</code_context>

<specifics>
## Specific Ideas

- 用户明确偏好短标签和紧凑展示：`C 12% | G 34% | M OK | ↓2.1M ↑512K`。
- GPU 压力不额外占用文本宽度，优先通过 GPU 段颜色表达。

</specifics>

<deferred>
## Deferred Ideas

- CPU 和 MEM 也根据压力/阈值上色：属于 Phase 4 Combined Display + Formatting 的整体展示优化，不在 Phase 3 扩大范围。

</deferred>

---

*Phase: 3-GPU Monitoring*
*Context gathered: 2026-05-14*
