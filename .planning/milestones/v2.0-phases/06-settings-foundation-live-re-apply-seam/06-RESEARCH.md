# Phase 6: Settings Foundation + Live Re-apply Seam — Research

**Researched:** 2026-06-16
**Domain:** Swift 6 Observation framework · UserDefaults versioned migration · NotificationCenter actor isolation · Timer reschedule · NSColor hex conversion
**Confidence:** HIGH — all key technical questions resolved via SE-0395 (official), Apple docs, and codebase audit

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

1. **Change broadcast:** `NotificationCenter` 单一 `.settingsDidChange` 通知，从每个属性 `didSet` 发出，`userInfo` 携带 `changedKeys: Set<String>`。
2. **Timer 重新调度：** `MetricCollector.reconfigure()` — 失效并按新间隔重建计时器，保留各 reader 的基线（不做 stop/start 全量重启）；`applyNow()` — 把最后一帧缓存样本重推过 `updateUI`。
3. **SettingsManager 改为 `@MainActor @Observable`**，`SettingsView` 改用 `@Bindable` 绑定；每个属性 `didSet` 负责写入 UserDefaults 并发出通知。消除 `SettingsView` 中的 `@AppStorage` 重复真源。
4. **版本化存储：** Int `schemaVersion` 键；init 时跑迁移阶梯；当前键集记为 v1。
5. **新增集合类键：** `metricOrder`/启用集存为 `[String]`；`customThresholds`/`customColors` 各存为 Codable → JSON `Data`；配色存为 `#RRGGBB` 十六进制字符串，读取时解码为 `NSColor`。
6. **`Metric` 枚举**（`cpu, memory, network, gpu`，预留 `battery`），以稳定 string rawValue 作通用 id。默认顺序 `[cpu, memory, network, gpu]`，默认全部启用。`updateTitle` 按启用集/顺序条件组合 segment（丢弃多余分隔符），**绝不**增删 `NSStatusItem`；启用集为空时显示最小占位字形。`colorForUsage` 实时读取自定义阈值/配色。

### Claude's Discretion

- `compact/verbose` 模式切换键：Phase 6 仅保证持久化；与现有 `displayMode` 的最终关系交由 Phase 9 决定。本阶段添加最小持久化键即可。
- `@unchecked Sendable` → `@MainActor @Observable` 转型后，若仍有后台读取需求，按需提供快照/线程安全读取路径，具体由 Claude 在规划/执行时依 Swift 6 严格并发裁定。

### Deferred Ideas (OUT OF SCOPE)

- 设置窗口 UI（开关、拖动排序、阈值/配色选择器）→ Phase 9
- 电池指标键与 `battery` 枚举成员的实际使用 → Phase 7
- 进程 Top-N 相关持久化 → Phase 8
- compact/verbose 与现有 displayMode 的统一形态 → Phase 9
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SET-07 | 用户的所有偏好在重启应用后保持（持久化） | SettingsManager 每个属性 didSet 写 UserDefaults；schemaVersion 迁移阶梯确保旧键安全升级；Codable → JSON Data 编码集合类键 |
| SET-08 | 设置更改即时生效，无需重启应用（实时重应用） | NotificationCenter `.settingsDidChange` + `MetricCollector.reconfigure()`/`applyNow()` + `StatusBarManager` 接缝 |
</phase_requirements>

---

## Summary

本阶段是 v2.0 所有可定制功能的管线层。研究确认三个核心技术点均有可靠的 Swift 6 + AppKit 原生实现路径，无需引入任何外部依赖。

**关键发现一：`@Observable` 与 `didSet` 的兼容性。** SE-0395（Swift 官方 proposal）明确规定：`@Observable` 宏会将带有 `willSet`/`didSet` 的属性展开时，将 observer 保留在私有 `_backing` 存储变量上，公开的计算属性做 `access`/`withMutation` 包装。因此，在 `_backing` 变量上写 `didSet { defaults.set(...); NotificationCenter.default.post(...) }` 是合法且稳定的模式。但实践中更简洁的做法是在公开计算属性的自定义 `set` 中触发副作用（见下文代码示例），因为这让副作用代码与属性声明并列，可读性更好。

**关键发现二：Timer 必须销毁再重建，无法原地修改间隔。** Apple 文档和 Swift Foundation 均不提供修改运行中 `Timer` 的 `timeInterval`。`reconfigure()` 的正确实现是 `timer?.invalidate(); timer = Timer.scheduledTimer(...)`。保留 reader 基线的关键在于：`reconfigure()` **只重建 MetricCollector 的调度 Timer**，不调用任何 reader 的 `setup()` 或 `stop()`；reader 内部存储的 `previousBytes`/`previousTime` 基线因此不受影响。

**关键发现三：NotificationCenter 在 Swift 6 严格并发下的安全用法。** 因为 `SettingsManager`、`MetricCollector`、`StatusBarManager` 三者均为 `@MainActor`，在 `@MainActor` 方法中调用 `NotificationCenter.default.post(...)` 是主线程安全的。使用 `addObserver(forName:object:queue:.main)` 时，回调在主线程上执行，不触发 actor 隔离错误。避免使用 `@objc #selector` 形式的 observer（与 @MainActor 存在已知 bug）；始终使用闭包形式。Swift 6.2 的 `NotificationCenter.MainActorMessage` 更优但要求 macOS 26+，本项目 deployment target 为 macOS 14，不可用。

