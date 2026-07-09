import SwiftUI

// MARK: - Settings View
//
// 1a 视觉语言的偏好设置窗口：pill 标签页（常规 / 指标与排序 / 配色与阈值）。
// "指标与排序" 还原 mock 的两栏布局：左＝拖拽排序列表，右＝文字模式 / 刷新 / 状态配色 / 登录。
// 蓝色为统一强调色；所有控件沿用现有 SettingsManager 绑定与 .settingsDidChange 数据流。

struct SettingsView: View {
    @Bindable var settings = SettingsManager.shared
    @State private var tab: SettingsTab = .metrics

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $tab)
            Divider().overlay(Color.hairline)

            Group {
                switch tab {
                case .general: GeneralTab(settings: settings)
                case .metrics: MetricsSortTab(settings: settings)
                case .colors: ColorsThresholdsTab(settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .tint(.metricBlue)
        .frame(width: 620, height: 468)
    }
}

// MARK: - Settings Tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case metrics
    case colors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "常规"
        case .metrics: return "指标与排序"
        case .colors: return "配色与阈值"
        }
    }
}

/// 顶部 pill 标签条：选中态蓝底蓝字。
private struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    selection = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.metricBlue : Color.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? Color.metricBlue.opacity(0.12) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.025))
    }
}

// MARK: - Blue Switch & Slider（自定义控件：不依赖系统 accent，保证 mock 蓝色）

/// mock 样式开关：34×20 胶囊，开=品牌蓝底 + 白圆点居右。
struct BlueSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 0)
            Capsule()
                .fill(configuration.isOn ? Color.metricBlue : Color.primary.opacity(0.13))
                .frame(width: 34, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.28), radius: 1, x: 0, y: 1)
                        .padding(2)
                }
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
                .contentShape(Capsule())
                .onTapGesture { configuration.isOn.toggle() }
        }
    }
}

/// mock 样式滑块：5pt 轨道（蓝色已填充段）+ 16pt 白色圆点，支持步进。
struct BlueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1

    var body: some View {
        GeometryReader { geo in
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? CGFloat((value - range.lowerBound) / span) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 5)
                Capsule()
                    .fill(Color.metricBlue)
                    .frame(width: max(0, geo.size.width * fraction), height: 5)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, x: 0, y: 0.5)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .offset(x: geo.size.width * fraction - 8)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let f = min(max(gesture.location.x / geo.size.width, 0), 1)
                        let raw = range.lowerBound + Double(f) * span
                        let stepped = step > 0 ? (raw / step).rounded() * step : raw
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    }
            )
        }
        .frame(height: 18)
    }
}

// MARK: - Section Header

/// 小型大写小节标题（SF Rounded semibold + 字距）。
struct SettingsSectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Color.metricLabel)
    }
}

// MARK: - General Tab

/// 常规：弹窗区块开关 + 数据 + 关于。
private struct GeneralTab: View {
    @Bindable var settings: SettingsManager

