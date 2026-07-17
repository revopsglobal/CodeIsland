import XCTest

final class CodeIslandCompanionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testQuestionStateRendersPrimaryControls() throws {
        let app = launchApp(mockState: "question")

        XCTAssertTrue(app.otherElements["companion.statusCard"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["companion.questionCard"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["companion.command.focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["companion.command.skip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["companion.liveActivity.inlineButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLongMessageStateCanScrollToRecentActivity() throws {
        let app = launchApp(mockState: "long")

        XCTAssertTrue(app.otherElements["companion.statusCard"].waitForExistence(timeout: 8))

        let messages = app.otherElements["companion.messages"]
        if !messages.waitForExistence(timeout: 4) {
            app.scrollViews["companion.scroll"].swipeUp()
        }
        XCTAssertTrue(messages.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["companion.liveActivity.primaryButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testIdleStateKeepsMacAndLiveActivityActionsReachable() throws {
        let app = launchApp(mockState: "idle")

        XCTAssertTrue(app.otherElements["companion.statusCard"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["companion.command.focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["companion.liveActivity.primaryButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLandscapeMultiSessionShowsBoard() throws {
        let app = launchApp(mockState: "multi")
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }

        let board = app.otherElements["companion.standby.board"]
        if !board.waitForExistence(timeout: 8) {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "landscape-board-missing"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            print(app.debugDescription)
            XCTFail("Landscape session board did not appear")
            return
        }
        let rows = app.descendants(matching: .any).matching(identifier: "companion.standby.sessionRow")
        XCTAssertGreaterThanOrEqual(rows.count, 2)
    }

    @MainActor
    func testPersonalHubModesRenderAdvertisedModules() throws {
        let expectations: [(mode: String, modules: [String])] = [
            ("home", ["nowPlaying", "calendar", "weather", "quickToggles", "audio", "bluetooth", "battery"]),
            ("work", ["calendar", "reminders", "notes", "teleprompter", "camera", "shelf", "notifications", "downloads"]),
            ("code", ["agents", "github", "claude", "shelf", "system", "downloads", "windowManager"]),
        ]

        for expectation in expectations {
            let app = launchHubApp(mode: expectation.mode)
            XCTAssertTrue(app.otherElements["hub.surface"].waitForExistence(timeout: 8))
            assertHubModules(expectation.modules, in: app, mode: expectation.mode)
            app.terminate()
        }
    }

    @MainActor
    func testTaskCreationRequiresReviewAndExplicitExecution() throws {
        let app = launchHubApp(mode: "work")
        XCTAssertTrue(app.otherElements["hub.surface"].waitForExistence(timeout: 8))

        let taskModule = findHubElement("hub.module.reminders", in: app)
        XCTAssertTrue(taskModule.exists)

        let addTask = app.buttons["Add task"].firstMatch
        XCTAssertTrue(addTask.waitForExistence(timeout: 4))
        addTask.tap()

        let composer = app.textFields["hub.reminders.composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 4))
        composer.tap()
        composer.typeText("Finish Simulator proof")

        let review = app.buttons["Review"].firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 4))
        review.tap()

        XCTAssertTrue(app.otherElements["hub.action.confirmation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Do it"].waitForExistence(timeout: 3))
        app.buttons["Do it"].tap()

        let message = app.staticTexts["hub.action.message"].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("Executed reminders.add"))
    }

    @MainActor
    func testClaudeDoProposalRequiresReviewAndExplicitExecution() throws {
        let app = launchHubApp(mode: "code")
        XCTAssertTrue(app.otherElements["hub.surface"].waitForExistence(timeout: 8))

        let claudeModule = findHubElement("hub.module.claude", in: app)
        XCTAssertTrue(claudeModule.exists)

        let doButton = app.buttons["Do"].firstMatch
        XCTAssertTrue(doButton.waitForExistence(timeout: 4))
        doButton.tap()

        let composer = app.textFields["hub.claude.composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 4))
        composer.tap()
        composer.typeText("Add finish the deck to my tasks")

        let review = app.buttons["Review"].firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 4))
        review.tap()

        XCTAssertTrue(app.otherElements["hub.action.confirmation"].waitForExistence(timeout: 5))
        app.buttons["Do it"].tap()

        let message = app.staticTexts["hub.action.message"].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("Executed claude.plan"))
    }

    @MainActor
    func testCompletedDownloadOpensNativeShareSheet() throws {
        let app = launchHubApp(mode: "code")
        XCTAssertTrue(app.otherElements["hub.surface"].waitForExistence(timeout: 8))

        let downloadsModule = findHubElement("hub.module.downloads", in: app)
        XCTAssertTrue(downloadsModule.exists)

        let download = app.buttons["hub.action.downloads.downloadToDevice"].firstMatch
        for _ in 0..<4 where !download.exists {
            app.swipeUp()
        }
        XCTAssertTrue(download.waitForExistence(timeout: 4))
        download.tap()

        let activityList = app.otherElements["ActivityListView"].firstMatch
        let nativeSheetAppeared = app.sheets.firstMatch.waitForExistence(timeout: 5)
            || activityList.waitForExistence(timeout: 2)
        XCTAssertTrue(nativeSheetAppeared, "Completed download did not open the native share sheet")
    }

    @MainActor
    private func launchApp(mockState: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-CodeIslandCompanionMockState", mockState]
        app.launch()
        return app
    }

    @MainActor
    private func launchHubApp(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-CodeIslandCompanionMockState", "idle",
            "-CodeIslandCompanionMockHub",
            "-CodeIslandCompanionMockHubMode", mode,
        ]
        app.launch()
        return app
    }

    @MainActor
    private func assertHubModules(_ moduleIDs: [String], in app: XCUIApplication, mode: String) {
        for moduleID in moduleIDs {
            let element = findHubElement("hub.module.\(moduleID)", in: app)
            XCTAssertTrue(element.exists, "Missing \(moduleID) in \(mode) mode")
        }
    }

    @MainActor
    private func findHubElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        let element = query.firstMatch
        let scroll = app.scrollViews["companion.scroll"].firstMatch
        for _ in 0..<10 where !element.exists {
            scroll.swipeUp()
        }
        return element
    }
}
