# Phase 4: Combined Display + Formatting - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-14
**Phase:** 04-combined-display-formatting
**Areas discussed:** CPU/MEM/GPU color rules, separator and density, fixed width strategy

---

## CPU/MEM/GPU Color Rules

| Option | Description | Selected |
|--------|-------------|----------|
| 异常上色 | 普通状态保持系统文字色，只有 warning/critical 变黄/红。 | |
| 全状态上色 | normal/warning/critical 都用绿/黄/红。 | |
| 只给数值上色 | 标签保持默认色，只给百分比或 OK/WARN/CRIT 上色。 | ✓ |

**User's choice:** 只给数值/状态词上色。
**Notes:** 用户随后细化为 CPU/MEM/GPU 标签都保持默认色。CPU 数值正常默认色，`60...84` 黄，`>=85` 红。MEM `OK` 默认色，`WARN` 黄，`CRIT` 红。GPU normal/default 也应为默认色，不再使用绿色 normal。

### GPU Thresholds

| Option | Description | Selected |
|--------|-------------|----------|
| 沿用 60/85 | `<60%` 默认色，`60-84%` 黄，`>=85%` 红。 | ✓ |
| 更保守 70/90 | `<70%` 默认色，`70-89%` 黄，`>=90%` 红。 | |
| 更敏感 50/80 | `<50%` 默认色，`50-79%` 黄，`>=80%` 红。 | |

**User's choice:** 沿用 60/85。
**Notes:** GPU 标签 `G` 默认色；只给 GPU 数值上色。

---

## Separator and Density

| Option | Description | Selected |
|--------|-------------|----------|
| 保留 ` | ` | 最清楚，当前已验证，改动最小。 | ✓ |
| 改成 ` · ` | 更像 macOS 菜单栏紧凑文本。 | |
| 极简空格分组 | 最短但可读性稍弱。 | |

**User's choice:** 保留 ` | `。
**Notes:** 目标格式继续是 `C 12% | G 34% | M OK | ↓2.1M ↑512K`。

---

## Fixed Width Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| 保守固定 300 | 保留当前宽度，覆盖常见峰值，避免菜单栏抖动。 | ✓ |
| 加宽到 340 | 更不容易裁剪极端值，但占更多菜单栏空间。 | |
| 300 + 缩短极端网络单位 | 宽度不变，极端网络值优先缩短/裁剪网络段。 | |

**User's choice:** 保守固定 300。
**Notes:** Phase 4 不增加菜单栏占用宽度。

---

## Agent's Discretion

- Planner 可决定 helper 拆分方式，只要满足标签和值分离上色、固定宽度和单一可见 status item。

## Deferred Ideas

None.
