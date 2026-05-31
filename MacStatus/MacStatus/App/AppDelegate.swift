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
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateExistingInstances()

        // Wipe any stale autosaved preferred position before creating the
        // NSStatusItem. A cached position from an earlier autosaveName-based
        // build (Preferred Position = 1000 on a notched display) parks the
        // item under the notch / Control Center cluster so it never renders.
        UserDefaults.standard.removeObject(
            forKey: "NSStatusItem Preferred Position com.macstatus.network"
        )
        UserDefaults.standard.removeObject(
            forKey: "NSStatusItem Visible com.macstatus.network"
        )
        UserDefaults.standard.removeObject(
            forKey: "NSStatusItem Preferred Position com.macstatus.status"
        )
        UserDefaults.standard.removeObject(
            forKey: "NSStatusItem Visible com.macstatus.status"
        )

        // Create status bar item via StatusBarManager (D-08)
        statusBarManager = StatusBarManager()
        statusBarManager?.setupNetworkItem()
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

    // MARK: - Instance Guard

    @MainActor
    private func terminateExistingInstances() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let existingInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID && !$0.isTerminated }

        guard !existingInstances.isEmpty else { return }

        for app in existingInstances {
            if !app.terminate() {
                app.forceTerminate()
            }
        }

        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline,
              existingInstances.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        for app in existingInstances where !app.isTerminated {
            app.forceTerminate()
        }
    }
}
