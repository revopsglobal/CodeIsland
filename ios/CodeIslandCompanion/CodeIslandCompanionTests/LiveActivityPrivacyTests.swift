import XCTest
@testable import CodeIslandCompanion

final class LiveActivityPrivacyTests: XCTestCase {
    func testCompactConnectionPrefersAuthenticatedTailscaleOverNearbySearch() {
        let presentation = CompanionConnectionPresentation.resolve(
            localActivitySubtitle: nil,
            localPeerName: nil,
            localBrowsing: true,
            remoteState: .connected,
            remoteServerName: "Greg's MacBook Air"
        )

        XCTAssertEqual(presentation.subtitle, "Greg's MacBook Air")
        XCTAssertTrue(presentation.isActive)
        XCTAssertFalse(
            presentation.isBrowsing,
            "Nearby discovery must not make an authenticated Tailscale connection look like it is still searching"
        )
    }

    func testCompactConnectionFallsBackToNearbyDiscoveryWhenRemoteIsUnpaired() {
        let presentation = CompanionConnectionPresentation.resolve(
            localActivitySubtitle: nil,
            localPeerName: nil,
            localBrowsing: true,
            remoteState: .unpaired,
            remoteServerName: nil
        )

        XCTAssertEqual(presentation.subtitle, "Searching nearby")
        XCTAssertFalse(presentation.isActive)
        XCTAssertTrue(presentation.isBrowsing)
    }

    func testBackgroundRefreshKeepsAnEstablishedConnectionStable() {
        XCTAssertEqual(
            RemoteApprovalClient.refreshStartState(hasCompletedSnapshot: false),
            .connecting
        )
        XCTAssertNil(
            RemoteApprovalClient.refreshStartState(hasCompletedSnapshot: true),
            "A routine poll must not replace stable content with a transient connecting state"
        )
    }

    func testStatusPulseIsReservedForActionRequiredStates() {
        XCTAssertFalse(CompanionMotionPolicy.shouldPulse(status: .idle, reduceMotion: false))
        XCTAssertFalse(CompanionMotionPolicy.shouldPulse(status: .processing, reduceMotion: false))
        XCTAssertFalse(CompanionMotionPolicy.shouldPulse(status: .running, reduceMotion: false))
        XCTAssertTrue(CompanionMotionPolicy.shouldPulse(status: .waitingApproval, reduceMotion: false))
        XCTAssertTrue(CompanionMotionPolicy.shouldPulse(status: .waitingQuestion, reduceMotion: false))
        XCTAssertFalse(CompanionMotionPolicy.shouldPulse(status: .waitingApproval, reduceMotion: true))
    }

    @MainActor
    func testRemoteAttentionAutoStartsOnlyForActionRequiredStates() {
        XCTAssertTrue(LiveActivityController.shouldAutoStart(for: .waitingApproval))
        XCTAssertTrue(LiveActivityController.shouldAutoStart(for: .waitingQuestion))
        XCTAssertFalse(LiveActivityController.shouldAutoStart(for: .processing))
        XCTAssertFalse(LiveActivityController.shouldAutoStart(for: .running))
        XCTAssertFalse(LiveActivityController.shouldAutoStart(for: .idle))
    }

    @MainActor
    func testLiveActivityReceiptMailboxClearsOnlyAcknowledgedEvents() throws {
        UserDefaults.standard.removeObject(forKey: LiveActivityTokenMailbox.receiptsKey)
        defer { UserDefaults.standard.removeObject(forKey: LiveActivityTokenMailbox.receiptsKey) }

        LiveActivityTokenMailbox.storeSnapshot()
        LiveActivityTokenMailbox.storeSnapshot()
        let receipts = LiveActivityTokenMailbox.pendingReceipts()
        XCTAssertEqual(receipts.count, 2)
        XCTAssertTrue(receipts.allSatisfy(\.isStructurallyValid))

        LiveActivityTokenMailbox.clearReceipts(eventIDs: [receipts[0].eventId])
        XCTAssertEqual(
            LiveActivityTokenMailbox.pendingReceipts().map(\.eventId),
            [receipts[1].eventId]
        )
    }

