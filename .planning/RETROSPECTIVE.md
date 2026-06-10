# Retrospective

Living document updated at each milestone boundary.

---

## Milestone: v1.0 — MVP

**Shipped:** 2026-06-10
**Phases:** 5 | **Plans:** 9 | **Tasks:** 18

### What Was Built

- 菜单栏实时 CPU 占用显示（Mach kernel API，后台队列，等宽数字，深色/浅色自适应）
- 网络吞吐量监控（getifaddrs 字节计数器 + SystemConfiguration 主接口检测）
- 内存压力状态展示（kern.memorystatus_vm_pressure_level）
- IOKit IOAccelerator GPU 利用率读取 + Apple Silicon 压力模型
- 四合一紧凑状态栏文本（值级着色 + 固定宽度 + 优雅降级）
- 开机自启动（SMAppService）+ 右键退出菜单 + 睡眠/唤醒恢复

### What Worked

- **风险递增构建顺序**: CPU 先行验证完整管线，GPU 最后处理最高风险指标，每阶段独立可验证
- **零外部依赖策略**: 直接调用 Mach/IOKit C API，参考 Stats 开源实现，避免依赖管理负担
- **垂直切片交付**: 每个 Plan 交付端到端可见功能，用户每步都能在菜单栏看到成果
- **Reader-Manager-AppDelegate 三层分离**: 清晰的职责划分，便于扩展新监控源

### What Was Inefficient

- **Phase 2 需要 3 个 Plan**: 原计划 2 个（网络+内存），但内存显示需要额外的 gap closure Plan 来确保在可见的组合状态项中渲染
- **Phase 1 Progress 表陈旧**: ROADMAP.md 的 Progress 表在 Phase 1 仍显示 1/2，实际两个 Plan 均已完成
- **快速任务状态缺失**: 5 个 quick task 的目录状态标记为 missing，说明快速任务流程的归档步骤不够自动化

### Patterns Established

- `TimerReader<T>` 基类：统一所有 Reader 的定时器生命周期管理
- `getifaddrs()` + delta + SCDynamicStore：网络监控的标准三件套
- 值级着色（非字符串解析）：防止降级后残留错误颜色
- `freeifaddrs()` in defer block：防止内存泄漏的关键模式

### Key Lessons

- macOS 26 的菜单栏隐私控制是重大变化，需要在 onboarding 中提前引导用户
- `host_statistics()` 比 `host_processor_info()` 更简单，对于聚合 CPU% 场景是更优选择
- IOKit `PerformanceStatistics` 字典的字段名因 GPU 型号而异，需要多键尝试 + nil 降级
- SCDynamicStore 每轮读取主接口名称是可行的，无需缓存或事件监听

### Cost Observations

- 提交数: 86
- 代码量: ~3000 行 Swift
- 时间跨度: 23 天（2026-05-14 → 2026-06-06）
- 模式: yolo（自动审批）

---

## Cross-Milestone Trends

| Metric | v1.0 |
|--------|------|
| Phases | 5 |
| Plans | 9 |
| LOC | ~3000 |
| Duration | 23 days |
| Commits | 86 |
