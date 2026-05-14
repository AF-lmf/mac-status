import Cocoa

/// MacStatus — macOS menu bar system monitor
/// AppDelegate: @main entry point and thin wiring hub between StatusBarManager and CPUReader.

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusBarManager: StatusBarManager?
    private var cpuReader: CPUReader?
    private var networkReader: NetworkReader?
    private var memoryReader: MemoryReader?

    // MARK: - Application Entry Point

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // .accessory = pure menu bar app, no Dock icon (reinforces Info.plist LSUIElement)
        app.setActivationPolicy(.accessory)
        app.run()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item via StatusBarManager (D-08)
        statusBarManager = StatusBarManager()

        // Create CPU reader — Timer-based polling on background queue via TimerReader
        cpuReader = CPUReader()

        // Wire callback: CPUReader.onUpdate → StatusBarManager.updateCPU
        cpuReader?.onUpdate = { [weak self] value in
            DispatchQueue.main.async {
                self?.statusBarManager?.updateCPU(value)
            }
        }

        // Start polling — TimerReader fires first read immediately (LIFE-03)
        // and schedules a repeating timer at the configured interval (D-05)
        cpuReader?.start()

        // Phase 2: Network reader (1s interval per D-06)
        statusBarManager?.setupNetworkItem()

        networkReader = NetworkReader()
        networkReader?.onUpdate = { [weak self] stats in
            DispatchQueue.main.async {
                self?.statusBarManager?.updateNetwork(stats)
            }
        }
        networkReader?.start()

        // Phase 2: Memory reader (2s interval per D-10)
        statusBarManager?.setupMemoryItem()

        memoryReader = MemoryReader()
        memoryReader?.onUpdate = { [weak self] stats in
            DispatchQueue.main.async {
                self?.statusBarManager?.updateMemory(stats)
            }
        }
        memoryReader?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop polling and invalidate timer
        cpuReader?.stop()
        networkReader?.stop()
        memoryReader?.stop()
        // Setting to nil triggers deinit → StatusBarManager.deinit → removeStatusItem (D-10)
        cpuReader = nil
        networkReader = nil
        memoryReader = nil
        statusBarManager = nil
    }

    deinit {
        print("AppDelegate deinit — status item cleaned up")
    }
}
