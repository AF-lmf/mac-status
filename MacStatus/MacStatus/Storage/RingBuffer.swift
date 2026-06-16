import Foundation

// MARK: - Ring Buffer

/// A thread-safe circular buffer for time-series metric samples.
/// Stores the most recent N samples in memory for fast access.
///
/// Uses a serial DispatchQueue for thread safety rather than
/// actor isolation, since it's accessed from multiple readers.
final class RingBuffer: @unchecked Sendable {
    private var buffer: [MetricSample]
    private let capacity: Int
    private var writeIndex: Int = 0
    private var count_: Int = 0
    private let lock = NSLock()

    init(capacity: Int = 300) {
        self.capacity = capacity
        self.buffer = Array(repeating: MetricSample(), count: capacity)
    }

    /// Append a new sample. If the buffer is full, the oldest sample is overwritten.
    func append(_ sample: MetricSample) {
        lock.lock()
        defer { lock.unlock() }
        buffer[writeIndex] = sample
        writeIndex = (writeIndex + 1) % capacity
        count_ = min(count_ + 1, capacity)
    }

    /// Get all samples in chronological order (oldest first).
    func allSamples() -> [MetricSample] {
        lock.lock()
        defer { lock.unlock() }

        guard count_ > 0 else { return [] }

        if count_ < capacity {
            return Array(buffer[0..<count_])
        }

        // Buffer is full — writeIndex points to the oldest sample
        return Array(buffer[writeIndex..<capacity]) + Array(buffer[0..<writeIndex])
    }

    /// Get the most recent N samples.
    func recentSamples(_ n: Int) -> [MetricSample] {
        let all = allSamples()
        return Array(all.suffix(n))
    }

    /// Get samples within a time range.
    func samples(from start: Date, to end: Date) -> [MetricSample] {
        allSamples().filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    /// Current number of samples in the buffer.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return count_
    }

    /// Clear all samples.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        count_ = 0
    }
}