    private var appVersionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0"
        return "v\(short)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionHeader("弹窗区块")
                toggleRow("电池区块", isOn: $settings.showBatterySection)
                toggleRow("散热区块", isOn: $settings.showThermalSection)
                toggleRow("风扇区块", isOn: $settings.showFanSection)
                toggleRow("进程区块", isOn: $settings.showProcessSection)
            }

            Divider().overlay(Color.hairline)

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionHeader("数据")
                HStack {
                    Text("已存采样点").font(.system(size: 13))
                    Spacer()
                    Text("\(MetricCollector.shared.persistedCount)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Divider().overlay(Color.hairline)

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionHeader("关于")
                aboutRow("MacStatus", appVersionText)
                aboutRow("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.system(size: 13))
        }
        .toggleStyle(BlueSwitchToggleStyle())
    }

    private func aboutRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Metrics & Sort Tab (two-pane, mirrors mock)

/// 指标与排序：左＝拖拽排序列表，右＝文字模式 / 刷新 / 状态配色 / 登录时启动。
private struct MetricsSortTab: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // 左栏：菜单栏显示 · 拖动排序
            VStack(alignment: .leading, spacing: 10) {
                SettingsSectionHeader("菜单栏显示 · 拖动排序")
                List {
                    ForEach(settings.metricOrder, id: \.rawValue) { metric in
                        MetricSortRow(metric: metric, settings: settings)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { from, to in
                        settings.metricOrder.move(fromOffsets: from, toOffset: to)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: CGFloat(settings.metricOrder.count) * 40)
                Spacer(minLength: 0)
            }
            .frame(width: 292, alignment: .leading)

            Rectangle().fill(Color.hairline).frame(width: 0.5).padding(.horizontal, 16)

            // 右栏：文字模式 / 刷新间隔 / 状态配色 / 登录时启动
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    SettingsSectionHeader("菜单栏样式")
                    PillSegmented(
                        selection: $settings.menuBarStyle,
                        options: [
                            (.sparkline, "趋势线"),
                            (.rings, "环形"),
                            (.capsule, "胶囊"),
                            (.levelBar, "水位条"),
                        ]
                    )
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        SettingsSectionHeader("刷新间隔")
                        Spacer()
                        Text("\(String(format: "%.1f", settings.refreshInterval))s")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                    BlueSlider(value: $settings.refreshInterval, range: 1...10, step: 1)
                }

                VStack(alignment: .leading, spacing: 9) {
                    SettingsSectionHeader("状态配色")
                    StatusColorLegend()
                }

                Spacer(minLength: 0)

                Toggle(isOn: $settings.launchAtLogin) {
                    Text("登录时启动").font(.system(size: 13))
                }
                .toggleStyle(BlueSwitchToggleStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
    }
}

/// 拖拽排序单行：手柄 + 指标色点 + 名称 + 阈值（`70 / 90`）+ 蓝色开关。
private struct MetricSortRow: View {
    let metric: Metric
    @Bindable var settings: SettingsManager

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(dotColor)
                .frame(width: 8, height: 8)

            Text(metric.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isEnabled ? .primary : .secondary)

            Spacer()

            Text(thresholdText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(BlueSwitchToggleStyle())
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 0.5)
        }
    }

    private var isEnabled: Bool { settings.enabledMetrics.contains(metric) }

    private var dotColor: Color {
        isEnabled ? .metricBlue : Color.secondary.opacity(0.35)
    }

    private var thresholdText: String {
        guard metric != .network, metric != .battery else { return "— / —" }
        let warning = settings.customThresholds[metric.rawValue]?["warning"] ?? defaultWarning
        let critical = settings.customThresholds[metric.rawValue]?["critical"] ?? defaultCritical
        return "\(Int(warning)) / \(Int(critical))"
    }

    private var defaultWarning: Double {
        switch metric {
        case .cpu: return settings.cpuWarningThreshold
        case .memory: return settings.memoryWarningThreshold
        case .gpu: return 60.0
        default: return 60.0
        }
    }

    private var defaultCritical: Double {
        switch metric {
        case .cpu: return settings.cpuCriticalThreshold
        case .memory: return settings.memoryCriticalThreshold
        case .gpu: return 80.0
        default: return 80.0
        }
    }

    /// 计算 Binding<Bool>：enabledMetrics.contains(metric) ↔ append/removeAll
    /// 定义为计算属性而非 body 内局部 Binding，防止无限重渲染（Research 陷阱 3）。
    private var enabledBinding: Binding<Bool> {
        Binding {
            settings.enabledMetrics.contains(metric)
        } set: { enabled in
            if enabled {
                if !settings.enabledMetrics.contains(metric) {
                    settings.enabledMetrics.append(metric)
                }
            } else {
                settings.enabledMetrics.removeAll { $0 == metric }
            }
        }
    }
}

