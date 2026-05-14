import Foundation

/// Protocol defining the lifecycle for periodic system data readers.
/// Conforming types poll a system API, transform raw data into a typed value,
/// and deliver results via the `onUpdate` callback.
///
/// Used by: CPUReader (Phase 1), MemoryReader (Phase 2), NetworkReader (Phase 3), GPUReader (Phase 4)
protocol ReaderProtocol: AnyObject {
    /// The typed value this reader produces (e.g., Double for CPU %, network rate tuple, etc.)
    associatedtype ValueType

    /// Closure called when a new reading is available.
    /// - Parameter value: The typed reading value, or nil if the read failed.
    var onUpdate: ((ValueType?) -> Void)? { get set }

    /// Perform one-time initialization (called before first read).
    func setup()

    /// Perform one data collection cycle.
    /// Subclasses override this to call system APIs and invoke onUpdate.
    func read()

    /// Begin periodic polling (fires first read immediately for zero-config startup).
    func start()

    /// Stop polling and release timer resources.
    func stop()
}
