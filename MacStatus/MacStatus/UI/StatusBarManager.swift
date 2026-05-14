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
            print("StatusBarManager deinit — status item removed")
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
