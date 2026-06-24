import Foundation
import ServiceManagement

// MARK: - Notification Name

extension Notification.Name {
    /// Posted by SettingsManager whenever one or more settings properties change.
    /// `userInfo` contains `[SettingsManager.changedKeysUserInfoKey: Set<String>]`
    /// identifying which UserDefaults keys changed.
    static let settingsDidChange = Notification.Name("com.macstatus.settingsDidChange")
}

// MARK: - Display Mode

/// How the menu bar title displays metric data.
enum DisplayMode: String, CaseIterable, Sendable {
    /// Full text: `CPU: 23% | MEM: 67% OK | NET: ↑0B/s ↓1.2KB/s | GPU: 12%`
    case full
    /// Compact: `C:23% G:0% M:67% N:↑0↓1.2K`
    case compact
    /// Percentage only: `23% | 67% | -- | 12%`
    case percentage
}

// MARK: - Display Unit

/// Unit system for byte values (network, memory).
enum DisplayUnit: String, CaseIterable, Sendable {
    case auto    // Automatic based on magnitude
    case bytes
    case kilobytes
    case megabytes
    case gigabytes
}

// MARK: - Settings Manager

/// Single source of truth for all MacStatus user preferences.
///
/// `@MainActor @Observable` — all access must be on the main actor.
/// Properties use private backing vars + public computed get/set so the
/// `@Observable` macro can track access properly; setters write UserDefaults
/// and broadcast `.settingsDidChange`.
///
/// Init order:
///   1. `runMigrations()` — writes defaults directly to UserDefaults (no setter calls, no notifications)
///   2. `loadAll()` — populates `_backing` vars from UserDefaults (no setter calls, no notifications)
@MainActor @Observable
final class SettingsManager {

    // MARK: - Singleton

    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    // MARK: - Changed Keys User Info Key

    /// Key for the `Set<String>` of changed UserDefaults keys in `.settingsDidChange` userInfo.
    static let changedKeysUserInfoKey = "changedKeys"

    // MARK: - Keys

    private enum Keys {
        // Existing v1.0 keys
        static let refreshInterval         = "refreshInterval"
        static let displayMode             = "displayMode"
        static let displayUnit             = "displayUnit"
        static let showIcons               = "showIcons"
        static let cpuWarningThreshold     = "cpuWarningThreshold"
        static let cpuCriticalThreshold    = "cpuCriticalThreshold"
        static let memoryWarningThreshold  = "memoryWarningThreshold"
        static let memoryCriticalThreshold = "memoryCriticalThreshold"

        // Phase 6 new keys
        static let schemaVersion    = "schemaVersion"
        static let metricOrder      = "metricOrder"
        static let enabledMetrics   = "enabledMetrics"
        static let customThresholds = "customThresholds"
        static let customColors     = "customColors"
        static let launchAtLogin    = "launchAtLogin"

        // Phase 9 new keys
        static let showBatterySection = "showBatterySection"
        static let showProcessSection = "showProcessSection"
        static let showThermalSection = "showThermalSection"
    }

    // MARK: - Init

    private init() {
        // Step 1: migrate (direct UserDefaults writes, no setter calls, no notifications)
        runMigrations()
        // Step 2: load all backing vars from UserDefaults (no setter calls, no notifications)
        loadAll()
    }

    // MARK: - Backing Storage

    @ObservationIgnored private var _refreshInterval: TimeInterval = 2.0
    @ObservationIgnored private var _displayMode: DisplayMode = .compact
    @ObservationIgnored private var _displayUnit: DisplayUnit = .auto
    @ObservationIgnored private var _showIcons: Bool = false
    @ObservationIgnored private var _cpuWarningThreshold: Double = 60.0
    @ObservationIgnored private var _cpuCriticalThreshold: Double = 80.0
    @ObservationIgnored private var _memoryWarningThreshold: Double = 60.0
    @ObservationIgnored private var _memoryCriticalThreshold: Double = 80.0
    @ObservationIgnored private var _metricOrder: [Metric] = [.cpu, .gpu, .memory, .network]
    @ObservationIgnored private var _enabledMetrics: [Metric] = [.cpu, .gpu, .memory, .network]
    @ObservationIgnored private var _launchAtLogin: Bool = false
    @ObservationIgnored private var _customThresholds: [String: [String: Double]] = [:]
    @ObservationIgnored private var _customColors: [String: [String: String]] = [:]
    @ObservationIgnored private var _showBatterySection: Bool = true
    @ObservationIgnored private var _showProcessSection: Bool = true
    @ObservationIgnored private var _showThermalSection: Bool = true

