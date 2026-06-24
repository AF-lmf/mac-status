import SwiftUI

// MARK: - Dashboard View

/// Main popover content — iStat-style card layout with sparkline trends.
/// Shows CPU, Memory, Network, GPU cards + top processes list.
struct DashboardView: View {
    @EnvironmentObject private var state: DashboardState

    var body: some View {
        let settings = SettingsManager.shared  // body 内读取，建立 @Observable 追踪依赖（无需 @State）
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

            // Battery section (laptops only; entire section hidden on desktop Macs)
            // 外层：设置门控（showBatterySection）；内层：硬件门控（hasBattery）。
            // 在无电池机型上 hasBattery = false，Toggle 可操作但弹窗不显示（原有行为不变）。
            if settings.showBatterySection && state.hasBattery, let battery = state.battery {
                BatterySectionView(snapshot: battery)
            }

            let showsFanRows = settings.showFanSection && state.fan.supportState != .unsupported
            if settings.showThermalSection || showsFanRows {
                TemperatureAndFanSectionView(
                    thermalSnapshot: state.thermal,
                    fanSnapshot: state.fan,
                    showsTemperature: settings.showThermalSection,
                    showsFan: settings.showFanSection
                )
            }

            // 进程相关三个区块整体由 showProcessSection 门控（整体显示或整体隐藏）
            if settings.showProcessSection {
                // Process list
                ProcessListView(
                    processes: state.topProcesses,
                    isLoading: state.processesLoading,
                    errorMessage: state.processError
                )

                // CPU Top 5 (PROC-01)
                ProcessResourceSectionView(
                    title: "CPU 占用 Top 5",
                    items: state.topCPUProcesses,
                    isLoading: state.resourceLoading,
                    trailingWidth: StableValueWidth.processCPU,
                    trailingText: { proc in
                        proc.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—"
                    }
                )

                // 内存 Top 5 (PROC-02)
                ProcessResourceSectionView(
                    title: "内存占用 Top 5",
                    items: state.topMemoryProcesses,
                    isLoading: state.resourceLoading,
                    trailingWidth: StableValueWidth.processMemory,
                    trailingText: { proc in
                        ByteFormatting.format(Double(proc.memoryBytes))
                    }
                )
            }

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
        .frame(width: DashboardLayout.popoverWidth)
    }
}

// MARK: - Temperature and Fan Section

