import AppKit

// MARK: - Status Bar Manager

/// Manages the NSStatusItem lifecycle and user interactions.
///
/// M002: Supports three display modes (full/compact/percentage) with
/// NSAttributedString colored text. Left-click toggles NSPopover.
///
/// Thread safety: All methods must be called on the main thread.
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
            title: "Preferences...",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit MacStatus",
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

    // MARK: - Title Update

    /// Update the status bar button title with current metrics.
    /// Respects the user's chosen DisplayMode from SettingsManager.
    func updateTitle(
        cpuUsage: Double?,
        memoryStats: MemoryStats?,
        networkStats: NetworkStats?,
        gpuStats: GPUStats?
    ) {
        guard let button = statusItem.button else { return }

        let mode = SettingsManager.shared.displayMode
        let title: NSAttributedString

        switch mode {
        case .full:
            title = buildFullTitle(
                cpuUsage: cpuUsage, memoryStats: memoryStats,
                networkStats: networkStats, gpuStats: gpuStats
            )
        case .compact:
            title = buildCompactTitle(
                cpuUsage: cpuUsage, memoryStats: memoryStats,
                networkStats: networkStats, gpuStats: gpuStats
            )
        case .percentage:
            title = buildPercentageTitle(
                cpuUsage: cpuUsage, memoryStats: memoryStats,
                networkStats: networkStats, gpuStats: gpuStats
            )
        }

        button.attributedTitle = title
    }

    // MARK: - Full Mode

    /// Full: `CPU: 23% | MEM: 67% OK | NET: ↑0B/s ↓1.2K/s | GPU: 12%`
    private func buildFullTitle(
        cpuUsage: Double?,
        memoryStats: MemoryStats?,
        networkStats: NetworkStats?,
        gpuStats: GPUStats?
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let sep = separator()

        let cpuText: String
        let cpuColor: NSColor
        if let cpu = cpuUsage {
            cpuText = "CPU: \(Int(cpu))%"
            cpuColor = colorForUsage(cpu, metric: .cpu)
        } else {
            cpuText = "CPU: --"
            cpuColor = .secondaryLabelColor
        }
        result.append(segment(cpuText, color: cpuColor))
        result.append(sep)

        let memText: String
        let memColor: NSColor
        if let mem = memoryStats, let used = mem.usedPercent {
            let label = pressureLabel(mem.pressureLevel)
            memText = "MEM: \(Int(used))% \(label)"
            memColor = colorForUsage(used, metric: .memory)
        } else {
            memText = "MEM: --"
            memColor = .secondaryLabelColor
        }
        result.append(segment(memText, color: memColor))
        result.append(sep)

        let netText: String
        let netColor: NSColor
        if let net = networkStats {
            let up = ByteFormatting.format(net.uploadBytesPerSec)
            let down = ByteFormatting.format(net.downloadBytesPerSec)
            netText = "NET: ↑\(up)/s ↓\(down)/s"
            netColor = .labelColor
        } else {
            netText = "NET: --"
            netColor = .secondaryLabelColor
        }
        result.append(segment(netText, color: netColor))
        result.append(sep)

        let gpuText: String
        let gpuColor: NSColor
        if let gpu = gpuStats {
            gpuText = "GPU: \(Int(gpu.utilizationPercent))%"
            gpuColor = colorForUsage(gpu.utilizationPercent, metric: .gpu)
        } else {
            gpuText = "GPU: N/A"
            gpuColor = .secondaryLabelColor
        }
        result.append(segment(gpuText, color: gpuColor))

        return result
    }

    // MARK: - Compact Mode

    /// Compact: `C:23% M:67% N:↑0↓1.2K G:12%`
    private func buildCompactTitle(
        cpuUsage: Double?,
        memoryStats: MemoryStats?,
        networkStats: NetworkStats?,
        gpuStats: GPUStats?
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let sep = NSAttributedString(string: " ", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])

        let cpuText = cpuUsage.map { "C:\(Int($0))%" } ?? "C:--"
        let cpuColor = cpuUsage.map { colorForUsage($0, metric: .cpu) } ?? NSColor.secondaryLabelColor
        result.append(segment(cpuText, color: cpuColor))
        result.append(sep)

        let gpuText = gpuStats.map { "G:\(Int($0.utilizationPercent))%" } ?? "G:--"
        let gpuColor = gpuStats.map { colorForUsage($0.utilizationPercent, metric: .gpu) } ?? NSColor.secondaryLabelColor
        result.append(segment(gpuText, color: gpuColor))
        result.append(sep)

        let memText: String
        let memColor: NSColor
        if let mem = memoryStats, let used = mem.usedPercent {
            memText = "M:\(Int(used))%"
            memColor = colorForUsage(used, metric: .memory)
        } else {
            memText = "M:--"
            memColor = .secondaryLabelColor
        }
        result.append(segment(memText, color: memColor))
        result.append(sep)

        let netText: String
        let netColor: NSColor
        if let net = networkStats {
            let up = ByteFormatting.format(net.uploadBytesPerSec)
            let down = ByteFormatting.format(net.downloadBytesPerSec)
            netText = "N:↑\(up)↓\(down)"
            netColor = .labelColor
        } else {
            netText = "N:--"
            netColor = .secondaryLabelColor
        }
        result.append(segment(netText, color: netColor))

        return result
    }

    // MARK: - Percentage Mode

    /// Percentage: `23% | 67% | -- | 12%`
    private func buildPercentageTitle(
        cpuUsage: Double?,
        memoryStats: MemoryStats?,
        networkStats: NetworkStats?,
        gpuStats: GPUStats?
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let sep = separator()

        let cpuText = cpuUsage.map { "\(Int($0))%" } ?? "--"
        let cpuColor = cpuUsage.map { colorForUsage($0, metric: .cpu) } ?? NSColor.secondaryLabelColor
        result.append(segment(cpuText, color: cpuColor))
        result.append(sep)

        let memText: String
        let memColor: NSColor
        if let mem = memoryStats, let used = mem.usedPercent {
            memText = "\(Int(used))%"
            memColor = colorForUsage(used, metric: .memory)
        } else {
            memText = "--"
            memColor = .secondaryLabelColor
        }
        result.append(segment(memText, color: memColor))
        result.append(sep)

        // Network in percentage mode: show total throughput
        let netText: String
        let netColor: NSColor
        if let net = networkStats {
            let total = net.uploadBytesPerSec + net.downloadBytesPerSec
            netText = ByteFormatting.format(total) + "/s"
            netColor = .labelColor
        } else {
            netText = "--"
            netColor = .secondaryLabelColor
        }
        result.append(segment(netText, color: netColor))
        result.append(sep)

        let gpuText = gpuStats.map { "\(Int($0.utilizationPercent))%" } ?? "--"
        let gpuColor = gpuStats.map { colorForUsage($0.utilizationPercent, metric: .gpu) } ?? NSColor.secondaryLabelColor
        result.append(segment(gpuText, color: gpuColor))

        return result
    }

    // MARK: - Helpers

    private func separator() -> NSAttributedString {
        NSAttributedString(
            string: " | ",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 12),
            ]
        )
    }

    private func segment(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            ]
        )
    }

    /// Metric type for threshold lookup.
    private enum MetricType { case cpu, memory, gpu }

    /// Color based on usage percentage.
    /// Normal: system label color (auto adapts to dark/light mode).
    /// High load (>= warning threshold): orange.
    private func colorForUsage(_ percent: Double, metric: MetricType) -> NSColor {
        let warning: Double

        switch metric {
        case .cpu:
            warning = SettingsManager.shared.cpuWarningThreshold
        case .memory:
            warning = SettingsManager.shared.memoryWarningThreshold
        case .gpu:
            warning = 80.0
        }

        return percent >= warning ? .systemOrange : .labelColor
    }

    private func pressureLabel(_ level: MemoryPressureLevel) -> String {
        switch level {
        case .normal: return "OK"
        case .warning: return "WARN"
        case .critical: return "CRIT"
        case .unknown: return "?"
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
