import AppKit
import SwiftUI

// MARK: - Status Bar Manager

/// Manages the NSStatusItem lifecycle and user interactions.
///
/// M002: Supports three display modes (full/compact/percentage) with
/// NSAttributedString colored text. Left-click toggles NSPopover.
///
/// Thread safety: All methods must be called on the main thread.
///
/// Repaint path: SettingsManager posts .settingsDidChange → MetricCollector
/// observer calls reconfigure() or applyNow() → updateUI(sample:) →
/// StatusBarManager.updateTitle(...). StatusBarManager itself does NOT register
/// a .settingsDidChange observer — doing so would trigger a double applyNow().
@MainActor
final class StatusBarManager {

    // MARK: - Singleton

    static let shared = StatusBarManager()

    // MARK: - Properties

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var popoverManager: PopoverManager?
    private var rightClickMenu: NSMenu?

    // MARK: - Initialization

    private init() {
        setupStatusBarButton()
        setupRightClickMenu()
    }

    // MARK: - Setup

    private func setupStatusBarButton() {
        guard let button = statusItem.button else { return }
        button.title = "⏳ Initializing..."
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupRightClickMenu() {
        let menu = NSMenu()

        let prefsItem = NSMenuItem(
            title: "偏好设置…",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 MacStatus",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        self.rightClickMenu = menu
    }

    func configure(popoverManager: PopoverManager) {
        self.popoverManager = popoverManager
    }

    // MARK: - Popover Anchor Width

    /// Pin the status item to its current width while the popover is open.
    ///
    /// The popover is anchored to this item via `show(relativeTo:of:)`. The item
    /// uses `variableLength`, so each refresh's title-width change resizes the
    /// item, shifts the button, and drags the attached popover left/right. Pinning
    /// the width holds the anchor still while the title text keeps updating, so the
    /// menu-bar numbers stay live and the popover no longer jitters. A value that
    /// grows wider than the pinned width is clipped until the popover closes.
    func pinWidthForPopover() {
        guard let button = statusItem.button else { return }
        statusItem.length = button.frame.width
    }

    /// Restore automatic width sizing once the popover closes; the item snaps back
    /// to fit the current (already up-to-date) title.
    func unpinWidthForPopover() {
        statusItem.length = NSStatusItem.variableLength
    }

    // MARK: - Title Update (2a–2d Menu Bar Styles)

    /// Render the status bar item per SettingsManager.menuBarStyle:
    /// 2a sparkline（标签+微型曲线+数值）/ 2b rings（标签+环+数值）/
    /// 2c capsule（玻璃胶囊：圆点+标签+数值）/ 2d levelBar（数值上、水位条下）。
    ///
    /// Reads SettingsManager.metricOrder + enabledMetrics to determine which metrics
    /// to render and in what order. The SwiftUI `MenuBarMetricsView` is rasterised via
    /// `ImageRenderer` and assigned to `button.image` (isTemplate=false so the coloured
    /// readouts survive). The button auto-sizes to the image, so `pinWidthForPopover()`
    /// (reads `button.frame.width`) keeps working unchanged. Falls back to "◆" when
    /// nothing is enabled.
    func updateTitle(
        cpuUsage: Double?,
        memoryStats: MemoryStats?,
        networkStats: NetworkStats?,
        gpuStats: GPUStats?,
        cpuSamples: [Double] = [],
        memorySamples: [Double] = [],
        gpuSamples: [Double] = [],
        networkSamples: [Double] = []
    ) {
        guard let button = statusItem.button else { return }

        let settings = SettingsManager.shared
        let order   = settings.metricOrder           // [Metric]
        let enabled = Set(settings.enabledMetrics)   // Set<Metric> for O(1) lookup
        let style   = settings.menuBarStyle

        let active = order.filter { enabled.contains($0) }

        // 菜单栏外观（可能与 App 全局外观不同：浅色系统 + 深色壁纸时菜单栏为 darkAqua）。
        // ImageRenderer 离屏渲染不会继承按钮外观，动态色必须先按此外观解析成具体色值。
        let appearance = button.effectiveAppearance

        var items: [MenuBarMetricsView.Item] = []
        for metric in active {
            switch metric {
            case .cpu:
                items.append(usageItem(cpuUsage, metric: .cpu, label: "CPU", samples: cpuSamples, appearance: appearance))
            case .memory:
                items.append(usageItem(memoryStats?.usedPercent, metric: .memory, label: "MEM", samples: memorySamples, appearance: appearance))
            case .gpu:
                items.append(usageItem(gpuStats?.utilizationPercent, metric: .gpu, label: "GPU", samples: gpuSamples, appearance: appearance))
            case .network:
                items.append(networkItem(networkStats, samples: networkSamples, appearance: appearance))
            case .battery:
                break  // Phase 7 reserved — no menu bar segment
            }
        }

        // 空启用集（或仅 .battery）——回退占位符，保持"菜单栏永不为空"的不变量。
        if items.isEmpty {
            button.image = nil
            button.imagePosition = .noImage
            button.title = "◆"
            return
        }

        let isDark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let renderer = ImageRenderer(content: MenuBarMetricsView(style: style, items: items, isDark: isDark))
        renderer.scale = button.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2.0

        if let image = renderer.nsImage {
            image.isTemplate = false   // 读数是彩色，不能被系统染成单色
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        }
    }

    // MARK: - Menu Bar Item Builders

    /// 负载型指标项（CPU/内存/GPU）：强调色给环/曲线/水位条/圆点，
    /// 数值用深/亮一档的文字变体（mock：环 #0A84FF、字 #0A6FD6）。
    private func usageItem(
        _ value: Double?,
        metric: Metric,
        label: String,
        samples: [Double],
        appearance: NSAppearance
    ) -> MenuBarMetricsView.Item {
        let usage = value ?? 0
        return MenuBarMetricsView.Item(
            label: label,
            number: value == nil ? "--" : "\(Int(usage))",
            unit: value == nil ? nil : "%",
            accent: Self.resolvedColor(colorForUsage(usage, metric: metric), in: appearance),
            numberColor: Self.resolvedColor(textColorForUsage(usage, metric: metric), in: appearance),
            progress: usage / 100.0,
            samples: samples
        )
    }

    /// 网络项：下行速率文字（`↓4.2M`），恒为品牌蓝；水位条按 100MB/s 满量程。
    private func networkItem(
        _ net: NetworkStats?,
        samples: [Double],
        appearance: NSAppearance
    ) -> MenuBarMetricsView.Item {
        let down = net?.downloadBytesPerSec
        let (number, unit) = Self.splitRate(down)
        let total = (net?.downloadBytesPerSec ?? 0) + (net?.uploadBytesPerSec ?? 0)
        return MenuBarMetricsView.Item(
            label: "NET",
            number: number,
            unit: unit,
            accent: Self.resolvedColor(Self.normalBlue, in: appearance),
            numberColor: Self.resolvedColor(Self.normalBlueText, in: appearance),
            progress: min(total / (100 * 1_000_000), 1.0),
            samples: samples
        )
    }

    /// 把（可能是动态的）NSColor 按指定外观解析为具体 sRGB 色值。
    /// ImageRenderer 离屏渲染不走 AppKit 外观链，动态 provider 色若不预解析，
    /// 会按 App 全局外观取值（浅色系统 + 深色菜单栏时取错变体，显示发灰）。
    private static func resolvedColor(_ nsColor: NSColor, in appearance: NSAppearance) -> Color {
        var resolved = nsColor
        appearance.performAsCurrentDrawingAppearance {
            if let concrete = NSColor(cgColor: nsColor.cgColor)?.usingColorSpace(.sRGB) {
                resolved = concrete
            }
        }
        return Color(nsColor: resolved)
    }

    /// "↓4.2M" → 数字部分 "↓4.2" + 小号单位 "M"（mock 的单位小字排法）。
    private static func splitRate(_ bytesPerSec: Double?) -> (String, String?) {
        guard let bytesPerSec else { return ("↓--", nil) }
        let text = ByteFormatting.format(bytesPerSec)   // e.g. "4.2M" / "512B"
        let digits = text.prefix { !$0.isLetter }
        let unit = String(text.dropFirst(digits.count))
        return ("↓" + digits, unit.isEmpty ? nil : unit)
    }

    // MARK: - Color

    /// Color based on usage percentage, reading real-time custom thresholds and colors
    /// from SettingsManager. Falls back to semantic system colors (.systemOrange, .systemRed,
    /// .labelColor) when no custom values are configured.
    ///
    /// T-06-06: NSColor(hex:) returns nil on malformed input — caller falls back to system color.
    /// T-06-07: threshold clamping is handled at the SettingsManager setter side.
    private func colorForUsage(_ percent: Double, metric: Metric) -> NSColor {
        let settings = SettingsManager.shared

        let warning  = settings.customThresholds[metric.rawValue]?["warning"]  ?? defaultWarning(for: metric)
        let critical = settings.customThresholds[metric.rawValue]?["critical"] ?? defaultCritical(for: metric)

        if percent >= critical {
            if let hex = settings.customColors[metric.rawValue]?["critical"],
               let color = NSColor(hex: hex) { return color }
            return Self.overloadRose   // 过载 · 玫红（取代 systemRed）
        } else if percent >= warning {
            if let hex = settings.customColors[metric.rawValue]?["warning"],
               let color = NSColor(hex: hex) { return color }
            return Self.highAmber      // 偏高 · 琥珀（取代 systemOrange）
        }
        return Self.normalBlue         // 正常 · 品牌蓝（取代 .labelColor）
    }

    /// 数字文字色：自定义色命中时与环同色，否则用比环深/亮一档的文字变体。
    private func textColorForUsage(_ percent: Double, metric: Metric) -> NSColor {
        let settings = SettingsManager.shared

        let warning  = settings.customThresholds[metric.rawValue]?["warning"]  ?? defaultWarning(for: metric)
        let critical = settings.customThresholds[metric.rawValue]?["critical"] ?? defaultCritical(for: metric)

        if percent >= critical {
            if let hex = settings.customColors[metric.rawValue]?["critical"],
               let color = NSColor(hex: hex) { return color }
            return Self.overloadRoseText
        } else if percent >= warning {
            if let hex = settings.customColors[metric.rawValue]?["warning"],
               let color = NSColor(hex: hex) { return color }
            return Self.highAmberText
        }
        return Self.normalBlueText
    }

    // MARK: - Fallback Palette (blue / amber / rose, light + dark)

    /// 亮/暗自适应 NSColor。非法 hex 回退到 `.labelColor`。
    private static func dynamic(light: String, dark: String) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light) ?? .labelColor
        }
    }

    private static let normalBlue = dynamic(light: "#0A84FF", dark: "#4DA3FF")
    private static let highAmber = dynamic(light: "#C9821F", dark: "#E3A24A")
    private static let overloadRose = dynamic(light: "#D6455A", dark: "#F26D7D")

    private static let normalBlueText = dynamic(light: "#0A6FD6", dark: "#7AB6FF")
    private static let highAmberText = dynamic(light: "#9C6310", dark: "#E3A24A")
    private static let overloadRoseText = dynamic(light: "#C23A4C", dark: "#F26D7D")

    /// Fallback warning threshold when no custom value is configured for the metric.
    private func defaultWarning(for metric: Metric) -> Double {
        switch metric {
        case .cpu:     return SettingsManager.shared.cpuWarningThreshold
        case .memory:  return SettingsManager.shared.memoryWarningThreshold
        case .gpu:     return 80.0
        default:       return 80.0
        }
    }

    /// Fallback critical threshold when no custom value is configured for the metric.
    private func defaultCritical(for metric: Metric) -> Double {
        switch metric {
        case .cpu:     return SettingsManager.shared.cpuCriticalThreshold
        case .memory:  return SettingsManager.shared.memoryCriticalThreshold
        case .gpu:     return 90.0
        default:       return 90.0
        }
    }

    // MARK: - Actions

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            if let menu = rightClickMenu {
                statusItem.menu = menu
                sender.performClick(nil)
                statusItem.menu = nil
            }
        } else {
            popoverManager?.toggle(from: sender)
        }
    }

    @objc private func showPreferences() {
        SettingsWindowManager.shared.showSettings()
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Menu Bar Metrics View (2a–2d)

/// SwiftUI 承载视图，经 `ImageRenderer` 渲成菜单栏图像。
/// 按 `MenuBarStyle` 渲染四种呈现：
/// 2a sparkline＝标签+微型曲线+数值；2b rings＝标签+环+数值；
/// 2c capsule＝半透明胶囊内圆点+标签+数值；2d levelBar＝数值上、水位条下。
struct MenuBarMetricsView: View {
    struct Item: Identifiable {
        let id = UUID()
        let label: String?      // 小型大写标签（"CPU"）；胶囊里的网络段不显示
        let number: String      // "23" / "↓4.2" / "--"
        let unit: String?       // 小号后缀："%" / "M"
        let accent: Color       // 环 / 曲线 / 水位条 / 圆点色
        let numberColor: Color  // 数值色（胶囊样式下改用主文本色）
        let progress: Double?   // rings / levelBar 用（0...1）
        let samples: [Double]   // sparkline 用
    }

    let style: MenuBarStyle
    let items: [Item]
    let isDark: Bool

    private var labelColor: Color {
        isDark ? Color(.sRGB, red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: 0.55)
               : Color(.sRGB, red: 60 / 255, green: 60 / 255, blue: 67 / 255, opacity: 0.55)
    }

    private var trackColor: Color {
        isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.13)
    }

    private var primaryText: Color {
        isDark ? Color(hex: "#F5F5F7") : Color(hex: "#1C1C1E")
    }

    var body: some View {
        Group {
            switch style {
            case .sparkline: sparklineBody
            case .rings: ringsBody
            case .capsule: capsuleBody
            case .levelBar: levelBarBody
            }
        }
        .environment(\.colorScheme, isDark ? .dark : .light)
        .padding(.horizontal, 1)
        .frame(height: 22)
        .fixedSize()
    }

    // MARK: 共用小部件

    private func labelText(_ text: String, size: CGFloat = 8) -> some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(labelColor)
    }

    private func valueText(_ item: Item, color: Color? = nil, size: CGFloat = 12) -> Text {
        styledValue(number: item.number, unit: item.unit, color: color ?? item.numberColor, size: size)
    }

    private func styledValue(number: String, unit: String?, color: Color, size: CGFloat) -> Text {
        let base = Text(number)
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .foregroundColor(color)
        guard let unit else { return base }
        return base + Text(unit)
            .font(.system(size: size * 0.67, weight: .medium, design: .monospaced))
            .foregroundColor(color.opacity(0.5))
    }

    /// 固定宽度数值槽：以最宽模板（等宽字体下 "888%" / "↓888M"）隐藏占位，
    /// 实际值左对齐（紧贴前面的环/曲线/标签，mock 的紧凑间距），富余空白留在组间。
    /// 位数从一位变两位时槽宽不变 → 渲染出的菜单栏图像宽度恒定，状态项不抖动。
    private func slotValue(_ item: Item, color: Color? = nil, size: CGFloat = 12) -> some View {
        let (templateNumber, templateUnit) = template(for: item)
        return ZStack(alignment: .leading) {
            styledValue(number: templateNumber, unit: templateUnit, color: .clear, size: size)
                .hidden()
            valueText(item, color: color, size: size)
        }
    }

    /// 数值槽模板：网络（↓ 前缀）按 "↓888M"；百分比按 "888"（含小 % 时带后缀）。
    /// 等宽字体下数字/字母/小数点同宽，模板即最大占位。
    private func template(for item: Item) -> (String, String?) {
        if item.number.hasPrefix("↓") {
            return ("↓888", item.unit ?? "M")
        }
        return ("888", item.unit)
    }

    // MARK: 2a 迷你趋势线

    private var sparklineBody: some View {
        HStack(spacing: 13) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    if let label = item.label { labelText(label) }
                    MenuBarSparkline(samples: item.samples, color: item.accent)
                        .frame(width: 24, height: 13)
                    slotValue(item)
                }
            }
        }
    }

    // MARK: 2b 环形量规

    private var ringsBody: some View {
        HStack(spacing: 13) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    if let label = item.label { labelText(label) }
                    if let progress = item.progress, item.unit == "%" {
                        MenuBarRing(progress: progress, color: item.accent, trackColor: trackColor)
                    }
                    // 数值带小号 % 后缀（一位数如 "9" 单独出现语义不明）
                    slotValue(item)
                }
            }
        }
    }

    // MARK: 2c 玻璃胶囊

    private var capsuleBody: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.12))
                        .frame(width: 0.5, height: 13)
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(item.accent)
                        .frame(width: 5, height: 5)
                    // 网络段不显示 NET 标签（mock：圆点 + ↓4.2M）
                    if let label = item.label, item.unit == "%" { labelText(label) }
                    slotValue(item, color: primaryText)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(
            Capsule()
                .fill(isDark ? Color.white.opacity(0.09) : Color.white.opacity(0.5))
                .overlay(
                    Capsule().strokeBorder(
                        isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08),
                        lineWidth: 0.5
                    )
                )
        )
    }

    // MARK: 2d 水位条

    private var levelBarBody: some View {
        HStack(spacing: 15) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if let label = item.label { labelText(label) }
                        slotValue(item, size: 11)
                    }
                    ZStack(alignment: .leading) {
                        Capsule().fill(trackColor)
                        Capsule()
                            .fill(item.accent)
                            .frame(width: 38 * CGFloat(max(0, min(1, item.progress ?? 0))))
                    }
                    .frame(width: 38, height: 3)
                }
            }
        }
    }

    /// 环形/胶囊样式下去掉 "%" 小后缀（数字更干净），网络的 "M/K" 后缀保留。
    private func stripUnit(_ item: Item, keepNonPercent: Bool) -> Item {
        guard item.unit == "%" else { return item }
        return Item(
            label: item.label,
            number: item.number,
            unit: nil,
            accent: item.accent,
            numberColor: item.numberColor,
            progress: item.progress,
            samples: item.samples
        )
    }
}

/// 迷你环形量规：轨道 + 前景弧（从 12 点方向起画）。直径 15pt，线宽 2.5pt。
struct MenuBarRing: View {
    let progress: Double
    let color: Color
    let trackColor: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 15, height: 15)
    }
}

/// 菜单栏微型趋势线：仅线条（2pt 圆头），按可见数据 min–max 自适应缩放。
struct MenuBarSparkline: View {
    let samples: [Double]
    let color: Color
    var maxSamples: Int = 24

    var body: some View {
        Canvas { context, size in
            let display = samples.suffix(maxSamples)
            guard display.count >= 2 else {
                // 数据不足时画一条基线，避免菜单栏空洞
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height - 1))
                line.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                context.stroke(line, with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                return
            }

            let minValue = display.min() ?? 0
            let maxValue = display.max() ?? 1
            let range = max(maxValue - minValue, 0.001)
            let stepX = size.width / CGFloat(display.count - 1)
            let pad: CGFloat = 1

            var path = Path()
            for (index, value) in display.enumerated() {
                let x = CGFloat(index) * stepX
                let normalized = CGFloat((value - minValue) / range)
                let y = size.height - pad - normalized * (size.height - 2 * pad)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
