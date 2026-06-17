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
                .frame(height: CGFloat(settings.metricOrder.count) * 36)
                .listStyle(.plain)
            }

            // ── Section 3: 弹窗区块（电池 + 进程区块开关）
            Section("弹窗区块") {
                Toggle("电池区块", isOn: $settings.showBatterySection)
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

            // ── Section 5: 告警阈值（占位，由 Plan 03 替换为按指标 ThresholdSubsection）
            Section("告警阈值") {
                // TODO: 由 Plan 03 替换为按指标 ThresholdSubsection 占位
                Text("（由 Plan 03 实现按指标编辑）")
                    .foregroundStyle(.secondary)
            }

            // ── Section 6: 配色（占位，由 Plan 03 替换为按指标 ColorSubsection）
            Section("配色") {
                // TODO: 由 Plan 03 替换为按指标 ColorSubsection 占位
                Text("（由 Plan 03 实现按指标配色）")
                    .foregroundStyle(.secondary)
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

    /// 是否悬停在拖动柄区域（控制 moveDisabled 行为）
    @State private var isHoveringHandle = false

    var body: some View {
        HStack(spacing: 8) {
            // 显式拖动柄图标
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .onHover { hovering in
                    isHoveringHandle = hovering
                }

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
        .moveDisabled(!isHoveringHandle)
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

// MARK: - Settings Window Manager

/// Manages the settings window lifecycle.
@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private var window: NSWindow?

    private init() {}

    /// Show the settings window, creating it if needed.
    func showSettings() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
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
