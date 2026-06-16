---
phase: 06-settings-foundation-live-re-apply-seam
reviewed: 2026-06-17T00:00:00Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - MacStatus/MacStatus/Utils/Metric.swift
  - MacStatus/MacStatus/Utils/SettingsManager.swift
  - MacStatus/MacStatus/Utils/NSColor+Hex.swift
  - MacStatus/MacStatus/Collectors/MetricCollector.swift
  - MacStatus/MacStatus/UI/Views/SettingsView.swift
  - MacStatus/MacStatus/UI/StatusBarManager.swift
  - MacStatus/MacStatus/Readers/CPUReader.swift
findings:
  critical: 2
  warning: 4
  info: 3
  total: 9
status: issues_found
---

# Phase 06: Code Review Report

**Reviewed:** 2026-06-17
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

本阶段实现了 `@MainActor @Observable SettingsManager` 单例、带版本迁移的 UserDefaults 持久化、`.settingsDidChange` 通知广播，以及 MetricCollector / StatusBarManager 的 live re-apply 接缝。整体架构思路清晰，关键路径（JSON 解码容错、hex 解析无崩溃、迁移幂等）设计合理。但发现 2 个 blocker 级问题：一是 NotificationCenter 观察者闭包违反 Swift 6 严格并发隔离规则；二是当 `.battery` metric 被加入 enabledMetrics 时，separator 逻辑产生双分隔符输出。另有 4 个 warning 和 3 个 info 级别问题。

---

## Critical Issues

### CR-01: Swift 6 严格并发违规 — NotificationCenter 观察者闭包直接调用 `@MainActor` 方法

**File:** `MacStatus/MacStatus/Collectors/MetricCollector.swift:118-133`

**Issue:**
`setupSettingsObserver()` 向 `NotificationCenter.addObserver(forName:object:queue:using:)` 传入的闭包在 `queue: .main`（即 `OperationQueue.main`）上执行，但该闭包本身并不具备 `@MainActor` 隔离属性。在 Swift 6 严格并发模式下，从非 `@MainActor` 隔离的 `@Sendable` 闭包内同步调用 `self.reconfigure()` 和 `self.applyNow()`（两者均为 `@MainActor` 实例方法）会产生编译期错误：*"Call to main actor-isolated instance method in a synchronous nonisolated context"*。

对比同文件 `start()` 和 `reconfigure()` 中的 Timer 回调——它们正确地包装在 `Task { @MainActor [weak self] in ... }` 中，而此处的 observer 闭包没有做同样的处理。

**Fix:**
```swift
private func setupSettingsObserver() {
    settingsObserver = NotificationCenter.default.addObserver(
        forName: .settingsDidChange,
        object: nil,
        queue: .main
    ) { [weak self] notification in
        guard let self,
              let changedKeys = notification.userInfo?[SettingsManager.changedKeysUserInfoKey] as? Set<String>
        else { return }
        // 显式 hop 回 MainActor，与 Timer 闭包的处理方式保持一致
        Task { @MainActor [weak self] in
            guard let self else { return }
            if changedKeys.contains("refreshInterval") {
                self.reconfigure()
            } else {
                self.applyNow()
            }
        }
    }
}
```

---

### CR-02: `.battery` metric 出现在 `active` 列表中间时产生双分隔符

**File:** `MacStatus/MacStatus/UI/StatusBarManager.swift:104-120`

**Issue:**
`updateTitle()` 的循环在进入 `switch` **之前**已无条件追加分隔符（`if index > 0 { result.append(sep) }`）。`case .battery: break` 不向 `result` 写入任何内容，但分隔符已被写入。若 `battery` 出现在两个已启用 metric 之间，菜单栏会出现连续两个分隔符；若 `battery` 排在第一位，则结果字符串以分隔符开头。

示例（compact 模式，`active = [cpu, battery, gpu]`）：
```
i=0 cpu   → "C:50%"
i=1 battery → "C:50% " (追加 sep，switch break 无输出)
i=2 gpu   → "C:50%  G:12%" (再追加 sep)
```
最终菜单栏显示 `C:50%  G:12%`（双空格 / 双竖线）。

虽然默认情况下 `.battery` 不在 `enabledMetrics` 中，但 `enabledMetrics` setter 接受任意 `[Metric]` 数组，存在运行期暴露路径。

**Fix:**
将分隔符追加移至 switch 内部，仅在实际生成了内容的 case 中追加：

