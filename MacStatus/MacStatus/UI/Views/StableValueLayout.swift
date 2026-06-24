import AppKit
import SwiftUI

// MARK: - Stable Dashboard Layout

enum DashboardLayout {
    static let popoverWidth = 372 as CGFloat
}

enum StableValueWidth {
    static let percentage = 64 as CGFloat
    static let memoryMetricCard = 96 as CGFloat
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

// MARK: - Layout Probe

enum LayoutProbeID: String, Hashable, CaseIterable {
    case networkMetricCardValue
    case temperatureValueColumn
    case fanRPMValueColumn
    case batteryPowerValueColumn
    case systemPowerValueColumn
    case networkProcessTrailingValue
    case cpuProcessTrailingValue
    case memoryProcessTrailingValue
}

struct LayoutProbeFrameSnapshot {
    let frames: [LayoutProbeID: CGRect]
}

struct LayoutProbeKey: PreferenceKey {
    static let defaultValue: [LayoutProbeID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [LayoutProbeID: Anchor<CGRect>],
        nextValue: () -> [LayoutProbeID: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

@MainActor
final class LayoutProbeFrameStore {
    private(set) var snapshot = LayoutProbeFrameSnapshot(frames: [:])

    func update(_ snapshot: LayoutProbeFrameSnapshot) {
        self.snapshot = snapshot
    }
}

extension View {
    func layoutProbe(_ id: LayoutProbeID) -> some View {
#if DEBUG
        anchorPreference(key: LayoutProbeKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
#else
        self
#endif
    }

    @ViewBuilder
    func layoutProbe(_ id: LayoutProbeID?) -> some View {
        if let id {
            layoutProbe(id)
        } else {
            self
        }
    }

    func readLayoutProbeFrames(into store: LayoutProbeFrameStore) -> some View {
#if DEBUG
        modifier(LayoutProbeFrameReader(store: store))
#else
        self
#endif
    }
}

#if DEBUG
private struct LayoutProbeFrameReader: ViewModifier {
    let store: LayoutProbeFrameStore

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(LayoutProbeKey.self) { anchors in
            GeometryReader { proxy in
                LayoutProbeFrameUpdater(
                    snapshot: LayoutProbeFrameSnapshot(
                        frames: anchors.mapValues { proxy[$0] }
                    ),
                    store: store
                )
            }
        }
    }
}

private struct LayoutProbeFrameUpdater: NSViewRepresentable {
    let snapshot: LayoutProbeFrameSnapshot
    let store: LayoutProbeFrameStore

    func makeNSView(context: Context) -> NSView {
        store.update(snapshot)
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        store.update(snapshot)
    }
}
#endif
