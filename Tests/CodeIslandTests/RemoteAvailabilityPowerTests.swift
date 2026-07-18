import XCTest
@testable import CodeIsland

final class RemoteAvailabilityPowerTests: XCTestCase {
    func testRemoteServiceKeepsMacAwakeWhenPreferenceIsEnabled() {
        XCTAssertTrue(
            RemoteApprovalService.shouldPreventSystemSleep(
                serviceRunning: true,
                preferenceEnabled: true
            )
        )
    }

    func testStoppedServiceOrDisabledPreferenceReleasesPowerAssertion() {
        XCTAssertFalse(
            RemoteApprovalService.shouldPreventSystemSleep(
                serviceRunning: false,
                preferenceEnabled: true
            )
        )
        XCTAssertFalse(
            RemoteApprovalService.shouldPreventSystemSleep(
                serviceRunning: true,
                preferenceEnabled: false
            )
        )
    }
}
