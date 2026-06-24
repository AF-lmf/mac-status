import AppKit
import SwiftUI
import XCTest

@testable import MacStatus

@MainActor
final class DashboardLayoutStabilityTests: XCTestCase {
    func testPopoverWidthIsFixedForShortAndExtremeFixtures() {
        withAllPopoverSectionsVisible {
            let shortSize = measuredDashboardSize(for: .short)
            let extremeSize = measuredDashboardSize(for: .extreme)

            print("DashboardLayoutSize short width=\(shortSize.width) height=\(shortSize.height)")
            print("DashboardLayoutSize extreme width=\(extremeSize.width) height=\(extremeSize.height)")

            XCTAssertEqual(shortSize.width, DashboardLayout.popoverWidth, accuracy: 0.5)
            XCTAssertEqual(extremeSize.width, DashboardLayout.popoverWidth, accuracy: 0.5)
            XCTAssertEqual(shortSize.width, extremeSize.width, accuracy: 0.5)
        }
    }

    func testSameVisibilityFixturesKeepStableHeight() {
        withAllPopoverSectionsVisible {
            let shortSize = measuredDashboardSize(for: .short)
            let extremeSize = measuredDashboardSize(for: .extreme)

            XCTAssertEqual(shortSize.height, extremeSize.height, accuracy: 0.5)
        }
    }

    func testStableValueWidthContractMatchesUISpec() {
        XCTAssertEqual(StableValueWidth.percentage, 64)
        XCTAssertEqual(StableValueWidth.memoryMetricCard, 96)
        XCTAssertEqual(StableValueWidth.networkCard, 76)
        XCTAssertEqual(StableValueWidth.processNetworkRate, 68)
        XCTAssertEqual(StableValueWidth.processNetworkPair, 148)
        XCTAssertEqual(StableValueWidth.temperature, 56)
        XCTAssertEqual(StableValueWidth.fanRPM, 78)
        XCTAssertEqual(StableValueWidth.batteryPower, 104)
        XCTAssertEqual(StableValueWidth.batteryHealthTime, 112)
        XCTAssertEqual(StableValueWidth.processCPU, 52)
        XCTAssertEqual(StableValueWidth.processMemory, 68)
    }

    func testMetricCardValueStringsFitStableColumns() {
        assertMetricCardValueFits("100%", width: StableValueWidth.percentage)
        assertMetricCardValueFits("N/A", width: StableValueWidth.percentage)
        assertMetricCardValueFits("100% (CRIT)", width: StableValueWidth.memoryMetricCard)
    }

    func testProcessRowsReserveTrailingValueColumns() {
        let shortFrame = measuredProcessTrailingFrame(
            processName: "Safari",
            pid: 101,
            uploadText: "↑1K/s",
            downloadText: "↓2K/s"
        )
        let longFrame = measuredProcessTrailingFrame(
            processName: "ExtremelyLongUploaderProcessNameForPopoverLayoutYieldValidation",
            pid: 9_901,
            uploadText: "↑999T/s",
            downloadText: "↓999T/s"
        )

        print("ProcessTrailingFrame short x=\(shortFrame.origin.x) width=\(shortFrame.width)")
        print("ProcessTrailingFrame long x=\(longFrame.origin.x) width=\(longFrame.width)")

        XCTAssertEqual(shortFrame.width, StableValueWidth.processNetworkPair, accuracy: 0.5)
        XCTAssertEqual(longFrame.width, StableValueWidth.processNetworkPair, accuracy: 0.5)
        XCTAssertEqual(shortFrame.origin.x, longFrame.origin.x, accuracy: 0.5)
        XCTAssertEqual(shortFrame.width, longFrame.width, accuracy: 0.5)
    }

    func testDashboardValueColumnFramesStayStableAcrossFixtures() {
        withAllPopoverSectionsVisible {
            let shortSnapshot = valueColumnFrameSnapshot(for: .short)
            let extremeSnapshot = valueColumnFrameSnapshot(for: .extreme)

            assertStableValueColumnFrames(
                shortSnapshot,
                extremeSnapshot,
                ids: [
                    .networkMetricCardValue,
                    .temperatureValueColumn,
                    .fanRPMValueColumn,
                    .batteryPowerValueColumn,
                    .systemPowerValueColumn,
                    .networkProcessTrailingValue,
                    .cpuProcessTrailingValue,
                    .memoryProcessTrailingValue,
                ]
            )
        }
    }

