import Cocoa

/// MacStatus — macOS menu bar system monitor
/// AppDelegate: @main entry point and wiring hub between StatusBarManager and CPUReader.

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusBarManager: StatusBarManager?
    private var cpuReader: CPUReader?
    private var timer: Timer?

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

        // Create CPU reader — pure data collection on background queue
        cpuReader = CPUReader()

        // Wire callback: CPUReader.onUpdate → StatusBarManager.updateCPU
        cpuReader?.onUpdate = { [weak self] value in
            DispatchQueue.main.async {
                self?.statusBarManager?.updateCPU(value)
            }
        }

        // LIFE-03: fire first read immediately for zero-config startup
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.cpuReader?.read()
        }

        // D-05: schedule repeating timer at 2-second intervals
        // Anti-Pattern 1: always poll on background queue, never on main thread
        let newTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                self?.cpuReader?.read()
            }
        }
        // Use .common mode so timer fires during menu tracking and modal states
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        // Setting to nil triggers deinit → StatusBarManager.deinit → removeStatusItem (D-10)
        cpuReader = nil
        statusBarManager = nil
    }

    deinit {
        print("AppDelegate deinit — status item cleaned up")
    }
}
