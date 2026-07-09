import AppKit
import SwiftUI
import XCTest

@testable import MacStatus

// MARK: - Design Snapshot Renderer
//
// 诊断用途：把 DashboardView / MenuBarMetricsView / SettingsView 用与 1a/2b 设计稿
// 相同的数据离屏渲染成亮/暗 PNG（默认输出到临时目录，可用 TEST_RUNNER_SNAPSHOT_DIR
// 覆盖），供与 ui/project/_ref/*.png 逐像素对照。不做断言（渲染失败才 fail）。

@MainActor
final class DesignSnapshotTests: XCTestCase {

    func testRenderDesignSnapshots() throws {
        let dirPath = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"]
            ?? NSTemporaryDirectory() + "macstatus-design-snapshots"
        let dir = URL(fileURLWithPath: dirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        print("DesignSnapshotDir \(dir.path)")

        let settings = SettingsManager.shared
        let previous = (
            settings.showBatterySection, settings.showThermalSection,
            settings.showFanSection, settings.showProcessSection
        )
        settings.showBatterySection = true
        settings.showThermalSection = true
        settings.showFanSection = true
        settings.showProcessSection = true
        defer {
            settings.showBatterySection = previous.0
            settings.showThermalSection = previous.1
            settings.showFanSection = previous.2
            settings.showProcessSection = previous.3
        }

        let state = Self.makeMockState()

        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let isDark = suffix == "dark"

            // 弹窗（包一层近似玻璃底色，便于观察）
            let glass = isDark
                ? NSColor(srgbRed: 36 / 255, green: 36 / 255, blue: 41 / 255, alpha: 1)
                : NSColor(srgbRed: 249 / 255, green: 249 / 255, blue: 251 / 255, alpha: 1)
            let dashboard = DashboardView()
                .environmentObject(state)
                .background(Color(nsColor: glass))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            try Self.writeSnapshot(
                dashboard,
                appearance: appearance,
                size: nil,
                to: dir.appendingPathComponent("dashboard_\(suffix).png")
            )

            // 菜单栏（2a–2d 四种样式各一条，衬菜单栏底色）
            let barColor = isDark
                ? NSColor(srgbRed: 30 / 255, green: 34 / 255, blue: 51 / 255, alpha: 1)
                : NSColor(srgbRed: 201 / 255, green: 200 / 255, blue: 245 / 255, alpha: 1)
            let menuBar = VStack(alignment: .leading, spacing: 0) {
                ForEach(MenuBarStyle.allCases, id: \.rawValue) { style in
                    MenuBarMetricsView(style: style, items: Self.makeMenuBarItems(isDark: isDark), isDark: isDark)
                        .padding(.horizontal, 12)
                        .frame(height: 28, alignment: .leading)
                }
            }
            .background(Color(nsColor: barColor))
            try Self.writeSnapshot(
                menuBar,
                appearance: appearance,
                size: nil,
                to: dir.appendingPathComponent("menubar_\(suffix).png")
            )

            // 电源概览排 · 已充满态（用户实机状态：100% / −0.5W / 24.2W）
            let fullBattery = BatterySnapshot(
                chargePercent: 100,
                isCharging: false,
                isOnAC: true,
                timeToEmptyMinutes: nil,
                timeToFullMinutes: nil,
                watts: -0.5,
                healthPercent: 95,
                cycleCount: 95,
                systemPowerWatts: 24.2
            )
            let strip = OverviewStripView(
                battery: fullBattery,
                thermal: state.thermal,
                fan: state.fan,
                showsTemperature: true,
                showsFan: true
            )
            .padding(14)
            .frame(width: DashboardLayout.popoverWidth)
            .background(Color(nsColor: glass))
            try Self.writeSnapshot(
                strip,
                appearance: appearance,
                size: nil,
                to: dir.appendingPathComponent("powerstrip_full_\(suffix).png")
            )

            // 设置窗口（默认"指标与排序"页；衬窗口底色，真实窗口由 NSWindow 提供）
            try Self.writeSnapshot(
                SettingsView().background(Color(nsColor: .windowBackgroundColor)),
                appearance: appearance,
                size: CGSize(width: 620, height: 468),
                to: dir.appendingPathComponent("settings_\(suffix).png")
            )
        }
    }

    // MARK: - Mock Data（与设计稿数值一致）

