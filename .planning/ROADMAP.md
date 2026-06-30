# Roadmap: MacStatus

## Prior Milestones

- **v1.0 MVP** - Phases 1-5 (shipped 2026-06-10)
- **v2.0 洞察与可定制** - Phases 6-9 (shipped 2026-06-23)

## Prior Milestone Summary

v1.0/v2.0 已交付单一菜单栏状态项、CPU/GPU/内存/网络实时监控、弹窗电池/功率/Top-N 进程、设置窗口与实时偏好重应用。历史阶段详情保留在 `.planning/milestones/`；本路线图只覆盖 v3.0 当前里程碑，不把 v3.0 需求映射回已归档的 v1/v2 阶段。

## v3.0 风扇与热状态

## Overview

v3.0 在保持轻量菜单栏体验的前提下，加入关键温度与风扇 RPM 只读监控并稳定 popover 布局。原计划中的风扇硬件控制写入路径（Phase 13）及其生命周期/真机 UAT（Phase 14）已于 2026-06-30 取消，详见下方 Descoped 小节。当前里程碑保持开放。

## Phases

- [x] **Phase 10: Thermal Read-Only Monitoring** - 弹窗显示可信 CPU/SoC 主温度、系统 thermal state 与可读次要温度，缺失时稳定降级。 (completed 2026-06-24)
- [x] **Phase 11: Fan Read-Only RPM & Capability Model** - 弹窗显示风扇数量、每个风扇 RPM/边界/能力状态，并区分可读、可读边界和可安全控制。 (completed 2026-06-24)
- [x] **Phase 12: Popover Layout Stability** - 在新增散热信息和极端网络/温度/RPM/进程值下，popover 宽度、行列和数值对齐保持稳定。 (completed 2026-06-24)
- ~~**Phase 13: Safe Fan Control Gate & Write Path**~~ - 取消（2026-06-30，风扇硬件改动功能撤销）。
- ~~**Phase 14: Lifecycle Recovery & Hardware UAT**~~ - 取消（2026-06-30，随 Phase 13 一并撤销）。

## Phase Details

### Phase 10: Thermal Read-Only Monitoring

**Goal**: 用户打开弹窗即可看到可信的 CPU/SoC 热状态；传感器缺失或不可信时显示稳定的 `N/A`，不会崩溃或弹错。
**Depends on**: Phase 9 (v2.0 shipped foundation)
**Requirements**: THERM-01, THERM-02, THERM-03, THERM-04
**Success Criteria** (what must be TRUE):

  1. 用户能在弹窗中看到一个主 CPU/SoC 温度值；该值来自可信传感器，无法确认时显示 `N/A`。
  2. 用户能看到系统 thermal state（正常、偏热、严重、临界等语义状态），即使精确温度不可读也能理解当前热压力。
  3. GPU、电池、SSD 等次要温度只在可读且可信时显示；不可读时不会出现假值、旧值或误导标签。
  4. 传感器缺失、机型不支持或单次读取失败时，温度区块保持可用并以 `N/A`/隐藏次要行降级，不刷错误弹窗。

**Plans**: 3 plans
**UI hint**: yes
Plans:

- [x] 10-01-PLAN.md — 建立只读 SMC 解码、ThermalReader 快照和 Mac15,9 严格信任边界
- [x] 10-02-PLAN.md — 接入 MetricCollector/DashboardState 并渲染稳定 `散热` 弹窗区块
- [x] 10-03-PLAN.md — 添加 `散热区块` 设置开关并记录硬件探针与最终防越界验证

### Phase 11: Fan Read-Only RPM & Capability Model

**Goal**: 用户能在支持风扇的 MacBook Pro 上看到风扇 RPM 和能力状态；不支持或 fanless 机器不会出现误导性的控制入口。
**Depends on**: Phase 10
**Requirements**: FAN-01, FAN-02, FAN-03, FAN-04
**Success Criteria** (what must be TRUE):

  1. 支持风扇的 MacBook Pro 弹窗中显示风扇数量，并为每个风扇显示当前 RPM。
  2. 每个风扇的 min/max/target 或控制能力状态在可读时可见，不可读字段以稳定 `N/A` 呈现。
  3. fanless、非 MacBook Pro 或不支持读取的机型显示普通降级状态，不显示手动风扇控制入口。
  4. UI 能区分"可读取 RPM""可读取硬件边界""可安全控制"，不会把可读 RPM 误判为可控。

**Plans**: 3 plans
**UI hint**: yes
Plans:
**Wave 1**

