# Requirements: MacStatus — v2.0 洞察与可定制

**Defined:** 2026-06-16
**Core Value:** 用户无需打开任何窗口，在菜单栏一眼就能看到当前系统资源的实时使用情况

## v2.0 Requirements

本里程碑的承诺范围。每条映射到一个路线图阶段。

### 逐进程 (PROC)

- [ ] **PROC-01**: 用户能在弹窗中看到 CPU 占用最高的 3-5 个进程（进程名 + CPU%）
- [ ] **PROC-02**: 用户能在弹窗中看到常驻内存占用最高的 3-5 个进程（进程名 + 内存）
- [ ] **PROC-03**: 逐进程数据仅在弹窗打开时采样，关闭弹窗即停止，不增加后台常驻开销

### 电池 (BATT)

- [ ] **BATT-01**: 用户能在弹窗中看到电池电量百分比与充电状态（充电中 / 已充满 / 使用电池）
- [ ] **BATT-02**: 用户能在弹窗中看到电池剩余可用时间（或充满时间）
- [ ] **BATT-03**: 用户能在弹窗中看到实时充 / 放电功率（瓦）
- [ ] **BATT-04**: 用户能在弹窗中看到电池健康度（最大容量百分比）与循环次数
- [ ] **BATT-05**: 在无电池机型（台式 Mac）上整个电池区块优雅降级隐藏，不显示空值 / 假值

### 设置与可定制 (SET)

- [ ] **SET-01**: 用户能从右键菜单打开一个独立的设置窗口
- [ ] **SET-02**: 用户能逐个开关每个指标在状态栏的显示（启用 / 禁用）
- [ ] **SET-03**: 用户能拖动调整状态栏各指标的显示顺序
- [ ] **SET-04**: 用户能自定义各指标的警告 / 危险阈值
- [ ] **SET-05**: 用户能自定义各指标的着色
- [ ] **SET-06**: 用户能在紧凑 / 详细两种状态栏文本模式间切换
- [ ] **SET-07**: 用户的所有偏好在重启应用后保持（持久化）
- [ ] **SET-08**: 设置更改即时生效，无需重启应用（实时重应用）

## Future Requirements

承认但推迟到后续版本，不在本里程碑路线图内。

### 逐进程

- **PROC-F1**: 点击进程行在「活动监视器」中揭示该进程（轻量只读跳转）
- **PROC-F2**: 逐进程网络已在 v1.0 后落地，未来可统一并入弹窗进程视图

### 设置与可定制

- **SET-F1**: 各指标可单独配置刷新间隔（需要按指标定时调度，暂缓）
- **SET-F2**: 弹窗内电池充放电功率的短期趋势曲线（sparkline）

### 显示

- **DISP-F1**: 状态栏新增紧凑电池段（如 🔋85%）— 本里程碑电池仅在弹窗显示，保持状态栏紧凑

## Out of Scope

显式排除，记录原因以防范围蔓延。

| Feature | Reason |
|---------|--------|
| 弹窗内 kill / 强制退出进程按钮 | Stats #593 前车之鉴（误点误杀）；MacStatus 保持只读 |
| 完整可排序 / 可筛选进程表 | 保持轻量 Top-N，不与活动监视器重叠 |
| 逐进程 GPU 占用 | macOS 无公开 API |
| 逐进程能耗 / energy impact | 复杂度高，边际价值低 |
| 通知 / 告警规则引擎 | 本轮未选，需持久化通知基础设施 |
| SMC 温度 / 风扇转速 | SMC API 逐步被 Apple 锁定 |
| 蓝牙外设电量 | 偏离核心，复杂度高 |
| 单位选择器 / 按状态条件主题 | iStat 式过度配置，破坏极简定位 |
| 配置档案 / 预设切换 | 过度工程，单一配置已足够 |
| iCloud 设置同步 | 需账户与同步基础设施，边际价值低 |
| 持久化历史存储与长期图表 | 仅做弹窗内内存态短期趋势，不落盘 |
| 多语言 i18n | 持续聚焦中文 |
| 磁盘空间 / IO 监控 | 日常频率低，系统设置已提供 |
| 远程监控 | 需网络服务与认证模型 |

## Traceability

哪些阶段覆盖哪些需求。路线图创建时填充。

| Requirement | Phase | Status |
|-------------|-------|--------|
| PROC-01 | Phase 8 | Pending |
| PROC-02 | Phase 8 | Pending |
| PROC-03 | Phase 8 | Pending |
| BATT-01 | Phase 7 | Pending |
| BATT-02 | Phase 7 | Pending |
| BATT-03 | Phase 7 | Pending |
| BATT-04 | Phase 7 | Pending |
| BATT-05 | Phase 7 | Pending |
| SET-01 | Phase 9 | Pending |
| SET-02 | Phase 9 | Pending |
| SET-03 | Phase 9 | Pending |
| SET-04 | Phase 9 | Pending |
| SET-05 | Phase 9 | Pending |
| SET-06 | Phase 9 | Pending |
| SET-07 | Phase 6 | Pending |
| SET-08 | Phase 6 | Pending |

**Coverage:**
- v2.0 requirements: 16 total
- Mapped to phases: 16 ✓
- Unmapped: 0 ✓

**Phase distribution:**
- Phase 6 (Settings Foundation + Live Re-apply Seam): SET-07, SET-08 (2)
- Phase 7 (Battery & Power): BATT-01..05 (5)
- Phase 8 (Per-Process Top-N CPU & Memory): PROC-01..03 (3)
- Phase 9 (Settings Window UI + Customization): SET-01..06 (6)

---
*Requirements defined: 2026-06-16*
*Last updated: 2026-06-16 after roadmap creation (traceability filled, coverage 16/16)*
