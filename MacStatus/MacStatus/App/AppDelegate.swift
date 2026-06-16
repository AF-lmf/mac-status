import AppKit
import Cocoa

/// Pure-menu-bar application delegate.
///
/// M002: Uses MetricCollector as the unified orchestrator for all readers.
/// MetricCollector handles reader creation, timer scheduling, and data routing
/// to both the status bar and popover dashboard.
///
/// AppDelegate's role is now minimal:
/// 1. Wire PopoverManager ↔ StatusBarManager
/// 2. Start MetricCollector
/// 3. Self-monitoring
final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {

    // MARK: - Properties

    private var selfMonitorTimer: Timer?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wire up popover ↔ status bar
        let popoverManager = PopoverManager.shared
        StatusBarManager.shared.configure(popoverManager: popoverManager)

        MetricCollector.shared.start()

        // Start self-monitoring (separate from MetricCollector to avoid skew)
        startSelfMonitor()
    }

    // NOTE: Do NOT implement applicationShouldTerminateAfterLastWindowClosed.
    // Menu bar apps have no regular windows; the popover doesn't count.
    // Returning true here would cause immediate termination when the popover closes.
    // Quit is handled explicitly via the popover Quit button or right-click menu.

    // MARK: - Self Monitoring

    private func startSelfMonitor() {
        selfMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSelfMonitor()
            }
        }
    }

    /// Measure MacStatus's own CPU and memory usage for the popover footer.
    @MainActor
    private func refreshSelfMonitor() {
        let dashboard = PopoverManager.shared.dashboardState

        // CPU via sysctl kinfo_proc
        let pid = getpid()
        var kinfo = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, UInt32(mib.count), &kinfo, &size, nil, 0)
        if result == 0 {
            let usagePercent = Double(kinfo.kp_proc.p_pctcpu) / Double(0x7fff) * 100.0
            dashboard.selfCpuUsage = max(0, usagePercent)
        }

        // Memory via task_info (resident size in MB)
        var info = task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_basic_info>.stride / MemoryLayout<integer_t>.stride
        )
        let memResult = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), $0, &count)
            }
        }
        if memResult == KERN_SUCCESS {
            let residentMB = Double(info.resident_size) / 1_048_576.0
            dashboard.selfMemoryMB = residentMB
        }
    }
}
