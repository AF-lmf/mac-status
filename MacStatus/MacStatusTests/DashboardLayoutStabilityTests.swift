import AppKit
import SwiftUI
import XCTest

@testable import MacStatus

enum LayoutProbeID: String, Hashable {
    case networkMetricCardValue
    case temperatureValueColumn
    case fanRPMValueColumn
    case batteryPowerValueColumn
    case systemPowerValueColumn
    case networkProcessTrailingValue
    case cpuProcessTrailingValue
    case memoryProcessTrailingValue
}

struct LayoutProbeFrameSnapshot {
    let frames: [LayoutProbeID: CGRect]
}

private struct LayoutProbeReader<Content: View>: View {
    let content: Content
    let snapshot: LayoutProbeFrameSnapshot? = nil

    var body: some View {
        content
    }
}

private extension View {
    func layoutProbe(_ id: LayoutProbeID) -> some View {
        self
    }

    func readLayoutProbeFrames() -> LayoutProbeReader<Self> {
        LayoutProbeReader(content: self)
    }
}

@MainActor
final class DashboardLayoutStabilityTests: XCTestCase {
    func testPopoverWidthIsFixedForShortAndExtremeFixtures() {
        withAllPopoverSectionsVisible {
            let shortSize = measuredDashboardSize(for: .short)
            let extremeSize = measuredDashboardSize(for: .extreme)

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
        let controller = NSHostingController(
            rootView: DashboardView()
                .environmentObject(state)
                .readLayoutProbeFrames()
        )
        controller.sizingOptions = [.preferredContentSize]
        controller.view.layoutSubtreeIfNeeded()
        _ = controller.view.fittingSize
        controller.view.layoutSubtreeIfNeeded()

        guard let snapshot = controller.rootView.snapshot else {
            return LayoutProbeFrameSnapshot(frames: [:])
        }
        return snapshot
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
            .readLayoutProbeFrames()
        )
        controller.sizingOptions = [.preferredContentSize]
        controller.view.layoutSubtreeIfNeeded()
        _ = controller.view.fittingSize
        controller.view.layoutSubtreeIfNeeded()
        return controller.rootView.snapshot?.frames[.networkProcessTrailingValue] ?? .zero
    }
}
