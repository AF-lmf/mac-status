# Phase 4: Combined Display + Formatting - Context

**Gathered:** 2026-05-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 4 将现有可见组合菜单栏项整理成最终 v1 展示格式：所有指标继续显示在一个紧凑、固定宽度、单行的 `NSStatusItem` 中，完成 CPU/GPU/MEM 的值级别配色、保留稳定分隔符和固定宽度策略，并保证任一指标不可用时仍以 `--` 降级而不影响其他指标。

本阶段不新增新的系统数据 reader、不新增设置窗口、不新增点击/菜单交互；只处理已接入指标的组合展示 polish。

</domain>

<decisions>
## Implementation Decisions

### 值级别颜色规则
- **D-01:** CPU 标签 `C` 保持默认文字色；CPU 数值 `<60%` 默认色，`60%...84%` 黄色，`>=85%` 红色。
- **D-02:** GPU 标签 `G` 保持默认文字色；GPU 数值 `<60%` 默认色，`60%...84%` 黄色，`>=85%` 红色。
- **D-03:** MEM 标签 `M` 保持默认文字色；`OK` 默认色，`WARN` 黄色，`CRIT` 红色。
- **D-04:** 只给数值或状态词上色，不给标签、分隔符、网络段整体上色。
- **D-05:** GPU 不再使用绿色 normal；normal/default 状态回到系统默认文字色，避免菜单栏常态出现过多颜色。

### 最终文本密度
- **D-06:** 最终分隔符保留 ` | `，不改为 ` · ` 或空格分组。
- **D-07:** 目标格式继续是 `C 12% | G 34% | M OK | ↓2.1M ↑512K`。
- **D-08:** 继续使用短标签 `C`、`G`、`M`，不恢复 `CPU`/`GPU`/`MEM` 长标签。

### 固定宽度与降级
- **D-09:** 可见组合 `NSStatusItem` 固定宽度保持当前 `300`，不在 Phase 4 加宽到 340。
- **D-10:** 继续保持单行、裁剪、不换行，防止菜单栏抖动。
- **D-11:** 不可用状态沿用现有降级文本：CPU `C --%`、GPU `G --`、MEM `M --`、网络 `↓-- ↑--`。

### Agent 的裁量空间
- Planner 可以选择内部 helper 的形状，例如按 segment 构建 attributed string、拆出 color threshold helper、或扩展现有 `baseAttributes()`/`gpuAttributes()`，但必须保持现有 `StatusBarManager` 为唯一可见展示入口。
- Planner 可以增加小范围 source-level 或 unit-style formatting checks，只要不引入外部依赖。

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project and Requirements
- `.planning/PROJECT.md` — 核心价值、菜单栏应用约束、Phase 3 后的 GPU 展示决策。
- `.planning/REQUIREMENTS.md` — DISP-01、DISP-02、DISP-03、DISP-04 的需求定义。
- `.planning/ROADMAP.md` — Phase 4 目标、成功标准和后续 Phase 5 边界。

### Prior Phase Decisions
- `.planning/phases/01-foundation-cpu-monitoring/01-CONTEXT.md` — monospaced digits、容差 redraw、NSStatusItem 生命周期。
- `.planning/phases/02-network-memory-monitoring/02-CONTEXT.md` — 网络/内存格式和 Reader -> UI 更新模式。
- `.planning/phases/03-gpu-monitoring/03-CONTEXT.md` — 短标签、`C | G | M | network` 顺序、GPU 段显示和 fallback。
- `.planning/phases/03-gpu-monitoring/03-UI-SPEC.md` — Phase 3 的字体、颜色、间距和 copywriting contract；Phase 4 需覆盖其中 GPU normal 绿色规则。
- `.planning/phases/03-gpu-monitoring/03-UAT.md` — 用户已确认菜单栏 GPU 段、fallback、GPU 压力颜色行为。

### Existing Code
- `MacStatus/MacStatus/UI/StatusBarManager.swift` — 唯一可见组合菜单栏项、segment-aware attributed title、颜色应用点。
- `MacStatus/MacStatus/Utils/ByteFormatting.swift` — 网络 compact bytes 和内存压力文本。
- `MacStatus/MacStatus/App/AppDelegate.swift` — CPU/GPU/MEM/network reader 到 `StatusBarManager` 的更新 wiring。

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `StatusBarManager.combinedAttributedString()` — 已按 CPU/GPU/MEM/network segment append attributed strings，可扩展为标签和值分别上色。
- `StatusBarManager.baseAttributes()` — 默认系统文字色和 monospaced digit 字体的单一来源。
- `StatusBarManager.gpuPressureColor()` — 当前 GPU pressure color helper，可改为 threshold/default-color 语义。
- `formatMemoryPressure(_:)` — 已返回 `M OK` / `M WARN` / `M CRIT` / `M --`，可被 UI 层拆分标签和值。

### Established Patterns
- 默认文字色使用 `NSColor.labelColor`，自动适配深色/浅色模式。
- 菜单栏文本使用 `NSFont.monospacedDigitSystemFont`，保持数字宽度稳定。
- `networkStatusItem` 是当前唯一可靠可见的组合项；不要新增独立 CPU/GPU/MEM status item。
- 指标 unavailable 时只更新自己的 latest text，不隐藏 segment。

### Integration Points
- `StatusBarManager.updateCPU(_:)` 需要保留数值以支持 CPU 阈值配色，或从 `latestCPUText` 安全解析当前值。
- `StatusBarManager.updateGPU(_:)` 可继续使用 `GPUStats.utilizationPercent` / `GPUPressureLevel`，但最终颜色语义要改为 default/yellow/red。
- `StatusBarManager.updateMemory(_:)` 需要保留 `MemoryPressureLevel` 或从 formatted text 派生 `OK/WARN/CRIT` 颜色。
- `combinedAttributedString()` 是 Phase 4 的主要改动点：标签默认色，值/状态词根据阈值上色，网络段保持默认色。

</code_context>

<specifics>
## Specific Ideas

- 用户明确选择只给值/状态词上色，标签不变色。
- 用户明确选择 CPU/GPU 阈值：`<60` 默认色、`60...84` 黄色、`>=85` 红色。
- 用户明确选择 MEM 颜色：`OK` 默认色、`WARN` 黄色、`CRIT` 红色。
- 用户明确选择保留 ` | ` 分隔符和固定宽度 `300`。

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 4-Combined Display + Formatting*
*Context gathered: 2026-05-14*