**主要建议：** 以"公开计算属性的自定义 `set` 触发副作用"模式实现 SettingsManager，配合 `addObserver(forName:queue:.main)` 闭包形式接收通知。

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| 偏好持久化（UserDefaults 读写） | SettingsManager | — | 唯一真源；消费者只读，不直接写 UserDefaults |
| 变更广播 | SettingsManager | — | 属性 set 时 post `.settingsDidChange`；消费者被动接收 |
| 计时重调度 | MetricCollector | — | 拥有 Timer；reconfigure() 失效旧 Timer 重建新 Timer |
| 最后帧缓存与重推 | MetricCollector | — | applyNow() 复用 updateUI(sample:)；需新增 lastSample 属性 |
| 状态栏段条件组合 | StatusBarManager | — | updateTitle 按 metricOrder + enabledMetrics 决定哪些 segment 入串 |
| 实时阈值/配色读取 | StatusBarManager | SettingsManager | colorForUsage 实时从 SettingsManager 读取；SM 为真源 |
| SwiftUI 绑定 | SettingsView | SettingsManager | @Bindable var settings 绑定到 SettingsManager.shared 的属性 |
| 版本化迁移 | SettingsManager.init | — | 在 singleton init() 中同步运行迁移阶梯 |

---

## Standard Stack

### Core（全部为 Apple 原生框架，零外部依赖）

| 框架/类型 | 版本/可用性 | 用途 | 理由 |
|-----------|------------|------|------|
| `Observation` (`@Observable`, `@Bindable`) | macOS 14+ ✓ | SettingsManager 可观察 + SettingsView 双向绑定 | 项目 deployment target = macOS 14，恰好满足最低要求 |
| `Foundation.NotificationCenter` | 全版本 | 设置变更广播（`.settingsDidChange`） | 零依赖、AppKit 惯用；两个消费者均在 @MainActor，天然线程安全 |
| `Foundation.UserDefaults` | 全版本 | 属性持久化 | 已有，文档明确线程安全 |
| `Foundation.JSONEncoder` / `JSONDecoder` | 全版本 | `[String]` 与 Codable 字典 → `Data` 序列化 | 内置，round-trip 可靠 |
| `AppKit.NSColor` | 全版本 | 自定义配色存储/恢复（hex ↔ NSColor） | 内置；user-chosen 绝对颜色，不走语义颜色系统 |
| `Foundation.Timer` | 全版本 | MetricCollector 的统一 tick 调度（reconfigure 需重建） | 已有；Main RunLoop 上调度，@MainActor 安全 |

### 无需引入的库

| 问题 | 不需要自建 | 用内置替代 | 原因 |
|------|-----------|-----------|------|
| Hex ↔ NSColor | 自定义 Hex 解析 | NSColor + Scanner 扩展（30 行） | 零依赖要求；无需第三方 |
| Codable 持久化 | 手写序列化 | JSONEncoder/JSONDecoder + UserDefaults.set(data:) | Swift 标准库，稳定可靠 |
| 变更广播 | Combine / KVO | NotificationCenter | 两个消费者均是 @MainActor，无需跨 actor 流 |

**安装：** 无需安装任何外部包。本阶段全部使用 Apple 原生 SDK。

---

## Package Legitimacy Audit

本阶段不安装任何外部包（项目约束：零外部依赖）。无需运行 slopcheck。

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

---

## Architecture Patterns

### System Architecture Diagram

```
用户改变偏好（Phase 9 UI 写入 / 初始加载）
        │
        ▼
SettingsManager (singleton, @MainActor @Observable)
  ├─ 属性计算 setter
  │    ├─ 写入 UserDefaults（持久化）
  │    └─ NotificationCenter.post(.settingsDidChange, userInfo: [changedKeys: {...}])
        │
        ├──────────────────────────────────────────┐
        ▼                                          ▼
MetricCollector (observer, @MainActor)      StatusBarManager (observer, @MainActor)
  ├─ changedKeys ∋ "refreshInterval"?         ├─ 任何 cosmetic key 变更？
  │    └─ reconfigure()                       │    └─ 读 SM.metricOrder / enabledMetrics
  │         ├─ timer?.invalidate()            │         / customThresholds / customColors
  │         └─ timer = Timer.scheduledTimer   └─ updateTitle(...) 重新组合 NSAttributedString
  └─ 其他 key 变更（cosmetic）?
       └─ applyNow()
            └─ updateUI(sample: lastSample)  ──▶ StatusBarManager.updateTitle(...)
                                                  ▶ PopoverManager.dashboardState update
```

### Recommended Project Structure（变动文件）

```
MacStatus/MacStatus/Utils/
├── SettingsManager.swift      # 改造目标：@MainActor @Observable + 版本化存储 + 新键
MacStatus/MacStatus/Collectors/
├── MetricCollector.swift      # 新增 lastSample 缓存 + reconfigure() + applyNow()
MacStatus/MacStatus/UI/
├── StatusBarManager.swift     # updateTitle 接入 metricOrder/enabledMetrics + colorForUsage 接缝
MacStatus/MacStatus/UI/Views/
├── SettingsView.swift         # 消除 @AppStorage，改用 @Bindable var settings
```

---

### Pattern 1: `@Observable` + `didSet` 副作用（最关键模式）