/// Full-width popover section for current thermal and read-only fan telemetry.
struct TemperatureAndFanSectionView: View {
    let thermalSnapshot: ThermalSnapshot
    let fanSnapshot: FanSnapshot
    let showsTemperature: Bool
    let showsFan: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("温度与风扇")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if showsTemperature {
                    HStack(spacing: 4) {
                        Text("CPU/SoC")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        StableValueText(
                            text: temperatureText(thermalSnapshot.cpuSocTemperatureCelsius),
                            width: StableValueWidth.temperature,
                            color: .primary,
                            font: .system(.body, design: .monospaced),
                            fontWeight: .medium
                        )
                    }
                    .accessibilityLabel(primaryTemperatureAccessibilityText)
                }
            }

            if showsTemperature {
                temperatureRow("CPU/SoC", temperatureText(thermalSnapshot.cpuSocTemperatureCelsius))
                temperatureRow("系统状态", thermalStateText, color: thermalStateColor)
                temperatureRow("GPU", temperatureText(thermalSnapshot.gpuTemperatureCelsius))
                temperatureRow("电池", temperatureText(thermalSnapshot.batteryTemperatureCelsius))
            }

            if showsTemperature && !visibleFans.isEmpty {
                Divider()
            }

            ForEach(visibleFans) { fan in
                fanRow(fan)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("温度与风扇信息")
    }

    private var visibleFans: [FanReading] {
        guard showsFan, fanSnapshot.supportState != .unsupported else { return [] }
        return fanSnapshot.fans
    }

    private func temperatureRow(_ label: String, _ value: String, color: Color = .secondary) -> some View {
        StableValueRow(label: label) {
            StableValueText(
                text: value,
                width: StableValueWidth.temperature,
                color: color
            )
                .accessibilityLabel(accessibilityText(label: label, value: value))
        }
    }

    private func fanRow(_ fan: FanReading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            StableValueRow(label: fan.displayName) {
                StableValueText(
                    text: fanRPMText(fan),
                    width: StableValueWidth.fanRPM,
                    color: fan.currentRPM == nil ? .secondary : .primary
                )
                    .accessibilityLabel(fanRPMAccessibilityText(fan))
            }

            if let range = fanRangeText(fan) {
                StableCaptionText(text: range)
                    .accessibilityLabel(fanRangeAccessibilityText(fan))
            }

            if let target = fanTargetText(fan) {
                StableCaptionText(text: target)
                    .accessibilityLabel(fanTargetAccessibilityText(fan))
            }

            if fanRangeText(fan) != nil || fanTargetText(fan) != nil {
                StableCaptionText(text: "边界可读，控制未启用")
            }
        }
    }

    private func temperatureText(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return "\(Int(value.rounded()))°C"
    }

    private func fanRPMText(_ fan: FanReading) -> String {
        guard let rpm = fan.currentRPM else { return "N/A" }
        return "\(Int(rpm.rounded())) RPM"
    }

    private func fanRangeText(_ fan: FanReading) -> String? {
        guard fan.capabilities.boundsReadable,
              let minRPM = fan.minRPM,
              let maxRPM = fan.maxRPM,
              minRPM <= maxRPM
        else { return nil }

        return "范围 \(Int(minRPM.rounded()))-\(Int(maxRPM.rounded())) RPM"
    }

    private func fanTargetText(_ fan: FanReading) -> String? {
        guard fan.capabilities.targetReadable,
              let targetRPM = fan.targetRPM
        else { return nil }
        return "目标 \(Int(targetRPM.rounded())) RPM"
    }

    private var thermalStateText: String {
        switch thermalSnapshot.systemState {
        case .nominal: return "正常"
        case .fair: return "偏热"
        case .serious: return "严重"
        case .critical: return "临界"
        case .unknown: return "未知"
        }
    }

    private var thermalStateColor: Color {
        switch thermalSnapshot.systemState {
        case .serious: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        case .nominal, .fair: return .primary
        }
    }

    private var primaryTemperatureAccessibilityText: String {
        guard let value = thermalSnapshot.cpuSocTemperatureCelsius else {
            return "CPU 或 SoC 温度不可用"
        }
        return "CPU 或 SoC 温度 \(Int(value.rounded())) 摄氏度"
    }

    private func fanRPMAccessibilityText(_ fan: FanReading) -> String {
        guard let rpm = fan.currentRPM else {
            return "\(fan.displayName) 转速不可用"
        }
        return "\(fan.displayName) 当前转速 \(Int(rpm.rounded())) RPM"
    }

    private func fanRangeAccessibilityText(_ fan: FanReading) -> String {
        guard let minRPM = fan.minRPM, let maxRPM = fan.maxRPM else {
            return "\(fan.displayName) 范围不可用"
        }
        return "\(fan.displayName) 范围 \(Int(minRPM.rounded())) 到 \(Int(maxRPM.rounded())) RPM"
    }

    private func fanTargetAccessibilityText(_ fan: FanReading) -> String {
        guard let targetRPM = fan.targetRPM else {
            return "\(fan.displayName) 目标转速不可用"
        }
        return "\(fan.displayName) 目标转速 \(Int(targetRPM.rounded())) RPM"
    }

    private func accessibilityText(label: String, value: String) -> String {
        switch label {
        case "CPU/SoC":
            return primaryTemperatureAccessibilityText
        case "系统状态":
            return "系统散热状态 \(value)"
        case "GPU":
            return value == "N/A" ? "GPU 温度不可用" : "GPU 温度 \(value.replacingOccurrences(of: "°C", with: " 摄氏度"))"
        case "电池":
            return value == "N/A" ? "电池温度不可用" : "电池温度 \(value.replacingOccurrences(of: "°C", with: " 摄氏度"))"
        default:
            return "\(label) \(value)"
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
                StableValueText(
                    text: value,
                    width: valueWidth,
                    color: color,
                    font: .system(.body, design: .monospaced),
                    fontWeight: .medium,
                    lineLimit: title == "Network" ? 2 : 1
                )
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

    private var valueWidth: CGFloat {
        title == "Network" ? StableValueWidth.networkCard : StableValueWidth.percentage
    }
}

// MARK: - Battery Section

/// Full-width popover battery section. Rendered only when a battery is present
/// (laptops); hidden entirely on desktop Macs. Each field degrades to "—" when its
/// underlying `AppleSmartBattery` key is unreadable.
struct BatterySectionView: View {
    let snapshot: BatterySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("电池")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(snapshot.chargePercent)% · \(chargeStateText)")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }

            row(timeLabel, timeText, width: StableValueWidth.batteryHealthTime)
            row("电池功率", wattsText, width: StableValueWidth.batteryPower)
            row("整机功耗", systemPowerText, width: StableValueWidth.batteryPower)
            row("健康度", healthText, width: StableValueWidth.batteryHealthTime)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func row(_ label: String, _ value: String, width: CGFloat) -> some View {
        StableValueRow(label: label) {
            StableValueText(text: value, width: width)
        }
    }

    /// 充电三态（不依赖 kIOPSIsChargedKey）：
    /// isCharging→充电中；!isCharging && isOnAC && chargePercent>=99→已充满；
    /// !isCharging && isOnAC && chargePercent<99→电源接入（优化充电暂停等）；否则→使用电池。
    private var chargeStateText: String {
        if snapshot.isCharging { return "充电中" }
        if snapshot.isOnAC {
            // 优化电池充电可能在 80% 暂停充电，需区分"已充满"与"电源接入"
            return snapshot.chargePercent >= 99 ? "已充满" : "电源接入"
        }
        return "使用电池"
    }

    /// 充电时显示"距充满"，使用电池时显示"剩余时间"，AC 已充满时无意义。
    private var timeLabel: String {
        snapshot.isCharging ? "距充满" : "剩余时间"
    }

    private var timeText: String {
        if snapshot.isCharging {
            return formatTime(snapshot.timeToFullMinutes)
        }
        if !snapshot.isOnAC {
            return formatTime(snapshot.timeToEmptyMinutes)
        }
        return "—"  // 已充满 / AC 待机：剩余时间无意义
    }

    /// 分钟 → 显示文本。nil（含 post-wake 抑制）→ 计算中；-1（Apple 哨兵）→ 计算中；0 → —。
    private func formatTime(_ minutes: Int?) -> String {
        guard let m = minutes else { return "计算中" }
        switch m {
        case -1: return "计算中"
        case 0: return "—"
        case let t where t > 0:
            let hrs = t / 60
            let mins = t % 60
            return hrs > 0 ? "\(hrs)小时\(mins)分" : "\(mins)分钟"
        default: return "—"
        }
    }

    /// 带语义瓦数：充电 → "充电 18.5W"；放电 → "耗电 12.3W"；
    /// nil（电池键缺失，或接入电源未充放电使净功率 <0.1W）→ —。
    private var wattsText: String {
        guard let w = snapshot.watts else { return "—" }
        let verb = w >= 0 ? "充电" : "耗电"
        return "\(verb) \(String(format: "%.1f", abs(w)))W"
    }

    /// 整机实时功耗（SMC PSTR），接入电源时也有意义；键不可用 → —。
    private var systemPowerText: String {
        guard let p = snapshot.systemPowerWatts else { return "—" }
        return "\(String(format: "%.1f", p))W"
    }

    /// "92%（320 次循环）"；健康度缺失 → —；循环数缺失则仅显示百分比。
    private var healthText: String {
        guard let h = snapshot.healthPercent else { return "—" }
        let pct = "\(Int(h.rounded()))%"
        if let cycles = snapshot.cycleCount {
            return "\(pct)（\(cycles) 次循环）"
        }
        return pct
    }
}

// MARK: - Process Resource Section View

/// Reusable card section for CPU or memory Top-N process lists.
/// Shows a spinner while the first sample is pending, "无数据" when the list is empty,
/// and a row per process using ProcessMetricRow with a caller-supplied trailing string.
struct ProcessResourceSectionView: View {
    let title: String
    let items: [ProcessResourceUsage]
    let isLoading: Bool
    let trailingWidth: CGFloat
    let trailingText: (ProcessResourceUsage) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Sampling...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else if items.isEmpty {
                Text("无数据")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(items.prefix(5), id: \.pid) { proc in
                    ProcessMetricRow(processName: proc.processName, pid: proc.pid) {
                        StableValueText(
                            text: trailingText(proc),
                            width: trailingWidth,
                            color: .primary,
                            font: .system(.caption2, design: .monospaced)
                        )
                    }
                }
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

    // Battery (popover-only; nil = no battery = desktop → section hidden)
    @Published var battery: BatterySnapshot? = nil
    @Published var hasBattery: Bool = false

    // Thermal (popover-only current snapshot; stable unavailable values render inline)
    @Published var thermal: ThermalSnapshot = .unavailable()

    // Fan (popover-only current snapshot; stable unavailable values render inline when expected)
    @Published var fan: FanSnapshot = .unavailable()

    // Processes
    @Published var topProcesses: [ProcessNetworkUsage] = []
    @Published var processesLoading: Bool = false
    @Published var processError: String?

    // Resource usage — CPU/memory Top-N (popover-gated, 1.5s loop)
    @Published var topCPUProcesses: [ProcessResourceUsage] = []
    @Published var topMemoryProcesses: [ProcessResourceUsage] = []
    @Published var resourceLoading: Bool = true

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
        // 用换行分隔上/下行，强制始终竖排（↑ 在上、↓ 在下），
        // 避免随数值长短在"并排一行"与"折成两行"之间来回抖动。
        networkText = "↑\(up)\n↓\(down)"

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

    /// Update the battery snapshot. nil (desktop / no battery) hides the whole section.
    func updateBattery(_ snapshot: BatterySnapshot?) {
        battery = snapshot
        hasBattery = snapshot != nil
    }

    /// Update the thermal snapshot. Unavailable values stay in the snapshot so rows remain stable.
    func updateThermal(_ snapshot: ThermalSnapshot) {
        thermal = snapshot
    }

    /// Update the fan snapshot. Unsupported/fanless machines keep an empty snapshot for quiet UI.
    func updateFans(_ snapshot: FanSnapshot) {
        fan = snapshot
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
