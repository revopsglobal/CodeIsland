import XCTest
@testable import CodeIsland

@MainActor
final class LaunchAtLoginReliabilityTests: XCTestCase {
    func testRemoteAccessRegistersLoginLaunchWhenNoChoiceExists() {
        XCTAssertTrue(
            SettingsManager.shouldAttemptAutomaticLaunchAtLoginRegistration(
                remoteAccessEnabled: true,
                explicitPreference: nil,
                serviceIsNotRegistered: true
            )
        )
    }

    func testExplicitOptOutIsRespected() {
        XCTAssertFalse(
            SettingsManager.shouldAttemptAutomaticLaunchAtLoginRegistration(
                remoteAccessEnabled: true,
                explicitPreference: false,
                serviceIsNotRegistered: true
            )
        )
    }

    func testExplicitOptInRetriesAfterTransientRegistrationFailure() {
        XCTAssertTrue(
            SettingsManager.shouldAttemptAutomaticLaunchAtLoginRegistration(
                remoteAccessEnabled: true,
                explicitPreference: true,
                serviceIsNotRegistered: true
            )
        )
    }

    func testDisabledRemoteAccessDoesNotChangeLoginLaunch() {
        XCTAssertFalse(
            SettingsManager.shouldAttemptAutomaticLaunchAtLoginRegistration(
                remoteAccessEnabled: false,
                explicitPreference: nil,
                serviceIsNotRegistered: true
            )
        )
    }

    func testExistingServiceStateIsLeftAlone() {
        XCTAssertFalse(
            SettingsManager.shouldAttemptAutomaticLaunchAtLoginRegistration(
                remoteAccessEnabled: true,
                explicitPreference: nil,
                serviceIsNotRegistered: false
            )
        )
    }
}