**What:** SE-0395 规定，`@Observable` 宏展开带有 `willSet`/`didSet` 的属性时，会将 observer 移到私有 `_backing` 变量上，公开计算属性负责 `access`/`withMutation` 包装。等效地，可以手写私有 backing + 公开计算属性，在 setter 中触发副作用。

**When to use:** 每个需要"写 UserDefaults + 发通知"的 SettingsManager 属性。

**推荐实现（手写 backing 风格，副作用在 computed setter 中）：**

```swift
// Source: SE-0395 Observation proposal (swiftlang/swift-evolution/proposals/0395-observability.md)
// 注：@Observable 宏会把 "var refreshInterval: TimeInterval { didSet { ... } }"
// 展开为等价的以下形式；手写更明确：

@MainActor @Observable
final class SettingsManager {
    static let shared = SettingsManager()

    // 私有 backing（被 @Observable 宏追踪）
    private var _refreshInterval: TimeInterval = 2.0

    // 公开计算属性：observation tracking + 副作用
    var refreshInterval: TimeInterval {
        get { _refreshInterval }
        set {
            _refreshInterval = newValue
            UserDefaults.standard.set(newValue, forKey: Keys.refreshInterval)
            NotificationCenter.default.post(
                name: .settingsDidChange,
                object: self,
                userInfo: [Keys.changedKeysUserInfo: Set([Keys.refreshInterval])]
            )
        }
    }

    private init() {
        loadAll()
        runMigrations()
    }
}
```

**为什么不直接写 `didSet` 在公开属性上：**
`@Observable` 宏将公开属性变成计算属性，计算属性不能直接附加 `didSet`。如果写了，编译器会静默忽略（不报错）。正确做法是在私有 backing 变量的 `didSet` 上加逻辑，或者使用手写的计算属性 setter（推荐，副作用代码更清晰）。

