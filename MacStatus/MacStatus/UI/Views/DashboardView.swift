import SwiftUI

// MARK: - Dashboard View
//
// 1a「原生精修 (Refined Native)」弹窗仪表盘：半透明玻璃面板内的圆角卡片群。
// 标题栏 → 2×2 指标卡（大数字 + 小型大写标签 + 面积 sparkline）
// → 电源概览排（电源卡 : 温度 : 风扇 = 2:1:1，详细数据默认收起可展开）
// → 资源占用 TOP（CPU/内存 pill 切换）→ 网络进程 → 底部。
//
// 布局不变量：数值列一律用固定宽度，保证 .short 与 .extreme fixture 下数值列
// x 位置与列宽不抖动（见 DashboardLayoutStabilityTests）。8 个 LayoutProbe 常驻：
// 概览排承载 battery/systemPower/temperature/fanRPM 四个探针；资源占用卡以
// ZStack 双渲染（未选中列表 opacity 0）保证 cpu/memory 两个探针同时存在。

struct DashboardView: View {
    @EnvironmentObject private var state: DashboardState
    @State private var detailsExpanded = false

    var body: some View {
        let settings = SettingsManager.shared  // body 内读取，建立 @Observable 追踪依赖（无需 @State）
        let showsBattery = settings.showBatterySection && state.hasBattery
        let showsThermal = settings.showThermalSection
        let showsFan = settings.showFanSection && state.fan.supportState != .unsupported

        VStack(spacing: 8) {
            DashboardHeader(refreshInterval: state.refreshInterval)

            // Metric cards grid (2x2) with sparklines — 顺序对齐 mock：CPU / MEM / GPU / NET
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                spacing: 8
            ) {
                MetricCardWithSparkline(
                    title: "CPU",
                    number: "\(Int(state.cpuUsage))",
                    unit: "%",
                    tint: .usage(state.cpuUsage),
                    samples: state.cpuSamples
                )

                MetricCardWithSparkline(
                    title: "Memory",
                    number: "\(Int(state.memoryUsage))",
                    unit: "%",
                    tint: .usage(state.memoryUsage),
                    samples: state.memorySamples
                )

                MetricCardWithSparkline(
                    title: "GPU",
                    number: state.gpuText == "N/A" ? nil : "\(Int(state.gpuUsage))",
                    unit: "%",
                    fallbackValue: state.gpuText,
                    tint: .usage(state.gpuUsage),
                    samples: state.gpuSamples
                )

                MetricCardWithSparkline(
                    title: "Network",
                    networkValue: state.networkText,
                    tint: .network,
                    samples: state.networkSamples
                )
            }

            // 电源概览排（电源卡 2 : 温度 1 : 风扇 1）+ 可展开详细区
            if showsBattery || showsThermal || showsFan {
                OverviewStripView(
                    battery: showsBattery ? state.battery : nil,
                    thermal: state.thermal,
                    fan: state.fan,
                    showsTemperature: showsThermal,
                    showsFan: showsFan
                )

                DetailsToggleButton(isExpanded: $detailsExpanded)

                if detailsExpanded {
                    DetailSectionView(
                        battery: showsBattery ? state.battery : nil,
                        thermal: state.thermal,
                        fan: state.fan,
                        showsTemperature: showsThermal,
                        showsFan: showsFan
                    )
                }
            }

            // 进程相关区块整体由 showProcessSection 门控
            if settings.showProcessSection {
                ProcessResourceCard(
                    cpuItems: state.topCPUProcesses,
                    memoryItems: state.topMemoryProcesses,
                    isLoading: state.resourceLoading
                )

                ProcessListView(
                    processes: state.topProcesses,
                    isLoading: state.processesLoading,
                    errorMessage: state.processError
                )
            }

            DashboardFooter(selfCpuUsage: state.selfCpuUsage, selfMemoryMB: state.selfMemoryMB)
        }
        .padding(14)
        .frame(width: DashboardLayout.popoverWidth)
    }
}

// MARK: - Dashboard Header

