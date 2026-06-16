import SwiftUI

// MARK: - Settings View

/// Preferences panel for MacStatus. Displayed in a separate window
/// via NSWindow + NSHostingView. Changes take effect immediately.
struct SettingsView: View {
    @Bindable var settings = SettingsManager.shared

    var body: some View {
        Form {
            // General
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

                HStack {
                    Text("显示模式")
                    Spacer()
                    Picker("", selection: $settings.displayMode) {
                        Text("完整").tag(DisplayMode.full)
                        Text("紧凑").tag(DisplayMode.compact)
                        Text("百分比").tag(DisplayMode.percentage)
                    }
                    .frame(width: 120)
                }

                Toggle("登录时启动", isOn: $settings.launchAtLogin)
            }

            // Alert Thresholds
            Section("告警阈值") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CPU 警告：\(Int(settings.cpuWarningThreshold))%")
                    Slider(value: $settings.cpuWarningThreshold, in: 30...90, step: 5)

                    Text("CPU 严重：\(Int(settings.cpuCriticalThreshold))%")
                    Slider(value: $settings.cpuCriticalThreshold, in: 50...95, step: 5)

                    Divider()

                    Text("内存警告：\(Int(settings.memoryWarningThreshold))%")
                    Slider(value: $settings.memoryWarningThreshold, in: 30...90, step: 5)

                    Text("内存严重：\(Int(settings.memoryCriticalThreshold))%")
                    Slider(value: $settings.memoryCriticalThreshold, in: 50...95, step: 5)
                }
            }

            // Data
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

            // About
            Section("关于") {
                HStack {
                    Text("MacStatus")
                    Spacer()
                    Text("v1.0 (M002)")
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
        .frame(width: 380, height: 440)
        .padding()
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
