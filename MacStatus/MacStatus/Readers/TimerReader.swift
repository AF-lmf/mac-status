import Foundation

/// Generic base class providing reusable Timer-based polling infrastructure.
///
/// Subclasses override `setup()` (one-time init) and `read()` (per-cycle data collection).
/// Timer lifecycle is managed automatically: `start()` fires the first read immediately
/// (LIFE-03 zero-config startup) then schedules a repeating Timer on a background queue.
///
/// - Note: `read()` is called on `DispatchQueue.global(qos: .utility)` — never on main.
/// - Note: Callbacks (`onUpdate`) are fired from the background queue; the caller is
///   responsible for dispatching UI updates to the main thread.
class TimerReader<T>: ReaderProtocol {

    // MARK: - Typealias

    typealias ValueType = T

    // MARK: - Properties

    private var timer: Timer?

    /// The polling interval in seconds.
    let interval: TimeInterval

    /// Callback delivering a typed value (or nil on error) from each read cycle.
    var onUpdate: ((T?) -> Void)?

    // MARK: - Initialization

    /// Initialize a timer-based reader.
    /// - Parameter interval: Polling interval in seconds (e.g., 2.0 for CPU).
    init(interval: TimeInterval) {
        self.interval = interval
        setup()
    }

    // MARK: - ReaderProtocol Lifecycle

    /// One-time setup — override in subclass to initialize state.
    func setup() {}

    /// Perform one data collection cycle — override in subclass.
    func read() {}

    /// Start periodic polling.
    /// - Calls `stop()` first to ensure idempotent restart.
    /// - Fires the first read immediately for zero-config startup (LIFE-03).
    /// - Schedules a repeating Timer dispatching reads to `.utility` background queue.
    func start() {
        stop()

        // LIFE-03: fire first read immediately for zero-config startup
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.read()
        }

        // Schedule repeating timer — always poll on background queue (Anti-Pattern 1)
        let newTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                self?.read()
            }
        }
        // Use .common mode so timer fires during menu tracking and modal states
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    /// Stop polling and release the timer.
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
