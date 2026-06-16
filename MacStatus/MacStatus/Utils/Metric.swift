import Foundation

// MARK: - Metric

/// Stable identifier for each monitored metric.
///
/// `rawValue` is used as the UserDefaults key component across all metric-keyed structures:
/// - `metricOrder`      — stored as `[String]` (array of rawValues)
/// - `enabledMetrics`   — stored as `[String]` (array of rawValues)
/// - `customThresholds` — stored as `[String: [String: Double]]` (metricRawValue → level → value)
/// - `customColors`     — stored as `[String: [String: String]]` (metricRawValue → level → "#RRGGBB")
enum Metric: String, CaseIterable, Sendable {
    case cpu     = "cpu"
    case memory  = "memory"
    case network = "network"
    case gpu     = "gpu"
    case battery = "battery"  // reserved; Phase 7 activates this case
}
