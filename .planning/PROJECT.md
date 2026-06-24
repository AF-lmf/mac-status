# MacStatus

## What This Is

一个轻量级 macOS 菜单栏应用，在状态栏实时展示系统资源使用情况（CPU/GPU/内存/网络），并在弹窗内提供更细的电源、进程、热状态与散热信息。面向需要持续监控系统状态的 macOS 用户（开发者、运维、重度用户），优先保持低开销、稳定布局和安全的硬件交互。

## Core Value

用户无需打开任何窗口，在菜单栏一眼就能看到当前系统资源的实时使用情况。

## Current Milestone: v3.0 风扇与热状态

**Goal:** 在保持 MacStatus 轻量菜单栏体验的前提下，为 MacBook Pro 增加风扇转速、关键温度与安全风扇控制能力，并修复网络数值变化导致下拉窗布局抖动的问题。

**Target features:**
- 热状态监控 — 显示整机 CPU/SoC 等关键温度，尽量读取 GPU、电池、SSD 等重要传感器；不可用时优雅显示 N/A。
- 风扇监控 — 在 MacBook Pro 上显示当前风扇 RPM、风扇数量、可用/不可用状态，非支持机型优雅降级。
- 风扇安全控制 — 提供明确控制入口、范围限制、失败恢复和一键恢复系统自动控制；不做无边界写入。
- 下拉窗布局稳定 — 网络上下行数值大幅变化时，popover 不应横向/纵向抖动，关键行列保持定宽或稳定布局。

## Requirements

### Validated

- ✓ 状态栏展示 GPU 占用/压力情况 — v1.0 (Phase 3)
- ✓ 状态栏展示实时网络上下行速率 — v1.0 (Phase 2)
- ✓ 状态栏展示 CPU 占用率 — v1.0 (Phase 1)
- ✓ 状态栏展示内存压力状态 — v1.0 (Phase 2)
- ✓ 应用开机自启动 — v1.0 (Phase 5)
- ✓ 数据实时刷新（1-3 秒更新） — v1.0 (Phase 1)
- ✓ 所有指标合并为单一紧凑状态栏文本 — v1.0 (Phase 4)
- ✓ 固定宽度布局，避免数值变化时抖动 — v1.0 (Phase 4)
- ✓ 深色/浅色模式自动适配 — v1.0 (Phase 4)
- ✓ 部分指标不可用时优雅降级 — v1.0 (Phase 4)
- ✓ 零配置启动，首次打开即显示数据 — v1.0 (Phase 1)
- ✓ 纯菜单栏运行，无 Dock 图标 — v1.0 (Phase 1)
- ✓ 右击状态栏显示退出菜单 — v1.0 (Phase 5)
- ✓ 自动检测活跃网络接口 — v1.0 (Phase 2)
- ✓ Apple Silicon GPU 压力指标 — v1.0 (Phase 3)
- ✓ Intel Mac GPU 优雅降级 — v1.0 (Phase 3)
- ✓ 睡眠/唤醒后读数恢复 — v1.0 (Phase 5)
- ✓ 设置单一真源、偏好持久化与实时重应用 — v2.0 (Phase 6)
- ✓ 弹窗电池信息、实时功率、健康度与台式机优雅降级 — v2.0 (Phase 7)
- ✓ 弹窗 CPU/内存 Top-N 进程按需采样 — v2.0 (Phase 8)
- ✓ 设置窗口：指标开关、拖动排序、阈值/配色与文字模式 — v2.0 (Phase 9)
- ✓ 网络弹窗上下行竖排与 SMC 整机功耗/电池功率增强 — v2.0 UAT 后增强
- ✓ 重要温度监控：可信 CPU/SoC 主温度、系统 thermal state、GPU/电池次要温度与不可用 N/A 降级 — v3.0 (Phase 10；SSD 传感器按决策 deferred)
- ✓ MacBook Pro 风扇 RPM 监控：多风扇识别、当前 RPM、min/max/target、能力模型与非支持机型优雅降级 — v3.0 (Phase 11；控制能力保持 fail-closed)

### Active

<!-- v3.0 风扇与热状态 — building toward these -->

- [ ] 风扇安全控制：受限手动控制、明确开关、失败恢复、一键恢复系统自动控制。
- [ ] 下拉窗布局稳定：网络数值长度变化时 popover 不再抖动，行列保持稳定宽度。

### Out of Scope

