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
}

// MARK: - Memory Reader
/// Reads memory pressure via `sysctlbyname("kern.memorystatus_vm_pressure_level")`.
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

        onUpdate?(MemoryStats(pressureLevel: MemoryPressureLevel(rawValue: level)))
    }
}