/// 标题栏：app 图标方块 + "MacStatus" + 实时状态点 + 刷新节奏。
struct DashboardHeader: View {
    let refreshInterval: Double

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#3D9BFF"), Color(hex: "#0A6FD6")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 19, height: 19)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(.white.opacity(0.95))
                        .frame(width: 7, height: 7)
                )
                .shadow(color: Color(hex: "#0A5AC8").opacity(0.45), radius: 2, x: 0, y: 1.5)

            Text("MacStatus")
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(Color.runningGreen)
                    .frame(width: 5, height: 5)
                    .shadow(color: Color.runningGreen.opacity(0.9), radius: 2.5)
                Text("\(Int(refreshInterval))s")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.metricLabel)
            }
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Metric Card with Sparkline

/// 指标卡：小型大写标签 + 大号读数 + 底部面积 sparkline。
/// 三种读数形态：普通百分比（number+unit）、网络（两行 ↓主色/↑弱化）、N/A 兜底。
struct MetricCardWithSparkline: View {
    let title: String
    let tint: MetricTint
    let samples: [Double]

    private let number: String?
    private let unit: String?
    private let fallbackValue: String?
    private let networkValue: String?

    /// 百分比型（CPU/GPU/内存）：`number` 为大数字，`unit` 为小单位；N/A 用 `fallbackValue`。
    init(
        title: String,
        number: String?,
        unit: String?,
        fallbackValue: String? = nil,
        tint: MetricTint,
        samples: [Double]
    ) {
        self.title = title
        self.number = number
        self.unit = unit
        self.fallbackValue = fallbackValue
        self.networkValue = nil
        self.tint = tint
        self.samples = samples
    }

    /// 网络型：两行速率文字（`↓` 主色在上、`↑` 弱化在下；保留探针与固定列宽）。
    init(title: String, networkValue: String, tint: MetricTint, samples: [Double]) {
        self.title = title
        self.number = nil
        self.unit = nil
        self.fallbackValue = nil
        self.networkValue = networkValue
        self.tint = tint
        self.samples = samples
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                CardLabel(text: title)
                    .padding(.top, networkValue != nil ? 2 : 0)
                Spacer(minLength: 4)
                valueView
            }

