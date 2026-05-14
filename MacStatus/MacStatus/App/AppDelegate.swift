import Cocoa

/// MacStatus — macOS menu bar system monitor
/// AppDelegate: @main entry point and thin wiring hub between StatusBarManager and CPUReader.

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusBarManager: StatusBarManager?
    private var cpuReader: CPUReader?

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop polling and invalidate timer
        cpuReader?.stop()
        // Setting to nil triggers deinit → StatusBarManager.deinit → removeStatusItem (D-10)
        cpuReader = nil
        statusBarManager = nil
    }

    deinit {
        print("AppDelegate deinit — status item cleaned up")
    }
}
