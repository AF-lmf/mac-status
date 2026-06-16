import Cocoa
import SystemConfiguration

// MARK: - Sendable Network Stats Wrapper
/// Holds a single snapshot of network throughput rates.
/// Conforms to Sendable for safe passage across Swift 6 actor boundaries
/// (TimerReader fires from a background queue; the callback delivers to MainActor).
struct NetworkStats: Sendable {
    /// Bytes per second received (download).
    let downloadBytesPerSec: Double
    /// Bytes per second sent (upload).
    let uploadBytesPerSec: Double
}

// MARK: - Network Reader
/// Reads network throughput via `getifaddrs()` byte counters and
/// `SystemConfiguration` primary-interface detection.
///
/// Extends `TimerReader<NetworkStats>` — polling runs on `.utility` background queue.
/// The primary interface is resolved every read cycle via `SCDynamicStoreCopyValue`,
/// never hardcoded (D-03, PITFALL P5).
///
/// Byte counters are 32-bit `u_int32_t` values; conversion to `Int64` before
/// subtraction prevents wraparound artifacts (PITFALL P2). Delta calculation
/// uses `max(delta, 0)` for safety (D-07).
///
/// - Note: A 1 KB/s tolerance threshold is applied by the StatusBarManager
///   caller; this reader always delivers raw rates.
/// - Note: On wake from sleep the stored baseline is reset to `nil` so the
///   next read cycle establishes a fresh baseline (PITFALLS P5).
final class NetworkReader: TimerReader<NetworkStats> {

    // MARK: - Private State

    /// Stored byte counters from the previous read cycle, used for delta calculation.
    /// Set to `nil` before the first read or after a wake event.
    private var previousBytes: (download: Int64, upload: Int64)?

    /// Timestamp of the previous read cycle.
    private var previousTime: Date?

    /// Token for the `NSWorkspace.didWakeNotification` observer;
    /// stored so it can be removed in `deinit`.
    private var wakeObserver: NSObjectProtocol?

    // MARK: - Initialization

    /// Create a network reader with a 1-second polling interval (D-06).
    init() {
        super.init(interval: 1.0)
    }

    // MARK: - ReaderProtocol Lifecycle

    override func setup() {
        previousBytes = nil
        previousTime = nil

        // PITFALLS P5: reset stored baseline on wake to avoid stale-zero readings
        wakeObserver = NSWorkspace.shared.notificationCenter
            .addObserver(forName: NSWorkspace.didWakeNotification,
                         object: nil,
                         queue: nil) { [weak self] _ in
                self?.previousBytes = nil
                self?.previousTime = nil
            }
    }

    override func read() {
        let now = Date()

        // Re-read the primary interface on every cycle — nearly zero overhead
        // and handles Wi-Fi → Ethernet transitions instantly (D-03).
        let interface = getPrimaryInterface()
        guard !interface.isEmpty else {
            onUpdate?(nil)
            return
        }

        guard let current = readBytes(for: interface) else {
            onUpdate?(nil)
            return
        }

        defer {
            previousBytes = current
            previousTime = now
        }

        guard let prev = previousBytes, let prevTime = previousTime else {
            // First read after startup (or after wake reset) —
            // store baseline only, no rate to report yet.
            return
        }

        let dt = now.timeIntervalSince(prevTime)
        guard dt > 0 else { return }

        // D-07: max(_, 0) handles 32-bit counter wraparound gracefully
        let dlRate = Double(max(current.download - prev.download, 0)) / dt
        let ulRate = Double(max(current.upload - prev.upload, 0)) / dt

        onUpdate?(NetworkStats(downloadBytesPerSec: dlRate,
                                uploadBytesPerSec: ulRate))
    }

    deinit {
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Private Helpers

    /// Resolve the BSD name of the primary network interface (D-03).
    ///
    /// Reads `State:/Network/Global/IPv4` from the SystemConfiguration dynamic
    /// store. Returns the `PrimaryInterface` value (e.g. `"en0"` for Wi-Fi,
    /// `"en4"` for USB-C Ethernet) or `""` on failure.
    private func getPrimaryInterface() -> String {
        guard let global = SCDynamicStoreCopyValue(
            nil, "State:/Network/Global/IPv4" as CFString
        ),
        let dict = global as? [String: Any],
        let name = dict["PrimaryInterface"] as? String else {
            return ""
        }
        return name
    }

    /// Read raw byte counters for a named interface via `getifaddrs()` (D-05).
    ///
    /// Walks the kernel-allocated linked list of `ifaddrs` structs, matches
    /// the requested BSD interface name, and returns the cumulative
    /// `ifi_ibytes` / `ifi_obytes` counters.
    ///
    /// - Parameter interface: BSD interface name (e.g. `"en0"`).
    /// - Returns: Tuple of `(download, upload)` as `Int64`, or `nil` if the
    ///   interface was not found or the syscall failed.
    ///
    /// - Important: `freeifaddrs()` is always called via `defer` to prevent
    ///   memory leaks (~86 MB/day at 1 Hz polling; PITFALL P3).
    private func readBytes(for interface: String) -> (download: Int64, upload: Int64)? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(first) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }

            let name = String(cString: current.pointee.ifa_name)
            guard name == interface else { continue }

            // AF_LINK (link-layer address) ensures ifa_data is a valid if_data struct
            guard let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else { continue }

            guard let raw = current.pointee.ifa_data else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self)

            // CRITICAL: convert u_int32_t → Int64 before any subtraction
            // to handle 32-bit counter wraparound (PITFALL P2)
            return (download: Int64(data.pointee.ifi_ibytes),
                    upload: Int64(data.pointee.ifi_obytes))
        }
        return nil
    }

    /// Synchronous read returning NetworkStats directly.
    func readValue() -> NetworkStats? {
        let now = Date()
        let interface = getPrimaryInterface()
        guard !interface.isEmpty else { return nil }
        guard let current = readBytes(for: interface) else { return nil }

        defer {
            previousBytes = current
            previousTime = now
        }

        guard let prev = previousBytes, let prevTime = previousTime else {
            return nil // First read — baseline only
        }

        let dt = now.timeIntervalSince(prevTime)
        guard dt > 0 else { return nil }

        let dlRate = Double(max(current.download - prev.download, 0)) / dt
        let ulRate = Double(max(current.upload - prev.upload, 0)) / dt

        return NetworkStats(downloadBytesPerSec: dlRate, uploadBytesPerSec: ulRate)
    }
}
