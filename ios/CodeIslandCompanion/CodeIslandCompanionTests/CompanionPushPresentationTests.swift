import XCTest
@testable import CodeIslandCompanion
import UserNotifications

final class CompanionPushPresentationTests: XCTestCase {
    func testAcceptedPushIsPresentedInForeground() {
        let options = CompanionAppDelegate.presentationOptions(for: .accepted)

        XCTAssertTrue(options.contains(.banner))
        XCTAssertNotEqual(options, [])
    }

    func testRejectedStalePushIsNotPresentedInForeground() {
        let options = CompanionAppDelegate.presentationOptions(for: .rejectedStale)

        XCTAssertEqual(options, [])
    }

    func testUnrecognizedPushFailsOpenForForegroundPresentation() {
        let options = CompanionAppDelegate.presentationOptions(for: .unrecognized)

        XCTAssertNotEqual(options, [])
    }

    func testAcceptedAndUnrecognizedPresentWhileRejectedStaleDoesNot() {
        let accepted = CompanionAppDelegate.presentationOptions(for: .accepted)
        let unrecognized = CompanionAppDelegate.presentationOptions(for: .unrecognized)
        let rejectedStale = CompanionAppDelegate.presentationOptions(for: .rejectedStale)

        XCTAssertEqual(accepted, unrecognized)
        XCTAssertNotEqual(rejectedStale, accepted)
        XCTAssertNotEqual(rejectedStale, unrecognized)
    }
}