```swift
var firstSegmentWritten = false
for metric in active {
    let segment: NSAttributedString?
    switch metric {
    case .cpu:     segment = cpuSegment(cpuUsage, mode: mode)
    case .memory:  segment = memSegment(memoryStats, mode: mode)
    case .network: segment = netSegment(networkStats, mode: mode)
    case .gpu:     segment = gpuSegment(gpuStats, mode: mode)
    case .battery: segment = nil  // Phase 7 activates this case
    }
    if let segment {
        if firstSegmentWritten { result.append(sep) }
        result.append(segment)
        firstSegmentWritten = true
    }
}
```

---

## Warnings

### WR-01: `loadAll()` 将阈值 `0.0` 误判为"未设置"并静默覆盖为默认值

**File:** `MacStatus/MacStatus/Utils/SettingsManager.swift:346-356`

**Issue:**
```swift
let rawCpuWarn = defaults.double(forKey: Keys.cpuWarningThreshold)
_cpuWarningThreshold = rawCpuWarn > 0 ? rawCpuWarn : 60.0
```
`UserDefaults.double(forKey:)` 在 key 不存在时返回 `0.0`，`rawValue > 0` 的判断合理地为此提供了保护。但若用户（或测试代码）将阈值合法地设置为 `0.0`（属于 `0...100` 的有效范围），重启后该值会被静默重置为 `60.0`，造成数据丢失。对 `_cpuCriticalThreshold`、`_memoryWarningThreshold`、`_memoryCriticalThreshold` 存在同样问题。

**Fix:**
使用 `defaults.object(forKey:) != nil` 来区分"key 不存在"和"值为 0"：

```swift
if let raw = defaults.object(forKey: Keys.cpuWarningThreshold) as? Double {
    _cpuWarningThreshold = raw
} else {
    _cpuWarningThreshold = 60.0
}
```

---

### WR-02: `launchAtLogin` setter 在 `SMAppService` 调用失败后不回滚状态

**File:** `MacStatus/MacStatus/Utils/SettingsManager.swift:217-229`

**Issue:**
setter 先写入 `_launchAtLogin` 和 `UserDefaults`，再调用 `SMAppService.mainApp.register()` / `unregister()`。若后者抛出异常，setter 仅打印日志，但内存状态和 UserDefaults 已持久化为"成功"状态。下次启动时 `loadAll()` 读到 `launchAtLogin = true`，但系统实际上未完成注册，导致 UI 开关状态与系统真实状态不一致。

**Fix:**
将 SMAppService 调用移至写入之前，或在失败时回滚：

```swift
var launchAtLogin: Bool {
    get { _launchAtLogin }
    set {
        do {
            if newValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            // 仅在系统调用成功后才持久化
            _launchAtLogin = newValue
            defaults.set(newValue, forKey: Keys.launchAtLogin)
            postChange(keys: [Keys.launchAtLogin])
        } catch {
            print("[Settings] launchAtLogin toggle failed: \(error)")
            // 不更新 backing var，UI 绑定会自动回弹到旧值
        }
    }
}
```

---

### WR-03: `NSColor.hexString` 未对 `> 1.0` 的颜色分量做截断

**File:** `MacStatus/MacStatus/Utils/NSColor+Hex.swift:27-29`

**Issue:**
```swift
let r = Int(rgb.redComponent * 255)
```
`usingColorSpace(.sRGB)` 对扩展色域颜色（如 Display P3 原色）转换后，分量值可能超过 `1.0`（如 `1.093`）。`Int(1.093 * 255) = 278`，`String(format: "#%02X%02X%02X", 278, 0, 0)` 输出 `"#11600"`（多于 7 字符），破坏 `customColors` setter 中 `hex.count == 7` 的不变量，同时使 `NSColor(hex:)` 解析失败。

**Fix:**
在转换前对分量做截断：

```swift
var hexString: String {
    guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
    let r = Int((rgb.redComponent   * 255).clamped(to: 0...255))
    let g = Int((rgb.greenComponent * 255).clamped(to: 0...255))
    let b = Int((rgb.blueComponent  * 255).clamped(to: 0...255))
    return String(format: "#%02X%02X%02X", r, g, b)
}
```
（或等价地 `min(255, max(0, Int(...)))`）

---

### WR-04: `customColors` 从 UserDefaults JSON 加载时绕过 setter 的格式校验

**File:** `MacStatus/MacStatus/Utils/SettingsManager.swift:375-379`

