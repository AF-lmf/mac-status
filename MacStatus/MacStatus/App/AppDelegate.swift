import Cocoa
import ServiceManagement

/// MacStatus — macOS menu bar system monitor
/// AppDelegate: @main entry point and thin wiring hub between StatusBarManager and CPUReader.

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusBarManager: StatusBarManager?
    private var cpuReader: CPUReader?
    private var networkReader: NetworkReader?
    private var memoryReader: MemoryReader?
    private var gpuReader: GPUReader?

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
        configureLaunchAtLogin()
        configureReaders()
        registerSleepWakeObservers()
        startReaders()
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterSleepWakeObservers()
        stopReaders()
        // Setting to nil triggers deinit -> StatusBarManager.deinit -> removeStatusItem (D-10)
        cpuReader = nil
        networkReader = nil
        memoryReader = nil
        gpuReader = nil
        statusBarManager = nil
    }

    // MARK: - Launch at Login

    private func configureLaunchAtLogin() {
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }

        do {
            try service.register()
        } catch {
            print("Launch at login registration failed: \(error)")
        }
    }

    // MARK: - Reader Lifecycle

    @MainActor
    private func configureReaders() {
        // Create CPU reader — Timer-based polling on background queue via TimerReader
        cpuReader = CPUReader()

        // Wire callback: CPUReader.onUpdate → StatusBarManager.updateCPU
        cpuReader?.onUpdate = { [weak self] value in
            DispatchQueue.main.async {
                self?.statusBarManager?.updateCPU(value)
            }
        }

        // Phase 2: Network reader (1s interval per D-06)
        statusBarManager?.setupNetworkItem()

        networkReader = NetworkReader()
        networkReader?.onUpdate = { [weak self] stats in
            DispatchQueue.main.async {
                self?.statusBarManager?.updateNetwork(stats)
            }
        }

        // Phase 2: Memory reader (2s interval per D-10)
        statusBarManager?.setupMemoryItem()

        memoryReader = MemoryReader()
        memoryReader?.onUpdate = { [weak self] stats in
            DispatchQueue.main.async {
                self?.statusBarManager?.updateMemory(stats)
            }
        }

        // Phase 3: GPU reader (2s interval per GPUReader)
        gpuReader = GPUReader()
        gpuReader?.onUpdate = { [weak self] stats in
            DispatchQueue.main.async {
                self?.statusBarManager?.updateGPU(stats)
            }
        }
    }

    private func startReaders() {
        // TimerReader fires first read immediately (LIFE-03) and replaces
        // any existing timer, so wake recovery can safely reuse this path.
        cpuReader?.start()
        networkReader?.start()
        memoryReader?.start()
        gpuReader?.start()
    }

    private func stopReaders() {
        cpuReader?.stop()
        networkReader?.stop()
        memoryReader?.stop()
        gpuReader?.stop()
    }

    // MARK: - Sleep/Wake Recovery

    private func registerSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(applicationWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    private func unregisterSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.removeObserver(self, name: NSWorkspace.willSleepNotification, object: nil)
        center.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func applicationWillSleep(_ notification: Notification) {
        stopReaders()
    }

    @objc private func applicationDidWake(_ notification: Notification) {
        startReaders()
    }

    deinit {
        print("AppDelegate deinit — status item cleaned up")
    }
}
