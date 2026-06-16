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
                    Text("Sampling...")
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
                Text("No active network processes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(processes.prefix(5).enumerated()), id: \.offset) { _, proc in
                    ProcessRow(process: proc)
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

// MARK: - Process Row

private struct ProcessRow: View {
    let process: ProcessNetworkUsage

    var body: some View {
        HStack(spacing: 6) {
            Text(process.processName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)

            if let pid = process.processIdentifier {
                Text("(\(pid))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Label(
                ByteFormatting.format(process.uploadBytesPerSec) + "/s",
                systemImage: "arrow.up"
            )
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.orange)

            Label(
                ByteFormatting.format(process.downloadBytesPerSec) + "/s",
                systemImage: "arrow.down"
            )
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.blue)
        }
        .padding(.vertical, 1)
    }
}
