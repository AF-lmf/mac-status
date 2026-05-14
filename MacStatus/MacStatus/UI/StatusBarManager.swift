import Cocoa

/// Manages the NSStatusItem lifecycle, display formatting, and macOS 26
/// menu bar privacy gate detection.
/// All NSStatusItem operations must occur on the main actor — marking the
/// class @MainActor satisfies Swift 6 strict concurrency checking.
@MainActor
final class StatusBarManager {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    /// Last displayed value for D-06 tolerance-based redraw (0.5% threshold).
    private var lastDisplayedValue: Double?
    private var latestCPUText = "C --%"
    private var latestGPUText = "G --"
    private var latestNetworkText = "↓-- ↑--"
    private var latestMemoryText = "M --"
    private var latestCPUUsage: Double?
    private var latestGPUUsage: Double?
    private var latestMemoryPressure: MemoryPressureLevel?

    // Visible combined status item: CPU + GPU + memory + network.
    private var networkStatusItem: NSStatusItem?
    /// Last displayed network stats for tolerance-based redraw (1 KB/s threshold).
    private var lastNetworkStats: NetworkStats?

    /// Last displayed memory stats for tolerance-based redraw (0.5% threshold).
    private var lastMemoryStats: MemoryStats?

    /// Last displayed GPU stats for redraw skipping.
    private var lastGPUStats: GPUStats?

    // MARK: - Initialization

