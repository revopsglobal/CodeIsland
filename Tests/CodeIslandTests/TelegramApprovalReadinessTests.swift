import XCTest
@testable import CodeIsland

final class TelegramApprovalReadinessTests: XCTestCase {
    func testReadyRequiresPrivateIdentityKeychainHTTPSAndRunningService() {
        let readiness = TelegramApprovalReadiness(
            enabled: true,
            credentialStored: true,
            chatID: "42",
            userID: "42",
            tailnetURL: "https://mac.tailnet:9443",
            serviceRunning: true
        )

        XCTAssertTrue(readiness.isReady)
        XCTAssertTrue(readiness.issues.isEmpty)
    }

    func testMismatchedGroupStyleIdentityFailsClosed() {
        let readiness = TelegramApprovalReadiness(
            enabled: true,
            credentialStored: true,
            chatID: "-1001234",
            userID: "42",
            tailnetURL: "https://mac.tailnet:9443",
            serviceRunning: true
        )

        XCTAssertFalse(readiness.isReady)
        XCTAssertTrue(readiness.issues.contains("Enter your positive private Chat ID"))
        XCTAssertTrue(readiness.issues.contains("Use the same ID for your private chat and allowlisted user"))
    }

    func testMissingSecurityDependenciesAreNamed() {
        let readiness = TelegramApprovalReadiness(
            enabled: false,
            credentialStored: false,
            chatID: "",
            userID: "",
            tailnetURL: "http://localhost:9443",
            serviceRunning: false
        )

        XCTAssertFalse(readiness.isReady)
        XCTAssertEqual(readiness.issues.count, 6)
    }
}
