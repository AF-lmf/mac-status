import SwiftUI

// MARK: - Metric Card

/// A single metric card displayed in the popover dashboard.
/// Shows title, current value, and a colored progress bar.
struct MetricCard: View {
    let title: String
    let value: String
    let progress: Double // 0.0 ... 1.0
    let color: Color

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
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - Color Helpers

extension Color {
    /// Returns green/yellow/red based on usage percentage thresholds.
    static func usageColor(_ percent: Double) -> Color {
        switch percent {
        case ..<60:
            return .green
        case ..<80:
            return .yellow
        default:
            return .red
        }
    }
}
