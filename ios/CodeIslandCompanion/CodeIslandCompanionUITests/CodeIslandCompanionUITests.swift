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
    func testLiveActivityEndsWhenWaitingRequestResolves() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-CodeIslandCompanionMockState", "question",
        ]
        app.launch()

        let sessions = app.buttons["companion.destination.sessions"]
        XCTAssertTrue(sessions.waitForExistence(timeout: 5))
        sessions.tap()

        let inline = app.buttons["companion.liveActivity.inlineButton"]
        XCTAssertTrue(inline.waitForExistence(timeout: 8))
        if !inline.label.localizedCaseInsensitiveContains("Stop Live Activity") {
            inline.tap()
        }
        let running = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS[c] %@", "Stop Live Activity"),
            object: inline
        )
        let runningResult = XCTWaiter.wait(for: [running], timeout: 5)
        XCTAssertEqual(
            runningResult,
            .completed,
            "Expected a running Live Activity control, got label: \(inline.label)"
        )

        app.terminate()
        app.launchArguments = [
            "-CodeIslandCompanionMockState", "idle",
            "-CodeIslandCompanionSmokeLiveActivity",
        ]
        app.launch()

        let idleSessions = app.buttons["companion.destination.sessions"]
        XCTAssertTrue(idleSessions.waitForExistence(timeout: 5))
        idleSessions.tap()

        let primary = app.buttons["companion.liveActivity.primaryButton"]
        if !primary.waitForExistence(timeout: 8) {
            app.swipeUp()
        }
        if !primary.waitForExistence(timeout: 5) {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "live-activity-resolved-state-missing"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            print(app.debugDescription)
            XCTFail("Resolved session did not expose the primary Live Activity control")
            return
        }
        let ended = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS[c] %@", "Start Live Activity"),
            object: primary
        )
        let endedResult = XCTWaiter.wait(for: [ended], timeout: 5)
        XCTAssertEqual(
            endedResult,
            .completed,
            "Expected the resolved request to end its Live Activity, got label: \(primary.label)"
        )
    }

    @MainActor
    func testPairingSurfaceKeepsRecoveryInline() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-CodeIslandCompanionMockState", "idle",
            "-CodeIslandCompanionMockPairing",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Connect to Greg's Mac"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["companion.discoveryCard"].exists)
        let pairingCode = app.textFields["Pairing code"]
        XCTAssertTrue(pairingCode.waitForExistence(timeout: 3))
        pairingCode.tap()
        pairingCode.typeText("123456")

        let connect = app.buttons["Connect securely"]
        XCTAssertTrue(connect.waitForExistence(timeout: 3))
        connect.tap()

        XCTAssertTrue(
            app.staticTexts[
                "That code expired. Open Code Island Settings → Buddy on your Mac for the current code."
            ].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["Connect to Greg's Mac"].exists)
    }

    @MainActor
    func testAttentionFirstShellKeepsToolsSecondary() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-CodeIslandCompanionMockState", "idle",
            "-CodeIslandCompanionMockHub",
            "-CodeIslandCompanionMockHubMode", "code",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["CodeIsland"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["companion.presence.menu"].exists)
        let now = app.buttons["companion.destination.now"]
        let sessions = app.buttons["companion.destination.sessions"]
        let capture = app.buttons["companion.capture"]
        let more = app.buttons["companion.more"]
        XCTAssertTrue(now.exists)
        XCTAssertTrue(sessions.exists)
        XCTAssertTrue(capture.exists)
        XCTAssertTrue(more.exists)
        XCTAssertGreaterThanOrEqual(now.frame.height, 44)
        XCTAssertGreaterThanOrEqual(capture.frame.height, 44)
        XCTAssertGreaterThanOrEqual(more.frame.height, 44)
        XCTAssertTrue(app.otherElements["companion.now.overview"].exists)
        XCTAssertFalse(hubSurface(in: app).exists)

        more.tap()
        XCTAssertTrue(hubSurface(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "companion.more.sheet").firstMatch.exists
        )
    }

    @MainActor
    func testApprovalAttentionStageKeepsExactActionsProminent() throws {
        let app = launchAttentionApp("approval")

        XCTAssertTrue(app.staticTexts["Approval needed"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Run release build"].exists)

        let deny = app.buttons["Deny"]
        let approve = app.buttons["Approve once"]
        XCTAssertTrue(deny.exists)
        XCTAssertTrue(approve.exists)
        XCTAssertGreaterThanOrEqual(deny.frame.height, 44)
        XCTAssertGreaterThanOrEqual(approve.frame.height, 44)
    }

    @MainActor
    func testQuestionAttentionStageUsesNativeSelectionAndSubmit() throws {
        let app = launchAttentionApp("question")

        XCTAssertTrue(app.staticTexts["Decision needed"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Ship the signed build tonight?"].exists)
        let option = app.buttons["Ship tonight"]
        XCTAssertTrue(option.exists)
        option.tap()

        let submit = app.buttons["Send answer"]
        XCTAssertTrue(submit.waitForExistence(timeout: 4))
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: submit
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [enabled], timeout: 4),
            .completed,
            "Selecting an answer must enable submission after SwiftUI commits the selection"
        )
        XCTAssertGreaterThanOrEqual(submit.frame.height, 44)
    }

    @MainActor
    func testMultipleAttentionItemsDoNotRotateAutomatically() throws {
        let app = launchAttentionApp("multiple")

        XCTAssertTrue(app.staticTexts["Run release build"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["1 of 2"].exists)
        sleep(5)
        XCTAssertTrue(app.staticTexts["Run release build"].exists)
        XCTAssertFalse(app.staticTexts["Ship the signed build tonight?"].exists)
    }

    @MainActor
    func testAuthenticatedTailscaleConnectionDoesNotLookLikeNearbySearch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CodeIslandCompanionMockHub"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Code Island UI Test Mac"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Searching"].exists)
        XCTAssertFalse(app.staticTexts["Searching nearby"].exists)
        XCTAssertFalse(app.staticTexts["Private to your Tailscale network"].exists)
        XCTAssertFalse(app.staticTexts["Fetching the selected mode over Tailscale."].exists)
    }

    @MainActor
    func testSessionsUsesAuthenticatedTailscaleInsteadOfNearbyDiscovery() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-CodeIslandCompanionMockHub",
            "-CodeIslandCompanionMockHubMode", "code",
        ]
        app.launch()

        let sessions = app.buttons["companion.destination.sessions"]
        XCTAssertTrue(sessions.waitForExistence(timeout: 8))
        sessions.tap()

        XCTAssertTrue(app.otherElements["companion.remote.sessions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Code Island UI Test Mac"].exists)
        XCTAssertFalse(app.staticTexts["Waiting for Mac"].exists)
        XCTAssertFalse(app.otherElements["companion.discoveryCard"].exists)
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
            XCTAssertTrue(hubSurface(in: app).waitForExistence(timeout: 8))
            assertHubModules(expectation.modules, in: app, mode: expectation.mode)
            app.terminate()
        }
    }

    @MainActor
    func testReadOnlyRefreshUpdatesHubWithoutConfirmation() throws {
        let app = launchHubApp(mode: "code")
        XCTAssertTrue(hubSurface(in: app).waitForExistence(timeout: 8))

        openHubModule("agents", in: app)

        let refresh = app.buttons["Refresh"].firstMatch
        XCTAssertTrue(refresh.waitForExistence(timeout: 4))
        refresh.tap()

        XCTAssertFalse(
            app.otherElements["hub.action.confirmation"].waitForExistence(timeout: 2),
            "Read-only refresh should not interrupt with a mutation confirmation sheet"
        )
        let message = findHubElement("hub.action.message", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("Refreshed Agents"))
    }

    @MainActor
    func testCalendarMonthNavigatesAndKeepsSelectedDaySurface() throws {
        let app = launchHubApp(mode: "home")
        XCTAssertTrue(hubSurface(in: app).waitForExistence(timeout: 8))

        openHubModule("calendar", in: app)
        let month = findHubElement("hub.calendar.month", in: app)
        XCTAssertTrue(month.exists)
        let title = app.staticTexts["hub.calendar.monthTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        let initialTitle = title.label

        let next = app.buttons["hub.calendar.next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 4))
        next.tap()

        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", initialTitle),
            object: title
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)

        let today = app.buttons["hub.calendar.today"].firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 4))
        today.tap()
        XCTAssertTrue(app.otherElements["hub.calendar.selectedEvents"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTaskCreationRequiresReviewAndExplicitExecution() throws {
        let app = launchHubApp(mode: "work")
        XCTAssertTrue(hubSurface(in: app).waitForExistence(timeout: 8))

        openHubModule("reminders", in: app)

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

        let message = findHubElement("hub.action.message", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("Executed reminders.add"))
    }

    @MainActor
    func testModeRackReorderRequiresReviewAndExplicitExecution() throws {
        let app = launchHubApp(mode: "work")
        XCTAssertTrue(hubSurface(in: app).waitForExistence(timeout: 8))

        let edit = app.buttons["hub.rack.edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 4))
        edit.tap()

        XCTAssertTrue(app.otherElements["hub.rack.editor"].waitForExistence(timeout: 5))
        let moveTasksUp = app.buttons["Move Tasks up"].firstMatch
        XCTAssertTrue(moveTasksUp.waitForExistence(timeout: 4))
        moveTasksUp.tap()
        app.buttons["Review"].tap()

        XCTAssertTrue(app.otherElements["hub.action.confirmation"].waitForExistence(timeout: 5))
        app.buttons["Do it"].tap()

        let message = findHubElement("hub.action.message", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("Executed quickToggles.setModeRack"))
    }

    @MainActor
    func testQuickNoteEntryRequiresReviewAndExplicitExecution() throws {
        let app = launchHubApp(mode: "work")
        XCTAssertTrue(hubSurface(in: app).waitForExistence(timeout: 8))

        app.buttons["Done"].firstMatch.tap()
        let capture = app.buttons["companion.capture"].firstMatch
        XCTAssertTrue(capture.waitForExistence(timeout: 4))
        capture.tap()
        let newNote = app.buttons["New note"].firstMatch
        XCTAssertTrue(newNote.waitForExistence(timeout: 4))
        newNote.tap()

        XCTAssertTrue(app.otherElements["hub.quickJot.sheet"].waitForExistence(timeout: 5))
        let field = app.textFields["What do you want to remember?"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        field.tap()
        field.typeText("Buddy quick note")
        app.buttons["Review"].tap()

        XCTAssertTrue(app.otherElements["hub.action.confirmation"].waitForExistence(timeout: 5))
        app.buttons["Do it"].tap()

        let message = findHubElement("hub.action.message", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("Executed notes.add"))
    }

    @MainActor
    func testModuleDeepLinkSelectsModeAndHighlightsDestination() throws {
        let app = launchHubApp(
            mode: "home",
            deepLink: "codeisland://hub/reminders"
        )
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["hub.module.reminders"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testQuickJotDeepLinkPrefillsDraftButStillRequiresReview() throws {
        let app = launchHubApp(
            mode: "work",
            deepLink: "codeisland://quick-jot/task?text=Call%20the%20bank"
        )
        XCTAssertTrue(app.otherElements["hub.quickJot.sheet"].waitForExistence(timeout: 8))
        let field = app.textFields["hub.quickJot.text"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        XCTAssertEqual(field.value as? String, "Call the bank")
        XCTAssertTrue(app.buttons["Review"].exists)
        XCTAssertFalse(app.buttons["Do it"].exists)
    }

    @MainActor
    func testClaudeAskResponseBodyIsVisible() throws {
        let app = launchHubApp(mode: "code")
        XCTAssertTrue(hubSurface(in: app).waitForExistence(timeout: 8))

        openHubModule("claude", in: app)

        XCTAssertTrue(
            app.staticTexts["CodeIsland 1.0.49 is running on your Mac."].waitForExistence(timeout: 4),
            "Claude Ask must render the answer body, not only echo the original question"
        )
    }

    @MainActor
    func testClaudeDoProposalRequiresReviewAndExplicitExecution() throws {
        let app = launchHubApp(mode: "code")
        XCTAssertTrue(hubSurface(in: app).waitForExistence(timeout: 8))

        openHubModule("claude", in: app)

        let doButton = app.buttons["Do"].firstMatch
        XCTAssertTrue(doButton.waitForExistence(timeout: 4))
        doButton.tap()

        let composer = app.textFields["hub.claude.composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["hub.claude.voice.pushToTalk"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["hub.claude.voice.continuous"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["hub.claude.attach"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["hub.claude.safety"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Claude voice and file context composer"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        composer.tap()
        composer.typeText("Add finish the deck to my tasks")

        let review = app.buttons["hub.claude.review"].firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 4))
        review.tap()

        XCTAssertTrue(app.otherElements["hub.action.confirmation"].waitForExistence(timeout: 5))
        app.buttons["Do it"].tap()

        let message = findHubElement("hub.action.message", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("Executed claude.plan"))
    }

    @MainActor
    func testCompletedDownloadOpensNativeShareSheet() throws {
        let app = launchHubApp(mode: "code")
        XCTAssertTrue(hubSurface(in: app).waitForExistence(timeout: 8))

        openHubModule("downloads", in: app)

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
    func testShelfFileOpensNativeShareSheet() throws {
        let app = launchHubApp(mode: "code")
        XCTAssertTrue(hubSurface(in: app).waitForExistence(timeout: 8))

        openHubModule("shelf", in: app)
        let download = app.buttons["hub.action.shelf.downloadToDevice"].firstMatch
        for _ in 0..<4 where !download.exists {
            app.swipeUp()
        }
        XCTAssertTrue(download.waitForExistence(timeout: 4))
        download.tap()

        let activityList = app.otherElements["ActivityListView"].firstMatch
        let nativeSheetAppeared = app.sheets.firstMatch.waitForExistence(timeout: 5)
            || activityList.waitForExistence(timeout: 2)
        XCTAssertTrue(nativeSheetAppeared, "Shelf file did not open the native share sheet")
    }

    @MainActor
    func testNowPlayingScrubberShowsExactSeekConfirmation() throws {
        let app = launchHubApp(mode: "home")
        XCTAssertTrue(hubSurface(in: app).waitForExistence(timeout: 8))

        openHubModule("nowPlaying", in: app)
        let slider = app.sliders["hub.seek.nowPlaying"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.7)

        let confirmation = app.otherElements["hub.action.confirmation"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS[c] %@ AND label CONTAINS[c] %@",
            "Now Playing",
            "seek"
        )).firstMatch.exists)
    }

    @MainActor
    func testCameraActionOpensPrivateNativePreview() throws {
        let app = launchHubApp(mode: "work")
        XCTAssertTrue(hubSurface(in: app).waitForExistence(timeout: 8))

        openHubModule("camera", in: app)

        addUIInterruptionMonitor(withDescription: "Camera permission") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists {
                allow.tap()
                return true
            }
            return false
        }

        let preview = app.buttons["Preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 4))
        preview.tap()
        app.tap()

        XCTAssertTrue(app.otherElements["hub.camera.preview"].waitForExistence(timeout: 8))
        let done = app.buttons["hub.camera.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 4))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Camera microphone private preflight"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        done.tap()
        XCTAssertFalse(app.otherElements["hub.camera.preview"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchApp(mockState: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-CodeIslandCompanionMockState", mockState]
        app.launch()
        let sessions = app.buttons["companion.destination.sessions"]
        if sessions.waitForExistence(timeout: 5) {
            sessions.tap()
        }
        return app
    }

    @MainActor
    private func launchHubApp(mode: String, deepLink: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-CodeIslandCompanionMockState", "idle",
            "-CodeIslandCompanionMockHub",
            "-CodeIslandCompanionMockHubMode", mode,
        ]
        if let deepLink {
            app.launchArguments += ["-CodeIslandCompanionMockDeepLink", deepLink]
        }
        app.launch()
        let hub = hubSurface(in: app)
        if !hub.waitForExistence(timeout: 2) {
            let more = app.buttons["companion.more"]
            if more.waitForExistence(timeout: 4) {
                more.tap()
            }
        }
        return app
    }

    @MainActor
    private func launchAttentionApp(_ kind: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-CodeIslandCompanionMockState", "idle",
            "-CodeIslandCompanionMockHub",
            "-CodeIslandCompanionMockHubMode", "code",
            "-CodeIslandCompanionMockAttention", kind,
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
    private func openHubModule(_ moduleID: String, in app: XCUIApplication) {
        let module = findHubElement("hub.module.\(moduleID)", in: app)
        XCTAssertTrue(module.exists, "Missing \(moduleID) tool row")
        module.tap()
        XCTAssertTrue(
            app.otherElements["hub.module.\(moduleID)"].waitForExistence(timeout: 5),
            "\(moduleID) detail did not open"
        )
    }

    @MainActor
    private func findHubElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        let element = query.firstMatch
        if element.waitForExistence(timeout: 1) {
            return element
        }

        let companionScroll = app.scrollViews["companion.scroll"].firstMatch
        let hubSurface = hubSurface(in: app)
        for _ in 0..<10 where !element.exists {
            if companionScroll.exists {
                companionScroll.swipeUp()
            } else if hubSurface.exists {
                hubSurface.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        return element
    }

    @MainActor
    private func hubSurface(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "hub.surface")
            .firstMatch
    }
}