    @MainActor
    func testLiveActivityUpdateTokenMailboxDeduplicatesTheSameToken() throws {
        UserDefaults.standard.removeObject(forKey: LiveActivityTokenMailbox.updateTokensKey)
        defer { UserDefaults.standard.removeObject(forKey: LiveActivityTokenMailbox.updateTokensKey) }

        XCTAssertTrue(LiveActivityTokenMailbox.storeUpdateToken(Data([0x01, 0x02]), requestID: "request-id"))
        XCTAssertFalse(LiveActivityTokenMailbox.storeUpdateToken(Data([0x01, 0x02]), requestID: "request-id"))
        XCTAssertTrue(LiveActivityTokenMailbox.storeUpdateToken(Data([0x03, 0x04]), requestID: "request-id"))

        let tokens = try XCTUnwrap(
            UserDefaults.standard.dictionary(forKey: LiveActivityTokenMailbox.updateTokensKey) as? [String: String]
        )
        XCTAssertEqual(tokens, ["request-id": "0304"])
    }

    func testLockScreenStateRedactsPromptTranscriptAndWorkspace() throws {
        let payload = CompanionStatePayload(
            version: 1,
            sequence: 41,
            sessionId: "sensitive-session",
            source: "codex",
            status: .waitingQuestion,
            toolName: "SecretTool",
            workspaceName: "ConfidentialWorkspace",
            messages: [CompanionMessagePreview(role: .assistant, text: "Secret transcript")],
            pendingAction: .question,
            question: CompanionQuestionPayload(
                header: "Secret header",
                question: "Secret question text",
                options: ["Secret option"],
                descriptions: ["Secret description"],
                index: 1,
                total: 1,
                allowsMultipleSelection: false
            ),
            sessions: [
                CompanionSessionPreview(
                    sessionId: "sensitive-session",
                    source: "codex",
                    status: .waitingQuestion,
                    toolName: "SecretTool",
                    workspaceName: "ConfidentialWorkspace",
                    message: "Secret session message",
                    updatedAt: Date()
                )
            ],
            updatedAt: Date()
        )

        let state = CodeIslandActivityAttributes.ContentState(payload: payload)
        XCTAssertNil(state.toolName)
        XCTAssertNil(state.workspaceName)
        XCTAssertNil(state.questionText)
        XCTAssertNil(state.questionHeader)
        XCTAssertNil(state.sessions.first?.toolName)
        XCTAssertNil(state.sessions.first?.workspaceName)

        let encoded = try JSONEncoder().encode(state)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        for secret in [
            "SecretTool", "ConfidentialWorkspace", "Secret transcript",
            "Secret header", "Secret question text", "Secret option",
            "Secret description", "Secret session message",
        ] {
            XCTAssertFalse(text.contains(secret), "Live Activity leaked \(secret)")
        }
        XCTAssertTrue(text.contains("open Buddy privately"))
    }

    func testAuthenticatedSnapshotPreservesSequenceAndOnlyGenericActivityCopy() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = RemoteApprovalSnapshot(
            serverName: "Private Mac",
            generatedAt: generatedAt,
            companionSequence: 88,
            approvals: [],
            questions: [
                RemoteQuestionItem(
                    id: "question-id",
                    sessionId: "session-id",
                    source: "claude",
                    workspace: "SecretWorkspace",
                    createdAt: generatedAt,
                    prompts: [
                        RemoteQuestionPrompt(
                            id: "prompt",
                            header: "SecretHeader",
                            question: "SecretQuestion",
                            options: ["SecretOption"],
                            descriptions: ["SecretDescription"],
                            allowsMultipleSelection: false
                        )
                    ],
                    requiresLocalResponse: false,
                    actionToken: "secret-token",
                    actionExpiresAt: generatedAt.addingTimeInterval(120)
                )
            ]
        )

        let payload = try XCTUnwrap(CompanionStatePayload(remoteApprovalSnapshot: snapshot))
        XCTAssertEqual(payload.sequence, 88)
        XCTAssertEqual(payload.status, .waitingQuestion)
        let activity = CodeIslandActivityAttributes.ContentState(payload: payload)
        let text = try XCTUnwrap(String(data: try JSONEncoder().encode(activity), encoding: .utf8))
        XCTAssertFalse(text.contains("SecretQuestion"))
        XCTAssertFalse(text.contains("SecretWorkspace"))
        XCTAssertFalse(text.contains("secret-token"))
        XCTAssertTrue(text.contains("open Buddy privately"))
    }
}
