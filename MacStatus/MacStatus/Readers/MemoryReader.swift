import Cocoa

// MARK: - Sendable Memory Stats Wrapper
/// Holds a single snapshot of memory utilization.
/// Conforms to Sendable for safe passage across Swift 6 actor boundaries
/// (TimerReader fires from a background queue; the callback delivers to MainActor).
struct MemoryStats: Sendable {
    /// Bytes currently in use (active + inactive + speculative + wired + compressed - purgeable - external).
    let usedBytes: Double
    /// Total physical memory in bytes (from host_basic_info.max_mem).
    let totalBytes: Double
    /// Bytes free (total - used, floored at 0).
    let freeBytes: Double
}

/// Cached page size — read via `getpagesize()` (a POSIX function) rather than
/// directly accessing the C `extern vm_page_size` global, which Swift 6 strict
/// concurrency flags as shared mutable state. Page size never changes during
/// process lifetime, so reading once at module load is safe and efficient.
private let cachedPageSize = Double(getpagesize())

// MARK: - Memory Reader
/// Reads memory utilization via `host_statistics64(HOST_VM_INFO64)` page statistics
/// and `host_info(HOST_BASIC_INFO).max_mem` for total physical RAM.
///
/// Extends `TimerReader<MemoryStats>` — polling runs on `.utility` background queue.
/// Total physical memory is read once during `setup()` and cached; page statistics
/// are queried every cycle. The standard macOS "used" formula matches Activity Monitor:
/// `active + inactive + speculative + wired + compressed - purgeable - external`.
///
/// - Important: Uses `host_basic_info.max_mem` (actual physical RAM), NEVER
///   `memory_size` (capped at 2 GB — PITFALL 1 from RESEARCH.md).
/// - Important: Page sizes come from the `vm_page_size` extern variable;
///   16 KB on Apple Silicon, 4 KB on Intel. No hardcoded constants.
/// - Note: Unlike NetworkReader, no sleep/wake handling is needed — this reader
///   queries absolute kernel values, not deltas dependent on a stored baseline.
final class MemoryReader: TimerReader<MemoryStats> {

    // MARK: - Private State

    /// Total physical memory in bytes — set once in `setup()`.
    private var totalSize: Double = 0

    // MARK: - Initialization

    /// Create a memory reader with a 2-second polling interval (D-10).
    init() {
        super.init(interval: 2.0)
    }

    // MARK: - ReaderProtocol Lifecycle

    /// Read total physical memory once via `host_info(HOST_BASIC_INFO)`.
    ///
    /// Uses `max_mem` (uint64_t, actual RAM) — never `memory_size`
    /// which is capped at 2 GB for backward compatibility (PITFALL 1).
    override func setup() {
        var stats = host_basic_info()
        var count = UInt32(MemoryLayout<host_basic_info_data_t>.size
                          / MemoryLayout<integer_t>.size)

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count)
            }
        }

        guard kerr == KERN_SUCCESS else {
            totalSize = 0
            return
        }

        // CRITICAL: use max_mem, NOT memory_size (capped at 2 GB — PITFALL 1)
        totalSize = Double(stats.max_mem)
    }

    /// Read current memory page statistics via `host_statistics64(HOST_VM_INFO64)`.
    ///
    /// Computes "used" memory with the standard macOS formula matching Activity Monitor:
    /// `active + inactive + speculative + wired + compressed - purgeable - external`.
    ///
    /// - Important: All page counts are multiplied by the runtime `vm_page_size`
    ///   global variable — never hardcoded to 16384 or 4096.
    override func read() {
        guard totalSize > 0 else {
            onUpdate?(nil)
            return
        }

        var stats = vm_statistics64()
        var count = UInt32(MemoryLayout<vm_statistics64_data_t>.size
                          / MemoryLayout<integer_t>.size)

        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            // T-02-06: kernel call failed — send nil so StatusBarManager
            // displays "MEM --/--" rather than stale data or a crash.
            onUpdate?(nil)
            return
        }

        let pageSize = cachedPageSize

        // Convert page counts to bytes using cached runtime page size
        let active      = Double(stats.active_count) * pageSize
        let wired       = Double(stats.wire_count) * pageSize
        let compressed  = Double(stats.compressor_page_count) * pageSize
        let inactive    = Double(stats.inactive_count) * pageSize
        let speculative = Double(stats.speculative_count) * pageSize
        let purgeable   = Double(stats.purgeable_count) * pageSize
        let external    = Double(stats.external_page_count) * pageSize

        // Standard macOS "used" formula (matches Activity Monitor)
        // T-02-08: clamp used ≥ 0 to guard against corrupted page counts
        let used = max(active + inactive + speculative + wired
                       + compressed - purgeable - external, 0)
        let free = max(totalSize - used, 0)

        onUpdate?(MemoryStats(
            usedBytes: used,
            totalBytes: totalSize,
            freeBytes: free
        ))
    }
}