    // MARK: - Public Properties

    /// Polling refresh interval in seconds. Defaults to 2.0.
    var refreshInterval: TimeInterval {
        get {
            access(keyPath: \.refreshInterval)
            return _refreshInterval
        }
        set {
            withMutation(keyPath: \.refreshInterval) { _refreshInterval = newValue }
            defaults.set(newValue, forKey: Keys.refreshInterval)
            postChange(keys: [Keys.refreshInterval])
        }
    }

    /// Menu bar display mode. Defaults to .compact.
    var displayMode: DisplayMode {
        get {
            access(keyPath: \.displayMode)
            return _displayMode
        }
        set {
            withMutation(keyPath: \.displayMode) { _displayMode = newValue }
            defaults.set(newValue.rawValue, forKey: Keys.displayMode)
            postChange(keys: [Keys.displayMode])
        }
    }

    /// Byte display unit. Defaults to .auto.
    var displayUnit: DisplayUnit {
        get {
            access(keyPath: \.displayUnit)
            return _displayUnit
        }
        set {
            withMutation(keyPath: \.displayUnit) { _displayUnit = newValue }
            defaults.set(newValue.rawValue, forKey: Keys.displayUnit)
            postChange(keys: [Keys.displayUnit])
        }
    }

    /// Whether to show SF Symbol icons in the menu bar. Defaults to false.
    var showIcons: Bool {
        get {
            access(keyPath: \.showIcons)
            return _showIcons
        }
        set {
            withMutation(keyPath: \.showIcons) { _showIcons = newValue }
            defaults.set(newValue, forKey: Keys.showIcons)
            postChange(keys: [Keys.showIcons])
        }
    }

    // MARK: - Alert Thresholds (clamped 0...100)

    var cpuWarningThreshold: Double {
        get {
            access(keyPath: \.cpuWarningThreshold)
            return _cpuWarningThreshold
        }
        set {
            let clamped = max(0, min(100, newValue))
            withMutation(keyPath: \.cpuWarningThreshold) { _cpuWarningThreshold = clamped }
            defaults.set(clamped, forKey: Keys.cpuWarningThreshold)
            postChange(keys: [Keys.cpuWarningThreshold])
        }
    }

    var cpuCriticalThreshold: Double {
        get {
            access(keyPath: \.cpuCriticalThreshold)
            return _cpuCriticalThreshold
        }
        set {
            let clamped = max(0, min(100, newValue))
            withMutation(keyPath: \.cpuCriticalThreshold) { _cpuCriticalThreshold = clamped }
            defaults.set(clamped, forKey: Keys.cpuCriticalThreshold)
            postChange(keys: [Keys.cpuCriticalThreshold])
        }
    }

    var memoryWarningThreshold: Double {
        get {
            access(keyPath: \.memoryWarningThreshold)
            return _memoryWarningThreshold
        }
        set {
            let clamped = max(0, min(100, newValue))
            withMutation(keyPath: \.memoryWarningThreshold) { _memoryWarningThreshold = clamped }
            defaults.set(clamped, forKey: Keys.memoryWarningThreshold)
            postChange(keys: [Keys.memoryWarningThreshold])
        }
    }