            SparklineView(samples: samples, color: tint.accent)
                .frame(height: 26)
        }
        .cardSurface()
    }

    @ViewBuilder private var valueView: some View {
        if let networkValue {
            NetworkValueBlock(text: networkValue, tint: tint)
                .layoutProbe(.networkMetricCardValue)
        } else if let number {
            MetricValueText(number: number, unit: unit, color: tint.text)
        } else {
            Text(fallbackValue ?? "N/A")
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// 网络卡读数：第一行（↓ 下行）主色、第二行（↑ 上行）弱化色，右对齐固定列宽。
private struct NetworkValueBlock: View {
    let text: String
    let tint: MetricTint

    var body: some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        VStack(alignment: .trailing, spacing: 1) {
            Text(lines.first ?? "--")
                .foregroundStyle(tint.text)
            if lines.count > 1 {
                Text(lines[1])
                    .foregroundStyle(Color.metricLabel)
            }
        }
        .font(.system(size: 10.5, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.9)
        .frame(width: StableValueWidth.networkCard, alignment: .trailing)
        .layoutPriority(1)
    }
}

// MARK: - Overview Strip (电源 : 温度 : 风扇 = 2 : 1 : 1)

/// 概览排：电源卡（电池图标 + 电量 + 充电胶囊 + 功率两列）与温度/风扇窄卡并排。
/// 四个数值探针（batteryPower/systemPower/temperature/fanRPM）常驻此排。
struct OverviewStripView: View {
    let battery: BatterySnapshot?
    let thermal: ThermalSnapshot
    let fan: FanSnapshot
    let showsTemperature: Bool
    let showsFan: Bool

    var body: some View {
        // 与上方 2×2 网格同分栏：电源卡＝左列（对齐 CPU/GPU），
        // 温度+风扇一组＝右列（对齐 MEMORY/NETWORK），组内对半分。
        // fixedSize + maxHeight 让同排卡片等高。
        HStack(alignment: .top, spacing: 8) {
            if let battery {
                PowerCard(snapshot: battery)
                    .frame(maxWidth: .infinity)
            }

            if showsTemperature || showsFan {
                HStack(alignment: .top, spacing: 8) {
                    if showsTemperature {
                        InfoTile(
                            label: "温度",
                            valueText: temperatureText(thermal.cpuSocTemperatureCelsius),
                            valueUnit: "°C",
                            caption: "SoC · \(thermalStateText)",
                            captionColor: thermalStateColor,
                            probe: .temperatureValueColumn
                        )
                        .accessibilityLabel(temperatureAccessibilityText)
                    }

                    if showsFan {
                        InfoTile(
                            label: "风扇",
                            valueText: fanRPMValueText,
                            valueUnit: nil,
                            caption: "RPM",
                            captionColor: nil,
                            probe: .fanRPMValueColumn
                        )
                        .accessibilityLabel(fanAccessibilityText)
                    }
                }
                .frame(maxWidth: .infinity)
            } else if battery != nil {
                // 无温度/风扇时占位，保证电源卡仍与左列等宽
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func temperatureText(_ value: Double?) -> String? {
        guard let value else { return nil }
        return "\(Int(value.rounded()))"
    }

    /// 概览显示第一个可读风扇的当前转速；无可读值 → N/A。
    private var fanRPMValueText: String? {
        guard let rpm = fan.fans.compactMap(\.currentRPM).first else { return nil }
        return "\(Int(rpm.rounded()))"
    }

    private var thermalStateText: String {
        switch thermal.systemState {
        case .nominal: return "正常"
        case .fair: return "偏热"
        case .serious: return "严重"
        case .critical: return "临界"
        case .unknown: return "未知"
        }
    }

    private var thermalStateColor: Color? {
        switch thermal.systemState {
        case .serious: return .metricAmber
        case .critical: return .metricRose
        default: return nil
        }
    }

    private var temperatureAccessibilityText: String {
        guard let value = thermal.cpuSocTemperatureCelsius else {
            return "CPU 或 SoC 温度不可用"
        }
        return "CPU 或 SoC 温度 \(Int(value.rounded())) 摄氏度，状态\(thermalStateText)"
    }

    private var fanAccessibilityText: String {
        guard let rpm = fan.fans.compactMap(\.currentRPM).first else {
            return "风扇转速不可用"
        }
        return "风扇当前转速 \(Int(rpm.rounded())) RPM"
    }
}

/// 电源卡：上排＝电池图标 + 大号电量 + 充电状态胶囊；下排＝电池功率（带符号）/ 整机功耗两列。
private struct PowerCard: View {
    let snapshot: BatterySnapshot

    /// 已充满：接入电源且电量 >= 99（优化充电在 80% 暂停时归"电源接入"，不算充满）。
    private var isFull: Bool { !snapshot.isCharging && snapshot.isOnAC && snapshot.chargePercent >= 99 }

    /// 绿色态 = 充电中 / 已充满（绿色在设计中保留给"运行中/充电"语义）。
    private var isGreenState: Bool { snapshot.isCharging || isFull }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                BatteryGlyph(
                    percent: snapshot.chargePercent,
                    isCharging: snapshot.isCharging,
                    isFull: isFull
                )
                MetricValueText(number: "\(snapshot.chargePercent)", unit: "%", color: .primary, size: 15)
                Spacer(minLength: 2)
                chargeStatePill
            }

            // 两列等宽，分隔线两侧对称 11pt（mock: margin 0 11px），垂直居中
            HStack(alignment: .center, spacing: 0) {
                powerColumn(
                    label: "电池功率",
                    value: wattsText,
                    color: wattsColor,
                    probe: .batteryPowerValueColumn
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.hairline)
                    .frame(width: 0.5, height: 22)
                    .padding(.horizontal, 11)

                powerColumn(
                    label: "整机功耗",
                    value: systemPowerText,
                    color: .primary,
                    probe: .systemPowerValueColumn
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(padding: EdgeInsets(top: 9, leading: 11, bottom: 9, trailing: 11))
    }

    private func powerColumn(label: String, value: String, color: Color, probe: LayoutProbeID) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            CardLabel(text: label, size: 8.5)
            Text(value)
                .font(.system(size: 12.5, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 58, alignment: .leading)
                .layoutProbe(probe)
        }
    }

    private var chargeStatePill: some View {
        Text(chargeStateText)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(isGreenState ? Color.chargingGreenText : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(
                    isGreenState ? Color.runningGreen.opacity(0.14) : Color.primary.opacity(0.06)
                )
            )
            .fixedSize()
    }

    /// 充电三态（不依赖 kIOPSIsChargedKey）：
    /// isCharging→充电中；!isCharging && isOnAC && chargePercent>=99→已充满；
    /// !isCharging && isOnAC && chargePercent<99→电源接入（优化充电暂停等）；否则→使用电池。
    private var chargeStateText: String {
        if snapshot.isCharging { return "充电中" }
        if snapshot.isOnAC {
            return snapshot.chargePercent >= 99 ? "已充满" : "电源接入"
        }
        return "使用电池"
    }

    /// 带符号瓦数：充电为正 `+18.5W`（绿），放电为负 `−12.3W`（中性）；
    /// nil（电池键缺失或净功率 <0.1W）→ —。
    private var wattsText: String {
        guard let w = snapshot.watts else { return "—" }
        let sign = w >= 0 ? "+" : "−"
        return "\(sign)\(String(format: "%.1f", abs(w)))W"
    }

    private var wattsColor: Color {
        guard let w = snapshot.watts else { return .primary }
        return w >= 0 ? .chargingGreenText : .primary
    }

    /// 整机实时功耗（SMC PSTR），中性色；键不可用 → —。
    private var systemPowerText: String {
        guard let p = snapshot.systemPowerWatts else { return "—" }
        return "\(String(format: "%.1f", p))W"
    }
}

/// 窄信息卡（温度/风扇）：小型大写标签 + 14pt 等宽值 + 底部弱化说明行。
private struct InfoTile: View {
    let label: String
    let valueText: String?
    let valueUnit: String?
    let caption: String
    let captionColor: Color?
    let probe: LayoutProbeID

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardLabel(text: label)

            Group {
                if let valueText {
                    MetricValueText(number: valueText, unit: valueUnit, color: .primary, size: 14)
                } else {
                    Text("N/A")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 52, alignment: .leading)
            .layoutProbe(probe)

            Spacer(minLength: 2)

            Text(caption)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(captionColor ?? Color.metricLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 58, maxHeight: .infinity, alignment: .top)
        .cardSurface(padding: EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 8))
    }
}

// MARK: - Details Toggle & Detail Section

/// 概览排下方的极弱化展开按钮："详情 ⌄ / 收起 ⌃"。
struct DetailsToggleButton: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 3) {
                Text(isExpanded ? "收起" : "详情")
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .font(.system(size: 9.5))
            .foregroundStyle(Color.metricTertiary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -2)
    }
}

/// 展开的详细区：单卡内按电池、温度与状态、风扇组织只读表格。
struct DetailSectionView: View {
    let battery: BatterySnapshot?
    let thermal: ThermalSnapshot
    let fan: FanSnapshot
    let showsTemperature: Bool
    let showsFan: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let battery {
                DetailSectionHeader(systemImage: "battery.100", title: "电池")
                DetailHairline()
                DetailKeyValueRow(
                    label: "供电状态",
                    value: powerSourceText(battery),
                    valueWidth: StableValueWidth.batteryHealthTime,
                    probe: .detailBatteryValue
                )
                DetailHairline()
                DetailKeyValueRow(
                    label: "健康度",
                    value: healthText(battery),
                    valueWidth: StableValueWidth.batteryHealthTime
                )
                DetailHairline()
                DetailKeyValueRow(
                    label: "电池温度",
                    value: temperatureText(thermal.batteryTemperatureCelsius),
                    valueWidth: StableValueWidth.batteryHealthTime
                )
            }

            if showsTemperature {
                if battery != nil { DetailSectionDivider() }
                DetailSectionHeader(systemImage: "thermometer.medium", title: "温度与状态")
                DetailHairline()
                DetailKeyValueRow(
                    label: "系统状态",
                    value: thermalStateText,
                    valueWidth: StableValueWidth.temperature,
                    color: thermalStateColor
                )
                DetailHairline()
                DetailTemperaturePairRow(
                    socText: temperatureText(thermal.cpuSocTemperatureCelsius),
                    gpuText: temperatureText(thermal.gpuTemperatureCelsius)
                )
            }

            if showsFan, !visibleFans.isEmpty {
                if battery != nil || showsTemperature { DetailSectionDivider() }
                DetailSectionHeader(systemImage: "fan", title: "风扇", showsFanColumns: true)
                DetailHairline()
                ForEach(Array(visibleFans.enumerated()), id: \.element.id) { index, fanReading in
                    if index > 0 { DetailHairline() }
                    DetailFanTableRow(
                        name: fanReading.displayName,
                        current: fanCurrentText(fanReading),
                        target: fanTargetText(fanReading),
                        range: fanRangeText(fanReading),
                        probes: index == 0
                            ? (.detailFanCurrent, .detailFanTarget, .detailFanRange)
                            : (nil, nil, nil)
                    )
                }
                DetailHairline()
                Text(fanCapabilityText)
                    .font(.caption2)
                    .foregroundStyle(Color.metricLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
        }
        .cardSurface(padding: EdgeInsets(top: 10, leading: 11, bottom: 10, trailing: 11))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("电源与散热详细信息")
    }

    private var visibleFans: [FanReading] {
        guard fan.supportState != .unsupported else { return [] }
        return fan.fans
    }

    private var fanCapabilityText: String {
        let boundsText = visibleFans.allSatisfy { fanRangeText($0) != "N/A" }
            ? "边界可读"
            : "边界不可用"
        let hasSafeControl = visibleFans.contains { $0.capabilities.safeControlAvailable }
        return hasSafeControl ? boundsText : "\(boundsText) · 控制未启用"
    }

    // MARK: helpers

    private func temperatureText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "N/A" }
        return "\(Int(value.rounded()))°C"
    }

    private func fanCurrentText(_ fanReading: FanReading) -> String {
        guard fanReading.capabilities.rpmReadable,
              let rpm = validRPM(fanReading.currentRPM)
        else { return "N/A" }
        return "\(rpm)"
    }

    private func fanRangeText(_ fanReading: FanReading) -> String {
        guard fanReading.capabilities.boundsReadable,
              let minRPM = validRPM(fanReading.minRPM),
              let maxRPM = validRPM(fanReading.maxRPM),
              minRPM <= maxRPM
        else { return "N/A" }
        return "\(minRPM)–\(maxRPM) RPM"
    }

    private func fanTargetText(_ fanReading: FanReading) -> String {
        guard fanReading.capabilities.targetReadable,
              let targetValue = validRPM(fanReading.targetRPM)
        else { return "N/A" }
        return "\(targetValue)"
    }

    private func validRPM(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return Int(value.rounded())
    }

    private var thermalStateText: String {
        switch thermal.systemState {
        case .nominal: return "正常"
        case .fair: return "偏热"
        case .serious: return "严重"
        case .critical: return "临界"
        case .unknown: return "未知"
        }
    }

    private var thermalStateColor: Color {
        switch thermal.systemState {
        case .serious: return .metricAmber
        case .critical: return .metricRose
        case .unknown: return .secondary
        case .nominal, .fair: return .primary
        }
    }

    private func powerSourceText(_ battery: BatterySnapshot) -> String {
        if battery.isCharging { return "充电中" }
        if battery.isOnAC, battery.chargePercent >= 100 { return "已充满" }
        if battery.isOnAC { return "电源接入" }
        return "使用电池"
    }

    /// "92% · 320 次循环"；健康度缺失 → —；循环数缺失则仅显示百分比。
    private func healthText(_ battery: BatterySnapshot) -> String {
        guard let h = battery.healthPercent, h.isFinite else { return "—" }
        let pct = "\(Int(h.rounded()))%"
        if let cycles = battery.cycleCount {
            return "\(pct) · \(cycles) 次循环"
        }
        return pct
    }
}

