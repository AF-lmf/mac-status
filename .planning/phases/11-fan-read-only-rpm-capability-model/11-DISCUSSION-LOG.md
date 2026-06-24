# Phase 11: Fan Read-Only RPM & Capability Model - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-24
**Phase:** 11-Fan Read-Only RPM & Capability Model
**Areas discussed:** 风扇展示位置, 风扇行内容, 不可用状态, 控制能力文案, 硬件验证边界

---

## 风扇展示位置

| Option | Description | Selected |
|--------|-------------|----------|
| A | 合并进现有 `散热` / thermal 信息流 | ✓ |
| B | 新建独立 `风扇` 区块 | |
| C | 由 agent 规划时决定 | |

**User's choice:** 1A
**Notes:** Fan information should feel like part of the cooling readout, not a new top-level dashboard surface.

### Combined Section Title

| Option | Description | Selected |
|--------|-------------|----------|
| A | `散热` | |
| B | `温度与风扇` | ✓ |
| C | `散热状态` | |

**User's choice:** 2B
**Notes:** The title should make both temperature and fan scope explicit.

### Settings Toggle

| Option | Description | Selected |
|--------|-------------|----------|
| A | Separate temperature and fan toggles | ✓ |
| B | Reuse one thermal/cooling toggle for both | |
| C | Agent decides | |

**User's choice:** 3A
**Notes:** Add a separate `风扇区块` toggle while preserving independent temperature visibility.

### Local Layout Adjustment

| Option | Description | Selected |
|--------|-------------|----------|
| A | Allow small local adjustments within current width | ✓ |
| B | Minimize all layout changes | |
| C | Agent decides | |

**User's choice:** 4A
**Notes:** Keep the 320pt width constraint. Do not attempt full Phase 12 layout hardening inside Phase 11.

---

## 风扇行内容

| Option | Description | Selected |
|--------|-------------|----------|
| A | `风扇 1 2400 RPM` | |
| B | `风扇 1 2400 RPM · Auto/未知` | |
| C | `左风扇 2400 RPM` / `右风扇 2400 RPM` | ✓ |
| D | Agent decides | |

**User's choice:** 1C
**Notes:** Prefer left/right names when reliable because they scan better on dual-fan MacBook Pro hardware.

### Bounds and Target Display

| Option | Description | Selected |
|--------|-------------|----------|
| A | Always reserve a range/target subrow | |
| B | Show min/max/target only when readable | ✓ |
| C | Build capability model but do not display bounds in Phase 11 | |
| D | Agent decides | |

**User's choice:** 2B
**Notes:** Missing optional fields should not create blank or noisy rows.

### Fan Count

| Option | Description | Selected |
|--------|-------------|----------|
| A | Show count in section header | |
| B | Show count as a subsection row | |
| C | No separate count | ✓ |
| D | Agent decides | |

**User's choice:** 3C
**Notes:** The number of fan rows is enough. Avoid extra chrome.

### Multi-Fan Naming Fallback

| Option | Description | Selected |
|--------|-------------|----------|
| A | Prefer `F{i}ID`, fallback to numbered fans | |
| B | Prefer left/right names, fallback to numbered fans | ✓ |
| C | Always use numbered fans | |
| D | Agent decides | |

**User's choice:** 4B
**Notes:** Do not overtrust raw identifiers; labels should remain honest and stable.

---

## 不可用状态

| Option | Description | Selected |
|--------|-------------|----------|
| A | Stable `风扇 N/A` / `风扇不可读取` row | ✓ |
| B | `无风扇` only when fan count is confirmed zero | |
| C | Hide fan rows | |
| D | Agent decides | |

**User's choice:** 1A
**Notes:** Supported MacBook Pro hardware should keep a stable fan surface even when RPM is unreadable.

### Fanless / Non-MacBook-Pro

| Option | Description | Selected |
|--------|-------------|----------|
| A | Explicit `无风扇` / `此机型无风扇` copy | |
| B | Hide fan information by default | ✓ |
| C | Document only in probe/debug artifacts | |
| D | Agent decides | |

**User's choice:** 2B
**Notes:** Avoid distracting normal users with unsupported-hardware copy.

### Missing Per-Fan Fields

