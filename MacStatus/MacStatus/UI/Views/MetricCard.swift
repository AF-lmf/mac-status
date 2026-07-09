import AppKit
import SwiftUI

// MARK: - Design Tokens (1a "Refined Native" palette)
//
// 语义配色从 v2 的红/黄/绿信号灯迁移到蓝/琥珀/玫红柔和梯度（正常=品牌蓝，
// 而非绿；绿色只保留给"运行中"状态点与"充电"）。所有令牌都提供亮/暗两套，
// 通过动态 NSColor 随 colorScheme 自动切换。数值以此文件为准。

extension Color {

    /// 从 "#RRGGBB" 初始化；非法输入回退到 `.clear`（不 crash）。
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .clear
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            opacity: 1.0
        )
    }

    /// 亮/暗自适应颜色，由动态 NSColor provider 背书（随外观自动切换，
    /// 无需在视图层手动读取 `@Environment(\.colorScheme)`）。
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    fileprivate static func hex(_ string: String) -> NSColor { NSColor(hex: string) ?? .clear }
    fileprivate static func black(_ alpha: CGFloat) -> NSColor { NSColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha) }
    fileprivate static func white(_ alpha: CGFloat) -> NSColor { NSColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha) }
}

extension Color {

    // MARK: 语义强调色（环 / 描边 / 填充 / 进度 / sparkline）
    static let metricBlue = dynamic(light: hex("#0A84FF"), dark: hex("#4DA3FF"))
    static let metricAmber = dynamic(light: hex("#C9821F"), dark: hex("#E3A24A"))
    static let metricRose = dynamic(light: hex("#D6455A"), dark: hex("#F26D7D"))

    // MARK: 数值文字变体（比强调色深一档，用于卡片大数字）
    static let metricBlueText = dynamic(light: hex("#0A6FD6"), dark: hex("#7AB6FF"))
    static let metricAmberText = dynamic(light: hex("#9C6310"), dark: hex("#E3A24A"))
    static let metricRoseText = dynamic(light: hex("#C23A4C"), dark: hex("#F26D7D"))

    // MARK: 运行中 / 充电 绿（仅状态点与充电，不用于负载语义）
    static let runningGreen = dynamic(light: hex("#30B85A"), dark: hex("#32D74B"))
    static let chargingGreenText = dynamic(light: hex("#30875A"), dark: hex("#5CD98A"))

    // MARK: 中性文本
    /// 小型大写标签色（二级）。
    static let metricLabel = dynamic(
        light: NSColor(srgbRed: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 0.55),
        dark: NSColor(srgbRed: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: 0.55)
    )
    /// 三级弱化文本（自身占用、单位等）。
    static let metricTertiary = dynamic(
        light: NSColor(srgbRed: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 0.42),
        dark: NSColor(srgbRed: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: 0.42)
    )

    // MARK: 卡片表面
    static let cardFill = dynamic(light: black(0.028), dark: white(0.05))
    static let cardStroke = dynamic(light: black(0.05), dark: white(0.06))
    /// 环形轨道 / 占比条轨道底色。
    static let trackFill = dynamic(light: black(0.09), dark: white(0.13))
    /// 分隔线。
    static let hairline = dynamic(light: black(0.09), dark: white(0.12))
}

// MARK: - Metric Tint

/// 一个指标的成对语义色：`accent` 用于环/描边/填充/sparkline，`text` 用于大数字。
struct MetricTint {
    let accent: Color
    let text: Color

    /// 按负载百分比映射（阈值 60/80 不变）：正常=蓝，偏高=琥珀，过载=玫红。
    static func usage(_ percent: Double) -> MetricTint {
        switch percent {
        case ..<60: return MetricTint(accent: .metricBlue, text: .metricBlueText)
        case ..<80: return MetricTint(accent: .metricAmber, text: .metricAmberText)
        default: return MetricTint(accent: .metricRose, text: .metricRoseText)
        }
    }

    /// 网络恒为品牌蓝（不参与负载阈值语义）。
    static let network = MetricTint(accent: .metricBlue, text: .metricBlueText)
}

// MARK: - Color Helpers

extension Color {
    /// 数值文字语义色（蓝/琥珀/玫红）。取代旧的 green/yellow/red 信号灯。
    static func usageColor(_ percent: Double) -> Color { MetricTint.usage(percent).text }

    /// 强调语义色（环/描边/填充）。
    static func usageAccent(_ percent: Double) -> Color { MetricTint.usage(percent).accent }
}

// MARK: - Small-caps Card Label

/// 小型大写标签：SF Rounded semibold + 字距 + 大写（Space Grotesk 的原生 fallback）。
struct CardLabel: View {
    let text: String
    var color: Color = .metricLabel
    var size: CGFloat = 9

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

// MARK: - Metric Value Text

/// 大号等宽数值 + 小号单位（如 `23%` 中的 `%` 更小更淡），复刻 1a 卡片读数。
struct MetricValueText: View {
    let number: String
    var unit: String? = nil
    let color: Color
    var size: CGFloat = 16

    var body: some View {
        let numberText = Text(number)
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .foregroundColor(color)
        if let unit {
            (numberText + Text(unit)
                .font(.system(size: size * 0.62, weight: .medium, design: .monospaced))
                .foregroundColor(color.opacity(0.45)))
                .monospacedDigit()
        } else {
            numberText
                .monospacedDigit()
        }
    }
}

// MARK: - Card Surface

/// 1a 半透明圆角卡片容器：`cardFill` + 0.5pt `cardStroke` 描边，圆角 12。
struct CardSurface: ViewModifier {
    var padding: EdgeInsets = EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10)
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.cardStroke, lineWidth: 0.5)
                    )
            )
    }
}

extension View {
    /// 套用 1a 卡片表面样式。
    func cardSurface(
        padding: EdgeInsets = EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10),
        cornerRadius: CGFloat = 12
    ) -> some View {
        modifier(CardSurface(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Metric Card

/// 单个指标卡（无 sparkline 的精简版；当前仅 `MetricCardWithSparkline` 在用，
/// 保留此类型并套用新卡片语言以维持一致性）。
struct MetricCard: View {
    let title: String
    let value: String
    let progress: Double // 0.0 ... 1.0
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                CardLabel(text: title)
                Spacer()
                Text(value)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.trackFill).frame(height: 4)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)), height: 4)
                }
            }
            .frame(height: 4)
        }
        .cardSurface()
    }
}