**Issue:**
`loadAll()` 将 JSON 解码结果直接赋值给 `_customColors`：
```swift
_customColors = decoded
```
`customColors` setter 过滤掉了非 `#RRGGBB` 格式（不以 `#` 开头或长度不为 7）的条目，但直接加载路径跳过了此过滤。若 UserDefaults 中的数据被外部工具（如 `defaults write` 命令）写入非法格式，这些数据会进入 `_customColors`，之后传递给 `NSColor(hex:)` 时会返回 `nil` 并静默回退，不会崩溃，但会产生不一致的内存状态（内存中存在无效条目而持久化时这些条目本应被过滤）。

**Fix:**
在 `loadAll()` 加载后应用与 setter 相同的过滤逻辑：

```swift
if let data = defaults.data(forKey: Keys.customColors),
   let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
    // 复用 setter 的过滤逻辑，保证内存与磁盘状态一致
    var filtered: [String: [String: String]] = [:]
    for (metric, levels) in decoded {
        let valid = levels.filter { _, hex in hex.hasPrefix("#") && hex.count == 7 }
        if !valid.isEmpty { filtered[metric] = valid }
    }
    _customColors = filtered
} else {
    _customColors = [:]
}
```

---

## Info

### IN-01: `CPUReader.setup()` 重置 `previousInfo` 但不重置 `hasPrevious`

**File:** `MacStatus/MacStatus/Readers/CPUReader.swift:40-42`

**Issue:**
```swift
override func setup() {
    previousInfo = host_cpu_load_info()
}
```
若将来 `MetricCollector` 在重启时再次调用 `cpuReader.setup()`，`hasPrevious` 仍为 `true`，首次 `readValue()` 将以归零的 `previousInfo` 计算 delta，产生异常的高 CPU 读数（全部 ticks 作为 delta 输出）。当前代码路径中 `setup()` 只调用一次，暂无影响，但存在潜在缺陷。

**Fix:**
```swift
override func setup() {
    previousInfo = host_cpu_load_info()
    hasPrevious = false
}
```

---

### IN-02: `SettingsView` 中版本号和"清除历史"按钮均为硬编码 / 未完成状态

**File:** `MacStatus/MacStatus/UI/Views/SettingsView.swift:70-80`

**Issue:**
- 版本字符串 `"v1.0 (M002)"` 硬编码在视图中，未从 `Bundle.main.infoDictionary` 读取，每次版本更新需手动同步。
- "清除历史" 按钮永久 `disabled(true)` 且有 `// TODO: Implement via MetricCollector.purgeAll()` 注释，属于未完成功能对外暴露。

**Fix:**
```swift
// 版本号读取
Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")

// 清除历史按钮暂时隐藏而非显示为禁用状态
// .hidden() 或直接移除，直到 MetricCollector.purgeAll() 实现后再放开
```

---

### IN-03: `defaultWarning(for:)` / `defaultCritical(for:)` 中的 `default` 分支为死代码

**File:** `MacStatus/MacStatus/UI/StatusBarManager.swift:288-305`

**Issue:**
```swift
private func defaultWarning(for metric: Metric) -> Double {
    switch metric {
    case .cpu:    return SettingsManager.shared.cpuWarningThreshold
    case .memory: return SettingsManager.shared.memoryWarningThreshold
    case .gpu:    return 80.0
    default:      return 80.0  // network 和 battery 永远不会调用此方法
    }
}
```
`colorForUsage(_:metric:)` 仅在 `cpuSegment`、`memSegment`、`gpuSegment` 中被调用，而 `netSegment` 直接使用 `.labelColor`，`.battery` case 直接 break。因此 `network` 和 `battery` 永远不会触发 `defaultWarning/defaultCritical`。`default` 分支是无法到达的死代码，并且掩盖了未来新增 metric 时可能漏处理的情况。

**Fix:**
将 `default` 替换为穷举的具名 case，让编译器在新增 metric 时报告未处理路径：

```swift
private func defaultWarning(for metric: Metric) -> Double {
    switch metric {
    case .cpu:     return SettingsManager.shared.cpuWarningThreshold
    case .memory:  return SettingsManager.shared.memoryWarningThreshold
    case .gpu:     return 80.0
    case .network: return 80.0  // 当前不使用；明确列出以便 Phase 7 检查
    case .battery: return 80.0  // 同上
    }
}
```

---

_Reviewed: 2026-06-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
