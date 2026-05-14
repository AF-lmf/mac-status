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
    private var latestCPUText = "CPU --%"
    private var latestNetworkText = "↓-- ↑--"
    private var latestMemoryText = "MEM --/--"

    // Phase 2 visible combined status item: CPU + network + memory.
    private var networkStatusItem: NSStatusItem?
    /// Last displayed network stats for tolerance-based redraw (1 KB/s threshold).
    private var lastNetworkStats: NetworkStats?

    /// Last displayed memory stats for tolerance-based redraw (0.5% threshold).
    private var lastMemoryStats: MemoryStats?

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
            latestCPUText = "CPU --%"
            updateCombinedStatus()
            lastDisplayedValue = nil
            return
        }

        // D-06: tolerance-based redraw — skip if change < 0.5%
        if let last = lastDisplayedValue, abs(value - last) < 0.5 {
            return
        }

        lastDisplayedValue = value
        // D-04: "CPU XX%" format
        latestCPUText = String(format: "CPU %.0f%%", value)
        updateCombinedStatus()
    }

    // MARK: - Network Display

    /// Create the network `NSStatusItem` (Phase 2 visible combined display).
    ///
    /// - Fixed width accommodates `"CPU 12% ↓2.1M ↑512K MEM 8.2G/16G"` plus macOS padding.
    /// - `autosaveName` persists position across launches.
    /// - Initial placeholder follows LIFE-03 zero-config pattern.
    func setupNetworkItem() {
        // D-14: FixedWidth — PITFALL P8: variableLength causes menu bar jitter
        networkStatusItem = NSStatusBar.system.statusItem(withLength: 280)
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
        latestMemoryText = "MEM --/--"
        updateCombinedStatus()
    }

    /// Update the menu bar memory usage display.
    /// - Parameter stats: Current memory statistics, or `nil` for error state.
    func updateMemory(_ stats: MemoryStats?) {
        guard let stats else {
            latestMemoryText = "MEM --/--"
            updateCombinedStatus()
            lastMemoryStats = nil
            return
        }

        // Tolerance check: skip redraw if used bytes changed < 0.5% of total
        // (same threshold pattern as CPU — memory changes slowly)
        if let last = lastMemoryStats {
            let change = abs(stats.usedBytes - last.usedBytes) / stats.totalBytes
            if change < 0.005 { return }
        }

        lastMemoryStats = stats
        latestMemoryText = formatMemoryCompact(used: stats.usedBytes,
                                                total: stats.totalBytes)
        updateCombinedStatus()
    }

    // MARK: - Text Formatting

    private func configureStatusButton(_ button: NSStatusBarButton?) {
        button?.cell?.lineBreakMode = .byClipping
        button?.cell?.usesSingleLineMode = true
        button?.cell?.wraps = false
    }

    private func setTitle(_ text: String, on item: NSStatusItem?) {
        item?.button?.title = text
        item?.button?.attributedTitle = attributedString(text)
    }

    private func updateCombinedStatus() {
        setTitle(
            "\(latestCPUText) \(latestNetworkText) \(latestMemoryText)",
            on: networkStatusItem
        )
    }

    /// Create an NSAttributedString with monospaced digits and label color.
    /// - D-07: monospacedDigitSystemFont prevents menu bar width jitter.
    /// - labelColor auto-adapts to light/dark mode.
    private func attributedString(_ text: String) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .regular
        )
        let color = NSColor.labelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping

        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
        )
    }
}