    var memoryCriticalThreshold: Double {
        get {
            access(keyPath: \.memoryCriticalThreshold)
            return _memoryCriticalThreshold
        }
        set {
            let clamped = max(0, min(100, newValue))
            withMutation(keyPath: \.memoryCriticalThreshold) { _memoryCriticalThreshold = clamped }
            defaults.set(clamped, forKey: Keys.memoryCriticalThreshold)
            postChange(keys: [Keys.memoryCriticalThreshold])
        }
    }

    // MARK: - Metric Order & Enabled Set

    /// Display order of metrics. Default matches v1.0 compact mode: [cpu, gpu, memory, network].
    var metricOrder: [Metric] {
        get {
            access(keyPath: \.metricOrder)
            return _metricOrder
        }
        set {
            withMutation(keyPath: \.metricOrder) { _metricOrder = newValue }
            defaults.set(newValue.map(\.rawValue), forKey: Keys.metricOrder)
            postChange(keys: [Keys.metricOrder])
        }
    }

    /// Set of enabled metrics (stored as [Metric] to preserve ordering for future use).
    /// Default: all four active metrics — does NOT include .battery (Phase 7).
    var enabledMetrics: [Metric] {
        get {
            access(keyPath: \.enabledMetrics)
            return _enabledMetrics
        }
        set {
            withMutation(keyPath: \.enabledMetrics) { _enabledMetrics = newValue }
            defaults.set(newValue.map(\.rawValue), forKey: Keys.enabledMetrics)
            postChange(keys: [Keys.enabledMetrics])
        }
    }

    // MARK: - Launch at Login

