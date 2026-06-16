import Foundation

// MARK: - Display Mode

/// How the menu bar title displays metric data.
enum DisplayMode: String, CaseIterable, Sendable {
    /// Full text: `CPU: 23% | MEM: 67% OK | NET: ↑0B/s ↓1.2KB/s | GPU: 12%`
    case full
    /// Compact: `C:23% M:67% N:↑0↓1.2K G:12%`
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

/// Thread-safe UserDefaults wrapper for MacStatus preferences.
/// Uses the singleton pattern — a single shared instance manages all settings.
///
/// Marked @unchecked Sendable because UserDefaults.standard is documented as
/// thread-safe, and all stored values are simple key-value types.
final class SettingsManager: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Keys

    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let displayMode = "displayMode"
        static let displayUnit = "displayUnit"
        static let showIcons = "showIcons"
        static let cpuWarningThreshold = "cpuWarningThreshold"
        static let cpuCriticalThreshold = "cpuCriticalThreshold"
        static let memoryWarningThreshold = "memoryWarningThreshold"
        static let memoryCriticalThreshold = "memoryCriticalThreshold"
    }

    // MARK: - Settings

    /// Polling refresh interval in seconds. Defaults to 2.0 if unset.
    var refreshInterval: TimeInterval {
        get {
            let value = defaults.double(forKey: Keys.refreshInterval)
            return value > 0 ? value : 2.0
        }
        set {
            defaults.set(newValue, forKey: Keys.refreshInterval)
        }
    }

    /// Menu bar display mode. Defaults to .full.
    var displayMode: DisplayMode {
        get {
            let raw = defaults.string(forKey: Keys.displayMode) ?? ""
            return DisplayMode(rawValue: raw) ?? .compact
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.displayMode)
        }
    }

    /// Byte display unit. Defaults to .auto.
    var displayUnit: DisplayUnit {
        get {
            let raw = defaults.string(forKey: Keys.displayUnit) ?? ""
            return DisplayUnit(rawValue: raw) ?? .auto
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.displayUnit)
        }
    }

    /// Whether to show SF Symbol icons in the menu bar. Defaults to false.
    var showIcons: Bool {
        get { defaults.bool(forKey: Keys.showIcons) }
        set { defaults.set(newValue, forKey: Keys.showIcons) }
    }

    // MARK: - Alert Thresholds

    var cpuWarningThreshold: Double {
        get {
            let v = defaults.double(forKey: Keys.cpuWarningThreshold)
            return v > 0 ? v : 60.0
        }
        set { defaults.set(newValue, forKey: Keys.cpuWarningThreshold) }
    }

    var cpuCriticalThreshold: Double {
        get {
            let v = defaults.double(forKey: Keys.cpuCriticalThreshold)
            return v > 0 ? v : 80.0
        }
        set { defaults.set(newValue, forKey: Keys.cpuCriticalThreshold) }
    }

    var memoryWarningThreshold: Double {
        get {
            let v = defaults.double(forKey: Keys.memoryWarningThreshold)
            return v > 0 ? v : 60.0
        }
        set { defaults.set(newValue, forKey: Keys.memoryWarningThreshold) }
    }

    var memoryCriticalThreshold: Double {
        get {
            let v = defaults.double(forKey: Keys.memoryCriticalThreshold)
            return v > 0 ? v : 80.0
        }
        set { defaults.set(newValue, forKey: Keys.memoryCriticalThreshold) }
    }
}
