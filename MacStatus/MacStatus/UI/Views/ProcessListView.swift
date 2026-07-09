import SwiftUI

// MARK: - Process List View

/// Displays the top 5 processes by network usage in the popover.
/// Shows process name, PID, upload/download rates.
struct ProcessListView: View {
    let processes: [ProcessNetworkUsage]
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "网络占用 TOP")

            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("采样中...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if processes.isEmpty {
                VStack(spacing: 2) {
                    Text("暂无活跃网络进程")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("等待新的网络进程活动")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else {
                ForEach(processes.prefix(5), id: \.stableID) { proc in
                    ProcessMetricRow(
                        processName: proc.processName,
                        pid: proc.processIdentifier,
                        trailingWidth: StableValueWidth.processNetworkPair
                    ) {
                        NetworkTrafficValueBlock(
                            uploadText: ByteFormatting.format(proc.uploadBytesPerSec) + "/s",
                            downloadText: ByteFormatting.format(proc.downloadBytesPerSec) + "/s"
                        )
                        .layoutProbe(.networkProcessTrailingValue)
                    }
                }
            }
        }
        .cardSurface(padding: EdgeInsets(top: 10, leading: 11, bottom: 10, trailing: 11))
    }
}

// MARK: - Network Traffic Value Block

struct NetworkTrafficValueBlock: View {
    let uploadText: String
    let downloadText: String

    var body: some View {
        HStack(spacing: 12) {
            rateLabel(uploadText, systemImage: "arrow.up", color: .metricAmber)
            rateLabel(downloadText, systemImage: "arrow.down", color: .metricBlue)
        }
        .frame(width: StableValueWidth.processNetworkPair, alignment: .trailing)
        .layoutPriority(1)
    }

    private func rateLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(.caption2, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .frame(width: StableValueWidth.processNetworkRate, alignment: .trailing)
    }
}

// MARK: - Ratio Bar

/// 细占比条：轨道 + 前景填充（ratio 0...1）。圆角 2，固定 52×4。
struct RatioBar: View {
    let ratio: Double
    var color: Color = .metricBlue

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.trackFill)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, ratio))))
            }
        }
        .frame(width: 52, height: 4)
    }
}

// MARK: - Process Metric Row

/// Generic process row: name + optional PID on the left; optional ratio bar; arbitrary trailing content.
/// Used by the network, CPU, and memory process sections. `ratio == nil` omits the bar (network rows).
struct ProcessMetricRow<Trailing: View>: View {
    let processName: String
    let pid: Int32?
    let trailingWidth: CGFloat
    var ratio: Double? = nil
    var ratioColor: Color = .metricBlue
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 4) {
                Text(processName)
                    .font(.caption2)

                if let pid {
                    Text("(\(pid))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)

            if let ratio {
                RatioBar(ratio: ratio, color: ratioColor)
                    .layoutPriority(1)
            }

            trailing()
                .frame(width: trailingWidth, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.vertical, 1)
    }
}
