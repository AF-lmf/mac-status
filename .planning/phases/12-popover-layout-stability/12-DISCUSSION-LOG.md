# Phase 12: Popover Layout Stability - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-24T23:32:48+08:00
**Phase:** 12-Popover Layout Stability
**Areas discussed:** 数值列策略, 宽度上限, 长文本策略, 验证策略

---

## 数值列策略

| Option | Description | Selected |
|--------|-------------|----------|
| 全局稳定行组件 | 抽 `StableMetricRow` / fixed value-column style helper, then apply it to Phase 12 high-jitter rows. | ✓ |
| 局部修热点 | Only tune individual rows/cards without shared helper. | |
| 由 agent 决定 | Let the agent lock the recommended approach. | |

**User's choice:** `1`
**Notes:** Captured as a reusable stable row/value-column abstraction, but scoped to the known Phase 12 jitter hotspots rather than a broad UI rewrite.

---

## 宽度上限

| Option | Description | Selected |
|--------|-------------|----------|
| 优先保持 320pt | Keep existing width unless deterministic fixture proves it cannot fit. | |
| 固定扩展到 360-380pt | Use a single fixed expanded width and prevent refresh-time changes. | ✓ |
| 由 agent 决定 | Let the agent choose based on planning. | |

**User's choice:** “我觉得可以扩展到 360-380不用卡死320”
**Notes:** The popover may fixed-expand to `360-380pt`; the important constraint is that width is selected once and does not vary with data refresh.

---

## 长文本策略

| Option | Description | Selected |
|--------|-------------|----------|
| 文字侧让位，数值列稳定优先 | Truncate or wrap labels/process names/status copy before they compress numeric values. | ✓ |
| 完整显示文本 | Preserve long labels even if layout must expand or values move. | |
| 由 agent 决定 | Let the agent choose during planning. | |

**User's choice:** “可以”
**Notes:** Value stability wins over complete display of long labels, process names, PID text, and status/capability copy.

---

## 验证策略

| Option | Description | Selected |
|--------|-------------|----------|
| 确定性极端测试数据或预览夹具 | Cover worst-case values and long text with deterministic fixtures. | ✓ |
| 只做人工运行观察 | Rely on a normal app run and visual confirmation. | |
| 由 agent 决定 | Let the agent choose during planning. | |

**User's choice:** “确定”
**Notes:** Verification must cover large network values, `9999 RPM`, `100°C`, `N/A`, long process names, long sensor labels, and fixed-width/row-column non-jitter checks.

---

## the agent's Discretion

- Exact helper/component names and file splits.
- Exact fixed popover width inside `360-380pt`.
- Exact deterministic verification mechanism, as long as UAT-04 is satisfied.

## Deferred Ideas

None.