- 持久化历史存储与长期图表 — v2.0 仅做弹窗内内存态短期趋势，不落盘，避免数据库/图表库负担
- 逐进程 GPU 占用 — macOS 无公开 API
- 完整活动监视器（可排序全进程列表）— 保持轻量 Top-N，不与 Activity Monitor 重叠
- 自定义通知规则 / 告警 — v2.0 未纳入（本轮未选），需持久化通知基础设施
- 磁盘空间/IO 监控 — 日常使用频率低，macOS 系统设置已提供
- 不受限风扇控制、绕过硬件保护或低于安全下限的控制 — 可能导致硬件损坏
- 完整自动温控曲线/守护式风扇策略 — v3.0 只做安全控制闭环，复杂策略后续再评估
- 远程监控 — 需要网络服务器和认证模型
- 多语言 i18n — 持续聚焦中文，暂不投入本地化

## Context

- **已交付**: v1.0 MVP（2026-06-10）；v2.0 洞察与可定制（2026-06-23 归档）；v3.0 Phase 10 温度只读监控与 Phase 11 风扇只读 RPM/能力模型（2026-06-24）
- **代码量**: ~3000 行 Swift
- **技术栈**: Swift 6 + AppKit (NSStatusBar) + IOKit + Mach kernel APIs
- **零外部依赖**: 所有系统监控通过原生 C/Mach API 实现
- **架构**: Reader → Manager → AppDelegate（三层分离）
- **热/电源基础**: 已有 AppleSMC user-client 读取整机功耗 `PSTR` 和电池功率 `PPBR` 的 SMCReader 经验，可作为 v3.0 温度/风扇研究起点
- **已知问题**: macOS 26 菜单栏隐私控制可能需要用户在系统设置中手动启用

## Constraints

- **平台**: macOS 14+（Sonoma 及以上）
- **语言**: Swift
- **框架**: SwiftUI + AppKit（混合，菜单栏应用需要 AppKit 的 NSStatusBar）
- **性能**: 状态栏更新不能导致明显 CPU 消耗（采样间隔合理，避免高频轮询）
- **包体**: 尽量小，无外部依赖或最小依赖
- **硬件安全**: 风扇控制必须可恢复系统自动模式，必须限制范围并在写入失败、退出或异常时回退
- **兼容性**: 温度/风扇传感器不可用时必须显示 N/A 或隐藏控制，不崩溃、不虚构数值

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Swift + AppKit/SwiftUI | macOS 原生开发最优选，系统 API 直接获取资源数据 | ✓ Good |
| 菜单栏应用（无 Dock 图标） | 用户明确要状态栏展示，不需要独立窗口 | ✓ Good |
| IOKit IOAccelerator GPU reader | 零外部依赖读取 GPU 利用率，缺失服务/字段时返回 nil 走降级 | ✓ Good |
| GPU 压力先用利用率阈值表达 | IOReport 压力字段不稳定，v1 先用 Apple Silicon 上的 GPU 利用率映射 | ✓ Good |
| host_statistics 聚合 CPU% | 比 host_processor_info() 更简单的 API，无 vm_deallocate | ✓ Good |
| getifaddrs() + delta 计算网络速率 | BSD 层 C 调用，近零开销，比 nettop 进程生成高效 | ✓ Good |
| SCDynamicStoreCopyValue 动态检测主接口 | 即时处理 Wi-Fi/Ethernet/VPN 切换 | ✓ Good |
| 值级着色（非字符串解析） | 防止降级后残留错误颜色，标签保持默认色 | ✓ Good |
| SMAppService 开机自启 | 单行 API，无需 Helper App，macOS 13+ 即可用 | ✓ Good |
| Phase 10 温度监控保持只读且 Mac15,9 白名单信任 | Apple Silicon 传感器命名不稳定，不能把未验证 key 或 thermalState 当作 CPU/SoC 温度 | ✓ Phase 10 |
| Phase 10 暂不实现 SSD 温度和风扇/控制入口 | 先关闭温度只读闭环，SSD 与风扇控制留给后续阶段按安全门推进 | ✓ Phase 10 |
| Phase 11 风扇监控保持只读、弹窗内当前快照 | Mac15,9 probe 已确认 `FNum=2`、两把风扇 RPM/bounds/target 可读，但 `F0ID/F1ID` 缺失且安全控制未验证 | ✓ Phase 11 |
| Phase 11 不推断左右风扇，不展示控制承诺 | 缺少可靠位置证据，且读取能力不能等同安全控制；非目标硬件无可读 RPM 时隐藏风扇行 | ✓ Phase 11 |
| 风扇控制必须先研究再落地 | SMC 写入涉及硬件安全和机型差异，不能直接按猜测写值 | — Pending |
| v3.0 控制边界为安全控制而非完整自动曲线 | 先交付可恢复、可限制、可验证的用户控制闭环 | — Pending |

---

*Last updated: 2026-06-24 after Phase 11 verification*

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
