# Requirements: MacStatus — v3.0 风扇与热状态

**Defined:** 2026-06-23
**Core Value:** 用户无需打开任何窗口，在菜单栏一眼就能看到当前系统资源的实时使用情况

## v3.0 Requirements

本里程碑的承诺范围。每条需求都必须映射到一个路线图阶段，并在实现后通过自动验证或真实 MacBook Pro UAT 确认。

### 温度监控 (THERM)

- [x] **THERM-01**: 用户能在弹窗中看到 CPU/SoC 主温度，显示值必须来自可信传感器或明确标为 `N/A`
- [x] **THERM-02**: 用户能在弹窗中看到系统 thermal state，用于补充说明当前系统热压力
- [x] **THERM-03**: 用户能看到可信的 GPU、电池、SSD 等次要温度；不可读或不可信时不显示假值
- [x] **THERM-04**: 传感器缺失、机型不支持或读取失败时，温度区块优雅降级，不崩溃、不刷错误弹窗

### 风扇监控 (FAN)

- [x] **FAN-01**: 用户能在 MacBook Pro 弹窗中看到风扇数量和每个风扇当前 RPM
- [x] **FAN-02**: 用户能看到每个风扇的 min/max/target 或控制能力状态；不可读字段显示为稳定的 `N/A`
- [x] **FAN-03**: fanless、非 MacBook Pro 或不支持读取的机型优雅降级，不显示误导性的风扇控制入口
- [x] **FAN-04**: 风扇能力模型能区分“可读取 RPM”“可读取边界”“可安全控制”，避免把可读误判为可控

### 弹窗布局稳定 (LAYOUT)

- [x] **LAYOUT-01**: 网络上下行、温度、RPM、功率等数值长度变化时，popover 不发生横向或纵向抖动
- [x] **LAYOUT-02**: 关键数值列使用固定宽度、右对齐、monospaced digits，并能容纳 `9999 RPM`、`100°C`、`N/A` 和大网络值
- [x] **LAYOUT-03**: 长进程名、长传感器标签、能力状态文本使用稳定裁切或换行策略，不挤压相邻数值列
- [x] **LAYOUT-04**: popover 宽度优先保持现有约 320pt；若新增散热区块需要扩展，允许上限到 360-380pt，但必须保持稳定布局

### 风扇安全控制 (FCTRL)

- [ ] **FCTRL-01**: 用户必须显式 opt-in 才能进入手动风扇控制，默认始终为系统自动控制
- [ ] **FCTRL-02**: 手动 RPM 目标必须 clamp 到实时硬件 min/max 安全范围内，不允许低于 Apple 默认下限或设置为静音模式
- [ ] **FCTRL-03**: 每次写入风扇控制后必须读回 mode、target RPM 和 current RPM 验证，不能只信 IOKit 返回成功
- [ ] **FCTRL-04**: 用户可以一键恢复系统自动风扇控制，恢复结果必须读回验证
- [ ] **FCTRL-05**: 写入失败、禁用控制、退出应用、睡眠前、唤醒后异常或能力重新探测失败时，应用必须尝试恢复系统自动控制
- [ ] **FCTRL-06**: 风扇控制写入必须集中在受限控制组件或受限 helper 中，SwiftUI 视图不得直接读写 raw SMC key

### 验证与发布门槛 (UAT)

- [ ] **UAT-01**: 风扇控制必须在真实 MacBook Pro 上完成人工验证后才能标记完成
- [ ] **UAT-02**: unsupported、fanless、传感器缺失、读取失败、写入失败和恢复自动失败状态都必须有可验证的 UI 表现
- [ ] **UAT-03**: quit、sleep、wake、失败 rollback 和重新打开 app 的生命周期路径必须验证不会遗留手动风扇状态
- [x] **UAT-04**: 布局稳定必须用确定性快照或测试数据覆盖极端数值，不只依赖肉眼观察

## Future Requirements

承认但推迟到后续版本，不在本里程碑路线图内。

### 风扇与热状态

- **THERM-F1**: 长期温度历史、趋势图或持久化热数据
- **THERM-F2**: 原始 SMC 传感器浏览器和全部 key 枚举 UI
- **FCTRL-F1**: 完整自动风扇曲线、按温度自动调速或多配置档案
- **FCTRL-F2**: 静音/低噪模式或任何低于 Apple 默认冷却策略的控制
- **FCTRL-F3**: 远程控制风扇或通过网络 API 暴露硬件控制

### 显示与告警

- **ALERT-F1**: 温度/风扇异常通知规则和告警策略
- **DISP-F1**: 状态栏新增温度或风扇段；v3.0 默认聚焦弹窗，避免状态栏过载

## Out of Scope

显式排除，记录原因以防范围蔓延。

| Feature | Reason |
|---------|--------|
| 不受限 raw SMC 写入 UI | 硬件安全风险高，且会破坏可验证控制边界 |
| 低于硬件 min 或 Apple 默认下限的风扇控制 | 可能导致过热或硬件损伤 |
| 完整自动温控曲线 | 需要长期策略、冲突处理和更大 UAT 面，推迟到后续版本 |
| 原始传感器浏览器 | 会把 MacStatus 变成调试工具，偏离轻量监控定位 |
| 长期温度/风扇历史图表 | 需要持久化采样和图表基础设施，本轮不落盘 |
| 通知 / 告警规则引擎 | 需要通知权限和规则管理，不属于 v3.0 主目标 |
| 风扇远程控制 | 需要网络服务与认证模型，硬件风险扩大 |
| Activity Monitor 替代品 | MacStatus 保持轻量，不做完整系统管理套件 |
| 多语言 i18n | 持续聚焦中文 |

## Traceability

哪些阶段覆盖哪些需求。路线图创建时填充。

| Requirement | Phase | Status |
|-------------|-------|--------|
| THERM-01 | Phase 10 | Complete |
| THERM-02 | Phase 10 | Complete |
| THERM-03 | Phase 10 | Complete |
| THERM-04 | Phase 10 | Complete |
| FAN-01 | Phase 11 | Complete |
| FAN-02 | Phase 11 | Complete |
| FAN-03 | Phase 11 | Complete |
| FAN-04 | Phase 11 | Complete |
| LAYOUT-01 | Phase 12 | Complete |
| LAYOUT-02 | Phase 12 | Complete |
| LAYOUT-03 | Phase 12 | Complete |
| LAYOUT-04 | Phase 12 | Complete |
| FCTRL-01 | Phase 13 | Pending |
| FCTRL-02 | Phase 13 | Pending |
| FCTRL-03 | Phase 13 | Pending |
| FCTRL-04 | Phase 13 | Pending |
| FCTRL-05 | Phase 14 | Pending |
| FCTRL-06 | Phase 13 | Pending |
| UAT-01 | Phase 14 | Pending |
| UAT-02 | Phase 14 | Pending |
| UAT-03 | Phase 14 | Pending |
| UAT-04 | Phase 12 | Complete |

**Coverage:**
- v3.0 requirements: 22 total
- Mapped to phases: 22
- Unmapped: 0

---
*Requirements defined: 2026-06-23*
*Last updated: 2026-06-23 after v3.0 requirement confirmation*
