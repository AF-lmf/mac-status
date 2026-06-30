import AppKit

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

    // MARK: - Title Update

    /// Update the status bar button title with current metrics.
    ///
    /// Reads SettingsManager.metricOrder + enabledMetrics to determine which
    /// segments to render and in what order. Inserts separator only between
    /// segments (no leading/trailing separators). Falls back to "◆" when the
    /// enabled set is empty (never leaves the status bar blank).
    func updateTitle(
        cpuUsage: Double?,
        memoryStats: MemoryStats?,
        networkStats: NetworkStats?,
        gpuStats: GPUStats?
    ) {
        guard let button = statusItem.button else { return }

        let settings = SettingsManager.shared
        let order   = settings.metricOrder           // [Metric]
        let enabled = Set(settings.enabledMetrics)   // Set<Metric> for O(1) lookup
        let mode    = settings.displayMode

        let active = order.filter { enabled.contains($0) }
        if active.isEmpty {
            button.title = "◆"   // minimal placeholder — never empty status bar
            return
        }

        let sep = mode == .compact ? compactSeparator() : separator()
        let result = NSMutableAttributedString()
        var firstSegmentWritten = false

        for metric in active {
            let segment: NSAttributedString?
            switch metric {
            case .cpu:     segment = cpuSegment(cpuUsage, mode: mode)
            case .memory:  segment = memSegment(memoryStats, mode: mode)
            case .network: segment = netSegment(networkStats, mode: mode)
            case .gpu:     segment = gpuSegment(gpuStats, mode: mode)
            case .battery: segment = nil  // Phase 7 activates this case
            }
            if let segment {
                if firstSegmentWritten { result.append(sep) }
                result.append(segment)
                firstSegmentWritten = true
            }
        }

        // 所有 active metrics 均返回 nil segment（例如仅含 .battery 时）——
        // 回退到占位符，保持"菜单栏永不为空"的不变量。
        if result.length == 0 {
            button.title = "◆"
            return
        }
        button.attributedTitle = result
    }

    // MARK: - Per-Metric Segment Helpers

    /// CPU segment: "CPU: X%" / "C:X%" / "X%" depending on mode.
    private func cpuSegment(_ cpu: Double?, mode: DisplayMode) -> NSAttributedString {
        switch mode {
        case .full:
            let text  = cpu.map { "CPU: \(Int($0))%" } ?? "CPU: --"
            let color = cpu.map { colorForUsage($0, metric: .cpu) } ?? NSColor.secondaryLabelColor
            return segment(text, color: color)
        case .compact:
            let text  = cpu.map { "C:\(Int($0))%" } ?? "C:--"
            let color = cpu.map { colorForUsage($0, metric: .cpu) } ?? NSColor.secondaryLabelColor
            return segment(text, color: color)
        case .percentage:
            let text  = cpu.map { "\(Int($0))%" } ?? "--"
            let color = cpu.map { colorForUsage($0, metric: .cpu) } ?? NSColor.secondaryLabelColor
            return segment(text, color: color)
        }
    }

    /// Memory segment: includes pressure label in full mode.
    private func memSegment(_ mem: MemoryStats?, mode: DisplayMode) -> NSAttributedString {
        switch mode {
        case .full:
            let text: String
            let color: NSColor
            if let m = mem, let used = m.usedPercent {
                let label = pressureLabel(m.pressureLevel)
                text  = "MEM: \(Int(used))% \(label)"
                color = colorForUsage(used, metric: .memory)
            } else {
                text  = "MEM: --"
                color = .secondaryLabelColor
            }
            return segment(text, color: color)
        case .compact:
            let text: String
            let color: NSColor
            if let m = mem, let used = m.usedPercent {
                text  = "M:\(Int(used))%"
                color = colorForUsage(used, metric: .memory)
            } else {
                text  = "M:--"
                color = .secondaryLabelColor
            }
            return segment(text, color: color)
        case .percentage:
            let text: String
            let color: NSColor
            if let m = mem, let used = m.usedPercent {
                text  = "\(Int(used))%"
                color = colorForUsage(used, metric: .memory)
            } else {
                text  = "--"
                color = .secondaryLabelColor
            }
            return segment(text, color: color)
        }
    }

    /// Network segment: colored with .labelColor (no usage threshold for network).
    private func netSegment(_ net: NetworkStats?, mode: DisplayMode) -> NSAttributedString {
        switch mode {
        case .full:
            if let n = net {
                let up   = ByteFormatting.format(n.uploadBytesPerSec)
                let down = ByteFormatting.format(n.downloadBytesPerSec)
                return segment("NET: ↑\(up)/s ↓\(down)/s", color: .labelColor)
            } else {
                return segment("NET: --", color: .secondaryLabelColor)
            }
        case .compact:
            if let n = net {
                let up   = ByteFormatting.format(n.uploadBytesPerSec)
                let down = ByteFormatting.format(n.downloadBytesPerSec)
                return segment("N:↑\(up)↓\(down)", color: .labelColor)
            } else {
                return segment("N:--", color: .secondaryLabelColor)
            }
        case .percentage:
            if let n = net {
                let total = n.uploadBytesPerSec + n.downloadBytesPerSec
                return segment(ByteFormatting.format(total) + "/s", color: .labelColor)
            } else {
                return segment("--", color: .secondaryLabelColor)
            }
        }
    }

    /// GPU segment: "GPU: X%" / "G:X%" / "X%" depending on mode.
    private func gpuSegment(_ gpu: GPUStats?, mode: DisplayMode) -> NSAttributedString {
        switch mode {
        case .full:
            let text  = gpu.map { "GPU: \(Int($0.utilizationPercent))%" } ?? "GPU: N/A"
            let color = gpu.map { colorForUsage($0.utilizationPercent, metric: .gpu) } ?? NSColor.secondaryLabelColor
            return segment(text, color: color)
        case .compact:
            let text  = gpu.map { "G:\(Int($0.utilizationPercent))%" } ?? "G:--"
            let color = gpu.map { colorForUsage($0.utilizationPercent, metric: .gpu) } ?? NSColor.secondaryLabelColor
            return segment(text, color: color)
        case .percentage:
            let text  = gpu.map { "\(Int($0.utilizationPercent))%" } ?? "--"
            let color = gpu.map { colorForUsage($0.utilizationPercent, metric: .gpu) } ?? NSColor.secondaryLabelColor
            return segment(text, color: color)
        }
    }

    // MARK: - Helpers

    /// " | " separator for full/percentage modes.
    private func separator() -> NSAttributedString {
        NSAttributedString(
            string: " | ",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 12),
            ]
        )
    }

    /// Single space separator for compact mode (preserves v1.0 compact appearance).
    private func compactSeparator() -> NSAttributedString {
        NSAttributedString(
            string: " ",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
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
            return .systemRed
        } else if percent >= warning {
            if let hex = settings.customColors[metric.rawValue]?["warning"],
               let color = NSColor(hex: hex) { return color }
            return .systemOrange
        }
        return .labelColor   // semantic; adapts to dark/light mode
    }

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
