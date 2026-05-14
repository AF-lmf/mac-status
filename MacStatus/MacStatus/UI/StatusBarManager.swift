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

    // Network monitoring (D-14: separate NSStatusItem with fixed width)
    private var networkStatusItem: NSStatusItem?
    /// Last displayed network stats for tolerance-based redraw (1 KB/s threshold).
    private var lastNetworkStats: NetworkStats?

    // Memory monitoring (D-14: separate NSStatusItem with fixed width)
    private var memoryStatusItem: NSStatusItem?
    /// Last displayed memory stats for tolerance-based redraw (0.5% threshold).
    private var lastMemoryStats: MemoryStats?

    // MARK: - Initialization

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.autosaveName = "com.macstatus.cpu"
        // D-04: zero-config startup shows "CPU --%" until first read completes
        statusItem?.button?.attributedTitle = attributedString("CPU --%")

        // macOS 26 (Tahoe) privacy gate detection.
        // On macOS 26+, the user must explicitly allow menu bar items
        // in System Settings. This check fires after 2 seconds to give
        // the system time to register the status item.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, let item = self.statusItem else { return }
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
            if let item = memoryStatusItem {
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
            statusItem?.button?.attributedTitle = attributedString("CPU --%")
            lastDisplayedValue = nil
            return
        }

        // D-06: tolerance-based redraw — skip if change < 0.5%
        if let last = lastDisplayedValue, abs(value - last) < 0.5 {
            return
        }

        lastDisplayedValue = value
        // D-04: "CPU XX%" format
        statusItem?.button?.attributedTitle = attributedString(
            String(format: "CPU %.0f%%", value)
        )
    }

    // MARK: - Network Display

    /// Create the network `NSStatusItem` (D-14: fixed width, separate from CPU).
    ///
    /// - Fixed width of 90pt accommodates `"↓2.1M ↑512K"` plus macOS padding.
    /// - `autosaveName` persists position across launches.
    /// - Initial placeholder `"↓-- ↑--"` follows LIFE-03 zero-config pattern.
    func setupNetworkItem() {
        // D-14: FixedWidth — PITFALL P8: variableLength causes menu bar jitter
        networkStatusItem = NSStatusBar.system.statusItem(withLength: 90)
        networkStatusItem?.autosaveName = "com.macstatus.network"
        networkStatusItem?.button?.attributedTitle = attributedString("↓-- ↑--")
    }

    /// Update the menu bar network rate display.
    /// - Parameter stats: Current network throughput rates, or `nil` for error state.
    func updateNetwork(_ stats: NetworkStats?) {
        guard let stats else {
            networkStatusItem?.button?.attributedTitle = attributedString("↓-- ↑--")
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
        let text = formatNetworkCompact(download: stats.downloadBytesPerSec,
                                         upload: stats.uploadBytesPerSec)
        networkStatusItem?.button?.attributedTitle = attributedString(text)
    }

    // MARK: - Memory Display

    /// Create the memory `NSStatusItem` (D-14: fixed width, separate from CPU/network).
    ///
    /// - Fixed width of 100pt accommodates `"MEM 8.2G/16G"` (longest variant on 16+ GB Macs).
    /// - `autosaveName` persists position across launches.
    /// - Initial placeholder `"MEM --/--"` follows LIFE-03 zero-config pattern.
    func setupMemoryItem() {
        // D-14: FixedWidth — PITFALL P8: variableLength causes menu bar jitter
        memoryStatusItem = NSStatusBar.system.statusItem(withLength: 100)
        memoryStatusItem?.autosaveName = "com.macstatus.memory"
        memoryStatusItem?.button?.attributedTitle = attributedString("MEM --/--")
    }

    /// Update the menu bar memory usage display.
    /// - Parameter stats: Current memory statistics, or `nil` for error state.
    func updateMemory(_ stats: MemoryStats?) {
        guard let stats else {
            memoryStatusItem?.button?.attributedTitle = attributedString("MEM --/--")
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
        let text = formatMemoryCompact(used: stats.usedBytes,
                                        total: stats.totalBytes)
        memoryStatusItem?.button?.attributedTitle = attributedString(text)
    }

    // MARK: - Text Formatting

    /// Create an NSAttributedString with monospaced digits and label color.
    /// - D-07: monospacedDigitSystemFont prevents menu bar width jitter.
    /// - labelColor auto-adapts to light/dark mode.
    private func attributedString(_ text: String) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .regular
        )
        let color = NSColor.labelColor

        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
            ]
        )
    }
}
