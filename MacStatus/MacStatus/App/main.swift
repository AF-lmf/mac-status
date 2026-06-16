import AppKit

// Application entry point for MacStatus.
// Using a dedicated main.swift allows top-level code execution
// even with Swift 6 strict concurrency checking.

// Prevent duplicate instances — menu bar apps should have exactly
// one status item. A second launch would create a second icon.
if let bundleId = Bundle.main.bundleIdentifier {
    let currentPid = ProcessInfo.processInfo.processIdentifier
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
    if runningApps.contains(where: { $0.processIdentifier != currentPid }) {
        // Another instance is already running — exit immediately.
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
