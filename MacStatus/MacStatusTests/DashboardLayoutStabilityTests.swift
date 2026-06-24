import XCTest

@testable import MacStatus

@MainActor
final class DashboardLayoutStabilityTests: XCTestCase {
    func testLayoutStabilityTargetIsConfigured() {
        XCTAssertEqual(DashboardLayout.popoverWidth, 372, accuracy: 0.5)
    }
}
