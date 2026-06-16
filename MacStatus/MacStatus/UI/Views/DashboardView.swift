import SwiftUI

// MARK: - Dashboard View

/// Main popover content — iStat-style card layout with sparkline trends.
/// Shows CPU, Memory, Network, GPU cards + top processes list.
struct DashboardView: View {
    @EnvironmentObject private var state: DashboardState

    var body: some View {
        ScrollView {
        VStack(spacing: 8) {
            // Header
            HStack {
                Spacer()
                Text("Refresh: \(Int(state.refreshInterval))s")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Metric cards grid (2x2) with sparklines
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                spacing: 8
            ) {
                MetricCardWithSparkline(
                    title: "CPU",
                    value: state.cpuText,
                    progress: state.cpuUsage / 100.0,
                    color: Color.usageColor(state.cpuUsage),
                    samples: state.cpuSamples
                )

                MetricCardWithSparkline(
                    title: "Memory",
                    value: state.memoryText,
                    progress: state.memoryUsage / 100.0,
                    color: Color.usageColor(state.memoryUsage),
                    samples: state.memorySamples
                )

                MetricCardWithSparkline(
                    title: "Network",
                    value: state.networkText,
                    progress: state.networkProgress,
                    color: .blue,
                    samples: state.networkSamples
                )

                MetricCardWithSparkline(
                    title: "GPU",
                    value: state.gpuText,
                    progress: state.gpuUsage / 100.0,
                    color: Color.usageColor(state.gpuUsage),
                    samples: state.gpuSamples
                )
            }

            // Process list
            ProcessListView(
                processes: state.topProcesses,
                isLoading: state.processesLoading,
                errorMessage: state.processError
            )

            // Footer — self monitoring
            HStack {
                if state.selfCpuUsage > 1.0 {
                    Label(
                        "Self: \(String(format: "%.1f%%", state.selfCpuUsage))",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                }
                Spacer()
                if state.selfMemoryMB > 0 {
                    Text("RAM: \(Int(state.selfMemoryMB))MB")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Quit MacStatus") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Metric Card with Sparkline

/// A metric card that includes a sparkline trend chart below the main value.
struct MetricCardWithSparkline: View {
    let title: String
    let value: String
    let progress: Double
    let color: Color
    let samples: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(color)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(
                            width: geo.size.width * CGFloat(min(max(progress, 0), 1)),
                            height: 4
                        )
                }
            }
            .frame(height: 4)

            // Sparkline trend (last 60 samples)
            if !samples.isEmpty {
                SparklineView(samples: samples, color: color)
                    .frame(height: 24)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - Dashboard State

@MainActor
final class DashboardState: ObservableObject {
    // CPU
    @Published var cpuUsage: Double = 0
    @Published var cpuText: String = "--"
    @Published var cpuSamples: [Double] = []

    // Memory
    @Published var memoryUsage: Double = 0
    @Published var memoryText: String = "--"
    @Published var memorySamples: [Double] = []

    // Network
    @Published var networkText: String = "--"
    @Published var networkProgress: Double = 0
    @Published var networkSamples: [Double] = []

    // GPU
    @Published var gpuUsage: Double = 0
    @Published var gpuText: String = "--"
    @Published var gpuSamples: [Double] = []

    // Processes
    @Published var topProcesses: [ProcessNetworkUsage] = []
    @Published var processesLoading: Bool = false
    @Published var processError: String?

    // Self monitoring
    @Published var selfCpuUsage: Double = 0
    @Published var selfMemoryMB: Double = 0

    // Settings
    @Published var refreshInterval: Double = 2.0

    // MARK: - Sparkline Config

    private let maxSamples = 60

    // MARK: - Update Methods

    func updateCPU(_ usage: Double?) {
        guard let usage else {
            cpuText = "--"
            cpuUsage = 0
            return
        }
        cpuUsage = usage
        cpuText = "\(Int(usage))%"
        appendSample(&cpuSamples, value: usage)
    }

    func updateMemory(_ stats: MemoryStats?) {
        guard let stats, let usedPercent = stats.usedPercent else {
            memoryText = "--"
            memoryUsage = 0
            return
        }
        memoryUsage = usedPercent
        let pressureLabel: String
        switch stats.pressureLevel {
        case .normal: pressureLabel = "OK"
        case .warning: pressureLabel = "WARN"
        case .critical: pressureLabel = "CRIT"
        case .unknown: pressureLabel = "?"
        }
        memoryText = "\(Int(usedPercent))% (\(pressureLabel))"
        appendSample(&memorySamples, value: usedPercent)
    }

    func updateNetwork(_ stats: NetworkStats?) {
        guard let stats else {
            networkText = "--"
            networkProgress = 0
            return
        }
        let up = ByteFormatting.format(stats.uploadBytesPerSec)
        let down = ByteFormatting.format(stats.downloadBytesPerSec)
        networkText = "↑\(up) ↓\(down)"

        let maxBytesPerSec: Double = 100 * 1_000_000 // 100 MB/s
        let total = stats.uploadBytesPerSec + stats.downloadBytesPerSec
        networkProgress = min(total / maxBytesPerSec, 1.0)
        // Sparkline shows total throughput in KB/s for reasonable scale
        appendSample(&networkSamples, value: total / 1000.0)
    }

    func updateGPU(_ stats: GPUStats?) {
        guard let stats else {
            gpuText = "N/A"
            gpuUsage = 0
            return
        }
        gpuUsage = stats.utilizationPercent
        gpuText = "\(Int(stats.utilizationPercent))%"
        appendSample(&gpuSamples, value: stats.utilizationPercent)
    }

    func updateRefreshInterval(_ interval: Double) {
        refreshInterval = interval
    }

    // MARK: - Sample Management

    private func appendSample(_ samples: inout [Double], value: Double) {
        samples.append(value)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }
}
