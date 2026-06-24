# Phase 10: Thermal Read-Only Monitoring - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-24
**Phase:** 10-Thermal Read-Only Monitoring
**Areas discussed:** 主温度口径, 二级温度范围, 降级展示, 散热区块入口, 验证机型范围

---

## 主温度口径

| Option | Description | Selected |
|--------|-------------|----------|
| A | 只认明确 CPU/SoC 传感器，找不到就显示 N/A | ✓ |
| B | 可信主温度，按 CPU/SoC/package/hottest 优先级取值，并在 UI 标出来源 | |
| C | Phase 10 只显示系统 thermal state，温度数值先不做 | |

**User's choice:** 1A
**Notes:** Locks a strict trust policy. Ambiguous temperature keys must not be relabeled as CPU/SoC.

---

## 二级温度范围

| Option | Description | Selected |
|--------|-------------|----------|
| A | CPU/SoC、GPU、电池、SSD 都做，全部严格可信才显示 | |
| B | CPU/SoC、GPU、电池先做，SSD 没有可靠公开路径就暂缓 | ✓ |
| C | Phase 10 只做 CPU/SoC 主温度和系统 thermal state | |

**User's choice:** 2B
**Notes:** GPU and battery are in scope as trustworthy secondary temperatures. SSD is deferred unless a reliable no-dependency path already exists.

---

## 降级展示

| Option | Description | Selected |
|--------|-------------|----------|
| A | 保留行，值显示 N/A 或 —，让用户知道这个指标尝试过但不可用 | ✓ |
| B | 直接隐藏不可用行，让面板更干净 | |
| C | 只在区块底部显示“部分传感器不可用” | |

**User's choice:** 3A
**Notes:** Prefer stable rows and explicit unavailable values over row churn.

---

## 散热区块入口

| Option | Description | Selected |
|--------|-------------|----------|
| A | 新增“散热”区块，默认开启，并加设置项控制显示/隐藏 | ✓ |
| B | 新增“散热”区块，Phase 10 暂不加设置项，有数据就显示 | |
| C | 不单独成区块，塞进现有系统/电池信息里 | |

**User's choice:** 4A
**Notes:** Follow the existing settings-toggle pattern used by battery and process sections.

---

## 验证机型范围

| Option | Description | Selected |
|--------|-------------|----------|
| A | 只针对当前 M3 Max MacBook Pro 验证，其他机型优雅降级 | ✓ |
| B | 同时做 Intel MacBook Pro 传感器键表 | |
| C | 代码结构预留多机型 catalog，但 Phase 10 只验证当前 Apple Silicon 机器 | |

**User's choice:** 5A
**Notes:** Current validation hardware discovered locally: MacBook Pro `Mac15,9`, Apple M3 Max.

## the agent's Discretion

- The agent may choose internal names and file split while preserving the read-only Reader -> MetricCollector -> DashboardState/UI pattern.
- The agent may choose exact settings grouping for the thermal toggle as long as it matches existing SettingsManager/UserDefaults conventions.

## Deferred Ideas

- SSD temperature support unless a reliable no-dependency path already exists.
- Intel/T2 and broader sensor catalog validation.
- Fan RPM, layout stress hardening, and fan control work remain in later v3.0 phases.
