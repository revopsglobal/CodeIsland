import XCTest
@testable import CodeIsland

@MainActor
final class LaunchAtLoginReliabilityTests: XCTestCase {
    func testRemoteAccessRegistersLoginLaunchWhenNoChoiceExists() {
        XCTAssertTrue(
            SettingsManager.shouldAttemptAutomaticLaunchAtLoginRegistration(
                remoteAccessEnabled: true,
                explicitPreference: nil,
                serviceNeedsRegistration: true
            )
        )
    }

    func testNotFoundServiceStillAttemptsRegistration() {
        // Both ServiceManagement's .notRegistered and .notFound states map to
        // this candidate flag; the latter must be attempted to surface the
        // framework's actionable registration error.
        XCTAssertTrue(
            SettingsManager.shouldAttemptAutomaticLaunchAtLoginRegistration(
                remoteAccessEnabled: true,
                explicitPreference: nil,
                serviceNeedsRegistration: true
            )
        )
    }

    func testExplicitOptOutIsRespected() {
        XCTAssertFalse(
            SettingsManager.shouldAttemptAutomaticLaunchAtLoginRegistration(
                remoteAccessEnabled: true,
                explicitPreference: false,
                serviceNeedsRegistration: true
            )
        )
    }

    func testExplicitOptInRetriesAfterTransientRegistrationFailure() {
        XCTAssertTrue(
            SettingsManager.shouldAttemptAutomaticLaunchAtLoginRegistration(
                remoteAccessEnabled: true,
                explicitPreference: true,
                serviceNeedsRegistration: true
            )
        )
    }

    func testDisabledRemoteAccessDoesNotChangeLoginLaunch() {
        XCTAssertFalse(
            SettingsManager.shouldAttemptAutomaticLaunchAtLoginRegistration(
                remoteAccessEnabled: false,
                explicitPreference: nil,
                serviceNeedsRegistration: true
            )
        )
    }

    func testExistingServiceStateIsLeftAlone() {
        XCTAssertFalse(
            SettingsManager.shouldAttemptAutomaticLaunchAtLoginRegistration(
                remoteAccessEnabled: true,
                explicitPreference: nil,
                serviceNeedsRegistration: false
            )
        )
    }
}
