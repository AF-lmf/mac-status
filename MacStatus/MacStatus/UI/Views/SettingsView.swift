import SwiftUI
import ServiceManagement

// MARK: - Settings View

/// Preferences panel for MacStatus. Displayed in a separate window
/// via NSWindow + NSHostingView. Changes take effect immediately.
struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
    @AppStorage("displayMode") private var displayModeRaw: String = DisplayMode.full.rawValue
    @AppStorage("displayUnit") private var displayUnitRaw: String = DisplayUnit.auto.rawValue
    @AppStorage("showIcons") private var showIcons: Bool = false
    @AppStorage("cpuWarningThreshold") private var cpuWarning: Double = 60.0
    @AppStorage("cpuCriticalThreshold") private var cpuCritical: Double = 80.0
    @AppStorage("memoryWarningThreshold") private var memWarning: Double = 60.0
    @AppStorage("memoryCriticalThreshold") private var memCritical: Double = 80.0
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false

    var body: some View {
        Form {
            // General
            Section("General") {
                HStack {
                    Text("Refresh Interval")
                    Spacer()
                    Picker("", selection: $refreshInterval) {
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                        Text("5s").tag(5.0)
                        Text("10s").tag(10.0)
                    }
                    .frame(width: 80)
                }

                HStack {
                    Text("Display Mode")
                    Spacer()
                    Picker("", selection: $displayModeRaw) {
                        Text("Full").tag(DisplayMode.full.rawValue)
                        Text("Compact").tag(DisplayMode.compact.rawValue)
                        Text("Percentage").tag(DisplayMode.percentage.rawValue)
                    }
                    .frame(width: 120)
                }

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            // Alert Thresholds
            Section("Alert Thresholds") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CPU Warning: \(Int(cpuWarning))%")
                    Slider(value: $cpuWarning, in: 30...90, step: 5)

                    Text("CPU Critical: \(Int(cpuCritical))%")
                    Slider(value: $cpuCritical, in: 50...95, step: 5)

                    Divider()

                    Text("Memory Warning: \(Int(memWarning))%")
                    Slider(value: $memWarning, in: 30...90, step: 5)

                    Text("Memory Critical: \(Int(memCritical))%")
                    Slider(value: $memCritical, in: 50...95, step: 5)
                }
            }

            // Data
            Section("Data") {
                HStack {
                    Text("Persisted Samples")
                    Spacer()
                    Text("\(MetricCollector.shared.persistedCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button("Clear History") {
                    // TODO: Implement via MetricCollector.purgeAll()
                }
                .disabled(true)
            }

            // About
            Section("About") {
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

    // MARK: - Launch at Login

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[Settings] Failed to \(enabled ? "register" : "unregister") login item: \(error)")
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
        window.title = "MacStatus Preferences"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}