    /// Mirrors system login item registration. Setter triggers SMAppService side-effect.
    /// SMAppService 调用成功后才持久化；失败时不写 UserDefaults 也不更新 backing var，
    /// 使 UI 绑定自动回弹到旧值，保持 UI 与系统真实状态一致。
    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return _launchAtLogin
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                // 仅在系统调用成功后才持久化
                withMutation(keyPath: \.launchAtLogin) { _launchAtLogin = newValue }
                defaults.set(newValue, forKey: Keys.launchAtLogin)
                postChange(keys: [Keys.launchAtLogin])
            } catch {
                print("[Settings] launchAtLogin toggle failed: \(error)")
                // 不更新 backing var，UI 绑定会自动回弹到旧值
            }
        }
    }

    // MARK: - Popover Section Visibility

    /// Whether to show the battery section in the popover. Defaults to true.
    var showBatterySection: Bool {
        get {
            access(keyPath: \.showBatterySection)
            return _showBatterySection
        }
        set {
            withMutation(keyPath: \.showBatterySection) { _showBatterySection = newValue }
            defaults.set(newValue, forKey: Keys.showBatterySection)
            postChange(keys: [Keys.showBatterySection])
        }
    }

    /// Whether to show the process section in the popover. Defaults to true.
    var showProcessSection: Bool {
        get {
            access(keyPath: \.showProcessSection)
            return _showProcessSection
        }
        set {
            withMutation(keyPath: \.showProcessSection) { _showProcessSection = newValue }
            defaults.set(newValue, forKey: Keys.showProcessSection)
            postChange(keys: [Keys.showProcessSection])
        }
    }

    /// Whether to show the thermal section in the popover. Defaults to true.
    var showThermalSection: Bool {
        get {
            access(keyPath: \.showThermalSection)
            return _showThermalSection
        }
        set {
            withMutation(keyPath: \.showThermalSection) { _showThermalSection = newValue }
            defaults.set(newValue, forKey: Keys.showThermalSection)
            postChange(keys: [Keys.showThermalSection])
        }
    }

    // MARK: - Custom Thresholds & Colors

    /// Per-metric custom thresholds: `[metricRawValue: ["warning": 60.0, "critical": 80.0]]`.
    /// Values clamped to 0...100 on write. Encoded as JSON Data in UserDefaults.
    var customThresholds: [String: [String: Double]] {
        get {
            access(keyPath: \.customThresholds)
            return _customThresholds
        }
        set {
            // Clamp all threshold values to 0...100
            var clamped: [String: [String: Double]] = [:]
            for (metric, levels) in newValue {
                clamped[metric] = levels.mapValues { max(0.0, min(100.0, $0)) }
            }
            withMutation(keyPath: \.customThresholds) { _customThresholds = clamped }
            if let data = try? JSONEncoder().encode(clamped) {
                defaults.set(data, forKey: Keys.customThresholds)
            }
            postChange(keys: [Keys.customThresholds])
        }
    }

    /// Per-metric custom colors: `[metricRawValue: ["warning": "#FF6600", "critical": "#FF0000"]]`.
    /// Values must be "#RRGGBB" format (7 chars, # prefix); invalid entries are silently dropped.
    /// Encoded as JSON Data in UserDefaults.
    var customColors: [String: [String: String]] {
        get {
            access(keyPath: \.customColors)
            return _customColors
        }
        set {
            // Filter invalid hex strings: must start with "#" and be exactly 7 characters
            var filtered: [String: [String: String]] = [:]
            for (metric, levels) in newValue {
                let validLevels = levels.filter { _, hex in
                    hex.hasPrefix("#") && hex.count == 7
                }
                if !validLevels.isEmpty {
                    filtered[metric] = validLevels
                }
            }
            withMutation(keyPath: \.customColors) { _customColors = filtered }
            if let data = try? JSONEncoder().encode(filtered) {
                defaults.set(data, forKey: Keys.customColors)
            }
            postChange(keys: [Keys.customColors])
        }
    }

    // MARK: - Migration

    private func runMigrations() {
        let current = defaults.integer(forKey: Keys.schemaVersion)
        // integer(forKey:) returns 0 when key absent — interpreted as "fresh install"
        if current < 1 {
            migrateToV1()
        }
        defaults.set(1, forKey: Keys.schemaVersion)
    }

    /// Write v1 default values directly to UserDefaults — NOT through property setters.
    /// This prevents `.settingsDidChange` notifications during init.
    private func migrateToV1() {
        if defaults.object(forKey: Keys.metricOrder) == nil {
            // Default order matches v1.0 compact mode layout: C G M N
            defaults.set([Metric.cpu, .gpu, .memory, .network].map(\.rawValue),
                         forKey: Keys.metricOrder)
        }
        if defaults.object(forKey: Keys.enabledMetrics) == nil {
            defaults.set([Metric.cpu, .gpu, .memory, .network].map(\.rawValue),
                         forKey: Keys.enabledMetrics)
        }
        if defaults.object(forKey: Keys.refreshInterval) == nil {
            defaults.set(2.0, forKey: Keys.refreshInterval)
        }
        if defaults.object(forKey: Keys.displayMode) == nil {
            defaults.set(DisplayMode.compact.rawValue, forKey: Keys.displayMode)
        }
        if defaults.object(forKey: Keys.displayUnit) == nil {
            defaults.set(DisplayUnit.auto.rawValue, forKey: Keys.displayUnit)
        }
        if defaults.object(forKey: Keys.showIcons) == nil {
            defaults.set(false, forKey: Keys.showIcons)
        }
        if defaults.object(forKey: Keys.cpuWarningThreshold) == nil {
            defaults.set(60.0, forKey: Keys.cpuWarningThreshold)
        }
        if defaults.object(forKey: Keys.cpuCriticalThreshold) == nil {
            defaults.set(80.0, forKey: Keys.cpuCriticalThreshold)
        }
        if defaults.object(forKey: Keys.memoryWarningThreshold) == nil {
            defaults.set(60.0, forKey: Keys.memoryWarningThreshold)
        }
        if defaults.object(forKey: Keys.memoryCriticalThreshold) == nil {
            defaults.set(80.0, forKey: Keys.memoryCriticalThreshold)
        }
        if defaults.object(forKey: Keys.launchAtLogin) == nil {
            defaults.set(false, forKey: Keys.launchAtLogin)
        }
        // customThresholds and customColors: leave nil — code defaults apply at read sites
    }

    // MARK: - Load All

    /// Populate all backing vars from UserDefaults without triggering property setters or notifications.
    /// Called once from init() after runMigrations().
    private func loadAll() {
        let rawInterval = defaults.double(forKey: Keys.refreshInterval)
        _refreshInterval = rawInterval > 0 ? rawInterval : 2.0

        let rawMode = defaults.string(forKey: Keys.displayMode) ?? ""
        _displayMode = DisplayMode(rawValue: rawMode) ?? .compact

        let rawUnit = defaults.string(forKey: Keys.displayUnit) ?? ""
        _displayUnit = DisplayUnit(rawValue: rawUnit) ?? .auto

        _showIcons = defaults.bool(forKey: Keys.showIcons)

        // 使用 object(forKey:) != nil 区分 "key 不存在" 与 "值为 0.0"，
        // 避免将合法的 0.0 阈值静默重置为默认值。
        if let raw = defaults.object(forKey: Keys.cpuWarningThreshold) as? Double {
            _cpuWarningThreshold = raw
        } else {
            _cpuWarningThreshold = 60.0
        }

        if let raw = defaults.object(forKey: Keys.cpuCriticalThreshold) as? Double {
            _cpuCriticalThreshold = raw
        } else {
            _cpuCriticalThreshold = 80.0
        }

        if let raw = defaults.object(forKey: Keys.memoryWarningThreshold) as? Double {
            _memoryWarningThreshold = raw
        } else {
            _memoryWarningThreshold = 60.0
        }

        if let raw = defaults.object(forKey: Keys.memoryCriticalThreshold) as? Double {
            _memoryCriticalThreshold = raw
        } else {
            _memoryCriticalThreshold = 80.0
        }

        let orderRaws = defaults.stringArray(forKey: Keys.metricOrder) ?? []
        let order = orderRaws.compactMap(Metric.init(rawValue:))
        _metricOrder = order.isEmpty ? [.cpu, .gpu, .memory, .network] : order

        let enabledRaws = defaults.stringArray(forKey: Keys.enabledMetrics) ?? []
        let enabled = enabledRaws.compactMap(Metric.init(rawValue:))
        _enabledMetrics = enabled.isEmpty ? [.cpu, .gpu, .memory, .network] : enabled

        _launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

        if defaults.object(forKey: Keys.showBatterySection) == nil {
            _showBatterySection = true
        } else {
            _showBatterySection = defaults.bool(forKey: Keys.showBatterySection)
        }

        if defaults.object(forKey: Keys.showProcessSection) == nil {
            _showProcessSection = true
        } else {
            _showProcessSection = defaults.bool(forKey: Keys.showProcessSection)
        }

        if defaults.object(forKey: Keys.showThermalSection) == nil {
            _showThermalSection = true
        } else {
            _showThermalSection = defaults.bool(forKey: Keys.showThermalSection)
        }

        if let data = defaults.data(forKey: Keys.customThresholds),
           let decoded = try? JSONDecoder().decode([String: [String: Double]].self, from: data) {
            _customThresholds = decoded
        } else {
            _customThresholds = [:]
        }

        if let data = defaults.data(forKey: Keys.customColors),
           let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            // 复用 setter 的过滤逻辑，过滤掉非 #RRGGBB 格式的条目，
            // 防止外部工具（如 defaults write）写入非法格式污染内存状态。
            var filtered: [String: [String: String]] = [:]
            for (metric, levels) in decoded {
                let valid = levels.filter { _, hex in hex.hasPrefix("#") && hex.count == 7 }
                if !valid.isEmpty { filtered[metric] = valid }
            }
            _customColors = filtered
        } else {
            _customColors = [:]
        }
    }

    // MARK: - Notification Helper

    /// Post `.settingsDidChange` with the given changed UserDefaults key names.
    private func postChange(keys: Set<String>) {
        NotificationCenter.default.post(
            name: .settingsDidChange,
            object: self,
            userInfo: [SettingsManager.changedKeysUserInfoKey: keys]
        )
    }
}
