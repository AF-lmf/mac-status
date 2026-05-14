# Phase 2: Network + Memory Monitoring - Context

**Gathered:** 2026-05-14
**Status:** Ready for planning

## Phase Boundary

在 Phase 1（CPU 监控 + 菜单栏骨架）基础上，新增网络上下行速率和内存占用的实时监控。沿用 Phase 1 建立的 TimerReader<T> + ReaderProtocol 模式，新增 NetworkReader 和 MemoryReader。Phase 4 再合并所有指标为单一条目。

## Implementation Decisions

### 网络显示格式
- **D-01:** 菜单栏显示 "↓2.1M ↑512K" 格式——箭头符号区分下载/上传，自动选择 KB/s 或 MB/s 单位

### 内存显示格式
- **D-02:** 菜单栏显示 "MEM 8.2G/16G" 格式——与 CPU 的 "CPU 45%" 保持一致的标签+值模式

### 网络接口检测
- **D-03:** 使用 SystemConfiguration `SCDynamicStoreCopyValue("State:/Network/Global/IPv4")` 动态获取主网络接口名，不硬编码 "en0"
- **D-04:** 过滤虚拟接口：awdl、utun、bridge、gif、stf、lo

### 网络速率计算
- **D-05:** 使用 `getifaddrs()` 读取 `if_data.ifi_ibytes/ifi_obytes`，通过两次采集的差值除以时间间隔计算速率
- **D-06:** 网络刷新间隔 1 秒（需要更快的采样来准确计算突发流量速率）
- **D-07:** 处理计数器回绕（64 位计数器，使用有符号差值避免负值）

### 内存数据采集
- **D-08:** 使用 `host_statistics64(HOST_VM_INFO64)` 获取内存页统计数据
- **D-09:** 通过 `host_info(HOST_BASIC_INFO)` 获取物理内存总量
- **D-10:** 内存刷新间隔 2 秒（变化较慢，无需高频更新）

### Reader 架构
- **D-11:** NetworkReader 和 MemoryReader 均继承 TimerReader<T> 基类（Phase 1 已建立），实现 ReaderProtocol
- **D-12:** NetworkReader 的 ValueType = `NetworkStats` (struct with downloadBytes, uploadBytes)，MemoryReader 的 ValueType = `MemoryStats` (struct with usedBytes, totalBytes)

### 菜单栏布局
- **D-13:** Phase 2 暂用多个 NSStatusItem 分别显示 CPU、网络、内存（Phase 4 再合并为单一条目）
- **D-14:** StatusBarManager 扩展 `updateNetwork()` 和 `updateMemory()` 方法，每个使用独立的 FixedWidth NSStatusItem

### 从 Phase 1 继承的决策
- D-03: Swift 6 + 严格并发
- D-06: 容差比较（0.5% 阈值）
- D-07: `.monospacedDigit()` 字体
- D-09: LSUIElement = YES，无 Dock 图标
- D-10: deinit 中 removeStatusItem 防止幽灵图标
- 后台 DispatchQueue 轮询 + 主线程更新 UI

### Agent 的裁量空间
- 网络接口变化时需要重新检测（如 Wi-Fi → 以太网切换），可通过定时器 + NSNotification 监听网络变化
- 内存压力级别（通过 `kern.memorystatus_vm_pressure_level`）可作为后续优化项
- NetworkReader 的字节格式化工具（B/KB/MB/GB 自动选择合适单位）

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 项目定义
- `.planning/PROJECT.md` — 项目上下文、核心价值、约束条件
- `.planning/REQUIREMENTS.md` — v1 需求定义，参见 NETW-01, NETW-02, NETW-03, MEM-01
- `.planning/ROADMAP.md` — Phase 2 成功标准

### 技术研究
- `.planning/research/STACK.md` — getifaddrs + SystemConfiguration 网络监测方案
- `.planning/research/ARCHITECTURE.md` — Reader→Widget 管道，网络速率增量计算模式
- `.planning/research/PITFALLS.md` — 关键陷阱：硬编码 "en0"（P5）、休眠唤醒数据冻结（P2）

### Phase 1 上下文（继承的决策和模式）
- `.planning/phases/01-foundation-cpu-monitoring/01-CONTEXT.md` — 项目结构、显示格式、刷新策略

### 现有代码（复用和扩展）
- `MacStatus/MacStatus/Readers/TimerReader.swift` — 泛型定时器基类，NetworkReader/MemoryReader 继承
- `MacStatus/MacStatus/Readers/ReaderProtocol.swift` — 接口协议，新增 Reader 需实现
- `MacStatus/MacStatus/Readers/CPUReader.swift` — CPU Reader 参考实现
- `MacStatus/MacStatus/UI/StatusBarManager.swift` — 需扩展 updateNetwork/updateMemory
- `MacStatus/MacStatus/App/AppDelegate.swift` — 需注册新的 Reader

## Existing Code Insights

### Reusable Assets
- **TimerReader<T>** — 泛型 Timer + 后台队列 + 回调模式，NetworkReader/MemoryReader 直接继承
- **ReaderProtocol** — start/stop/read 生命周期，所有新 Reader 遵循
- **StatusBarManager** — NSStatusItem 管理，扩展 updateNetwork/updateMemory 方法
- **SettingsManager** — UserDefaults 共享实例，存储用户偏好

### Established Patterns
- `TimerReader.start()` → 后台 DispatchQueue 轮询 → `onUpdate` 闭包 → `DispatchQueue.main.async` → UI 更新
- `CPULoad: Sendable` struct 模式 → `NetworkStats: Sendable` / `MemoryStats: Sendable`
- `@MainActor` StatusBarManager + `MainActor.assumeIsolated` 更新 UI

### Integration Points
- AppDelegate 中注册 NetworkReader、MemoryReader，连接到 StatusBarManager
- 新增源文件：`MacStatus/MacStatus/Readers/NetworkReader.swift`、`MacStatus/MacStatus/Readers/MemoryReader.swift`
- 修改：`StatusBarManager.swift`（新增方法）、`AppDelegate.swift`（新增 reader 初始化）

---

*Phase: 2-Network + Memory Monitoring*
*Context gathered: 2026-05-14*
