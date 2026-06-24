import SwiftUI

// MARK: - Settings View

/// Preferences panel for MacStatus. Displayed in a separate window
/// via NSWindow + NSHostingView. Changes take effect immediately.
struct SettingsView: View {
    @Bindable var settings = SettingsManager.shared

    var body: some View {
        Form {
            // ── Section 1: 通用（保留刷新间隔 + 登录时启动，移出显示模式）
            Section("通用") {
                HStack {
                    Text("刷新间隔")
                    Spacer()
                    Picker("", selection: $settings.refreshInterval) {
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                        Text("5s").tag(5.0)
                        Text("10s").tag(10.0)
                    }
                    .frame(width: 80)
                }

                Toggle("登录时启动", isOn: $settings.launchAtLogin)
            }

            // ── Section 2: 状态栏指标（可拖动重排 + 各指标开关）
            Section("状态栏指标") {
                List {
                    ForEach(settings.metricOrder, id: \.rawValue) { metric in
                        MetricOrderRow(metric: metric, settings: settings)
                    }
                    .onMove { from, to in
                        settings.metricOrder.move(fromOffsets: from, toOffset: to)
                    }
                }
                .frame(height: CGFloat(settings.metricOrder.count) * 44)  // WR-04: 44pt/行适配辅助功能大字体（Dynamic Type）
                .listStyle(.plain)
            }

            // ── Section 3: 弹窗区块（电池 + 散热 + 进程区块开关）
            Section("弹窗区块") {
                Toggle("电池区块", isOn: $settings.showBatterySection)
                Toggle("散热区块", isOn: $settings.showThermalSection)
                Toggle("风扇区块", isOn: $settings.showFanSection)
                Toggle("进程区块", isOn: $settings.showProcessSection)
            }

            // ── Section 4: 状态栏文字模式（从通用移出，独立 section）
            Section("状态栏文字模式") {
                LabeledContent("文字模式") {
                    Picker("", selection: $settings.displayMode) {
                        Text("详细").tag(DisplayMode.full)
                        Text("紧凑").tag(DisplayMode.compact)
                        Text("百分比").tag(DisplayMode.percentage)
                    }
                    .pickerStyle(.segmented)
                }
            }

            // ── Section 5: 告警阈值（按指标 ThresholdSubsection，替换 Plan 02 占位）
            Section("告警阈值") {
                ForEach([Metric.cpu, .memory, .gpu], id: \.rawValue) { metric in
                    ThresholdSubsection(metric: metric, settings: settings)
                    if metric != .gpu { Divider() }
                }
            }

            // ── Section 6: 配色（按指标 ColorSubsection，替换 Plan 02 占位）
            Section("配色") {
                ForEach([Metric.cpu, .memory, .gpu], id: \.rawValue) { metric in
                    ColorSubsection(metric: metric, settings: settings)
                    if metric != .gpu { Divider() }
                }
            }

            // ── Section 7: 数据（原样保留）
            Section("数据") {
                HStack {
                    Text("已存采样点")
                    Spacer()
                    Text("\(MetricCollector.shared.persistedCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button("清除历史") {
                    // TODO: Implement via MetricCollector.purgeAll()
                }
                .disabled(true)
            }

            // ── Section 8: 关于（版本号更新为 v2.0）
            Section("关于") {
                HStack {
                    Text("MacStatus")
                    Spacer()
                    Text("v2.0 (M009)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("macOS")
                    Spacer()
                    Text(ProcessInfo.processInfo.operatingSystemVersionString)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .frame(minHeight: 400)
        .padding()
    }
}

// MARK: - MetricOrderRow（内嵌私有 struct，避免 pbxproj 变更）

/// 状态栏指标列表的单行视图：拖动柄 + 指标名 + 启用开关。
/// enabledBinding 定义为计算属性而非 body 内局部变量，防止无限重渲染（Research 陷阱 3）。
private struct MetricOrderRow: View {
    let metric: Metric
    @Bindable var settings: SettingsManager

    var body: some View {
        HStack(spacing: 8) {
            // 显式拖动柄图标（视觉提示；macOS List 整行可拖动重排）
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            // 指标中文名（已禁用时灰显）
            Text(metric.displayName)
                .foregroundStyle(
                    enabledBinding.wrappedValue ? Color.primary : Color.secondary
                )

            Spacer()

            // 启用开关
            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
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

// MARK: - ThresholdSubsection（内嵌私有 struct，避免 pbxproj 变更）

/// 单个指标的告警阈值编辑区：warning Slider + critical Slider + 恢复默认按钮。
/// 所有计算 Binding 定义为 struct 计算属性（非 body 内局部），防止无限重渲染（Research 陷阱 3）。
private struct ThresholdSubsection: View {
    let metric: Metric
    @Bindable var settings: SettingsManager

    // MARK: - Default Values（迁移种子）
    // cpu/memory 的旧全局键（cpuWarningThreshold / memoryWarningThreshold 等）
    // 仅作"迁移种子"——提供首次进入时的初始显示值。
    // 用户改动后写入 customThresholds[metric]，旧键不再被本 UI 更新。
    // 后续里程碑可弃用并移除旧全局键。
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
            Text(metric.displayName)
                .font(.caption.weight(.semibold))

            // Warning Slider
            Text("\(metric.displayName) 警告：\(Int(warningBinding.wrappedValue))%")
            Slider(value: warningBinding, in: 30...90, step: 5)
                .onChange(of: warningBinding.wrappedValue) { _, newWarning in
                    // 约束：warning < critical（调高 warning 时推高 critical）
                    if newWarning >= criticalBinding.wrappedValue {
                        criticalBinding.wrappedValue = min(newWarning + 5, 95)
                    }
                }

            // Critical Slider
            Text("\(metric.displayName) 严重：\(Int(criticalBinding.wrappedValue))%")
            Slider(value: criticalBinding, in: 50...95, step: 5)
                .onChange(of: criticalBinding.wrappedValue) { _, newCritical in
                    // 约束：critical > warning（调低 critical 时拉低 warning）
                    if newCritical <= warningBinding.wrappedValue {
                        warningBinding.wrappedValue = max(newCritical - 5, 30)
                    }
                }

            HStack {
                Spacer()
                Button("恢复默认") {
                    resetThresholds()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
            }
        }
        .onAppear {
            // WR-01: 修正迁移种子产生的倒置初始状态（warning >= critical）。
            // 仅当 customThresholds 尚未为该指标写入有效值时才可能出现此状态。
            // 将 critical 推高到 min(warning+5, 95)，非破坏性（不影响已有有效阈值）。
            let w = warningBinding.wrappedValue
            let c = criticalBinding.wrappedValue
            if w >= c {
                criticalBinding.wrappedValue = min(w + 5, 95)
            }
        }
    }

    // MARK: - Computed Bindings（定义为计算属性，不在 body 内构造，避免无限重渲染）

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
        // 移除整个 metric key → StatusBarManager.colorForUsage 自动回退到内置默认阈值
        var updated = settings.customThresholds
        updated.removeValue(forKey: metric.rawValue)
        settings.customThresholds = updated
    }
}

// MARK: - ColorSubsection（内嵌私有 struct，避免 pbxproj 变更）

/// 单个指标的配色编辑区：warning ColorPicker + critical ColorPicker + 恢复默认按钮。
/// 所有计算 Binding 定义为 struct 计算属性（非 body 内局部），防止无限重渲染（Research 陷阱 3）。
/// 颜色经 NSColor(hex:)/NSColor.hexString/Color(nsColor:)/NSColor(_ color:) 双向转换。
private struct ColorSubsection: View {
    let metric: Metric
    @Bindable var settings: SettingsManager

    // 默认颜色与 StatusBarManager.colorForUsage 内置默认色对齐
    private let defaultWarningHex = "#FF9500"   // 系统橙
    private let defaultCriticalHex = "#FF3B30"  // 系统红

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("警告色")
                Spacer()
                ColorPicker("警告色", selection: warningColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44)
            }

            HStack {
                Text("严重色")
                Spacer()
                ColorPicker("严重色", selection: criticalColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44)
            }

            HStack {
                Spacer()
                Button("恢复默认") {
                    resetColors()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Computed Bindings（定义为计算属性，不在 body 内构造，避免无限重渲染）

    private var warningColorBinding: Binding<Color> {
        colorBinding(for: "warning", defaultHex: defaultWarningHex)
    }

    private var criticalColorBinding: Binding<Color> {
        colorBinding(for: "critical", defaultHex: defaultCriticalHex)
    }

    private func colorBinding(for level: String, defaultHex: String) -> Binding<Color> {
        Binding {
            // 读：hex string → NSColor → SwiftUI Color（macOS 12+）
            let hex = settings.customColors[metric.rawValue]?[level] ?? defaultHex
            let ns = NSColor(hex: hex) ?? NSColor(hex: defaultHex)!
            return Color(nsColor: ns)
        } set: { newColor in
            // 写：SwiftUI Color → NSColor（macOS 11+）→ hex string → customColors
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
        // 移除整个 metric key → colorForUsage 自动回退内置默认色（橙/红）
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
            // isReleasedWhenClosed=false 的正确模式：整个生命周期复用同一 NSWindow，
            // 不重建。移除 isVisible 检查以避免关闭后再打开时创建新实例导致旧窗口泄漏。
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.isReleasedWhenClosed = false  // WR-02: 阻止 AppKit 在关闭时额外 release；manager 持有强引用并复用此窗口
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
        case .battery: return "电池"  // 不出现在状态栏指标列表中，但提供以满足 switch exhaustive
        }
    }
}
