import Cocoa

// MARK: - Sendable CPU Load Wrapper
// Converts Mach C struct (host_cpu_load_info) to a Swift Sendable type,
// ensuring Swift 6 strict concurrency compliance when crossing actor boundaries.
struct CPULoad: Sendable {
    let user: Double
    let system: Double
    let idle: Double
    let nice: Double

    var usage: Double {
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return ((user + system + nice) / total) * 100.0
    }
}

// MARK: - CPU Reader
/// Reads aggregate CPU usage via host_statistics(HOST_CPU_LOAD_INFO).
/// Pure data collection — no Timer, no main-thread dispatch.
/// The caller is responsible for polling frequency and UI dispatch.
final class CPUReader {

    // MARK: - Properties

    private var previousInfo = host_cpu_load_info()
    private var hasPrevious = false

    /// Callback delivering CPU usage percentage (0-100) or nil on error.
    var onUpdate: ((Double?) -> Void)?

    // MARK: - Data Collection

    /// Perform one CPU data collection cycle.
    /// Calls onUpdate with the computed CPU usage percentage, or nil if
    /// host_statistics fails.
    func read() {
        let count = MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        var size = mach_msg_type_number_t(count)
        var cpuLoadInfo = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: count) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }

        guard result == KERN_SUCCESS else {
            onUpdate?(nil)
            return
        }

        guard hasPrevious else {
            previousInfo = cpuLoadInfo
            hasPrevious = true
            return
        }

        // Delta calculation using &- (overflow-safe subtraction)
        let userDiff = Double(cpuLoadInfo.cpu_ticks.0 &- previousInfo.cpu_ticks.0)
        let sysDiff  = Double(cpuLoadInfo.cpu_ticks.1 &- previousInfo.cpu_ticks.1)
        let idleDiff = Double(cpuLoadInfo.cpu_ticks.2 &- previousInfo.cpu_ticks.2)
        let niceDiff = Double(cpuLoadInfo.cpu_ticks.3 &- previousInfo.cpu_ticks.3)
        let totalTicks = userDiff + sysDiff + idleDiff + niceDiff

        previousInfo = cpuLoadInfo

        guard totalTicks > 0 else {
            onUpdate?(0.0)
            return
        }

        let usage = ((userDiff + sysDiff + niceDiff) / totalTicks) * 100.0
        onUpdate?(usage.isNaN ? nil : usage)
    }
}
