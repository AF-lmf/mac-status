import Cocoa

// MacStatus — macOS menu bar system monitor
// AppDelegate: @main entry point, NSStatusBar lifecycle, and inline CPU reader
// Uses host_statistics(HOST_CPU_LOAD_INFO) on a background queue for minimal overhead

@MainActor
@main
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var timer: Timer?

    // nonisolated(unsafe): accessed from serial background queue (readCPU) and main thread
    // (updateDisplay). The serial dispatch pattern ensures no concurrent access in practice.
    nonisolated(unsafe) private var previousCPUInfo = host_cpu_load_info()
    nonisolated(unsafe) private var hasPreviousCPUInfo = false
    nonisolated(unsafe) private var lastDisplayedCPU: Double?

    // MARK: - Application Entry Point

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // .accessory = pure menu bar app, no Dock icon (reinforces Info.plist LSUIElement)
        app.setActivationPolicy(.accessory)
        app.run()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the menu bar status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.autosaveName = "com.macstatus.cpu"
        // Initial placeholder — zero-config startup shows "CPU --%" until first read completes
        statusItem?.button?.attributedTitle = attributedString("CPU --%")

        startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPolling()
        // CRITICAL: prevent ghost icons (PITFALLS.md Pitfall 1)
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    deinit {
        print("AppDelegate deinit — status item cleaned up")
    }

    // MARK: - Polling

    private func startPolling() {
        // Fire first read immediately — LIFE-03 zero-config startup
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.readCPU()
        }

        // Schedule repeating timer at 2-second intervals (D-05)
        let newTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                self?.readCPU()
            }
        }
        // Use .common mode so timer fires during menu tracking and other modal states
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - CPU Reading (runs on background queue)

    nonisolated private func readCPU() {
        let count = MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        var size = mach_msg_type_number_t(count)
        var cpuLoadInfo = host_cpu_load_info()

        // Call host_statistics with pointer rebinding (RESEARCH.md verified pattern)
        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: count) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }

        // Threat T-01-01: Check kern_return_t, degrade gracefully on failure
        guard result == KERN_SUCCESS else {
            Task { @MainActor [weak self] in
                self?.updateDisplay(nil)
            }
            return
        }

        // Skip first read — no delta possible (need two samples to calculate usage)
        guard hasPreviousCPUInfo else {
            previousCPUInfo = cpuLoadInfo
            hasPreviousCPUInfo = true
            return
        }

        // Delta calculation using &- (overflow-safe subtraction, RESEARCH.md A3)
        let userDiff = Double(cpuLoadInfo.cpu_ticks.0 &- previousCPUInfo.cpu_ticks.0)
        let sysDiff  = Double(cpuLoadInfo.cpu_ticks.1 &- previousCPUInfo.cpu_ticks.1)
        let idleDiff = Double(cpuLoadInfo.cpu_ticks.2 &- previousCPUInfo.cpu_ticks.2)
        let niceDiff = Double(cpuLoadInfo.cpu_ticks.3 &- previousCPUInfo.cpu_ticks.3)
        let totalTicks = userDiff + sysDiff + idleDiff + niceDiff

        // Store current as previous for next delta calculation
        previousCPUInfo = cpuLoadInfo

        // guard division by zero
        guard totalTicks > 0 else {
            Task { @MainActor [weak self] in
                self?.updateDisplay(0.0)
            }
            return
        }

        let usage = ((userDiff + sysDiff + niceDiff) / totalTicks) * 100.0

        // Dispatch result to main thread for UI update
        Task { @MainActor [weak self] in
            self?.updateDisplay(usage.isNaN ? nil : usage)
        }
    }

    // MARK: - Display Update (runs on main thread)

    private func updateDisplay(_ value: Double?) {
        guard let value = value else {
            // Error state: Mach API failed → show "--"
            statusItem?.button?.attributedTitle = attributedString("CPU --%")
            lastDisplayedCPU = nil
            return
        }

        // D-06 tolerance check: skip redraw if change < 0.5%
        if let last = lastDisplayedCPU, abs(value - last) < 0.5 {
            return
        }

        lastDisplayedCPU = value
        // D-04 format: "CPU XX%"
        statusItem?.button?.attributedTitle = attributedString(
            String(format: "CPU %.0f%%", value)
        )
    }

    // MARK: - Attributed String Helper

    private func attributedString(_ text: String) -> NSAttributedString {
        // D-07: monospaced digits prevent menu bar width jitter
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .regular
        )
        // labelColor auto-adapts to light/dark mode
        let color = NSColor.labelColor

        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
    }
}
