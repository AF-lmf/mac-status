import AppKit
import SwiftUI

// MARK: - Popover Manager

/// Manages the NSPopover lifecycle and bridges SwiftUI views to AppKit.
/// The popover replaces NSMenu as the primary interaction surface.
///
/// Thread safety: All methods must be called on the main thread.
/// NSPopover is not thread-safe and must be manipulated on the main actor.
@MainActor
final class PopoverManager: NSObject, NSPopoverDelegate {

    // MARK: - Singleton

    static let shared = PopoverManager()

    // MARK: - Properties

    let popover: NSPopover
    let dashboardState = DashboardState()

    private var processRefreshTask: Task<Void, Never>?

    /// Global mouse monitor that dismisses the popover when the user clicks
    /// outside the app. Installed while the popover is shown, removed when it
    /// closes. Global monitors only observe events delivered to *other* apps,
    /// so clicks on our own status item or the popover content are never seen
    /// here — that avoids the classic "click the status item and the popover
    /// just re-opens" race while still dismissing on focus loss.
    private var outsideClickMonitor: Any?

    // MARK: - Initialization

    private override init() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let hostingController = NSHostingController(
            rootView: DashboardView()
                .environmentObject(dashboardState)
        )
        // Size the popover to the SwiftUI content's intrinsic height
        // (DashboardView pins a fixed 320pt width) so there's no dead space
        // below short content — the process list is capped at 5 rows, so the
        // body is always bounded. macOS 13+.
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        self.popover = popover
        super.init()
        // Used to clean up the outside-click monitor no matter how it closes.
        popover.delegate = self
    }

    // MARK: - Toggle

    /// Toggle the popover relative to the status bar button.
    /// Called from StatusBarManager when the button is clicked.
    func toggle(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Trigger process list refresh when popover opens
            refreshProcessList()
            // Make the popover window key so keyboard shortcuts work
            popover.contentViewController?.view.window?.becomeKey()
            // Dismiss on clicks outside the app (`.accessory` apps don't get
            // these through NSPopover's own `.transient` monitoring).
            startOutsideClickMonitor()
        }
    }

    /// Close the popover if it's currently shown.
    func close() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    // MARK: - Outside-click dismissal

    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func stopOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - NSPopoverDelegate

    /// Tear down the outside-click monitor however the popover was closed
    /// (outside click, status-item toggle, or transient app deactivation).
    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitor()
    }

    // MARK: - Process List

    /// Refresh the top processes list asynchronously.
    /// nettop takes ~1s, so this runs on a background task and updates on MainActor.
    func refreshProcessList() {
        // Cancel any in-flight refresh
        processRefreshTask?.cancel()

        dashboardState.processesLoading = true
        dashboardState.processError = nil

        processRefreshTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                ProcessNetworkReader.readTopProcesses()
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                switch result {
                case .processes(let procs):
                    self.dashboardState.topProcesses = procs
                    self.dashboardState.processesLoading = false
                case .idle:
                    self.dashboardState.topProcesses = []
                    self.dashboardState.processesLoading = false
                case .unavailable(let reason):
                    self.dashboardState.processError = reason
                    self.dashboardState.processesLoading = false
                }
            }
        }
    }
}