    private static func makeMockState() -> DashboardState {
        let state = DashboardState()

        state.cpuUsage = 23
        state.cpuText = "23%"
        state.cpuSamples = wave(base: 22, amplitude: 14, count: 40, seed: 3)

        state.memoryUsage = 68
        state.memoryText = "68% (OK)"
        state.memorySamples = rising(from: 20, to: 70, count: 40)

        state.gpuUsage = 12
        state.gpuText = "12%"
        state.gpuSamples = spiky(base: 8, spike: 70, count: 40, spikeAt: 18)

        state.networkText = "↓4.2M\n↑512K"
        state.networkProgress = 0.05
        state.networkSamples = spiky(base: 120, spike: 4200, count: 40, spikeAt: 14)

        state.battery = BatterySnapshot(
            chargePercent: 86,
            isCharging: true,
            isOnAC: true,
            timeToEmptyMinutes: nil,
            timeToFullMinutes: 42,
            watts: 18.5,
            healthPercent: 95,
            cycleCount: 95,
            systemPowerWatts: 12.4
        )
        state.hasBattery = true

        state.thermal = ThermalSnapshot(
            cpuSocTemperatureCelsius: 54,
            systemState: .nominal,
            gpuTemperatureCelsius: 48,
            batteryTemperatureCelsius: 33,
            capturedAt: Date(timeIntervalSince1970: 1_782_300_000)
        )

        let fanCaps = FanCapabilities(
            rpmReadable: true,
            boundsReadable: true,
            targetReadable: true,
            safeControlAvailable: false
        )
        let fan1 = FanReading(
            id: 0,
            index: 0,
            displayName: "风扇 1",
            currentRPM: 2150,
            minRPM: 1200,
            maxRPM: 5200,
            targetRPM: 2000,
            capabilities: fanCaps
        )
        state.fan = FanSnapshot(
            supportState: .supported,
            fans: [fan1],
            capturedAt: Date(timeIntervalSince1970: 1_782_300_000)
        )

        let chrome = ProcessResourceUsage(processName: "Google Chrome", pid: 1, cpuPercent: 48.3, memoryBytes: 746_000_000)
        let xcode = ProcessResourceUsage(processName: "Xcode", pid: 2, cpuPercent: 19.1, memoryBytes: 900_000_000)
        let windowServer = ProcessResourceUsage(processName: "WindowServer", pid: 3, cpuPercent: 7.6, memoryBytes: 700_000_000)
        let pycharm = ProcessResourceUsage(processName: "pycharm", pid: 4, cpuPercent: 3.5, memoryBytes: 1_300_000_000)
        let bambu = ProcessResourceUsage(processName: "BambuStudio", pid: 5, cpuPercent: 1.2, memoryBytes: 1_300_000_000)
        state.topCPUProcesses = [chrome, xcode, windowServer, pycharm]
        state.topMemoryProcesses = [bambu, pycharm, chrome]
        state.resourceLoading = false

        let todesk = ProcessNetworkUsage(processName: "ToDesk", processIdentifier: 824, downloadBytesPerSec: 36_000, uploadBytesPerSec: 5_600)
        let chromeH = ProcessNetworkUsage(processName: "Google Chrome H", processIdentifier: 5_129, downloadBytesPerSec: 24_000, uploadBytesPerSec: 7_100)
        let mdns = ProcessNetworkUsage(processName: "mDNSResponder", processIdentifier: 497, downloadBytesPerSec: 3_800, uploadBytesPerSec: 0)
        state.topProcesses = [todesk, chromeH, mdns]
        state.processesLoading = false
        state.processError = nil

        state.selfCpuUsage = 0.4
        state.selfMemoryMB = 83
        state.refreshInterval = 2
        return state
    }

    private static func makeMenuBarItems(isDark: Bool) -> [MenuBarMetricsView.Item] {
        let cpuSamples = wave(base: 20, amplitude: 12, count: 24, seed: 3)
        let memSamples = rising(from: 30, to: 68, count: 24)
        let netSamples = spiky(base: 120, spike: 4200, count: 24, spikeAt: 10)
        return [
            MenuBarMetricsView.Item(
                label: "CPU",
                number: "23",
                unit: "%",
                accent: .metricBlue,
                numberColor: .metricBlueText,
                progress: 0.23,
                samples: cpuSamples
            ),
            MenuBarMetricsView.Item(
                label: "MEM",
                number: "68",
                unit: "%",
                accent: .metricAmber,
                numberColor: .metricAmberText,
                progress: 0.68,
                samples: memSamples
            ),
            MenuBarMetricsView.Item(
                label: "NET",
                number: "↓4.2",
                unit: "M",
                accent: .metricBlue,
                numberColor: .metricBlueText,
                progress: 0.05,
                samples: netSamples
            ),
        ]
    }

    // MARK: - Sample Generators

    private static func wave(base: Double, amplitude: Double, count: Int, seed: Int) -> [Double] {
        var result: [Double] = []
        for i in 0..<count {
            let x = Double(i + seed) * 0.55
            let envelope: Double = 0.6 + 0.4 * sin(Double(i) * 0.13)
            let value: Double = base + amplitude * sin(x) * envelope
            result.append(value)
        }
        return result
    }

    private static func rising(from: Double, to: Double, count: Int) -> [Double] {
        var result: [Double] = []
        for i in 0..<count {
            let t: Double = Double(i) / Double(count - 1)
            let jitter: Double = 2.0 * sin(Double(i) * 0.9)
            result.append(from + (to - from) * t + jitter)
        }
        return result
    }

    private static func spiky(base: Double, spike: Double, count: Int, spikeAt: Int) -> [Double] {
        var result: [Double] = []
        for i in 0..<count {
            let d: Double = Double(abs(i - spikeAt))
            let s: Double = d <= 2 ? spike * (1.0 - d * 0.4) : 0.0
            let jitter: Double = 3.0 * sin(Double(i) * 0.7)
            result.append(base + s + jitter)
        }
        return result
    }

    // MARK: - Offscreen PNG Renderer (2x)

    private static func writeSnapshot<V: View>(
        _ view: V,
        appearance name: NSAppearance.Name,
        size: CGSize?,
        to url: URL
    ) throws {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: name)

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.appearance = NSAppearance(named: name)
        window.contentView = host

        let target = size ?? host.fittingSize
        window.setContentSize(target)
        host.frame = CGRect(origin: .zero, size: target)
        host.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        guard target.width > 0, target.height > 0,
              let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: Int(target.width * scale),
                  pixelsHigh: Int(target.height * scale),
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .calibratedRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              )
        else {
            XCTFail("Cannot create bitmap rep for \(url.lastPathComponent)")
            return
        }
        rep.size = target

        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx
                host.displayIgnoringOpacity(host.bounds, in: ctx)
                ctx.flushGraphics()
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        guard let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("Cannot encode PNG for \(url.lastPathComponent)")
            return
        }
        try png.write(to: url)
        print("DesignSnapshot wrote \(url.path)")
    }
}
