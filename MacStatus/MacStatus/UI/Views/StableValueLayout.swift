import SwiftUI

// MARK: - Stable Dashboard Layout

enum DashboardLayout {
    static let popoverWidth = 372 as CGFloat
}

enum StableValueWidth {
    static let percentage = 64 as CGFloat
    static let networkCard = 76 as CGFloat
    static let processNetworkRate = 68 as CGFloat
    static let processNetworkPair = 148 as CGFloat
    static let temperature = 56 as CGFloat
    static let fanRPM = 78 as CGFloat
    static let batteryPower = 104 as CGFloat
    static let batteryHealthTime = 112 as CGFloat
    static let processCPU = 52 as CGFloat
    static let processMemory = 68 as CGFloat
}

struct StableValueText: View {
    let text: String
    let width: CGFloat
    var color: Color = .secondary
    var font: Font = .system(.caption, design: .monospaced)
    var fontWeight: Font.Weight?
    var lineLimit: Int = 1

    var body: some View {
        Text(text)
            .font(font)
            .fontWeight(fontWeight)
            .monospacedDigit()
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.9)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: .trailing)
            .layoutPriority(1)
    }
}

struct StableValueRow<Value: View>: View {
    let label: String
    let spacing: CGFloat
    @ViewBuilder let value: () -> Value

    init(
        label: String,
        spacing: CGFloat = 8,
        @ViewBuilder value: @escaping () -> Value
    ) {
        self.label = label
        self.spacing = spacing
        self.value = value
    }

    var body: some View {
        HStack(spacing: spacing) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)

            value()
        }
    }
}

struct StableCaptionText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)
    }
}
