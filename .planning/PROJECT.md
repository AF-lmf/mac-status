# MacStatus

## What This Is

一个轻量级 macOS 菜单栏应用，在状态栏实时展示系统资源使用情况（CPU/GPU/内存/网络），以单一紧凑的固定宽度文本呈现，支持数值级着色和深色/浅色模式自适应。面向需要持续监控系统状态的 macOS 用户（开发者、运维、重度用户）。

## Core Value

用户无需打开任何窗口，在菜单栏一眼就能看到当前系统资源的实时使用情况。

## Current Milestone: v2.0 洞察与可定制（Insight & Customization）

**Goal:** 把 MacStatus 从"看一眼系统状态"升级为"看明白哪个进程在吃资源、看到电池全貌，并按我自己的方式配置"。

**Target features:**
- 弹窗仪表盘深化 — 为 CPU/内存补上 Top 3-5 占用进程（精简版），延续 sparklines 的内存态短期历史趋势图
- 电池与电源 — 电量、充电状态、实时充放电功率(W)、剩余时间、电池健康度；非笔记本机型优雅降级
- 设置界面 + 可定制 — 独立设置窗口：指标开关与拖动排序、各指标刷新间隔、自定义阈值与配色、紧凑/详细模式切换，偏好持久化

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

### Active

<!-- v2.0 洞察与可定制 — building toward these -->

- [ ] CPU/内存 Top 占用进程（弹窗内精简 Top-N）
- [ ] 弹窗内内存态短期历史趋势图
- [ ] 电池监控：电量、充电状态、实时功率(W)、剩余时间、健康度
- [ ] 非笔记本机型电池段优雅降级
- [ ] 设置窗口：指标显示开关与拖动排序
- [ ] 设置窗口：各指标刷新间隔可调
- [ ] 设置窗口：自定义阈值与配色
- [ ] 紧凑/详细状态栏模式切换
- [ ] 偏好持久化

### Out of Scope

- 持久化历史存储与长期图表 — v2.0 仅做弹窗内内存态短期趋势，不落盘，避免数据库/图表库负担
- 逐进程 GPU 占用 — macOS 无公开 API
- 完整活动监视器（可排序全进程列表）— 保持轻量 Top-N，不与 Activity Monitor 重叠
- CPU 温度 / 风扇转速 — SMC API 逐步被 Apple 锁定
- 自定义通知规则 / 告警 — v2.0 未纳入（本轮未选），需持久化通知基础设施
- 磁盘空间/IO 监控 — 日常使用频率低，macOS 系统设置已提供
- 风扇控制 — 可能导致硬件损坏
- 远程监控 — 需要网络服务器和认证模型
- 多语言 i18n — 持续聚焦中文，暂不投入本地化

## Context

- **已交付**: v1.0 MVP（2026-06-10）
- **代码量**: ~3000 行 Swift
- **技术栈**: Swift 6 + AppKit (NSStatusBar) + IOKit + Mach kernel APIs
- **零外部依赖**: 所有系统监控通过原生 C/Mach API 实现
- **架构**: Reader → Manager → AppDelegate（三层分离）
- **已知问题**: macOS 26 菜单栏隐私控制可能需要用户在系统设置中手动启用

## Constraints

- **平台**: macOS 14+（Sonoma 及以上）
- **语言**: Swift
- **框架**: SwiftUI + AppKit（混合，菜单栏应用需要 AppKit 的 NSStatusBar）
- **性能**: 状态栏更新不能导致明显 CPU 消耗（采样间隔合理，避免高频轮询）
- **包体**: 尽量小，无外部依赖或最小依赖

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

---

*Last updated: 2026-06-16 after v2.0 milestone start*

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
