import Cocoa

/// Manages the NSStatusItem lifecycle, display formatting, and macOS 26
/// menu bar privacy gate detection.
/// All NSStatusItem operations must occur on the main actor — marking the
/// class @MainActor satisfies Swift 6 strict concurrency checking.
@MainActor
final class StatusBarManager: NSObject, NSMenuDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    /// Last displayed value for D-06 tolerance-based redraw (0.5% threshold).
    private var lastDisplayedValue: Double?
    private var latestCPUText = "C--"
    private var latestGPUText = "G--"
    private var latestNetworkText = "↓-- ↑--"
    private var latestMemoryText = "M--"
    private var latestCPUUsage: Double?
    private var latestGPUUsage: Double?
    private var latestMemoryPressure: MemoryPressureLevel?
    private var hasPresentedMenuBarNotice = false
    private let minimumStatusItemLength: CGFloat = 120
    private let maximumStatusItemLength: CGFloat = 260

    // Visible combined status item: CPU + GPU + memory + network.
    private var networkStatusItem: NSStatusItem?
    /// Last displayed network stats for tolerance-based redraw (1 KB/s threshold).
    private var lastNetworkStats: NetworkStats?

    /// Last displayed memory stats for tolerance-based redraw (0.5% threshold).
    private var lastMemoryStats: MemoryStats?

    /// Last displayed GPU stats for redraw skipping.
    private var lastGPUStats: GPUStats?

    private let processNetworkQueue = DispatchQueue(
        label: "com.aflmf.macstatus.process-network",
        qos: .utility
    )
    private var processNetworkRequestID = 0
    private lazy var processNetworkHeaderItem = disabledMenuItem("网络占用最高 5 个进程")
    private lazy var processNetworkItems: [NSMenuItem] = (0..<5).map { _ in
        disabledMenuItem("正在采样...")
    }

    private lazy var statusMenu: NSMenu = {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        menu.addItem(processNetworkHeaderItem)
        processNetworkItems.forEach { menu.addItem($0) }
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit MacStatus",
            action: #selector(quitMacStatus(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }()

    // MARK: - Initialization

    override init() {
        super.init()

        scheduleMenuBarVisibilityNotice()
    }

    /// D-10: Prevent ghost icons by removing the status item before deallocation.
    deinit {
        // deinit is nonisolated in a @MainActor class — assumeIsolated is safe
        // because the AppDelegate holds the sole strong reference and releases it
        // on the main thread via applicationWillTerminate.
        MainActor.assumeIsolated {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            if let item = networkStatusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            print("StatusBarManager deinit — status items removed")
        }
    }

    // MARK: - Display Update

    /// Update the menu bar CPU display.
    /// - Parameter value: CPU usage percentage (0-100), or nil for error state.
    func updateCPU(_ value: Double?) {
        guard let value else {
            // Error state: Mach API failed, always update to "--"
            latestCPUText = "C--"
            latestCPUUsage = nil
            updateCombinedStatus()
            lastDisplayedValue = nil
            return
        }

        let nextCPUText = String(format: "C%.0f", value)

        // D-06: tolerance-based redraw — still redraw if rounded text or
        // warning/critical color band changes inside the 0.5% tolerance.
        if let last = lastDisplayedValue,
           abs(value - last) < 0.5,
           nextCPUText == latestCPUText,
           usageSeverity(for: value) == usageSeverity(for: latestCPUUsage) {
            return
        }

        lastDisplayedValue = value
        latestCPUText = nextCPUText
        latestCPUUsage = value
        updateCombinedStatus()
    }

    private func scheduleMenuBarVisibilityNotice() {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else { return }

        // macOS 26+ exposes a per-app menu bar visibility toggle in
        // System Settings → Menu Bar. Only prompt the user when the item
        // genuinely failed to register (isVisible == false), otherwise the
        // alert pops on every launch even when everything is fine.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.presentMenuBarVisibilityNoticeIfNeeded()
        }
    }

    private func presentMenuBarVisibilityNoticeIfNeeded() {
        guard !hasPresentedMenuBarNotice else { return }
        guard let item = networkStatusItem, item.isVisible == false else { return }
        hasPresentedMenuBarNotice = true

        let alert = NSAlert()
        alert.messageText = "Menu Bar Permission Needed"
        alert.informativeText = "MacStatus needs permission to display in the menu bar. Open System Settings → Menu Bar and enable MacStatus."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.menubar") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - GPU Display

    /// Update the menu bar GPU display.
    /// - Parameter stats: Current GPU statistics, or `nil` for unavailable GPU data.
    func updateGPU(_ stats: GPUStats?) {
        guard let stats else {
            latestGPUText = "G--"
            latestGPUUsage = nil
            lastGPUStats = nil
            updateCombinedStatus()
            return
        }

        if let last = lastGPUStats, stats == last {
            return
        }

        lastGPUStats = stats
        latestGPUText = String(format: "G%.0f", stats.utilizationPercent)
        latestGPUUsage = stats.utilizationPercent
        updateCombinedStatus()
    }

    // MARK: - Network Display

    /// Create the network `NSStatusItem` (Phase 2 visible combined display).
    ///
    /// - `variableLength` sizes the slot to the metric string. A fixed/oversized
    ///   width can exceed the available menu bar space on a notched display, in
    ///   which case macOS hides the item even though `isVisible` reports true.
    /// - No `autosaveName`: persisting a Preferred Position previously cached a
    ///   slot that landed under the notch / Control Center overlay and never
    ///   rendered. Letting AppKit place the item fresh each launch avoids that.
    func setupNetworkItem() {
        if networkStatusItem == nil {
            networkStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            networkStatusItem?.menu = statusMenu
            configureStatusButton(networkStatusItem?.button)
        }

        networkStatusItem?.isVisible = true
        updateCombinedStatus()
    }

    /// Update the menu bar network rate display.
    /// - Parameter stats: Current network throughput rates, or `nil` for error state.
    func updateNetwork(_ stats: NetworkStats?) {
        guard let stats else {
            latestNetworkText = "↓-- ↑--"
            updateCombinedStatus()
            lastNetworkStats = nil
            return
        }

        // Tolerance check: skip redraw if both rates changed less than 1 KB/s
        if let last = lastNetworkStats,
           abs(stats.downloadBytesPerSec - last.downloadBytesPerSec) < 1024,
           abs(stats.uploadBytesPerSec - last.uploadBytesPerSec) < 1024 {
            return
        }

        lastNetworkStats = stats
        latestNetworkText = formatNetworkCompact(download: stats.downloadBytesPerSec,
                                                  upload: stats.uploadBytesPerSec)
        updateCombinedStatus()
    }

    // MARK: - Memory Display

    /// Initialize memory text for the visible combined status item.
    ///
    /// Memory used to render into a separate `NSStatusItem`, but UAT showed that
    /// item is not reliably visible for the user. The visible source of truth is
    /// now the combined `networkStatusItem`.
    func setupMemoryItem() {
        latestMemoryText = "M--"
        latestMemoryPressure = nil
        updateCombinedStatus()
    }

    /// Update the menu bar memory pressure display.
    /// - Parameter stats: Current memory statistics, or `nil` for error state.
    func updateMemory(_ stats: MemoryStats?) {
        guard let stats else {
            latestMemoryText = "M--"
            latestMemoryPressure = nil
            updateCombinedStatus()
            lastMemoryStats = nil
            return
        }

        let nextMemoryText = formatMemoryPressure(
            stats.pressureLevel,
            usedPercent: stats.usedPercent
        )

        if latestMemoryPressure == stats.pressureLevel,
           nextMemoryText == latestMemoryText {
            lastMemoryStats = stats
            return
        }

        lastMemoryStats = stats
        latestMemoryText = nextMemoryText
        latestMemoryPressure = stats.pressureLevel
        updateCombinedStatus()
    }

    // MARK: - Text Formatting

    private func configureStatusButton(_ button: NSStatusBarButton?) {
        button?.cell?.lineBreakMode = .byClipping
        button?.cell?.usesSingleLineMode = true
        button?.cell?.wraps = false
        button?.imagePosition = .imageOnly
    }

    @objc private func quitMacStatus(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshProcessNetworkMenu()
    }

    private func disabledMenuItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func refreshProcessNetworkMenu() {
        processNetworkRequestID += 1
        let requestID = processNetworkRequestID
        showProcessNetworkLoadingState()

        processNetworkQueue.async { [requestID] in
            let result = ProcessNetworkReader.readTopProcesses(limit: 5)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.processNetworkRequestID == requestID else { return }
                self.updateProcessNetworkMenu(with: result)
            }
        }
    }

    private func showProcessNetworkLoadingState() {
        for (index, item) in processNetworkItems.enumerated() {
            item.isHidden = index != 0
            item.title = index == 0 ? "正在采样..." : ""
            item.toolTip = nil
        }
    }

    private func updateProcessNetworkMenu(with result: ProcessNetworkUsageResult) {
        switch result {
        case let .processes(usages):
            for (index, item) in processNetworkItems.enumerated() {
                guard usages.indices.contains(index) else {
                    item.isHidden = true
                    item.title = ""
                    item.toolTip = nil
                    continue
                }

                let usage = usages[index]
                item.isHidden = false
                item.title = formattedProcessRow(for: usage)
                item.toolTip = formattedProcessTooltip(for: usage)
            }

        case .idle:
            showSingleProcessNetworkMessage("当前没有明显网络活动")

        case let .unavailable(reason):
            showSingleProcessNetworkMessage("无法读取进程网络状态", toolTip: reason)
        }
    }

    private func showSingleProcessNetworkMessage(_ title: String, toolTip: String? = nil) {
        for (index, item) in processNetworkItems.enumerated() {
            item.isHidden = index != 0
            item.title = index == 0 ? title : ""
            item.toolTip = index == 0 ? toolTip : nil
        }
    }

    private func formattedProcessTitle(for usage: ProcessNetworkUsage) -> String {
        guard let pid = usage.processIdentifier else {
            return usage.processName
        }
        return "\(usage.processName) (PID \(pid))"
    }

    private func formattedProcessRow(for usage: ProcessNetworkUsage) -> String {
        let processTitle = trimmedMenuTitle(formattedProcessTitle(for: usage), limit: 34)
        let uploadRate = formatNetworkRateCompact(usage.uploadBytesPerSec)
        let downloadRate = formatNetworkRateCompact(usage.downloadBytesPerSec)
        return "\(processTitle)  ↑ \(uploadRate)  ↓ \(downloadRate)"
    }

    private func formattedProcessTooltip(for usage: ProcessNetworkUsage) -> String {
        let uploadRate = formatNetworkRateCompact(usage.uploadBytesPerSec)
        let downloadRate = formatNetworkRateCompact(usage.downloadBytesPerSec)
        return "\(formattedProcessTitle(for: usage))  ↑ \(uploadRate)  ↓ \(downloadRate)"
    }

    private func trimmedMenuTitle(_ text: String, limit: Int = 48) -> String {
        guard text.count > limit else { return text }
        return "\(text.prefix(max(limit - 3, 0)))..."
    }

    private func updateCombinedStatus() {
        let text = "\(latestCPUText) \(latestGPUText) \(latestMemoryText) \(latestNetworkText)"
        let attributedText = combinedAttributedString()
        let image = renderedStatusImage(for: attributedText)

        networkStatusItem?.button?.title = ""
        networkStatusItem?.button?.toolTip = text
        networkStatusItem?.button?.attributedTitle = NSAttributedString()
        networkStatusItem?.button?.image = image
        networkStatusItem?.button?.setAccessibilityLabel(text)
        updateStatusItemLength(for: image.size.width)
    }

    private func updateStatusItemLength(for contentWidth: CGFloat) {
        guard let item = networkStatusItem else { return }

        let targetLength = min(
            max(ceil(contentWidth) + 18, minimumStatusItemLength),
            maximumStatusItemLength
        )

        if abs(item.length - targetLength) >= 1 {
            item.length = targetLength
        }
    }

    private func renderedStatusImage(for attributedText: NSAttributedString) -> NSImage {
        let drawableText = NSMutableAttributedString(attributedString: attributedText)
        let fullRange = NSRange(location: 0, length: drawableText.length)
        drawableText.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            if value == nil {
                drawableText.addAttribute(.foregroundColor, value: NSColor.white, range: range)
            }
        }

        let textSize = drawableText.size()
        let imageSize = NSSize(
            width: ceil(textSize.width),
            height: NSStatusBar.system.thickness
        )
        let image = NSImage(size: imageSize)

        image.lockFocus()
        drawableText.draw(
            at: NSPoint(
                x: 0,
                y: floor((imageSize.height - textSize.height) / 2)
            )
        )
        image.unlockFocus()

        return image
    }

    private func combinedAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let separator = NSAttributedString(string: " ", attributes: baseAttributes())

        appendMetric(
            label: "C",
            value: valueText(from: latestCPUText, label: "C"),
            valueColor: usageColor(for: latestCPUUsage),
            to: result
        )
        result.append(separator)
        appendMetric(
            label: "G",
            value: valueText(from: latestGPUText, label: "G"),
            valueColor: usageColor(for: latestGPUUsage),
            to: result
        )
        result.append(separator)
        appendMetric(
            label: "M",
            value: valueText(from: latestMemoryText, label: "M"),
            valueColor: memoryColor(for: latestMemoryPressure),
            to: result
        )
        result.append(separator)
        result.append(NSAttributedString(string: latestNetworkText, attributes: baseAttributes()))

        return result
    }

    private func appendMetric(
        label: String,
        value: String,
        valueColor: NSColor?,
        to result: NSMutableAttributedString
    ) {
        result.append(NSAttributedString(string: label, attributes: baseAttributes()))
        result.append(NSAttributedString(string: value, attributes: metricAttributes(valueColor: valueColor)))
    }

    private func valueText(from text: String, label: String) -> String {
        let prefix = label
        guard text.hasPrefix(prefix) else { return text }
        return String(text.dropFirst(prefix.count))
    }

    private func metricAttributes(valueColor: NSColor?) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes()
        if let valueColor {
            attributes[.foregroundColor] = valueColor
        }
        return attributes
    }

    private func usageColor(for value: Double?) -> NSColor? {
        switch usageSeverity(for: value) {
        case 1:
            return .systemYellow
        case 2:
            return .systemRed
        default:
            return nil
        }
    }

    private func usageSeverity(for value: Double?) -> Int {
        guard let value else { return 0 }

        switch value {
        case ..<60:
            return 0
        case ..<85:
            return 1
        default:
            return 2
        }
    }

    private func memoryColor(for level: MemoryPressureLevel?) -> NSColor? {
        switch level {
        case .warning:
            return .systemYellow
        case .critical:
            return .systemRed
        case .normal, .unknown, nil:
            return nil
        }
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping

        return [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.smallSystemFontSize,
                weight: .regular
            ),
            .paragraphStyle: paragraph,
        ]
    }

}
