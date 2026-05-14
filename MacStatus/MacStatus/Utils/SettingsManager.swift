import Foundation

/// Thread-safe UserDefaults wrapper for MacStatus preferences.
/// Uses the singleton pattern — a single shared instance manages all settings.
/// v1 stores only the refresh interval; future phases add additional keys.
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
}
