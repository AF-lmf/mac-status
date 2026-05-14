import Foundation

class TimerReader<T>: ReaderProtocol {

    typealias ValueType = T

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.macstatus.reader", qos: .utility)

    let interval: TimeInterval

    var onUpdate: ((T?) -> Void)?

    init(interval: TimeInterval) {
        self.interval = interval
        setup()
    }

    func setup() {}

    func read() {}

    func start() {
        stop()

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.setEventHandler { [weak self] in
            self?.read()
        }
        source.schedule(deadline: .now(), repeating: interval)
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