| Option | Description | Selected |
|--------|-------------|----------|
| A | Keep row and degrade fields independently | ✓ |
| B | Hide row when RPM is missing | |
| C | Mark whole fan subsection unreadable | |
| D | Agent decides | |

**User's choice:** 3A
**Notes:** RPM, bounds, and target readability should fail independently.

### Read Failure Alerting

| Option | Description | Selected |
|--------|-------------|----------|
| A | Quiet inline degradation | ✓ |
| B | First-failure status text | |
| C | Visible warning | |
| D | Agent decides | |

**User's choice:** 4A
**Notes:** Fan reads are not important enough to interrupt users with alerts.

---

## 控制能力文案

| Option | Description | Selected |
|--------|-------------|----------|
| A | Show short UI statuses such as `只读` / `边界可读` / `控制待验证` | |
| B | Record full state internally; UI mainly shows RPM and readable bounds | ✓ |
| C | Show only when control is unavailable | |
| D | Agent decides | |

**User's choice:** 1B
**Notes:** Capability distinctions matter for code and planning, but should not become a noisy constant label.

### Bounds Readable but Control Not Implemented

| Option | Description | Selected |
|--------|-------------|----------|
| A | `边界可读，控制未启用` | ✓ |
| B | `可读取边界` | |
| C | `控制待验证` | |
| D | Agent decides | |

**User's choice:** 2A
**Notes:** This wording avoids implying that control is currently available.

### `控制可用`

| Option | Description | Selected |
|--------|-------------|----------|
| A | Do not allow it anywhere in Phase 11 | |
| B | Allow internally, not in UI | ✓ |
| C | Allow in UI without a button | |
| D | Agent decides | |

**User's choice:** 3B
**Notes:** Future capability states may exist internally, but Phase 11 UI must not promise control.

### Future Control Affordance

| Option | Description | Selected |
|--------|-------------|----------|
| A | No control entry point | ✓ |
| B | Disabled control text/button | |
| C | Settings placeholder | |
| D | Agent decides | |

**User's choice:** 4A
**Notes:** No disabled controls, no future-control teaser, no Settings placeholder.

---

## 硬件验证边界

| Option | Description | Selected |
|--------|-------------|----------|
| A | Use current `Mac15,9` as first-class validation hardware | ✓ |
| B | Generic implementation only, no current-machine probe required | |
| C | Cover more models now | |
| D | Agent decides | |

**User's choice:** 1A
**Notes:** Current validation target is MacBook Pro `Mac15,9` with Apple M3 Max.

### Optional Fan Keys Unreadable

| Option | Description | Selected |
|--------|-------------|----------|
| A | Complete with recorded `N/A` / `不可读取` evidence | ✓ |
| B | Block until RPM key is found | |
| C | Complete but mark FAN-01 partial | |
| D | Agent decides | |

**User's choice:** 2A
**Notes:** Optional missing keys are acceptable when behavior and evidence are recorded.

### Probe Evidence

| Option | Description | Selected |
|--------|-------------|----------|
| A | Record model, fan key reads, decoded values, and no-write checks | |
| B | Only final UI screenshot/readout | |
| C | Only build pass and source grep | |
| D | Agent decides exact evidence | ✓ |

**User's choice:** 3D
**Notes:** Planner should record enough read-only evidence to prove behavior without overfitting the probe artifact.

### Fan Key Exploration Scope

| Option | Description | Selected |
|--------|-------------|----------|
| A | Allow read-only SMC diagnostic exploration only | ✓ |
| B | Only read fixed known keys | |
| C | Add internal raw key browser | |
| D | Agent decides | |

**User's choice:** 4A
**Notes:** Broader fan key exploration is allowed only as read-only diagnostics.

## the agent's Discretion

- The agent may decide exact internal type names and layout shape.
- The agent may decide exact probe artifact format as long as it proves read-only behavior and captures `N/A` / unavailable states.
- The agent should preserve the Phase 10 read-only snapshot pattern and avoid Phase 13 control scope.

## Deferred Ideas

- SMC writes, manual fan controls, helper/XPC, restore-auto lifecycle logic, and any user-facing control affordance.
- Full popover layout hardening for extreme network/temperature/RPM/process values.
- Status-bar fan or temperature segments.
- Raw SMC browser, history charts, alerts, fan curves, and broad multi-model hardware catalogs.
