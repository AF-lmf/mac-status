import Foundation

// MARK: - Metric Sample

/// A single time-series data point for any metric.
/// Sendable for safe cross-actor transport in Swift 6.
struct MetricSample: Sendable, Equatable {
    let timestamp: Date
    let cpuUsage: Double?
    let memoryUsage: Double?
    let networkUploadBps: Double?
    let networkDownloadBps: Double?
    let gpuUsage: Double?

    /// Create a sample from current readings.
    init(
        timestamp: Date = Date(),
        cpuUsage: Double? = nil,
        memoryUsage: Double? = nil,
        networkUploadBps: Double? = nil,
        networkDownloadBps: Double? = nil,
        gpuUsage: Double? = nil
    ) {
        self.timestamp = timestamp
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.networkUploadBps = networkUploadBps
        self.networkDownloadBps = networkDownloadBps
        self.gpuUsage = gpuUsage
    }
}

// MARK: - Aggregated Sample

/// Pre-aggregated sample for long-term storage (5-minute buckets).
struct AggregatedSample: Sendable, Equatable {
    let timestamp: Date
    let cpuAvg: Double
    let cpuMax: Double
    let memoryAvg: Double
    let memoryMax: Double
    let networkAvgBps: Double
    let gpuAvg: Double
    let gpuMax: Double
}
