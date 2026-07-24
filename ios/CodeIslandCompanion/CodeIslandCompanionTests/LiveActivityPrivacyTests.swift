import XCTest
@testable import CodeIslandCompanion

@MainActor
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

    func testNormalConnectionCopyHidesTransportDetails() {
        XCTAssertEqual(
            RemoteApprovalClient.connectionDetail(serverName: "Greg's MacBook Air"),
            "Connected to Greg's MacBook Air"
        )
        XCTAssertEqual(
            RemoteApprovalClient.connectionDetail(serverName: nil),
            "Connected to Greg's Mac"
        )
        XCTAssertFalse(RemoteApprovalClient.invalidServerURLMessage.localizedCaseInsensitiveContains("Tailscale"))
        XCTAssertFalse(RemoteApprovalClient.invalidServerURLMessage.localizedCaseInsensitiveContains("HTTPS"))
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

    func testTransientRefreshFailuresKeepEstablishedContentStable() {
        XCTAssertEqual(
            RemoteApprovalClient.refreshFailureState(
                hasCompletedSnapshot: false,
                consecutiveFailures: 1,
                message: "network unavailable"
            ),
            .offline("network unavailable"),
            "Before the first authenticated snapshot, a failed refresh must still show the actionable connection error."
        )
        XCTAssertNil(
            RemoteApprovalClient.refreshFailureState(
                hasCompletedSnapshot: true,
                consecutiveFailures: 1,
                message: "network unavailable"
            ),
            "A single routine poll miss after content has loaded must not flash the whole Now surface to offline."
        )
        XCTAssertNil(
            RemoteApprovalClient.refreshFailureState(
                hasCompletedSnapshot: true,
                consecutiveFailures: 2,
                message: "network unavailable"
            ),
            "Two routine poll misses should keep the established signal board stable instead of alternating every 4 seconds."
        )
        XCTAssertEqual(
            RemoteApprovalClient.refreshFailureState(
                hasCompletedSnapshot: true,
                consecutiveFailures: 3,
                message: "network unavailable"
            ),
            .offline("network unavailable"),
            "Three consecutive misses indicate the Mac is probably unavailable, so the offline recovery controls should appear."
        )
    }

    @MainActor
    func testMockHubUsesOnlyProductionBuddyActionVocabulary() {
        for mode in PersonalHubMode.allCases {
            let violations = RemoteApprovalClient.mockHubParityViolations(requestedMode: mode)
            XCTAssertEqual(
                violations.map(\.description),
                [],
                "\(mode.rawValue) mock hub exposes an action that the real Buddy contract does not classify"
            )
        }
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

    func testLiveActivityOrdersActionRequiredSessionsBeforeRoutineActivity() {
        let state = CodeIslandActivityAttributes.ContentState(
            sequence: 7,
            source: "codeisland",
            status: "running",
            toolName: nil,
            workspaceName: nil,
            message: nil,
            pendingAction: nil,
            questionText: nil,
            questionHeader: nil,
            questionProgress: nil,
            sessions: [
                liveActivitySession(id: "running", source: "codex", status: "running", updatedAt: 300),
                liveActivitySession(id: "approval", source: "claude", status: "waitingApproval", updatedAt: 100),
                liveActivitySession(id: "question", source: "codex", status: "waitingQuestion", updatedAt: 200),
            ],
            updatedAt: Date(timeIntervalSince1970: 400)
        )

        XCTAssertEqual(state.actionRequiredSessionCount, 2)
        XCTAssertEqual(state.orderedSessions.map(\.id), ["approval", "question", "running"])
    }

    func testLiveActivityRoutineSessionsUseStableIdentityInsteadOfHeartbeatOrder() {
        let olderRunning = liveActivitySession(id: "codex", source: "codex", status: "running", updatedAt: 100)
        let newerRunning = liveActivitySession(id: "claude", source: "claude", status: "running", updatedAt: 200)

        XCTAssertEqual(
            CodeIslandActivityAttributes.ContentState.orderedSessions([olderRunning, newerRunning]).map(\.id),
            CodeIslandActivityAttributes.ContentState.orderedSessions([newerRunning, olderRunning]).map(\.id)
        )
    }

    func testAgentOpsPushEnvelopeContainsNoTaskTitleTranscriptOrApprovalDetails() throws {
        let payload: [String: Any] = [
            "aps": ["content-available": 1],
            "taskId": "11111111-1111-4111-8111-111111111111",
            "approvalId": "22222222-2222-4222-8222-222222222222",
            "eventType": "approval.required",
            "version": 7,
            "deepLink":
                "codeisland://agentops/approvals/22222222-2222-4222-8222-222222222222?taskId=11111111-1111-4111-8111-111111111111",
        ]

        let envelope = try XCTUnwrap(
            AgentOpsPushEnvelope(payloadFields: payload)
        )
        XCTAssertTrue(envelope.customPayloadIsContentFree)
        let serialized = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        let text = String(decoding: serialized, as: UTF8.self)
        for secret in [
            "Private task title",
            "Secret transcript",
            "Deploy a verified production release.",
            String(repeating: "a", count: 64),
        ] {
            XCTAssertFalse(text.contains(secret))
        }
    }

    func testAgentOpsParserRejectsSensitiveCustomPushFields() {
        let payload: [String: Any] = [
            "aps": ["content-available": 1],
            "taskId": "11111111-1111-4111-8111-111111111111",
            "eventType": "task.needs_you",
            "version": 7,
            "deepLink":
                "codeisland://agentops/tasks/11111111-1111-4111-8111-111111111111",
            "transcript": "must not leave the server",
        ]

        XCTAssertNil(AgentOpsPushEnvelope(payloadFields: payload))
    }

    private func liveActivitySession(
        id: String,
        source: String,
        status: String,
        updatedAt: TimeInterval
    ) -> CodeIslandSessionActivityPreview {
        CodeIslandSessionActivityPreview(
            sessionId: id,
            source: source,
            status: status,
            toolName: nil,
            workspaceName: "CodeIsland",
            message: nil,
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}
