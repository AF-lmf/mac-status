# Phase 1: Foundation + CPU Monitoring - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-14
**Phase:** 01-foundation-cpu-monitoring
**Areas discussed:** Xcode 项目结构, CPU 显示格式, 刷新间隔, 菜单栏文本更新策略

---

## Xcode 项目结构

| Option | Description | Selected |
|--------|-------------|----------|
| Single target + folder groups | 单一 macOS App target，源码按 App/Readers/UI/Utils 分组文件夹 | ✓ |
| SPM 多模块 | Swift Package Manager 多模块 target 架构 | |

**Choice:** [auto] Single target + folder groups — recommended default for v1 simplicity
**Notes:** Research confirms single target is sufficient for v1 (4 readers, 1 display); SPM multi-module complexity not warranted yet

---

## CPU 显示格式

| Option | Description | Selected |
|--------|-------------|----------|
| "CPU 45%" | 带简短标签的百分比格式 | ✓ |
| "45%" | 仅百分比数字 | |

**Choice:** [auto] "CPU 45%" — provides context without being verbose
**Notes:** Label needed when combined display format is not yet implemented (Phase 4)

---

## 刷新间隔

| Option | Description | Selected |
|--------|-------------|----------|
| 2 秒 | 在响应性和 CPU 开销之间平衡 | ✓ |
| 1 秒 | 最灵敏，但 CPU 开销更高 | |
| 3 秒 | 最低 CPU 开销，但感知延迟明显 | |

**Choice:** [auto] 2 秒 — recommended balance per research (Stats uses 1s but 2s is safer for battery-aware v1)
**Notes:** Refresh interval stored in UserDefaults via SettingsManager for future customization

---

## 菜单栏文本更新策略

| Option | Description | Selected |
|--------|-------------|----------|
| 容差比较（0.5%） | 值变化超过阈值才重绘 | ✓ |
| 仅在值变化时更新 | 严格比较新旧值 | |
| 每秒全量重绘 | 每次 tick 都重绘 | |

**Choice:** [auto] 容差比较 — prevents unnecessary NSStatusItem redraws while allowing small fluctuations to be visible
**Notes:** Combined with `.monospacedDigit()` font for stable width

---

## Auto-resolved Decisions

All decisions auto-resolved in --auto mode. The agent selected the recommended (first) option for each gray area:

- [auto] [Xcode structure] — Q: "How should the Xcode project be structured?" → Selected: "Single target + folder groups" (recommended default)
- [auto] [CPU format] — Q: "What format for CPU display text?" → Selected: "CPU 45%" (recommended default)
- [auto] [Refresh interval] — Q: "How often should CPU data refresh?" → Selected: "2 seconds" (recommended default)
- [auto] [Text update] — Q: "When should menu bar text be redrawn?" → Selected: "Tolerance-based (0.5% threshold)" (recommended default)

## Deferred Ideas

None — discussion stayed within phase scope.