private struct DetailSectionHeader: View {
    let systemImage: String
    let title: String
    var showsFanColumns = false

    var body: some View {
        HStack(spacing: 8) {
            if showsFanColumns {
                label.frame(width: StableValueWidth.detailFanLabel, alignment: .leading)
                columnTitle("当前", width: StableValueWidth.detailFanCurrent)
                columnTitle("目标", width: StableValueWidth.detailFanTarget)
                columnTitle("范围", width: StableValueWidth.detailFanRange)
            } else {
                label
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 6)
    }

    private var label: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 15)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Color.metricLabel)
    }

    private func columnTitle(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Color.metricLabel)
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }
}

private struct DetailKeyValueRow: View {
    let label: String
    let value: String
    let valueWidth: CGFloat
    var color: Color = .primary
    var probe: LayoutProbeID?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            StableValueText(
                text: value,
                width: valueWidth,
                color: color,
                fontWeight: .medium
            )
            .layoutProbe(probe)
        }
        .padding(.vertical, 5)
    }
}

private struct DetailTemperaturePairRow: View {
    let socText: String
    let gpuText: String

    var body: some View {
        HStack(spacing: 0) {
            temperatureCell(label: "SoC", value: socText, probe: .detailSoCTemperature)
            Rectangle()
                .fill(Color.hairline)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 8)
            temperatureCell(label: "GPU", value: gpuText, probe: .detailGPUTemperature)
        }
        .padding(.vertical, 5)
    }

    private func temperatureCell(label: String, value: String, probe: LayoutProbeID) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            StableValueText(
                text: value,
                width: StableValueWidth.temperature,
                color: value == "N/A" ? .secondary : .primary,
                fontWeight: .medium
            )
            .layoutProbe(probe)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DetailFanTableRow: View {
    let name: String
    let current: String
    let target: String
    let range: String
    let probes: (LayoutProbeID?, LayoutProbeID?, LayoutProbeID?)

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: StableValueWidth.detailFanLabel, alignment: .leading)

            tableValue(current, width: StableValueWidth.detailFanCurrent, probe: probes.0)
            tableValue(target, width: StableValueWidth.detailFanTarget, probe: probes.1)
            tableValue(range, width: StableValueWidth.detailFanRange, probe: probes.2)
        }
        .padding(.vertical, 5)
    }

    private func tableValue(_ text: String, width: CGFloat, probe: LayoutProbeID?) -> some View {
        StableValueText(
            text: text,
            width: width,
            color: text == "N/A" ? .secondary : .primary,
            fontWeight: .medium
        )
        .layoutProbe(probe)
    }
}

