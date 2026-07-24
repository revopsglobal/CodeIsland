import XCTest

final class AgentOpsVoiceFailureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRealtimeAndGatewayFailuresStayRetrySafe() throws {
        var app = launch("realtime-unavailable")
        XCTAssertTrue(
            app.staticTexts[
                "AgentOps could not open the voice session. Your request was not sent."
            ].waitForExistence(timeout: 8)
        )
        XCTAssertFalse(canonicalTask(in: app).exists)

        app.terminate()
        app = launch("gateway-unavailable")
        XCTAssertTrue(
            app.staticTexts[
                "AgentOps is reconnecting. Any unsent request stays privately on this iPhone."
            ].waitForExistence(timeout: 8)
        )
        XCTAssertFalse(canonicalTask(in: app).exists)
    }

    @MainActor
    func testClaudeAndLockedWorkerFailuresNeverClaimFallback() throws {
        var app = launch("claude-unavailable")
        XCTAssertTrue(
            app.staticTexts[
                "Claude Max is temporarily unavailable. AgentOps did not switch providers or create a task."
            ].waitForExistence(timeout: 8)
        )
        XCTAssertFalse(canonicalTask(in: app).exists)

        app.terminate()
        app = launch("locked-worker-unavailable")
        XCTAssertTrue(
            app.staticTexts[
                "The locked worker is unavailable. AgentOps did not fall back to another provider."
            ].waitForExistence(timeout: 8)
        )
        XCTAssertFalse(canonicalTask(in: app).exists)
    }

    @MainActor
    func testMissingContextAndCaptureFailureDoNotClaimDurableWork() throws {
        var app = launch("context-unavailable")
        XCTAssertTrue(
            app.staticTexts[
                "Required Wiki context is unavailable. AgentOps did not create durable work."
            ].waitForExistence(timeout: 8)
        )
        XCTAssertFalse(canonicalTask(in: app).exists)

        app.terminate()
        app = launch("capture-unavailable")
        XCTAssertTrue(
            app.staticTexts[
                "AgentOps could not capture durable work. The request is saved privately on this iPhone."
            ].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(
            app.staticTexts[
                "Saved locally with the same request identity for a safe retry."
            ].exists
        )
        XCTAssertFalse(canonicalTask(in: app).exists)
    }

    @MainActor
    func testFailedVerificationNeverRendersVerified() throws {
        let app = launch("failed-verification", destination: "work")
        let task = app.descendants(matching: .any).matching(
            identifier:
                "agentops.work.task.e7e843c5-733d-4492-a863-1c337684653b"
        ).firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 8))
        task.tap()

        XCTAssertTrue(app.staticTexts["failed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["verified"].exists)
        XCTAssertFalse(app.staticTexts["Verified"].exists)
    }

    @MainActor
    func testBackgroundDraftRemainsRecoverableAfterReconnect() throws {
        let app = launch("offline-draft")
        XCTAssertTrue(
            app.staticTexts[
                "Saved locally. This request will sync when AgentOps reconnects."
            ].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["Reconnecting"].exists)
        XCTAssertFalse(canonicalTask(in: app).exists)
    }

    @MainActor
    private func launch(
        _ scenario: String,
        destination: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AgentOpsVoiceMock", scenario]
        if let destination {
            app.launchArguments += ["-AgentOpsMockDestination", destination]
        }
        app.launch()
        return app
    }

    @MainActor
    private func canonicalTask(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts[
            "e7e843c5-733d-4492-a863-1c337684653b"
        ]
    }
}
