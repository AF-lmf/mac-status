# MacStatus

## What This Is

一个轻量级 macOS 菜单栏应用，在状态栏实时展示系统资源使用情况，包括网络上下行速率、CPU 占用率、内存使用量和 GPU 占用率/压力。面向需要持续监控系统状态的 macOS 用户（开发者、运维、重度用户）。

## Core Value

用户无需打开任何窗口，在菜单栏一眼就能看到当前系统资源的实时使用情况。

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] 状态栏展示实时网络上下行速率
- [ ] 状态栏展示 CPU 占用率
- [ ] 状态栏展示内存占用情况
- [ ] 状态栏展示 GPU 占用/压力情况
- [ ] 应用开机自启动
- [ ] 数据实时刷新（秒级更新）

### Out of Scope

- 历史数据记录和图表 — v1 专注实时展示
- 远程监控 — v1 仅本地监控
- 多语言支持 — v1 中文即可
- CPU 温度/风扇转速 — v1 聚焦核心资源指标

## Context

- **平台**: macOS（原生 Swift/SwiftUI 或 AppKit 开发）
- **运行方式**: 菜单栏应用（Menu Bar App），无 Dock 图标，纯状态栏运行
- **目标用户**: 需要在状态栏快速查看系统状态的 macOS 用户
- **同类参考**: iStat Menus、Stats（开源）、MenuMeters

## Constraints

- **平台**: macOS 14+（Sonoma 及以上）
- **语言**: Swift
- **框架**: SwiftUI + AppKit（混合，菜单栏应用需要 AppKit 的 NSStatusBar）
- **性能**: 状态栏更新不能导致明显 CPU 消耗（采样间隔合理，避免高频轮询）
- **包体**: 尽量小，无外部依赖或最小依赖

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Swift + AppKit/SwiftUI | macOS 原生开发最优选，系统 API 直接获取资源数据 | — Pending |
| 菜单栏应用（无 Dock 图标） | 用户明确要状态栏展示，不需要独立窗口 | — Pending |

---

*Last updated: 2026-05-14 after initialization*

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state
