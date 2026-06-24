# Roadmap: MacStatus

## Prior Milestones

- **v1.0 MVP** - Phases 1-5 (shipped 2026-06-10)
- **v2.0 洞察与可定制** - Phases 6-9 (shipped 2026-06-23)

## Prior Milestone Summary

v1.0/v2.0 已交付单一菜单栏状态项、CPU/GPU/内存/网络实时监控、弹窗电池/功率/Top-N 进程、设置窗口与实时偏好重应用。历史阶段详情保留在 `.planning/milestones/`；本路线图只覆盖 v3.0 当前里程碑，不把 v3.0 需求映射回已归档的 v1/v2 阶段。

## v3.0 风扇与热状态

## Overview

v3.0 在保持轻量菜单栏体验的前提下，加入关键温度、风扇 RPM 与安全风扇控制。交付顺序按风险递增：先完成只读温度与风扇能力，再稳定 popover 布局，最后才进入带决策门、读回验证、失败回退和真实硬件 UAT 的风扇控制。

## Phases

- [ ] **Phase 10: Thermal Read-Only Monitoring** - 弹窗显示可信 CPU/SoC 主温度、系统 thermal state 与可读次要温度，缺失时稳定降级。
- [ ] **Phase 11: Fan Read-Only RPM & Capability Model** - 弹窗显示风扇数量、每个风扇 RPM/边界/能力状态，并区分可读、可读边界和可安全控制。
- [ ] **Phase 12: Popover Layout Stability** - 在新增散热信息和极端网络/温度/RPM/进程值下，popover 宽度、行列和数值对齐保持稳定。
- [ ] **Phase 13: Safe Fan Control Gate & Write Path** - 只有在能力验证通过时，用户才能显式 opt-in 使用受限、可读回验证、可恢复自动的手动风扇控制。
- [ ] **Phase 14: Lifecycle Recovery & Hardware UAT** - quit/sleep/wake/failure 生命周期不遗留手动风扇状态，并通过真实 MacBook Pro 与降级场景 UAT 后放行。

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
- [ ] 10-03-PLAN.md — 添加 `散热区块` 设置开关并记录硬件探针与最终防越界验证

### Phase 11: Fan Read-Only RPM & Capability Model
**Goal**: 用户能在支持风扇的 MacBook Pro 上看到风扇 RPM 和能力状态；不支持或 fanless 机器不会出现误导性的控制入口。
**Depends on**: Phase 10
**Requirements**: FAN-01, FAN-02, FAN-03, FAN-04
**Success Criteria** (what must be TRUE):
  1. 支持风扇的 MacBook Pro 弹窗中显示风扇数量，并为每个风扇显示当前 RPM。
  2. 每个风扇的 min/max/target 或控制能力状态在可读时可见，不可读字段以稳定 `N/A` 呈现。
  3. fanless、非 MacBook Pro 或不支持读取的机型显示普通降级状态，不显示手动风扇控制入口。
  4. UI 能区分“可读取 RPM”“可读取硬件边界”“可安全控制”，不会把可读 RPM 误判为可控。
**Plans**: TBD
**UI hint**: yes

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
**Plans**: TBD
**UI hint**: yes

### Phase 13: Safe Fan Control Gate & Write Path
**Goal**: 用户只有明确 opt-in 后才能进入手动风扇控制；所有控制都被边界限制、写后读回验证，并能一键恢复系统自动控制。
**Depends on**: Phase 11, Phase 12
**Requirements**: FCTRL-01, FCTRL-02, FCTRL-03, FCTRL-04, FCTRL-06
**Success Criteria** (what must be TRUE):
  1. 应用默认始终处于系统自动风扇控制；用户必须明确 opt-in 后才会看到或进入手动控制界面。
  2. 用户输入或拖动的手动 RPM 目标会被 clamp 到实时硬件 min/max 安全范围内，不能低于 Apple 默认下限或设置为静音/停转。
  3. 每次手动控制写入后，界面只在 mode、target RPM 和 current RPM 读回验证通过后显示“手动已生效”。
  4. 手动模式下用户始终能看到并点击一键“恢复系统自动控制”，恢复结果也必须读回验证后才显示成功。
  5. SwiftUI 视图只能调用高层控制动作；raw SMC key 写入集中在受限控制组件或受限 helper 中。
**Decision gate**: 如果 SMC 写入、helper/XPC、模式切换或读回验证在目标硬件上无法证明安全可恢复，则本阶段必须 fail closed：控制界面保持不可用，已完成的温度/风扇监控继续以只读模式工作。
**Plans**: TBD
**UI hint**: yes

### Phase 14: Lifecycle Recovery & Hardware UAT
**Goal**: 用户不会因为应用退出、睡眠、唤醒、写入失败或能力重新探测失败而遗留手动风扇状态；风扇控制只在真实硬件验证后标记完成。
**Depends on**: Phase 13
**Requirements**: FCTRL-05, UAT-01, UAT-02, UAT-03
**Success Criteria** (what must be TRUE):
  1. 写入失败、禁用控制、退出应用、睡眠前、唤醒后异常或能力重新探测失败时，应用会尝试恢复系统自动风扇控制并显示验证结果。
  2. 重新打开 app 或睡眠唤醒后，界面以硬件读回状态为准，不会凭旧设置假装仍处于手动或自动状态。
  3. unsupported、fanless、传感器缺失、读取失败、写入失败和恢复自动失败都有可验证、克制且不误导的 UI 表现。
  4. quit、sleep、wake、失败 rollback 和重新打开 app 的路径验证后，不会遗留 MacStatus 启动的手动风扇状态。
  5. 风扇控制必须在真实 MacBook Pro 上完成人工验证后，才能把本阶段和 v3.0 风扇控制标记为完成。
**Decision gate**: 如果真实硬件 UAT 未通过或不可执行，v3.0 可以保留只读温度/风扇能力，但风扇控制必须保持未完成或禁用。
**Plans**: TBD
**UI hint**: yes

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
| FCTRL-01 | Phase 13 |
| FCTRL-02 | Phase 13 |
| FCTRL-03 | Phase 13 |
| FCTRL-04 | Phase 13 |
| FCTRL-05 | Phase 14 |
| FCTRL-06 | Phase 13 |
| UAT-01 | Phase 14 |
| UAT-02 | Phase 14 |
| UAT-03 | Phase 14 |
| UAT-04 | Phase 12 |

**Mapped:** 22/22 v3.0 requirements.
**Unmapped:** 0.

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 10. Thermal Read-Only Monitoring | v3.0 | 2/3 | In Progress|  |
| 11. Fan Read-Only RPM & Capability Model | v3.0 | 0/TBD | Not started | - |
| 12. Popover Layout Stability | v3.0 | 0/TBD | Not started | - |
| 13. Safe Fan Control Gate & Write Path | v3.0 | 0/TBD | Not started | - |
| 14. Lifecycle Recovery & Hardware UAT | v3.0 | 0/TBD | Not started | - |
