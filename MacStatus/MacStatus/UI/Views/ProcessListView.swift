import SwiftUI

// MARK: - Process List View

/// Displays the top 5 processes by network usage in the popover.
/// Shows process name, PID, upload/download rates.
struct ProcessListView: View {
    let processes: [ProcessNetworkUsage]
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top Processes (by network)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

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
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - Network Traffic Value Block

struct NetworkTrafficValueBlock: View {
    let uploadText: String
    let downloadText: String

    var body: some View {
        HStack(spacing: 12) {
            rateLabel(uploadText, systemImage: "arrow.up", color: .orange)
            rateLabel(downloadText, systemImage: "arrow.down", color: .blue)
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

// MARK: - Process Metric Row

/// Generic process row: name + optional PID on the left; arbitrary trailing content on the right.
/// Used by the network, CPU, and memory process sections.
struct ProcessMetricRow<Trailing: View>: View {
    let processName: String
    let pid: Int32?
    let trailingWidth: CGFloat
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
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
            trailing()
                .frame(width: trailingWidth, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.vertical, 1)
    }
}
