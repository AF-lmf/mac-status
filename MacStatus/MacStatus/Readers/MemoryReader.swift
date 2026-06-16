import Darwin
import Foundation

// MARK: - Memory Pressure Model
/// macOS memory pressure levels from `kern.memorystatus_vm_pressure_level`.
enum MemoryPressureLevel: Sendable, Equatable {
    case normal
    case warning
    case critical
    case unknown(Int32)

    init(rawValue: Int32) {
        switch rawValue {
        case 1:
            self = .normal
        case 2:
            self = .warning
        case 4:
            self = .critical
        default:
            self = .unknown(rawValue)
        }
    }
}

// MARK: - Sendable Memory Stats Wrapper
/// Holds a single snapshot of memory pressure.
/// Conforms to Sendable for safe passage across Swift 6 actor boundaries
/// (TimerReader fires from a background queue; the callback delivers to MainActor).
struct MemoryStats: Sendable, Equatable {
    /// Current system memory pressure level.
    let pressureLevel: MemoryPressureLevel
    /// Estimated physical memory used percentage, excluding file cache where possible.
    let usedPercent: Double?
}

// MARK: - Memory Reader
/// Reads memory pressure via `sysctlbyname("kern.memorystatus_vm_pressure_level")`
/// and estimates physical memory usage via `host_statistics64`.
///
/// Extends `TimerReader<MemoryStats>` — polling runs on `.utility` background queue.
///
/// Values observed by this sysctl are:
/// - `1`: normal
/// - `2`: warning
/// - `4`: critical
final class MemoryReader: TimerReader<MemoryStats> {

    // MARK: - Initialization

    /// Create a memory reader with a 2-second polling interval (D-10).
    init() {
        super.init(interval: 2.0)
    }

    // MARK: - ReaderProtocol Lifecycle

    /// Read the current memory pressure level. On failure, sends `nil` so the
    /// UI displays `MEM --` instead of stale or misleading data.
    override func read() {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname(
            "kern.memorystatus_vm_pressure_level",
            &level,
            &size,
            nil,
            0
        )

        guard result == 0 else {
            onUpdate?(nil)
            return
        }

        onUpdate?(
            MemoryStats(
                pressureLevel: MemoryPressureLevel(rawValue: level),
                usedPercent: readUsedMemoryPercent()
            )
        )
    }

    private func readUsedMemoryPercent() -> Double? {
        let count = MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        var vmStats = vm_statistics64()
        var size = mach_msg_type_number_t(count)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: count) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let usedPages = UInt64(vmStats.active_count)
            + UInt64(vmStats.wire_count)
            + UInt64(vmStats.compressor_page_count)
        let usedBytes = Double(usedPages) * Double(getpagesize())
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)

        guard totalBytes > 0 else { return nil }
        return min(max((usedBytes / totalBytes) * 100.0, 0), 100)
    }

    /// Synchronous read returning MemoryStats directly.
    func readValue() -> MemoryStats? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname(
            "kern.memorystatus_vm_pressure_level",
            &level, &size, nil, 0
        )

        guard result == 0 else { return nil }

        return MemoryStats(
            pressureLevel: MemoryPressureLevel(rawValue: level),
            usedPercent: readUsedMemoryPercent()
        )
    }
}