// MARK: - Pill Segmented Control

/// 自定义分段控件：圆角轨道 + 选中态白底蓝字（复刻 mock 文字模式）。
struct PillSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, title: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isSelected = selection == option.value
                Text(option.title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.metricBlue : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Color(nsColor: .textBackgroundColor) : .clear)
                            .shadow(color: isSelected ? .black.opacity(0.12) : .clear, radius: 1, x: 0, y: 0.5)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option.value }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
    }
}

// MARK: - Status Color Legend

/// 状态配色三色样本：正常＝蓝 / 偏高＝琥珀 / 过载＝玫红（取代红黄绿）。
struct StatusColorLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            swatch(.metricBlue, "正常")
            swatch(.metricAmber, "偏高")
            swatch(.metricRose, "过载")
        }
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
                .frame(width: 22, height: 22)
                .shadow(color: color.opacity(0.4), radius: 2, x: 0, y: 1)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(color.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(color.opacity(0.18), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Colors & Thresholds Tab

/// 配色与阈值：状态配色图例 + 每指标 warning/critical 阈值滑块与配色选择器。
private struct ColorsThresholdsTab: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsSectionHeader("状态配色")
                    StatusColorLegend()
                }

                ForEach([Metric.cpu, .memory, .gpu], id: \.rawValue) { metric in
                    VStack(alignment: .leading, spacing: 12) {
                        ThresholdSubsection(metric: metric, settings: settings)
                        Divider().overlay(Color.hairline)
                        ColorSubsection(metric: metric, settings: settings)
                    }
                    .cardSurface(padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }
            }
            .padding(18)
        }
    }
}

// MARK: - ThresholdSubsection（内嵌私有 struct，避免 pbxproj 变更）

/// 单个指标的告警阈值编辑区：warning Slider + critical Slider + 恢复默认按钮。
/// 所有计算 Binding 定义为 struct 计算属性（非 body 内局部），防止无限重渲染（Research 陷阱 3）。
private struct ThresholdSubsection: View {
    let metric: Metric
    @Bindable var settings: SettingsManager

    // MARK: - Default Values（迁移种子）
    private var defaultWarning: Double {
        switch metric {
        case .cpu:    return settings.cpuWarningThreshold
        case .memory: return settings.memoryWarningThreshold
        case .gpu:    return 60.0
        default:      return 60.0
        }
    }

    private var defaultCritical: Double {
        switch metric {
        case .cpu:    return settings.cpuCriticalThreshold
        case .memory: return settings.memoryCriticalThreshold
        case .gpu:    return 80.0
        default:      return 80.0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader("\(metric.displayName) · 阈值")

            Text("\(metric.displayName) 警告：\(Int(warningBinding.wrappedValue))%")
                .font(.system(size: 12))
            BlueSlider(value: warningBinding, range: 30...90, step: 5)
                .onChange(of: warningBinding.wrappedValue) { _, newWarning in
                    if newWarning >= criticalBinding.wrappedValue {
                        criticalBinding.wrappedValue = min(newWarning + 5, 95)
                    }
                }

            Text("\(metric.displayName) 严重：\(Int(criticalBinding.wrappedValue))%")
                .font(.system(size: 12))
            BlueSlider(value: criticalBinding, range: 50...95, step: 5)
                .onChange(of: criticalBinding.wrappedValue) { _, newCritical in
                    if newCritical <= warningBinding.wrappedValue {
                        warningBinding.wrappedValue = max(newCritical - 5, 30)
                    }
                }

            HStack {
                Spacer()
                Button("恢复默认") { resetThresholds() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.metricBlue)
            }
        }
        .onAppear {
            // WR-01: 修正迁移种子产生的倒置初始状态（warning >= critical）。
            let w = warningBinding.wrappedValue
            let c = criticalBinding.wrappedValue
            if w >= c {
                criticalBinding.wrappedValue = min(w + 5, 95)
            }
        }
    }

