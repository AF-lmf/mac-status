import Foundation

// MARK: - Metric Collector

/// Unified orchestrator that triggers all readers on a single timer
/// and routes data to both the UI and the persistence layer.
///
/// Data flow:
/// ```
/// Timer → readAll() → RingBuffer (memory)
///                     → HistoryStore (SQLite, batched)
///                     → DashboardState (SwiftUI, @MainActor)
///                     → StatusBarManager (menu bar title, @MainActor)
/// ```
@MainActor
final class MetricCollector {

    // MARK: - Singleton

    static let shared = MetricCollector()

    // MARK: - Properties

    private let ringBuffer = RingBuffer(capacity: 300) // 5 minutes at 1s interval
    private let historyStore = HistoryStore()
    private var timer: Timer?

    // Individual readers
    private let cpuReader = CPUReader()
    private let memoryReader = MemoryReader()
    private let networkReader = NetworkReader()
    private let gpuReader = GPUReader()

    // Batch buffer for SQLite writes (flush every 30 seconds)
    private var pendingSamples: [MetricSample] = []
    private let flushInterval = 30

    // Tick counter
    private var tickCount = 0

    // MARK: - Initialization

    private init() {}

    // MARK: - Lifecycle

    /// Start collecting metrics on a unified timer.
    func start() {
        // Initialize reader baselines
        cpuReader.setup()
        memoryReader.setup()
        networkReader.setup()
        gpuReader.setup()

        // First read establishes baseline (network needs two reads for delta)
        _ = cpuReader.readValue()
        _ = memoryReader.readValue()
        _ = networkReader.readValue()
        _ = gpuReader.readValue()

        // Unified tick timer on the main run loop
        let interval = SettingsManager.shared.refreshInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }

        // Load recent history from SQLite for the popover sparklines
        loadRecentHistory()
    }

    /// Stop collecting.
    func stop() {
        timer?.invalidate()
        timer = nil

        if !pendingSamples.isEmpty {
            historyStore.insertSamples(pendingSamples)
            pendingSamples.removeAll()
        }
    }

    // MARK: - Tick

    private func tick() {
        tickCount += 1

        // Read all metrics directly — no callback indirection
        let cpu = cpuReader.readValue()
        let mem = memoryReader.readValue()
        let net = networkReader.readValue()
        let gpu = gpuReader.readValue()

        let sample = MetricSample(
            cpuUsage: cpu,
            memoryUsage: mem?.usedPercent,
            networkUploadBps: net?.uploadBytesPerSec,
            networkDownloadBps: net?.downloadBytesPerSec,
            gpuUsage: gpu?.utilizationPercent
        )

        // 1. In-memory ring buffer
        ringBuffer.append(sample)

        // 2. Batch for SQLite
        pendingSamples.append(sample)
        if pendingSamples.count >= flushInterval {
            historyStore.insertSamples(pendingSamples)
            pendingSamples.removeAll()
        }

        // 3. Update UI
        updateUI(sample: sample)

        // 4. Periodic cleanup (once per hour)
        if tickCount % 1800 == 0 {
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            historyStore.purgeOlder(than: cutoff)
        }
    }

    private func updateUI(sample: MetricSample) {
        let dashboard = PopoverManager.shared.dashboardState

        dashboard.updateCPU(sample.cpuUsage)
        dashboard.updateMemory(sample.memoryUsage.map {
            MemoryStats(pressureLevel: .normal, usedPercent: $0)
        })

        let netStats: NetworkStats? = (sample.networkUploadBps != nil || sample.networkDownloadBps != nil)
            ? NetworkStats(downloadBytesPerSec: sample.networkDownloadBps ?? 0,
                           uploadBytesPerSec: sample.networkUploadBps ?? 0)
            : nil
        dashboard.updateNetwork(netStats)

        dashboard.updateGPU(sample.gpuUsage.map {
            GPUStats(utilizationPercent: $0, pressureLevel: nil)
        })

        // Update sparkline samples from ring buffer
        let recent = ringBuffer.recentSamples(60)
        dashboard.cpuSamples = recent.compactMap(\.cpuUsage)
        dashboard.memorySamples = recent.compactMap(\.memoryUsage)
        dashboard.networkSamples = recent.compactMap { $0.networkDownloadBps.map { $0 / 1000.0 } }
        dashboard.gpuSamples = recent.compactMap(\.gpuUsage)

        // Update status bar
        let memStats: MemoryStats? = sample.memoryUsage.map {
            MemoryStats(pressureLevel: .normal, usedPercent: $0)
        }
        let netStats2: NetworkStats? = (sample.networkUploadBps != nil || sample.networkDownloadBps != nil)
            ? NetworkStats(downloadBytesPerSec: sample.networkDownloadBps ?? 0,
                           uploadBytesPerSec: sample.networkUploadBps ?? 0)
            : nil

        StatusBarManager.shared.updateTitle(
            cpuUsage: sample.cpuUsage,
            memoryStats: memStats,
            networkStats: netStats2,
            gpuStats: sample.gpuUsage.map { GPUStats(utilizationPercent: $0, pressureLevel: nil) }
        )
    }

    private func loadRecentHistory() {
        let start = Date().addingTimeInterval(-300)
        let samples = historyStore.querySamples(from: start, to: Date())

        for sample in samples {
            ringBuffer.append(sample)
        }

        if !samples.isEmpty {
            let dashboard = PopoverManager.shared.dashboardState
            let recent = ringBuffer.recentSamples(60)
            dashboard.cpuSamples = recent.compactMap(\.cpuUsage)
            dashboard.memorySamples = recent.compactMap(\.memoryUsage)
            dashboard.networkSamples = recent.compactMap { $0.networkDownloadBps.map { $0 / 1000.0 } }
            dashboard.gpuSamples = recent.compactMap(\.gpuUsage)
        }
    }

    // MARK: - Accessors

    func recentCPUSamples(_ n: Int = 60) -> [Double] {
        ringBuffer.recentSamples(n).compactMap(\.cpuUsage)
    }

    func recentMemorySamples(_ n: Int = 60) -> [Double] {
        ringBuffer.recentSamples(n).compactMap(\.memoryUsage)
    }

    func recentGPUSamples(_ n: Int = 60) -> [Double] {
        ringBuffer.recentSamples(n).compactMap(\.gpuUsage)
    }

    var persistedCount: Int {
        historyStore.sampleCount
    }
}
