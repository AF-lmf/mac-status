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
    private var resourceSampleTask: Task<Void, Never>?
    private let resourceReader = ProcessResourceReader()

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
            // Start resource (CPU/memory) sampling loop — cancelled on close (PROC-03)
            startResourceSampling()
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
        // PROC-03: cancel sampling loop, reset loading state
        resourceSampleTask?.cancel()
        resourceSampleTask = nil
        dashboardState.resourceLoading = true  // reset spinner for next open
        // Clear snapshot asynchronously — actor serialises this after any in-flight
        // sample() completes, so there is no concurrent read-write on prevSnapshot.
        Task { [weak self] in
            await self?.resourceReader.clearSnapshot()
        }
    }

    // MARK: - Process List

    /// Start the CPU/memory resource sampling loop (1.5s interval).
    /// Cancels any prior loop first to prevent double-sampling if popover reopens quickly.
    /// Must be called on @MainActor (toggle() is already on main actor).
    ///
    /// `resourceReader.sample()` is an actor method — calling it with `await` hops to
    /// the actor's executor automatically (off MainActor), so there is no need for an
    /// extra `Task.detached` wrapper. The actor's serial executor also serialises
    /// concurrent calls, eliminating the CR-01/CR-02 data races.
    func startResourceSampling() {
        resourceSampleTask?.cancel()
        resourceSampleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Actor hop: sample() runs on ProcessResourceReader's executor (off MainActor).
                let (cpuTop, memTop) = await self.resourceReader.sample()

                guard !Task.isCancelled else { return }

                self.dashboardState.topCPUProcesses = cpuTop
                self.dashboardState.topMemoryProcesses = memTop
                self.dashboardState.resourceLoading = false

                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

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