[VERIFIED: SE-0395 官方 proposal — https://github.com/swiftlang/swift-evolution/blob/main/proposals/0395-observability.md]

---

### Pattern 2: `@Bindable` 在 SettingsView 中的用法

**What:** `SettingsView` 通过 `@Bindable` 绑定到 `SettingsManager.shared`，消除所有 `@AppStorage` 重复真源。

```swift
// Source: Apple Observation framework, macOS 14+
struct SettingsView: View {
    @Bindable var settings = SettingsManager.shared

    var body: some View {
        Picker("刷新间隔", selection: $settings.refreshInterval) {
            Text("1s").tag(1.0)
            Text("2s").tag(2.0)
            Text("5s").tag(5.0)
        }
        // 每次用户选择，settings.refreshInterval 的 setter 自动触发：
        // 1. UserDefaults 持久化
        // 2. NotificationCenter 广播
    }
}
```

**注意：** `@Bindable` 需要 macOS 14+（项目 deployment target = 14.0，满足）。`SettingsWindowManager.showSettings()` 中 `SettingsView()` 的创建不需要传入参数——`settings` 属性直接引用单例。

[VERIFIED: Apple Observation framework — 可用性 macOS 14+，与项目 MACOSX_DEPLOYMENT_TARGET=14.0 匹配]

---

### Pattern 3: NotificationCenter 在 @MainActor 环境下的安全用法

**What:** 闭包形式 observer，`queue: .main`，Swift 6 严格并发下安全。

```swift
// Source: Apple Foundation docs + Swift 6 forum guidance
// 在 MetricCollector / StatusBarManager 的 init（或 start()）中注册：
private var settingsObserver: NSObjectProtocol?

func setupSettingsObserver() {
    settingsObserver = NotificationCenter.default.addObserver(
        forName: .settingsDidChange,
        object: nil,
        queue: .main          // 回调在主线程，与 @MainActor 兼容
    ) { [weak self] notification in
        guard let self,
              let changedKeys = notification.userInfo?["changedKeys"] as? Set<String>
        else { return }

        if changedKeys.contains("refreshInterval") {
            self.reconfigure()
        } else {
            self.applyNow()
        }
    }
}

deinit {
    if let observer = settingsObserver {
        NotificationCenter.default.removeObserver(observer)
    }
}
```

**Swift 6 注意事项：**
- 避免 `@objc #selector` 形式（与 @MainActor 存在已知编译器 bug — swift#74037）。
- 始终使用闭包形式的 `addObserver(forName:object:queue:using:)`。
- `queue: .main` 保证回调在主线程；由于消费者本身是 `@MainActor`，不会出现 actor 隔离错误。
- Swift 6.2 的 `NotificationCenter.MainActorMessage` 更类型安全，但需要 macOS 26+，本项目不可用。

[ASSUMED — Swift 6 严格并发下 NotificationCenter 闭包行为：基于多个社区源和 Apple 论坛验证，但 Apple 官方文档未为此具体模式提供规范性示例]

---

### Pattern 4: Timer 重新调度（reconfigure()）

**What:** 必须销毁旧 Timer，创建新 Timer。无法原地修改 `timeInterval`。保留 reader 基线的关键是不触碰 reader 内部状态。

```swift
// Source: Apple Foundation Timer docs
// MetricCollector.swift — 新增 reconfigure()
func reconfigure() {
    // 只替换调度 Timer，不触碰 reader 的内部基线
    timer?.invalidate()
    timer = nil

    let interval = SettingsManager.shared.refreshInterval
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
            self?.tick()
        }
    }
    // reader.previousBytes / reader.previousTime 完全不受影响
}
```

**为什么不调用 `stop()` / `start()`：**
`stop()` 会清空 `pendingSamples` 并走全量停止路径；`start()` 会重新调用 `setup()` 并清除各 reader 的基线（`networkReader.previousBytes = nil`），导致下一帧网络 delta 为 0（假值）。`reconfigure()` 只替换 MetricCollector 层面的调度 Timer，reader 层面一律不动。

[VERIFIED: Apple Foundation Timer 文档 — Timer 不提供修改 timeInterval 的 API；invalidate + 重建是唯一路径]

---

### Pattern 5: applyNow()（最后帧缓存重推）

**What:** 新增 `lastSample: MetricSample?` 属性；`applyNow()` 用它调用 `updateUI`。

```swift
// MetricCollector.swift 新增
private var lastSample: MetricSample?

private func tick() {
    // ... 现有采样逻辑 ...
    let sample = MetricSample(...)
    lastSample = sample          // 缓存最后一帧
    updateUI(sample: sample)
}

/// 外观类变更时立即重绘，不等下一个 tick。
func applyNow() {
    guard let sample = lastSample else { return }
    updateUI(sample: sample)
}
```

[ASSUMED — 该模式基于现有 updateUI 结构推断；无需外部文档，属于内部架构决策]

---

### Pattern 6: 版本化 UserDefaults 迁移阶梯

**What:** 在 `SettingsManager.init()` 中读取 `schemaVersion`，按版本号顺序执行迁移闭包，然后写入最新版本号。

```swift
private func runMigrations() {
    let currentVersion = UserDefaults.standard.integer(forKey: Keys.schemaVersion)
    // integer(forKey:) 在 key 不存在时返回 0，即"全新安装"

    if currentVersion < 1 {
        migrateToV1()
    }
    // 未来：if currentVersion < 2 { migrateToV2() }

    UserDefaults.standard.set(1, forKey: Keys.schemaVersion)
}

private func migrateToV1() {
    // 补充 v1 新增键的默认值（仅在未明确写入时设置）
    // 注意：不使用 register(defaults:)，因为已有 v1.0 用户可能已有旧值
    if UserDefaults.standard.object(forKey: Keys.metricOrder) == nil {
        let defaultOrder = [Metric.cpu, .memory, .network, .gpu].map(\.rawValue)
        UserDefaults.standard.set(defaultOrder, forKey: Keys.metricOrder)
    }
    if UserDefaults.standard.object(forKey: Keys.enabledMetrics) == nil {
        let allEnabled = [Metric.cpu, .memory, .network, .gpu].map(\.rawValue)
        UserDefaults.standard.set(allEnabled, forKey: Keys.enabledMetrics)
    }
    // customThresholds / customColors 留空（nil = 使用代码默认值）
}
```

**与现有 sentinel 模式的兼容性：** 当前代码用 `value > 0 ? value : default` 处理未设置键（如 `refreshInterval`）。迁移后，这些键若存在则读取实际值，若不存在则迁移在 v1 中设置默认值，sentinel 模式可以保留或移除皆可。建议在 v1 迁移时为所有数值键（`refreshInterval`, `cpuWarningThreshold` 等）显式写入默认值，从而在属性 getter 中可以安全地直接 `defaults.double(forKey:)` 而无需 sentinel。

[ASSUMED — 迁移阶梯模式基于通用 UserDefaults 迁移实践；无针对此模式的 Apple 官方规范文档]

---

### Pattern 7: Codable 字典 → UserDefaults as JSON Data

**What:** `customThresholds`/`customColors` 为嵌套字典，无法直接存 UserDefaults；先 JSONEncoder 编码为 `Data`，再 `set(data:forKey:)`。

```swift
// 编码示例（customThresholds: [String: [String: Double]]）
func saveCustomThresholds(_ thresholds: [String: [String: Double]]) {
    guard let data = try? JSONEncoder().encode(thresholds) else { return }
    UserDefaults.standard.set(data, forKey: Keys.customThresholds)
}

// 解码示例
func loadCustomThresholds() -> [String: [String: Double]] {
    guard let data = UserDefaults.standard.data(forKey: Keys.customThresholds),
          let decoded = try? JSONDecoder().decode([String: [String: Double]].self, from: data)
    else { return [:] }
    return decoded
}

// customColors: [String: [String: String]]（metricId → [level → "#RRGGBB"]）
// 同等模式，String 值不需要特殊处理
```

**Round-trip 安全性：** `[String: [String: Double]]` 完整符合 `Codable`（Swift 内置）。JSON 键顺序不保证，但解码时无顺序依赖，安全。

[ASSUMED — 基于 Apple Foundation JSONEncoder/JSONDecoder 文档和 Swift Codable 规范；编码细节按标准路径]

---

### Pattern 8: NSColor ↔ `#RRGGBB` 十六进制字符串转换

**What:** 自定义配色以 `#RRGGBB` 字符串存 UserDefaults，读取时解码为 `NSColor`。用户选择的配色是绝对颜色（不走 semantic/dynamic color），因此无需考虑 Dark/Light Mode 自适应——用户主动选择了这个颜色，显示即为所选。

```swift
// NSColor+Hex.swift（新建，约 40 行，零外部依赖）
extension NSColor {
    /// 从 "#RRGGBB" 字符串初始化 NSColor（sRGB 色彩空间）。
    convenience init?(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }
        self.init(
            sRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    /// 转回 "#RRGGBB" 字符串（sRGB，截断到 0-255）。
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
```

**与现有着色逻辑的关系：** 现有 `colorForUsage` 在 normal 时返回 `.labelColor`（semantic，随 dark/light 自适应）。用户自定义配色覆盖的是 warning/critical 槽，使用绝对 `#RRGGBB`。两者共存：normal 级别继续使用 `.labelColor`，其余级别优先读 `SettingsManager.customColors[metricId][level]`，无自定义时回退到硬编码颜色（orange/red）。

[ASSUMED — NSColor hex 转换模式基于社区实现和 Scanner API 文档；无 Apple 官方 hex 扩展示例]

---

### Pattern 9: `Metric` 枚举与 `updateTitle` 启用集/顺序条件组合

**What:** `Metric` 枚举作为稳定 id，`updateTitle` 按顺序 + 启用集条件组合 segment，并动态处理分隔符（不在首/末 segment 前后加多余分隔符）。

```swift
enum Metric: String, CaseIterable, Sendable {
    case cpu      = "cpu"
    case memory   = "memory"
    case network  = "network"
    case gpu      = "gpu"
    case battery  = "battery"  // 预留；Phase 7 激活
}

// StatusBarManager.updateTitle 重构（伪代码）
func updateTitle(cpuUsage: Double?, memoryStats: MemoryStats?, networkStats: NetworkStats?, gpuStats: GPUStats?) {
    guard let button = statusItem.button else { return }
    let settings = SettingsManager.shared
    let order = settings.metricOrder           // [Metric]
    let enabled = settings.enabledMetrics      // Set<Metric>

    let activeMetrics = order.filter { enabled.contains($0) }

    if activeMetrics.isEmpty {
        // 占位字形：避免状态栏完全空白
        button.title = "◆"
        return
    }

    let result = NSMutableAttributedString()
    for (index, metric) in activeMetrics.enumerated() {
        if index > 0 { result.append(separator()) }
        switch metric {
        case .cpu:    result.append(cpuSegment(cpuUsage))
        case .memory: result.append(memSegment(memoryStats))
        case .network:result.append(netSegment(networkStats))
        case .gpu:    result.append(gpuSegment(gpuStats))
        case .battery:break  // Phase 7 激活
        }
    }
    button.attributedTitle = result
}
```

**零行为变化保证：** 默认 `metricOrder = [.cpu, .memory, .network, .gpu]`，全部 enabled。现有 compact mode 顺序是 C G M N（GPU 在 Memory 前），需检查 `buildCompactTitle` 的当前顺序并在默认值中复现，或在 Phase 6 中统一为文档顺序（`buildFullTitle` 的顺序 C M N G）。**这是一个需要确认的细节**（见 Open Questions）。

[ASSUMED — 枚举设计和条件组合模式基于项目架构推断；无需外部文档]

---

### Pattern 10: Swift 6 中 SettingsManager 的并发性分析

**关键发现：** 检查 `MetricCollector.start()` 和 `tick()` 的读取路径：

```swift
// MetricCollector.swift:62
let interval = SettingsManager.shared.refreshInterval  // 在 @MainActor start() 中读取
```

`MetricCollector` 是 `@MainActor`，因此它读 `SettingsManager.shared` 时已在 main actor 上。**无后台读取路径**。`StatusBarManager` 同样是 `@MainActor`，读 `SettingsManager.shared.cpuWarningThreshold` 也在主线程。

结论：将 `SettingsManager` 改为 `@MainActor @Observable` 后，移除 `@unchecked Sendable` 是安全的。**不需要快照 struct 或 `nonisolated` 访问器**，因为目前不存在后台读取路径。Swift 6 严格并发将自然强制任何意外的后台访问为编译错误，届时按需处理。

[VERIFIED: 代码库审计 — MetricCollector, StatusBarManager, AppDelegate 三处 SettingsManager 访问均在 @MainActor 上下文中]

---

### Anti-Patterns to Avoid

- **在 `@Observable` 公开属性上直接写 `didSet`：** 宏展开后这是计算属性，`didSet` 被静默忽略（无编译错误）。使用手写 computed setter 或在 `_backing` 变量上写 `didSet`。
- **使用 `@objc #selector` 形式注册 NotificationCenter observer：** 与 `@MainActor` 类存在已知崩溃 bug（swift#74037）。始终使用闭包形式。
- **在 `reconfigure()` 中调用 `stop()` / `start()`：** 会清除 NetworkReader 的 `previousBytes` 基线，下一帧网络 delta 为 0（假值）。只替换 `timer`。
- **在 `reconfigure()` 之外触碰 reader 的 `setup()` 方法：** `setup()` 会重置基线（`previousBytes = nil`），相当于重启 reader。
- **直接存 `[String: Any]` 到 UserDefaults：** `customThresholds`/`customColors` 是嵌套字典，须先 JSONEncoder → Data 再存；直接存 `[String: Any]` 在含嵌套 Dictionary 时不可靠（plist 序列化限制）。
- **在 `updateTitle` 中增删 `NSStatusItem`：** 严格禁止（项目硬约束）。始终在单一 `statusItem` 上条件组合 `NSAttributedString`。
- **将 `loadAll()` 与 `runMigrations()` 顺序颠倒：** 迁移须在加载属性前完成（或迁移内直接写 UserDefaults 而不经过属性 setter，避免触发通知）。

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 属性变更追踪 | 手动 KVO / Combine @Published | `@Observable` + 手写 computed setter | macOS 14+ 已有原生方案；KVO 与 Swift 6 严格并发摩擦 |
| 颜色十六进制转换 | 第三方库（HexColors 等） | NSColor 扩展（40 行，见 Pattern 8） | 零依赖项目约束；实现极简，无需库 |
| 变更广播总线 | Combine PassthroughSubject | NotificationCenter | 两个消费者均 @MainActor，NotificationCenter 已足够；Combine 无附加价值 |
| 类型安全通知（Swift 6.2 风格） | NotificationCenter.MainActorMessage | 继续用 String-keyed userInfo + `as? Set<String>` | 需 macOS 26+，项目 deployment target 14.0 不满足 |

---

## Common Pitfalls

### Pitfall 1: `@Observable` 属性上的 `didSet` 被静默忽略

**What goes wrong:** 开发者写 `var refreshInterval: TimeInterval = 2.0 { didSet { defaults.set(...) } }`，Swift 编译通过，但 `didSet` 从不执行——`@Observable` 宏已将其变为计算属性，计算属性不支持 observer 附加语法（宏生成的 `_backing` 变量上有内部 observer，但自定义的公开 `didSet` 被丢弃）。
**Why it happens:** `@Observable` 宏的展开产生计算属性，而计算属性的 `didSet` 在 Swift 中是无效语法——但宏展开后编译器不报错，只是忽略。
**How to avoid:** 使用手写 computed setter（见 Pattern 1）或将副作用放在私有 `_backing` 变量的 `didSet` 中。
**Warning signs:** UserDefaults 中数值未更新，或 NotificationCenter 通知未发出——断点证实 setter 被调用但 `didSet` 未执行。

### Pitfall 2: `reconfigure()` 调用 `stop()` 破坏网络基线

**What goes wrong:** `MetricCollector.reconfigure()` 调用了 `stop()`，后者让 `pendingSamples` 被 flush，但更严重的是若 reader 有 `stop()` 路径（TimerReader.stop() 取消 DispatchSource），下次 `start()` 时 `NetworkReader.previousBytes` 被 `setup()` 重置为 `nil`，导致首帧网络速率报 0。
**Why it happens:** `stop()`/`start()` 是全量生命周期切换，而 `reconfigure()` 只应替换调度层。
**How to avoid:** `reconfigure()` 只做 `timer?.invalidate(); timer = Timer.scheduledTimer(...)`，一律不调用 reader 方法（见 Pattern 4）。注意 MetricCollector 的 readers（cpuReader, networkReader 等）是独立的、用自己的 `readValue()` 方式调用——不经过 TimerReader 的 DispatchSourceTimer，所以无需担心 TimerReader.stop()；但 `MetricCollector.stop()` 内有 `pendingSamples` flush，也不应调用。

### Pitfall 3: `SettingsView` 中旧 `@AppStorage` 残留

**What goes wrong:** 部分属性改为 `@Bindable` 绑定，但遗漏了某些键（如 `launchAtLogin`），导致 `SettingsView` 同时有两个真源——`@AppStorage` 直写 UserDefaults，`SettingsManager` 也写同一键，互相干扰，且 `@AppStorage` 不会触发 `.settingsDidChange` 通知。
**Why it happens:** `launchAtLogin` 目前在 `SettingsView` 中有 `@AppStorage`，但 Phase 6 要求 SettingsManager 成为唯一真源。
**How to avoid:** 将 `launchAtLogin` 键也迁移到 SettingsManager；从 SettingsView 彻底删除所有 `@AppStorage` 声明。

### Pitfall 4: schemaVersion 迁移在属性 setter 中触发通知

**What goes wrong:** 如果 `migrateToV1()` 通过属性 setter（如 `self.metricOrder = [...]`）写入默认值，会触发 `.settingsDidChange` 通知。此时 MetricCollector 可能尚未启动，observer 尚未注册，通知被丢弃——但这是在 init 期间，逻辑顺序本应如此。潜在问题是如果 AppDelegate 在 MetricCollector.start() 之前调用了 SettingsManager.shared（单例懒初始化可能在任意时刻触发）。
**Why it happens:** 单例 init 与 AppDelegate 启动序列的交织。
**How to avoid:** 在迁移内直接调用 `UserDefaults.standard.set(...)` 而非通过属性 setter，避免在 init 期间发出通知。迁移完成后属性 getter 正常读取已迁移的值。

### Pitfall 5: `Metric.battery` 被错误地加入默认启用集

**What goes wrong:** 如果默认 `enabledMetrics` 包含 `.battery`，而 Phase 7 尚未实现 BatteryReader，`updateTitle` 的 switch 中 `case .battery: break` 会静默跳过，但 Phase 6 测试可能不会察觉——直到 Phase 9 设置界面显示 "电池" 为已启用状态时用户感到困惑。
**Why it happens:** 枚举预留成员与默认启用集不同步。
**How to avoid:** 默认 `enabledMetrics` 只包含 `[.cpu, .memory, .network, .gpu]`，不含 `.battery`。

### Pitfall 6: compact mode 中 segment 顺序与 v1.0 不一致

**What goes wrong:** 现有 `buildCompactTitle` 的顺序是 C G M N（CPU, GPU, Memory, Network），而 `buildFullTitle` 是 C M N G。如果 `metricOrder` 默认值使用 Full 顺序 `[cpu, memory, network, gpu]`，则 compact mode 下 GPU 从第二位移到最后，升级后 v1.0 用户会察觉顺序变化（违反"升级零行为变化"约束）。
**Why it happens:** 两套 build*Title 函数有不同的内部顺序，迁移到统一的 `metricOrder` 必须选定其一。
**How to avoid:** 以 compact mode 的现有顺序 `[cpu, gpu, memory, network]` 作为默认 `metricOrder`（因为 compact 是当前默认 displayMode）；或在 Phase 6 中将两种模式统一为同一顺序（推荐，但需确认用户是否可接受 full mode 的 GPU 位置调整）。**见 Open Questions #1。**

---

## Code Examples

### Notification Name 定义

```swift
// Source: Apple Foundation NotificationCenter docs
extension Notification.Name {
    static let settingsDidChange = Notification.Name("com.macstatus.settingsDidChange")
}

// userInfo keys
extension SettingsManager {
    static let changedKeysUserInfoKey = "changedKeys"
}
```

### SettingsManager init + loadAll + migration 骨架

```swift
@MainActor @Observable
final class SettingsManager {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard

    // --- Backing storage (所有属性用 @ObservationIgnored 私有 backing 或直接 computed) ---
    // refreshInterval, displayMode, metricOrder, enabledMetrics, customThresholds, customColors...

    private init() {
        // 1. 先跑迁移（直接写 UserDefaults，不走 setter）
        runMigrations()
        // 2. 再从 UserDefaults 加载到私有 backing（只读，不发通知）
        loadAll()
    }

    private func loadAll() {
        // 把 UserDefaults 值赋给私有 _backing 变量（不经过 setter）
        // 避免 init 期间触发通知
    }
}
```

### colorForUsage 实时阈值/配色接缝

```swift
// StatusBarManager.swift — colorForUsage 改造
private func colorForUsage(_ percent: Double, metric: Metric) -> NSColor {
    let settings = SettingsManager.shared

    // 读取自定义阈值（若无则用硬编码默认）
    let warningThreshold = settings.customThresholds[metric.rawValue]?["warning"]
        ?? defaultWarning(for: metric)
    let criticalThreshold = settings.customThresholds[metric.rawValue]?["critical"]
        ?? defaultCritical(for: metric)

    // 读取自定义颜色（若无则用 semantic 颜色）
    if percent >= criticalThreshold {
        if let hex = settings.customColors[metric.rawValue]?["critical"],
           let color = NSColor(hex: hex) {
            return color
        }
        return .systemRed
    } else if percent >= warningThreshold {
        if let hex = settings.customColors[metric.rawValue]?["warning"],
           let color = NSColor(hex: hex) {
            return color
        }
        return .systemOrange
    }
    return .labelColor  // semantic，随 dark/light 自适应
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `@ObservableObject` + `@Published` | `@Observable` macro + `@Bindable` | macOS 14 / iOS 17（2023） | 无 Combine 依赖；更细粒度重绘（只刷新读取了变更属性的 View） |
| `@AppStorage` 分散于各 View | 集中 SettingsManager + `@Bindable` | — | 单一真源；变更可触发业务逻辑 |
| `@unchecked Sendable` 绕过 Swift 6 检查 | `@MainActor` 隔离（所有访问已在主线程） | Swift 6（2024） | 编译器强制 actor 边界；移除 `@unchecked Sendable` |
| `NotificationCenter.MainActorMessage`（Swift 6.2） | 不可用（需 macOS 26+） | Swift 6.2 / macOS 26 | 本项目暂不采用 |

**Deprecated/outdated:**
- `@unchecked Sendable` on SettingsManager：应在本阶段移除，改为 `@MainActor` 隔离。
- `@AppStorage` in SettingsView：应完全删除，统一走 SettingsManager。

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | NotificationCenter 闭包形式 observer (`queue: .main`) 在 Swift 6 严格并发下不产生编译错误 | Pattern 3 | 若产生错误，需改为 `MainActor.assumeIsolated` 包装或 `Task { @MainActor in }` 跳转 |
| A2 | 迁移阶梯中直接写 `UserDefaults.standard.set(...)` 不触发属性 setter，因此不发通知 | Pattern 6 | 若实现为通过 setter 写入，init 期间通知被发出但无 observer 监听，影响低 |
| A3 | compact mode 的当前顺序是 C G M N（从 buildCompactTitle 代码读出） | Pitfall 6 + Open Questions | 若用户实际体验与代码不符，默认顺序需再校准 |
| A4 | NSColor(sRed:green:blue:alpha:) 在 macOS 14 中稳定存在 | Pattern 8 | 极低风险；NSColor sRGB 初始化器在 macOS 10.7+ 存在 |
| A5 | customThresholds / customColors 在 Phase 6 仅建立数据结构，不提供 UI 编辑（Phase 9 交付） | 全文 | Phase 6 实现需包含数据加载/保存路径，即使无 UI 驱动写入也需有合理默认值 |

---

## Open Questions

1. **compact mode 默认顺序：C G M N 还是 C M N G？**
   - What we know: `buildFullTitle` 顺序是 C M N G；`buildCompactTitle` 代码顺序是 C G M N。当前默认 displayMode 是 compact（`SettingsManager.displayMode` getter 默认 `.compact`）。
   - What's unclear: 统一到单一 `metricOrder` 后应使用哪个顺序？若用 C M N G，compact 用户会发现 GPU 顺序变了（违反零行为变化）；若用 C G M N，full mode 用户 GPU 移位。
   - Recommendation: 以 compact 当前顺序 `[.cpu, .gpu, .memory, .network]` 作为默认 `metricOrder`，因为 compact 是实际默认模式。或者在 Phase 6 规划中加入一个明确决策任务。

2. **`launchAtLogin` 键是否纳入 SettingsManager？**
   - What we know: 现有 SettingsView 有 `@AppStorage("launchAtLogin")`，Phase 6 要求彻底消除 @AppStorage。
   - What's unclear: `launchAtLogin` 写入会触发 `SMAppService` API 调用，不是纯粹的 UserDefaults 持久化；是否在 SettingsManager 的 setter 中触发 `SMAppService.mainApp.register()` 会引入副作用？
   - Recommendation: 将 `launchAtLogin` 纳入 SettingsManager，在 setter 中封装 SMAppService 调用（移植现有 `setLaunchAtLogin` 逻辑）。保持 SettingsView 使用 `@Bindable`，无需 onChange 额外处理。

3. **`MetricCollector` 的 `pendingSamples` 在 `reconfigure()` 时应该 flush 吗？**
   - What we know: `reconfigure()` 不应调用 `stop()`，但停止旧 timer 后新 timer 开始前可能有一个间隔。`pendingSamples` 会在下一次 tick 时正常累积。
   - Recommendation: 不 flush（保持简单）。`reconfigure()` 只替换 timer，`pendingSamples` 继续积累，下次 tick 自然处理。

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode / Swift 6 toolchain | 编译 | ✓ | Swift 6.3.2 (Xcode 26) | — |
| macOS SDK (Observation, Foundation, AppKit) | @Observable, NotificationCenter, NSColor | ✓ | macOS 14+ APIs ✓ | — |
| UserDefaults | 持久化 | ✓ | 内置 | — |

**Missing dependencies with no fallback:** None。本阶段全部使用已安装工具链内的原生框架。

---

## Security Domain

本阶段 `security_enforcement` 未显式设为 false，但评估后认为适用范围极窄：

- **V5 Input Validation:** 自定义阈值数值应在 setter 中 clamp 到合理范围（0.0...100.0），防止非法值写入（例如 Phase 9 UI 输入错误类型）。本阶段即便无 UI，数据结构层面应有边界。
- **其他 ASVS 类别（V2 Authentication, V3 Session, V4 Access Control, V6 Cryptography）：** 不适用——本阶段仅涉及本地 UserDefaults 读写，无网络、无认证、无加密需求。

---

## Sources

### Primary (HIGH confidence)
- [SE-0395 Observability proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0395-observability.md) — `@Observable` 宏展开规则，`willSet`/`didSet` 与 backing 变量的关系
- [Apple Foundation Timer docs](https://developer.apple.com/documentation/foundation/timer) — Timer 不可原地修改 timeInterval；invalidate + 重建是唯一路径
- [Malcolm Hall: @Observable and didSet](https://www.malcolmhall.com/2024/11/21/observable-and-didset/) — 手写 backing + computed setter 模式的具体验证
- [Swift Forums: Property Observers with Observation](https://forums.swift.org/t/using-property-observers-with-observation/68039) — SE-0395 指定 `_backing` 变量保留 observer 的 forum 确认
- Apple macOS 14 SDK — `@Observable`, `@Bindable` 可用性确认 (macOS 14+, Xcode 15+)

### Secondary (MEDIUM confidence)
- [Fatbobman: Mastering Observation](https://fatbobman.com/en/posts/mastering-observation/) — `@Observable` 宏内部展开细节
- [Fatbobman: NotificationCenter.Message Swift 6.2](https://fatbobman.com/en/posts/notificationcentermessage-a-new-concurrency-safe-notification-experience-in-swift-62/) — Swift 6.2 API 需 macOS 26+ 确认
- [Swift swift#74037: @objc @MainActor selector crashes](https://github.com/swiftlang/swift/issues/74037) — @objc selector + @MainActor 的已知 bug 证据
- 代码库审计（MetricCollector, StatusBarManager, AppDelegate）— 确认所有 SettingsManager 访问路径均在 @MainActor 上

### Tertiary (LOW confidence, flagged)
- WebSearch 结果关于 NotificationCenter 闭包 observer 在 Swift 6 下的行为——多个社区源收敛，但无 Apple 规范性文档直接声明
- WebSearch 结果关于 UserDefaults schemaVersion 迁移阶梯模式——通用实践，无 Apple 官方指南

---

## Metadata

**Confidence breakdown:**
- Standard Stack: HIGH — @Observable/macOS 14 可用性经 Apple SDK 验证；Timer 行为经官方文档确认
- Architecture: HIGH — 代码库充分审计；所有 actor 访问路径已确认
- Core Pattern (@Observable + didSet): HIGH — SE-0395 原文明确规定展开行为
- NotificationCenter Swift 6 safety: MEDIUM — 闭包形式 `queue:.main` 模式有社区验证，但无官方规范性陈述
- Pitfalls: HIGH — 大多数来自直接代码审计和官方文档

**Research date:** 2026-06-16
**Valid until:** 2026-07-16（Observation 框架和 Swift 6 并发规则已稳定，30 天内不预期变化）

---

## RESEARCH COMPLETE