    init() {
        // macOS 26 (Tahoe) privacy gate detection.
        // On macOS 26+, the user must explicitly allow menu bar items
        // in System Settings. This check fires after 2 seconds to give
        // the system time to register the status item.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, let item = self.networkStatusItem else { return }
            if item.isVisible == false {
                let alert = NSAlert()
                alert.messageText = "Menu Bar Permission Needed"
                alert.informativeText = "MacStatus needs permission to display in the menu bar. Open System Settings → Menu Bar and enable MacStatus."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.menubar")!
                    )
                }
            }
        }
    }

    /// D-10: Prevent ghost icons by removing the status item before deallocation.
    deinit {
        // deinit is nonisolated in a @MainActor class — assumeIsolated is safe
        // because the AppDelegate holds the sole strong reference and releases it
        // on the main thread via applicationWillTerminate.
        MainActor.assumeIsolated {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            if let item = networkStatusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            print("StatusBarManager deinit — status items removed")
        }
    }

    // MARK: - Display Update

    /// Update the menu bar CPU display.
    /// - Parameter value: CPU usage percentage (0-100), or nil for error state.
    func updateCPU(_ value: Double?) {
        guard let value else {
            // Error state: Mach API failed, always update to "--"
            latestCPUText = "C --%"
            latestCPUUsage = nil
            updateCombinedStatus()
            lastDisplayedValue = nil
            return
        }

        // D-06: tolerance-based redraw — skip if change < 0.5%
        if let last = lastDisplayedValue, abs(value - last) < 0.5 {
            return
        }

        lastDisplayedValue = value
        latestCPUText = String(format: "C %.0f%%", value)
        latestCPUUsage = value
        updateCombinedStatus()
    }

    // MARK: - GPU Display

    /// Update the menu bar GPU display.
    /// - Parameter stats: Current GPU statistics, or `nil` for unavailable GPU data.
    func updateGPU(_ stats: GPUStats?) {
        guard let stats else {
            latestGPUText = "G --"
            latestGPUUsage = nil
            lastGPUStats = nil
            updateCombinedStatus()
            return
        }

        if let last = lastGPUStats, stats == last {
            return
        }

        lastGPUStats = stats
        latestGPUText = String(format: "G %.0f%%", stats.utilizationPercent)
        latestGPUUsage = stats.utilizationPercent
        updateCombinedStatus()
    }

    // MARK: - Network Display

    /// Create the network `NSStatusItem` (Phase 2 visible combined display).
    ///
    /// - Fixed width accommodates `"C 12% | G 34% | M OK | ↓2.1M ↑512K"` plus macOS padding.
    /// - `autosaveName` persists position across launches.
    /// - Initial placeholder follows LIFE-03 zero-config pattern.
    func setupNetworkItem() {
        // D-14: FixedWidth — PITFALL P8: variableLength causes menu bar jitter
        networkStatusItem = NSStatusBar.system.statusItem(withLength: 300)
        networkStatusItem?.autosaveName = "com.macstatus.network"
        networkStatusItem?.isVisible = true
        configureStatusButton(networkStatusItem?.button)
        updateCombinedStatus()
    }

    /// Update the menu bar network rate display.
    /// - Parameter stats: Current network throughput rates, or `nil` for error state.
    func updateNetwork(_ stats: NetworkStats?) {
        guard let stats else {
            latestNetworkText = "↓-- ↑--"
            updateCombinedStatus()
            lastNetworkStats = nil
            return
        }

        // Tolerance check: skip redraw if both rates changed less than 1 KB/s
        if let last = lastNetworkStats,
           abs(stats.downloadBytesPerSec - last.downloadBytesPerSec) < 1024,
           abs(stats.uploadBytesPerSec - last.uploadBytesPerSec) < 1024 {
            return
        }

        lastNetworkStats = stats
        latestNetworkText = formatNetworkCompact(download: stats.downloadBytesPerSec,
                                                  upload: stats.uploadBytesPerSec)
        updateCombinedStatus()
    }

    // MARK: - Memory Display

    /// Initialize memory text for the visible combined status item.
    ///
    /// Memory used to render into a separate `NSStatusItem`, but UAT showed that
    /// item is not reliably visible for the user. The visible source of truth is
    /// now the combined `networkStatusItem`.
    func setupMemoryItem() {
        latestMemoryText = "M --"
        latestMemoryPressure = nil
        updateCombinedStatus()
    }

    /// Update the menu bar memory pressure display.
    /// - Parameter stats: Current memory statistics, or `nil` for error state.
    func updateMemory(_ stats: MemoryStats?) {
        guard let stats else {
            latestMemoryText = "M --"
            latestMemoryPressure = nil
            updateCombinedStatus()
            lastMemoryStats = nil
            return
        }

        if let last = lastMemoryStats, stats == last {
            return
        }

        lastMemoryStats = stats
        latestMemoryText = formatMemoryPressure(stats.pressureLevel)
        latestMemoryPressure = stats.pressureLevel
        updateCombinedStatus()
    }

    // MARK: - Text Formatting

    private func configureStatusButton(_ button: NSStatusBarButton?) {
        button?.cell?.lineBreakMode = .byClipping
        button?.cell?.usesSingleLineMode = true
        button?.cell?.wraps = false
    }

    private func updateCombinedStatus() {
        let text = "\(latestCPUText) | \(latestGPUText) | \(latestMemoryText) | \(latestNetworkText)"
        networkStatusItem?.button?.title = text
        networkStatusItem?.button?.attributedTitle = combinedAttributedString()
    }

    private func combinedAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let separator = NSAttributedString(string: " | ", attributes: baseAttributes())

        appendMetric(
            label: "C",
            value: valueText(from: latestCPUText, label: "C"),
            valueColor: usageColor(for: latestCPUUsage),
            to: result
        )
        result.append(separator)
        appendMetric(
            label: "G",
            value: valueText(from: latestGPUText, label: "G"),
            valueColor: usageColor(for: latestGPUUsage),
            to: result
        )
        result.append(separator)
        appendMetric(
            label: "M",
            value: valueText(from: latestMemoryText, label: "M"),
            valueColor: memoryColor(for: latestMemoryPressure),
            to: result
        )
        result.append(separator)
        result.append(NSAttributedString(string: latestNetworkText, attributes: baseAttributes()))

        return result
    }

    private func appendMetric(
        label: String,
        value: String,
        valueColor: NSColor?,
        to result: NSMutableAttributedString
    ) {
        result.append(NSAttributedString(string: "\(label) ", attributes: baseAttributes()))
        result.append(NSAttributedString(string: value, attributes: metricAttributes(valueColor: valueColor)))
    }

    private func valueText(from text: String, label: String) -> String {
        let prefix = "\(label) "
        guard text.hasPrefix(prefix) else { return text }
        return String(text.dropFirst(prefix.count))
    }

    private func metricAttributes(valueColor: NSColor?) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes()
        if let valueColor {
            attributes[.foregroundColor] = valueColor
        }
        return attributes
    }

    private func usageColor(for value: Double?) -> NSColor? {
        guard let value else { return nil }

        switch value {
        case ..<60:
            return nil
        case ..<85:
            return .systemYellow
        default:
            return .systemRed
        }
    }

    private func memoryColor(for level: MemoryPressureLevel?) -> NSColor? {
        switch level {
        case .warning:
            return .systemYellow
        case .critical:
            return .systemRed
        case .normal, .unknown, nil:
            return nil
        }
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping

        return [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.smallSystemFontSize,
                weight: .regular
            ),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }

}