private struct DetailHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
    }
}

private struct DetailSectionDivider: View {
    var body: some View {
        DetailHairline()
            .padding(.vertical, 8)
    }
}

// MARK: - Battery Glyph

/// 电池图标：圆角外框 + 按电量填充 + 右侧凸点；充电/已充满时填充变绿，充电中叠 ⚡。
struct BatteryGlyph: View {
    let percent: Int
    let isCharging: Bool
    var isFull: Bool = false

    private var fraction: CGFloat { max(0, min(1, CGFloat(percent) / 100)) }

    private var fillColor: Color {
        if isCharging || isFull { return .runningGreen }
        if percent <= 20 { return .metricRose }
        return Color.primary.opacity(0.72)
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.32), lineWidth: 1.3)
                    .frame(width: 30, height: 14)

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(fillColor)
                    .frame(width: max(2, 26 * fraction), height: 10)
                    .padding(.leading, 2)

                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 14)
                }
            }
            Capsule()
                .fill(Color.primary.opacity(0.32))
                .frame(width: 2, height: 5)
        }
        .accessibilityLabel("电量 \(percent)%\(isCharging ? "，充电中" : "")")
    }
}

// MARK: - Process Resource Card (资源占用 TOP · CPU/内存 pill 切换)

/// mock 的单卡进程区："资源占用 TOP" 标题 + 右上角 CPU/内存 pill 分段。
/// 两个列表以 ZStack 同时渲染（未选中 opacity 0 + 禁点击），保证
/// cpu/memory 两个 LayoutProbe 恒存在且卡高稳定（取两列表最大高度）。
struct ProcessResourceCard: View {
    let cpuItems: [ProcessResourceUsage]
    let memoryItems: [ProcessResourceUsage]
    let isLoading: Bool