    private var warningBinding: Binding<Double> {
        thresholdBinding(for: "warning", default: defaultWarning)
    }

    private var criticalBinding: Binding<Double> {
        thresholdBinding(for: "critical", default: defaultCritical)
    }

    private func thresholdBinding(for level: String, default defaultValue: Double) -> Binding<Double> {
        Binding {
            settings.customThresholds[metric.rawValue]?[level] ?? defaultValue
        } set: { newValue in
            var updated = settings.customThresholds
            var levels = updated[metric.rawValue] ?? [:]
            levels[level] = newValue
            updated[metric.rawValue] = levels
            settings.customThresholds = updated  // setter: clamp 0...100 + postChange + applyNow
        }
    }

    private func resetThresholds() {
        var updated = settings.customThresholds
        updated.removeValue(forKey: metric.rawValue)
        settings.customThresholds = updated
    }
}

// MARK: - ColorSubsection（内嵌私有 struct，避免 pbxproj 变更）

/// 单个指标的配色编辑区：warning ColorPicker + critical ColorPicker + 恢复默认按钮。
/// 默认色与 StatusBarManager.colorForUsage 内置默认色对齐（1a 新梯度）。
private struct ColorSubsection: View {
    let metric: Metric
    @Bindable var settings: SettingsManager

    private let defaultWarningHex = "#C9821F"   // 偏高 · 琥珀
    private let defaultCriticalHex = "#D6455A"  // 过载 · 玫红

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSectionHeader("\(metric.displayName) · 配色")

            HStack {
                Text("警告色").font(.system(size: 12))
                Spacer()
                ColorPicker("警告色", selection: warningColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44)
            }

            HStack {
                Text("严重色").font(.system(size: 12))
                Spacer()
                ColorPicker("严重色", selection: criticalColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44)
            }

            HStack {
                Spacer()
                Button("恢复默认") { resetColors() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.metricBlue)
            }
        }
    }

    private var warningColorBinding: Binding<Color> {
        colorBinding(for: "warning", defaultHex: defaultWarningHex)
    }

    private var criticalColorBinding: Binding<Color> {
        colorBinding(for: "critical", defaultHex: defaultCriticalHex)
    }

    private func colorBinding(for level: String, defaultHex: String) -> Binding<Color> {
        Binding {
            let hex = settings.customColors[metric.rawValue]?[level] ?? defaultHex
            let ns = NSColor(hex: hex) ?? NSColor(hex: defaultHex)!
            return Color(nsColor: ns)
        } set: { newColor in
            let ns = NSColor(newColor)
            let hex = ns.hexString
            var updated = settings.customColors
            var levels = updated[metric.rawValue] ?? [:]
            levels[level] = hex
            updated[metric.rawValue] = levels
            settings.customColors = updated  // setter: 过滤非 #RRGGBB + postChange
        }
    }

    private func resetColors() {
        var updated = settings.customColors
        updated.removeValue(forKey: metric.rawValue)
        settings.customColors = updated
    }
}

// MARK: - Settings Window Manager

/// Manages the settings window lifecycle.
@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private var window: NSWindow?

    private init() {}

    /// Show the settings window, creating it if needed.
    func showSettings() {
        if let window {
            // WR-02-REGR: 复用已有窗口实例（无论是否可见），直接唤起前台。
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.isReleasedWhenClosed = false  // WR-02: manager 持有强引用并复用此窗口
        window.title = "MacStatus 偏好设置"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}

// MARK: - Metric.displayName 扩展

extension Metric {
    /// 指标的用户可见中文名称（用于设置界面列表行）。
    var displayName: String {
        switch self {
        case .cpu:     return "CPU"
        case .memory:  return "内存"
        case .network: return "网络"
        case .gpu:     return "GPU"
        case .battery: return "电池"
        }
    }
}