- [x] 11-01-PLAN.md — 建立只读风扇解码、快照和能力模型

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 11-02-PLAN.md — 接入采集、设置并渲染 `温度与风扇` 弹窗行

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 11-03-PLAN.md — 记录 Mac15,9 读证据并执行只读/无越界收口门

### Phase 12: Popover Layout Stability

**Goal**: 用户打开 popover 时，网络、温度、RPM、功率和进程文本变化不会造成横向或纵向抖动。
**Depends on**: Phase 10, Phase 11
**Requirements**: LAYOUT-01, LAYOUT-02, LAYOUT-03, LAYOUT-04, UAT-04
**Success Criteria** (what must be TRUE):

  1. 网络上下行、温度、RPM、功率等数值从短值变成长值时，popover 不发生横向或纵向跳动。
  2. 关键数值列固定宽度、右对齐并使用 monospaced digits，能稳定容纳 `9999 RPM`、`100°C`、`N/A` 和大网络值。
  3. 长进程名、长传感器标签和长能力状态文本被稳定裁切或换行，不挤压相邻数值列。
  4. popover 宽度保持一个明确上限：优先约 320pt，若新增散热区块必须扩展，则固定在 360-380pt 范围内且不随刷新变化。
  5. 极端数值和长文本通过确定性快照或测试数据验证，不只依赖肉眼观察。

**Plans**: 3 plans
**UI hint**: yes
Plans:
**Wave 1**

- [x] 12-01-PLAN.md — 建立稳定值列 helper，并把 Dashboard popover 固定到 372pt

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 12-02-PLAN.md — 稳定 Top-N 进程行，并创建短值/极端值 DEBUG fixtures

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 12-03-PLAN.md — 添加 XCTest 布局稳定验证并记录确定性证据

## Descoped (v3.0)

以下阶段于 2026-06-30 取消（用户决定撤销风扇硬件改动功能）。两者均未执行、无代码落地；规划产物保留在 `.planning/cancelled/13-safe-fan-control-gate-write-path/` 以备将来恢复。

- **Phase 13: Safe Fan Control Gate & Write Path** — 手动风扇控制的硬件写入路径（opt-in 门、SMC 写入、helper/XPC、读回验证、失败回退）。撤销需求：FCTRL-01, FCTRL-02, FCTRL-03, FCTRL-04, FCTRL-06。
- **Phase 14: Lifecycle Recovery & Hardware UAT** — 仅服务于风扇控制的生命周期恢复与真机 UAT，随 Phase 13 一并取消。撤销需求：FCTRL-05, UAT-01, UAT-02, UAT-03。

只读温度/风扇监控（Phase 10–12）不受影响，照常工作。撤销的需求未被废弃，可在后续里程碑重新提出。

## Coverage

| Requirement | Phase |
|-------------|-------|
| THERM-01 | Phase 10 |
| THERM-02 | Phase 10 |
| THERM-03 | Phase 10 |
| THERM-04 | Phase 10 |
| FAN-01 | Phase 11 |
| FAN-02 | Phase 11 |
| FAN-03 | Phase 11 |
| FAN-04 | Phase 11 |
| LAYOUT-01 | Phase 12 |
| LAYOUT-02 | Phase 12 |
| LAYOUT-03 | Phase 12 |
| LAYOUT-04 | Phase 12 |
| FCTRL-01 | ~~Phase 13~~ Descoped |
| FCTRL-02 | ~~Phase 13~~ Descoped |
| FCTRL-03 | ~~Phase 13~~ Descoped |
| FCTRL-04 | ~~Phase 13~~ Descoped |
| FCTRL-05 | ~~Phase 14~~ Descoped |
| FCTRL-06 | ~~Phase 13~~ Descoped |
| UAT-01 | ~~Phase 14~~ Descoped |
| UAT-02 | ~~Phase 14~~ Descoped |
| UAT-03 | ~~Phase 14~~ Descoped |
| UAT-04 | Phase 12 |

**Mapped:** 13/22 v3.0 requirements (Phase 10–12).
**Descoped:** 9 (FCTRL-01..06, UAT-01/02/03 — fan control write path cancelled 2026-06-30).
**Unmapped:** 0.

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 10. Thermal Read-Only Monitoring | v3.0 | 3/3 | Complete   | 2026-06-24 |
| 11. Fan Read-Only RPM & Capability Model | v3.0 | 3/3 | Complete    | 2026-06-24 |
| 12. Popover Layout Stability | v3.0 | 3/3 | Complete    | 2026-06-24 |
| 13. Safe Fan Control Gate & Write Path | v3.0 | - | Cancelled 2026-06-30 | - |
| 14. Lifecycle Recovery & Hardware UAT | v3.0 | - | Cancelled 2026-06-30 | - |