    func measuredDashboardSize(for kind: DashboardLayoutFixture.Kind) -> CGSize {
        let state = DashboardLayoutFixture.make(kind)
        let controller = NSHostingController(
            rootView: DashboardView()
                .environmentObject(state)
        )
        controller.sizingOptions = [.preferredContentSize]
        controller.view.layoutSubtreeIfNeeded()
        return controller.view.fittingSize
    }

    func valueColumnFrameSnapshot(for kind: DashboardLayoutFixture.Kind) -> LayoutProbeFrameSnapshot {
        let state = DashboardLayoutFixture.make(kind)
        let store = LayoutProbeFrameStore()
        let controller = NSHostingController(
            rootView: DashboardView()
                .environmentObject(state)
                .readLayoutProbeFrames(into: store)
        )
        controller.sizingOptions = [.preferredContentSize]
        controller.view.layoutSubtreeIfNeeded()
        _ = controller.view.fittingSize
        controller.view.layoutSubtreeIfNeeded()

        return store.snapshot
    }

    func assertStableValueColumnFrames(
        _ short: LayoutProbeFrameSnapshot,
        _ extreme: LayoutProbeFrameSnapshot,
        ids: [LayoutProbeID],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for id in ids {
            guard let shortFrame = short.frames[id] else {
                XCTFail("Missing short frame for \(id.rawValue)", file: file, line: line)
                continue
            }
            guard let extremeFrame = extreme.frames[id] else {
                XCTFail("Missing extreme frame for \(id.rawValue)", file: file, line: line)
                continue
            }

            XCTAssertEqual(
                shortFrame.origin.x,
                extremeFrame.origin.x,
                accuracy: 0.5,
                "x-position changed for \(id.rawValue)",
                file: file,
                line: line
            )
            XCTAssertEqual(
                shortFrame.width,
                extremeFrame.width,
                accuracy: 0.5,
                "width changed for \(id.rawValue)",
                file: file,
                line: line
            )
            print(
                "LayoutProbeFrame \(id.rawValue) x-position short=\(shortFrame.origin.x) " +
                    "extreme=\(extremeFrame.origin.x) width short=\(shortFrame.width) extreme=\(extremeFrame.width)"
            )
        }
    }

    func withAllPopoverSectionsVisible(_ body: () -> Void) {
        let settings = SettingsManager.shared
        let previousBattery = settings.showBatterySection
        let previousThermal = settings.showThermalSection
        let previousFan = settings.showFanSection
        let previousProcess = settings.showProcessSection

        settings.showBatterySection = true
        settings.showThermalSection = true
        settings.showFanSection = true
        settings.showProcessSection = true

        body()

        settings.showBatterySection = previousBattery
        settings.showThermalSection = previousThermal
        settings.showFanSection = previousFan
        settings.showProcessSection = previousProcess
    }

    private func measuredProcessTrailingFrame(
        processName: String,
        pid: Int32?,
        uploadText: String,
        downloadText: String
    ) -> CGRect {
        let store = LayoutProbeFrameStore()
        let controller = NSHostingController(
            rootView: ProcessMetricRow(
                processName: processName,
                pid: pid,
                trailingWidth: StableValueWidth.processNetworkPair
            ) {
                NetworkTrafficValueBlock(uploadText: uploadText, downloadText: downloadText)
                    .layoutProbe(.networkProcessTrailingValue)
            }
            .frame(width: DashboardLayout.popoverWidth)
            .readLayoutProbeFrames(into: store)
        )
        controller.sizingOptions = [.preferredContentSize]
        controller.view.layoutSubtreeIfNeeded()
        _ = controller.view.fittingSize
        controller.view.layoutSubtreeIfNeeded()
        return store.snapshot.frames[.networkProcessTrailingValue] ?? .zero
    }

    private func assertMetricCardValueFits(
        _ text: String,
        width: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let measuredWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)

        XCTAssertLessThanOrEqual(
            measuredWidth,
            width,
            "\(text) measured \(measuredWidth)pt, which exceeds the fixed metric card width \(width)pt",
            file: file,
            line: line
        )
    }
}
