import XCTest
@testable import CodeIsland

@MainActor
final class ApplicationQuitControllerTests: XCTestCase {
    func testRemoteAccessCancelKeepsAppRunningAndWarnsWhatWillStop() {
        var receivedConfirmation: ApplicationQuitController.Confirmation?
        var terminationCount = 0
        let controller = ApplicationQuitController(
            isRemoteAccessEnabled: { true },
            confirm: {
                receivedConfirmation = $0
                return false
            },
            terminate: { terminationCount += 1 }
        )

        let shouldTerminate = controller.shouldTerminate()

        XCTAssertFalse(shouldTerminate)
        XCTAssertEqual(terminationCount, 0)
        XCTAssertEqual(receivedConfirmation?.confirmButtonTitle, "Quit CodeIsland")
        XCTAssertEqual(receivedConfirmation?.cancelButtonTitle, "Cancel")
        XCTAssertTrue(receivedConfirmation?.message.localizedCaseInsensitiveContains("Buddy") == true)
        XCTAssertTrue(receivedConfirmation?.message.localizedCaseInsensitiveContains("remote access") == true)
        XCTAssertTrue(receivedConfirmation?.message.localizedCaseInsensitiveContains("stop") == true)
    }

    func testConfirmedRemoteAccessQuitTerminates() {
        var confirmationCount = 0
        var terminationCount = 0
        let controller = ApplicationQuitController(
            isRemoteAccessEnabled: { true },
            confirm: { _ in
                confirmationCount += 1
                return true
            },
            terminate: { terminationCount += 1 }
        )

        let shouldTerminate = controller.shouldTerminate()

        XCTAssertTrue(shouldTerminate)
        XCTAssertEqual(confirmationCount, 1)
        XCTAssertEqual(terminationCount, 0)
    }

    func testLocalOnlyQuitDoesNotAddAConfirmationStep() {
        var confirmationCount = 0
        var terminationCount = 0
        let controller = ApplicationQuitController(
            isRemoteAccessEnabled: { false },
            confirm: { _ in
                confirmationCount += 1
                return false
            },
            terminate: { terminationCount += 1 }
        )

        let shouldTerminate = controller.shouldTerminate()
        controller.requestQuit()

        XCTAssertTrue(shouldTerminate)
        XCTAssertEqual(confirmationCount, 0)
        XCTAssertEqual(terminationCount, 1)
    }

    func testQuitRequestAsksApplicationToTerminateOnce() {
        var terminationCount = 0
        let controller = ApplicationQuitController(
            isRemoteAccessEnabled: { true },
            confirm: { _ in false },
            terminate: { terminationCount += 1 }
        )

        controller.requestQuit()

        XCTAssertEqual(terminationCount, 1)
    }

    func testNotchAndStatusMenuRouteQuitThroughGuard() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let notch = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/CodeIsland/NotchPanelView.swift"),
            encoding: .utf8
        )
        let statusItem = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/CodeIsland/StatusItemController.swift"),
            encoding: .utf8
        )
        let appDelegate = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/CodeIsland/AppDelegate.swift"),
            encoding: .utf8
        )

        XCTAssertEqual(
            notch.components(separatedBy: "ApplicationQuitController.shared.requestQuit()").count - 1,
            2
        )
        XCTAssertFalse(notch.contains("NSApplication.shared.terminate(nil)"))
        XCTAssertTrue(statusItem.contains("ApplicationQuitController.shared.requestQuit()"))
        XCTAssertFalse(statusItem.contains("NSApp.terminate(nil)"))
        XCTAssertTrue(appDelegate.contains("func applicationShouldTerminate"))
        XCTAssertTrue(appDelegate.contains("ApplicationQuitController.shared.shouldTerminate()"))
    }
}
