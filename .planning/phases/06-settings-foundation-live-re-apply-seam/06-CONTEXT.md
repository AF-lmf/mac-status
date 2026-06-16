# Phase 6: Settings Foundation + Live Re-apply Seam - Context

**Gathered:** 2026-06-16
**Status:** Ready for planning

<domain>
## Phase Boundary

建立 v2.0 所有可定制功能依赖的"管线层"：让一个强类型的 `SettingsManager` 成为唯一的偏好真源，偏好可跨重启持久化，且修改偏好无需重启即时生效。本阶段交付 SettingsManager（含版本化存储与变更广播）、`MetricCollector` 的 `reconfigure()`/`applyNow()` 重应用入口，以及 `StatusBarManager.updateTitle` 的"启用集 + 顺序"组合接缝和 `colorForUsage` 的实时阈值/配色读取接缝 —— 即 Phase 9 控件将驱动的那条缝。

本阶段**不**交付设置窗口 UI（Phase 9）、电池/进程等新指标（Phase 7/8）。只做底座与接缝。
</domain>

<decisions>
## Implementation Decisions

### 实时重应用机制 (Live Re-apply Mechanism)
- 广播方式：`SettingsManager` 在每个属性的 `didSet` 中通过 `NotificationCenter` 发出单一 `.settingsDidChange` 通知。零依赖、AppKit 惯用，且两个消费者（`MetricCollector`、`StatusBarManager`）均已是 `@MainActor`。
- 广播载荷：在 `userInfo` 中携带 `changedKeys: Set<String>`，让消费者区分"计时类变更"与"外观类变更"。
- 计时类变更（`refreshInterval`）：触发 `MetricCollector.reconfigure()` —— 失效并按新间隔重排计时器，保留各 reader 的基线（不做 stop/start 全量重启，避免丢失网络 delta 基线与历史）。
- 外观类变更（顺序/启用集/阈值/配色/模式）：触发 `MetricCollector.applyNow()` —— 重新把最后一帧缓存样本推过 `updateUI`，状态栏与弹窗立即重绘，不必等下一个 tick。

### 设置模型与 SwiftUI 绑定 (Settings Model & Binding)
- 消除 `SettingsView` 的 `@AppStorage` 重复真源：将 `SettingsManager` 改为 `@MainActor @Observable` 类，`SettingsView` 通过 `@Bindable` 绑定；每个属性 `didSet` 负责写入 `UserDefaults` 并发出通知。单一真源、SwiftUI 自动刷新。
- 版本化存储/迁移：存一个 Int `schemaVersion` 键；init 时跑一条迁移阶梯（为新增键补默认值）；当前键集记为 v1，未来加键可干净迁移。
- 新增集合类键编码：`metricOrder` 与启用集存为 `[String]`；`customThresholds`/`customColors` 各存为 Codable → JSON `Data`（每类一个键）。
- 配色存储格式：按 (指标, 等级) 存十六进制字符串 `#RRGGBB`，读取时解码为 `NSColor`。可移植、可读、易 diff。

### 指标标识、顺序与启用集 (Metric Identity, Order & Enabled-set)
- 规范标识：引入 `Metric` 枚举（现 `cpu, memory, network, gpu`，预留 `battery`），以稳定的 string rawValue 作为顺序/启用/阈值/配色处处通用的 id。
- 默认 `metricOrder`：`[cpu, memory, network, gpu]` —— 与当前标题组合顺序一致，升级后行为不变。
- 默认启用集：四项全部启用 —— 保留 v1.0 行为，升级后不会有指标消失。
- `updateTitle` 如何尊重禁用/重排：在唯一的合并 `NSStatusItem` 上按启用集与顺序**条件式组合** segment（并丢弃多余的分隔符），**绝不**增删 status item；启用集为空时显示一个最小占位字形（如应用 glyph），而非空白栏。`colorForUsage` 实时读取自定义阈值/配色。

### Claude's Discretion
- "紧凑/详细模式切换"键（compact/verbose）：Phase 6 仅需保证其在版本化存储中持久化；其与现有 `displayMode`(full/compact/percentage) 的最终关系与 UI 交由 Phase 9 决定。本阶段按 Claude 判断添加最小持久化键即可。
- `SettingsManager` 当前为 `@unchecked Sendable` 单例；改为 `@MainActor @Observable` 后若仍有后台读取需求，按需提供快照/线程安全读取路径，具体由 Claude 在规划/执行时依 Swift 6 严格并发裁定。
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MacStatus/Utils/SettingsManager.swift` — 已有单例 + `Keys` 枚举 + `DisplayMode`/`DisplayUnit` 枚举与阈值访问器，作为改造起点。
- `MacStatus/UI/Views/SettingsView.swift` — 含 8 个 `@AppStorage` 重复键（待消除）+ `SettingsWindowManager`。
- `MacStatus/Collectors/MetricCollector.swift` — `@MainActor` 单例，`start()` 中**只在启动时**读一次 `refreshInterval`（无实时重应用）；`updateUI(sample:)` 是 applyNow() 的天然复用点；需缓存"最后一帧样本"。
- `MacStatus/UI/StatusBarManager.swift` — `updateTitle` 无条件组合四指标；`colorForUsage` 已读 `SettingsManager` 阈值（CPU/MEM 实时，GPU 硬编码 80）；`buildFullTitle/Compact/Percentage` 三套组合逻辑需接入启用集/顺序。

### Established Patterns
- 三层架构：Reader → Manager → AppDelegate，单一 `Timer` 统一 tick。
- 单例 `@MainActor` Manager；`NSAttributedString` 着色（值级，非字符串解析）。
- 零外部依赖，原生 Swift 6 + AppKit/SwiftUI 混合。

### Integration Points
- `MetricCollector.start()` 的 timer 调度 → `reconfigure()` 接入点。
- `MetricCollector.updateUI(sample:)` → `applyNow()` 复用点（需新增 lastSample 缓存）。
- `StatusBarManager.updateTitle` / 三个 build*Title / `colorForUsage` → 启用集 + 顺序 + 实时阈值/配色接缝。
- `SettingsView` body → 由 `@AppStorage` 切换为 `@Bindable` 绑定 `SettingsManager`。
</code_context>

<specifics>
## Specific Ideas

- 升级零行为变化是硬约束：默认顺序/启用集必须复现 v1.0 状态栏外观，升级后用户不应察觉任何指标消失或重排。
- 绝不在状态栏增删 `NSStatusItem`（success criteria #4 明确）：始终在单一合并 item 上条件组合。
- 用户接受全部推荐方案（三个领域 Accept all）。
</specifics>

<deferred>
## Deferred Ideas

- 设置窗口 UI（开关、拖动排序、阈值/配色选择器、紧凑/详细切换的可视控件）→ Phase 9。
- 电池指标键与 `battery` 枚举成员的实际使用 → Phase 7。
- 进程 Top-N 相关持久化（若有）→ Phase 8。
- compact/verbose 模式与现有 displayMode 的统一/取舍最终形态 → Phase 9。
</deferred>
