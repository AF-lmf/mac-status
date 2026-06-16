import SwiftUI

// MARK: - Sparkline View

/// A compact line chart showing recent metric history in a rolling window.
/// Uses SwiftUI Canvas for efficient rendering with zero allocations per frame.
///
/// Designed to be embedded inside MetricCard in the popover.
/// The chart auto-scales to the visible data range.
struct SparklineView: View {
    /// Historical data points (newest last).
    let samples: [Double]
    /// Color for the line and fill.
    let color: Color
    /// Maximum number of data points to display.
    var maxSamples: Int = 60
    /// Whether to show a gradient fill under the line.
    var showFill: Bool = true

    var body: some View {
        Canvas { context, size in
            let displaySamples = samples.suffix(maxSamples)
            guard displaySamples.count >= 2 else { return }

            let minValue = displaySamples.min() ?? 0
            let maxValue = displaySamples.max() ?? 100
            let range = max(maxValue - minValue, 1) // avoid division by zero

            let stepX = size.width / CGFloat(displaySamples.count - 1)
            let padding: CGFloat = 1

            // Build path
            var path = Path()
            var fillPath = Path()

            for (index, value) in displaySamples.enumerated() {
                let x = CGFloat(index) * stepX
                let normalizedY = CGFloat((value - minValue) / range)
                let y = size.height - padding - normalizedY * (size.height - 2 * padding)

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                    fillPath.move(to: CGPoint(x: x, y: size.height))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Close fill path
            let lastX = CGFloat(displaySamples.count - 1) * stepX
            fillPath.addLine(to: CGPoint(x: lastX, y: size.height))
            fillPath.closeSubpath()

            // Draw fill gradient
            if showFill {
                let gradient = Gradient(colors: [
                    color.opacity(0.3),
                    color.opacity(0.05),
                ])
                context.fill(
                    fillPath,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }

            // Draw line
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )

            // Draw current value dot (last point)
            if let lastValue = displaySamples.last {
                let lastNormY = CGFloat((lastValue - minValue) / range)
                let dotY = size.height - padding - lastNormY * (size.height - 2 * padding)
                let dotRect = CGRect(
                    x: lastX - 2, y: dotY - 2,
                    width: 4, height: 4
                )
                context.fill(
                    Path(ellipseIn: dotRect),
                    with: .color(color)
                )
            }
        }
        .frame(height: 30)
    }
}
