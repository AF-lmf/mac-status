# Requirements: MacStatus

**Defined:** 2026-05-14
**Core Value:** 用户无需打开任何窗口，在菜单栏一眼就能看到当前系统资源的实时使用情况

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### 网络监控 (NETW)

- [x] **NETW-01**: 状态栏实时展示网络下行速率（KB/s 或 MB/s，自动选择合适单位）
- [x] **NETW-02**: 状态栏实时展示网络上行速率（KB/s 或 MB/s，自动选择合适单位）
- [x] **NETW-03**: 自动检测当前活跃网络接口（Wi-Fi / 以太网 / 雷电），不硬编码接口名

### CPU 监控 (CPU)

- [x] **CPU-01**: 状态栏实时展示 CPU 总占用率百分比
- [x] **CPU-02**: CPU 数据刷新间隔 1-3 秒，CPU 占用 < 1%

### 内存监控 (MEM)

- [x] **MEM-01**: 状态栏实时展示内存压力状态（如 MEM OK / MEM WARN / MEM CRIT）

### GPU 监控 (GPU)

- [x] **GPU-01**: 状态栏实时展示 GPU 占用率百分比
- [x] **GPU-02**: Apple Silicon 设备展示 GPU 压力指标（绿色/黄色/红色）
- [x] **GPU-03**: Intel Mac 上优雅降级，仅显示 GPU 占用率或不显示 GPU

### 展示 (DISP)

- [x] **DISP-01**: 所有指标合并为一个紧凑的状态栏文本（如 `CPU 12% · MEM OK · ↓2.1M ↑512K · GPU 34%`）
- [x] **DISP-02**: 状态栏使用固定宽度布局，避免数值变化时抖动
- [x] **DISP-03**: 深色/浅色模式自动适配文字颜色
- [x] **DISP-04**: 部分指标不可用时优雅降级，显示 `--` 而非崩溃

### 应用生命周期 (LIFE)

- [x] **LIFE-01**: 应用以纯菜单栏方式运行，无 Dock 图标（LSUIElement = YES）
- [ ] **LIFE-02**: 支持开机自启动（SMAppService）
- [x] **LIFE-03**: 零配置启动，首次打开即显示数据
- [ ] **LIFE-04**: 右击状态栏显示退出菜单

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### 性能增强

- **PERF-01**: 自适应刷新频率——电池供电时降低轮询频率，交流电时恢复正常
- **PERF-02**: 低电量模式自动检测并降频

### 展示优化

- **DISP-V2-01**: 紧凑模式——允许用户选择显示哪些指标
- **DISP-V2-02**: GPU 压力色标（绿色/黄色/红色）可视化

### 国际化

- **I18N-01**: 英文界面支持

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| 历史数据图表 | 破坏"极简状态栏"定位，需要数据存储和图表库 |
| CPU 温度 / 风扇转速 | SM​C API 逐步被 Apple 锁定，Stats 维护者已放弃维护 |
| 逐进程 CPU/内存分解 | 复杂度高，对话式 UI 不可行，Activity Monitor 已覆盖此需求 |
| 自定义通知规则 | 需要持久化通知基础设施，边际价值低 |
| 磁盘空间/IO 监控 | 日常使用频率低，macOS 系统设置已提供 |
| 风扇控制 | 可能导致硬件损坏，Stats 已标记为废弃功能 |
| 远程监控 | 需要网络服务器和认证模型，架构完全不同 |
| 多语言支持（v1） | v1 专注中文，v2+ 再考虑英文 |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| NETW-01 | Phase 2 | Complete |
| NETW-02 | Phase 2 | Complete |
| NETW-03 | Phase 2 | Complete |
| CPU-01 | Phase 1 | Complete |
| CPU-02 | Phase 1 | Complete |
| MEM-01 | Phase 2 | Complete |
| GPU-01 | Phase 3 | Complete |
| GPU-02 | Phase 3 | Complete |
| GPU-03 | Phase 3 | Complete |
| DISP-01 | Phase 4 | Complete |
| DISP-02 | Phase 4 | Complete |
| DISP-03 | Phase 4 | Complete |
| DISP-04 | Phase 4 | Complete |
| LIFE-01 | Phase 1 | Complete |
| LIFE-02 | Phase 5 | Pending |
| LIFE-03 | Phase 1 | Complete |
| LIFE-04 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 17 total
- Mapped to phases: 17 ✓
- Unmapped: 0

*Traceability updated: 2026-05-14 after roadmap creation*

---
*Requirements defined: 2026-05-14*
*Last updated: 2026-05-14 after Phase 3 completion*