    @State private var selection: Tab = .cpu

    enum Tab { case cpu, memory }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                CardLabel(text: "资源占用 TOP")
                Spacer()
                picker
            }

            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("采样中...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
            } else {
                ZStack(alignment: .top) {
                    listView(
                        items: cpuItems,
                        trailingWidth: StableValueWidth.processCPU,
                        emptyTitle: "暂无 CPU 进程采样",
                        emptyBody: "等待 CPU 采样更新",
                        ratioValue: { $0.cpuPercent },
                        trailingText: { $0.cpuPercent.map { String(format: "%.1f", $0) } ?? "—" },
                        probe: .cpuProcessTrailingValue
                    )
                    .opacity(selection == .cpu ? 1 : 0)
                    .allowsHitTesting(selection == .cpu)

                    listView(
                        items: memoryItems,
                        trailingWidth: StableValueWidth.processMemory,
                        emptyTitle: "暂无内存进程采样",
                        emptyBody: "等待内存采样更新",
                        ratioValue: { Double($0.memoryBytes) },
                        trailingText: { ByteFormatting.format(Double($0.memoryBytes)) },
                        probe: .memoryProcessTrailingValue
                    )
                    .opacity(selection == .memory ? 1 : 0)
                    .allowsHitTesting(selection == .memory)
                }
            }
        }
        .cardSurface(padding: EdgeInsets(top: 10, leading: 11, bottom: 10, trailing: 11))
    }

    /// CPU / 内存 pill 分段（选中态白底蓝字）。
    private var picker: some View {
        HStack(spacing: 0) {
            pickerSegment("CPU", tab: .cpu)
            pickerSegment("内存", tab: .memory)
        }
        .padding(1.5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func pickerSegment(_ title: String, tab: Tab) -> some View {
        let isSelected = selection == tab
        return Text(title)
            .font(.system(size: 9.5, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.metricBlueText : Color.metricLabel)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .textBackgroundColor) : .clear)
                    .shadow(color: isSelected ? .black.opacity(0.12) : .clear, radius: 0.75, x: 0, y: 0.5)
            )
            .contentShape(Rectangle())
            .onTapGesture { selection = tab }
    }

    @ViewBuilder
    private func listView(
        items: [ProcessResourceUsage],
        trailingWidth: CGFloat,
        emptyTitle: String,
        emptyBody: String,
        ratioValue: @escaping (ProcessResourceUsage) -> Double?,
        trailingText: @escaping (ProcessResourceUsage) -> String,
        probe: LayoutProbeID
    ) -> some View {
        let top = Array(items.prefix(5))
        let maxRaw = top.compactMap(ratioValue).max() ?? 0

        if top.isEmpty {
            VStack(spacing: 2) {
                Text(emptyTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(emptyBody)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(top, id: \.pid) { proc in
                    ProcessMetricRow(
                        processName: proc.processName,
                        pid: nil,  // mock 不显示 pid，保持行干净（网络进程区仍显示）
                        trailingWidth: trailingWidth,
                        ratio: maxRaw > 0 ? ratioValue(proc).map { max(0, min(1, $0 / maxRaw)) } : nil
                    ) {
                        StableValueText(
                            text: trailingText(proc),
                            width: trailingWidth,
                            color: .primary,
                            font: .system(.caption2, design: .monospaced)
                        )
                        .layoutProbe(probe)
                    }
                }
            }
        }
    }
}

// MARK: - Dashboard Footer

/// 底部：自身占用（弱化）+ "退出" 低调 pill。
struct DashboardFooter: View {
    let selfCpuUsage: Double
    let selfMemoryMB: Double

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.hairline)
            HStack {
                Text("自身 \(String(format: "%.1f", selfCpuUsage))% · \(Int(selfMemoryMB))MB")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color.metricTertiary)
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("退出")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(.top, 2)
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
        // 用换行分隔上/下行，强制始终竖排（↓ 主行在上、↑ 弱化在下，对齐 1a mock），
        // 避免随数值长短在"并排一行"与"折成两行"之间来回抖动。
        networkText = "↓\(down)\n↑\(up)"

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
