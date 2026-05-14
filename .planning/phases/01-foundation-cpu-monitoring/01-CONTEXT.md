# Phase 1: Foundation + CPU Monitoring - Context

**Gathered:** 2026-05-14
**Status:** Ready for planning

## Phase Boundary

搭建 MacStatus 的 Xcode 项目骨架、菜单栏生命周期（AppKit NSStatusBar）、以及 CPU 占用率实时监控管道。本阶段是整个应用的基础——后续所有资源监控都依赖本阶段建立的 Reader→Widget 数据管道和菜单栏展示链路。

## Implementation Decisions

### Xcode 项目结构
- **D-01:** 单 target（macOS App），不使用 Swift Package Manager 多模块架构
- **D-02:** 源码按功能分组文件夹：App/（AppDelegate、Info.plist）、Readers/（CPUReader、ReaderProtocol）、UI/（StatusBarManager、TextWidget）、Utils/（SettingsManager）
- **D-03:** Swift 6 语言模式，`SWIFT_STRICT_CONCURRENCY = complete`

### CPU 显示格式
- **D-04:** 菜单栏显示 "CPU 45%" 格式——简短标签 + 百分比，提供足够上下文又不冗长

### 刷新间隔
- **D-05:** CPU 数据采集间隔 2 秒——在响应性与 CPU 开销之间取得平衡

### 菜单栏文本更新策略
- **D-06:** 使用容差比较（值变化 > 0.5% 才重绘），避免不必要的 NSStatusItem 重绘
- **D-07:** 使用 `.monospacedDigit()` 字体，确保数字宽度稳定，防止菜单栏抖动

### 菜单栏生命周期
- **D-08:** 使用 `NSStatusBar.system.statusItem(withLength:)` 创建状态栏项
- **D-09:** `LSUIElement = YES` 隐藏 Dock 图标，纯菜单栏运行
- **D-10:** StatusBarManager 的 `deinit` 中调用 `removeStatusItem(_:)` 防止幽灵图标

### Agent 的裁量空间
- SettingsManager 使用 `UserDefaults` 存储偏好（刷新间隔等），v1 不设设置窗口
- CPUReader 使用 `host_processor_info()` Mach API，在后台 DispatchQueue 轮询
- 错误处理：Mach API 返回非 KERN_SUCCESS 时返回 nil，菜单栏显示 "--"

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 项目定义
- `.planning/PROJECT.md` — 项目上下文、核心价值、约束条件
- `.planning/REQUIREMENTS.md` — v1 需求定义，参见 CPU-01, CPU-02, LIFE-01, LIFE-03
- `.planning/ROADMAP.md` — 阶段划分和依赖关系

### 技术研究
- `.planning/research/STACK.md` — 技术栈推荐，AppKit + Mach API 详细说明
- `.planning/research/ARCHITECTURE.md` — 三层架构（Reader→Module→Widget），组件边界和数据流
- `.planning/research/PITFALLS.md` — 关键陷阱：幽灵图标（P1）、主线程轮询、未检查 Mach 返回值、LSUIElement 冲突

### 参考实现
- Stats (exelban/stats) 源码 — `Stats/AppDelegate.swift`（NSStatusBar 生命周期）、`Modules/CPU/readers.swift`（CPUReader 实现）

## Existing Code Insights

### Reusable Assets
- 无现有代码——全新项目（greenfield）

### Established Patterns
- AppKit AppDelegate + NSStatusBar 模式（参考 Stats）
- ReaderProtocol 协议 + TimerReader 基类模式
- 闭包回调将数据从后台队列传递到主线程

### Integration Points
- CPUReader 的输出将被后续 Phase 2/3/4 的 NetworkReader、MemoryReader、GPUReader 和 CombinedStatusView 复用

---

*Phase: 1-Foundation + CPU Monitoring*
*Context gathered: 2026-05-14*
