import XCTest
@testable import CodeIslandCore

final class RemoteAttentionLifecycleTests: XCTestCase {
    func testTaskEnvelopeRequiresOpaqueUUIDAndState() throws {
        let id = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = RemoteAttentionPushEnvelope(
            kind: .task,
            state: .pending,
            requestID: id.uuidString.lowercased(),
            taskState: .needsYou,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(600)
        )
        let data = try JSONSerialization.data(withJSONObject: envelope.payloadFields)
        let fields = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(RemoteAttentionPushEnvelope(payloadFields: fields), envelope)
        XCTAssertEqual(fields["ciTaskState"] as? String, "needs-you")
        XCTAssertNil(RemoteAttentionPushEnvelope(payloadFields: [
            "ciVersion": 1, "ciEventId": "e", "ciAttentionKind": "task",
            "ciAttentionState": "pending", "ciRequestId": "not-a-uuid",
            "ciTaskState": "needs-you", "ciIssuedAt": 1, "ciExpiresAt": 2,
        ]))
    }

    func testTaskAttentionPolicyIsSignalFirstAndTerminalCannotRegress() {
        XCTAssertFalse(RemoteTaskAttentionPolicy.shouldNotifyImmediately(state: .working, isFollowed: true))
        XCTAssertTrue(RemoteTaskAttentionPolicy.shouldNotifyImmediately(state: .needsYou, isFollowed: false))
        XCTAssertTrue(RemoteTaskAttentionPolicy.shouldNotifyImmediately(state: .failed, isFollowed: false))
        XCTAssertFalse(RemoteTaskAttentionPolicy.shouldNotifyImmediately(state: .verified, isFollowed: false))
        XCTAssertTrue(RemoteTaskAttentionPolicy.shouldNotifyImmediately(state: .verified, isFollowed: true))
        XCTAssertFalse(RemoteTaskAttentionPolicy.accepts(previousState: .verified, incomingState: .working))
        XCTAssertTrue(RemoteTaskAttentionPolicy.accepts(previousState: .working, incomingState: .verified))
    }

    func testOpaquePushEnvelopeRoundTripsWithoutPrivateContent() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = RemoteAttentionPushEnvelope(
            eventID: "event-1",
            kind: .question,
            state: .pending,
            requestID: "opaque-request-7",
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(600)
        )

        let data = try JSONSerialization.data(withJSONObject: envelope.payloadFields)
        let decodedFields = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(RemoteAttentionPushEnvelope(payloadFields: decodedFields), envelope)
        XCTAssertNil(decodedFields["question"])
        XCTAssertNil(decodedFields["prompt"])
        XCTAssertNil(decodedFields["workspace"])
        XCTAssertNil(decodedFields["tool"])
        XCTAssertNil(decodedFields["actionToken"])
    }

    func testLegacyNotificationTokenRegistrationStillDecodes() throws {
        let data = Data(#"{"token":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","environment":"production"}"#.utf8)
        let registration = try JSONDecoder().decode(RemotePushRegistrationRequest.self, from: data)

        XCTAssertEqual(registration.token, String(repeating: "a", count: 64))
        XCTAssertEqual(registration.environment, "production")
        XCTAssertNil(registration.liveActivityPushToStartToken)
        XCTAssertNil(registration.liveActivityUpdateTokens)
        XCTAssertNil(registration.liveActivityReceipts)
        XCTAssertNil(registration.clientVersion)
        XCTAssertNil(registration.clientBuild)
    }

    func testClientBuildRegistrationRoundTripsWithoutPushTokens() throws {
        let registration = RemotePushRegistrationRequest(
            environment: "production",
            clientVersion: "1.0.0",
            clientBuild: "20260718075059"
        )

        let data = try JSONEncoder().encode(registration)
        let decoded = try JSONDecoder().decode(RemotePushRegistrationRequest.self, from: data)

        XCTAssertEqual(decoded.clientVersion, "1.0.0")
        XCTAssertEqual(decoded.clientBuild, "20260718075059")
        XCTAssertNil(decoded.token)
    }

    func testLiveActivityReceiptIsBoundedAndContainsNoPrivateContent() throws {
        let receipt = RemoteLiveActivityReceipt(
            eventId: "receipt-1",
            source: .activityStarted,
            requestId: "opaque-request-7",
            kind: .question,
            state: .pending,
            activityState: .active,
            observedAt: Date(timeIntervalSince1970: 1_800_000_000),
            activitiesEnabled: true,
            activeActivityCount: 1,
            activeRequestIds: ["opaque-request-7"]
        )

        XCTAssertTrue(receipt.isStructurallyValid)
        let text = try XCTUnwrap(String(data: JSONEncoder().encode(receipt), encoding: .utf8))
        XCTAssertFalse(text.contains("prompt"))
        XCTAssertFalse(text.contains("workspace"))
        XCTAssertFalse(text.contains("actionToken"))
        XCTAssertFalse(text.contains("pushToken"))

        XCTAssertFalse(RemoteLiveActivityReceipt(
            eventId: "receipt-2",
            source: .notification,
            requestId: nil,
            kind: .approval,
            state: .pending,
            activitiesEnabled: true,
            activeActivityCount: 0,
            activeRequestIds: []
        ).isStructurallyValid)
        XCTAssertFalse(RemoteLiveActivityReceipt(
            eventId: "receipt-3",
            source: .snapshot,
            activitiesEnabled: true,
            activeActivityCount: 0,
            activeRequestIds: ["request-without-an-activity"]
        ).isStructurallyValid)
    }

    func testPendingPushExpiresAndResolvedPushSuppressesOlderReplay() {
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let pending = RemoteAttentionPushEnvelope(
            eventID: "pending",
            kind: .approval,
            state: .pending,
            requestID: "request",
            issuedAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(10)
        )
        XCTAssertTrue(pending.isFresh(lastIssuedAt: nil, now: now))
        XCTAssertFalse(pending.isFresh(lastIssuedAt: now, now: now))

        let expired = RemoteAttentionPushEnvelope(
            eventID: "expired",
            kind: .approval,
            state: .pending,
            requestID: "request",
            issuedAt: now.addingTimeInterval(-20),
            expiresAt: now.addingTimeInterval(-1)
        )
        XCTAssertFalse(expired.isFresh(lastIssuedAt: nil, now: now))

        let resolved = RemoteAttentionPushEnvelope(
            eventID: "resolved",
            kind: .approval,
            state: .resolved,
            requestID: "request",
            issuedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        XCTAssertTrue(resolved.isFresh(lastIssuedAt: nil, now: now))
        XCTAssertFalse(pending.isFresh(lastIssuedAt: resolved.issuedAt, now: now))

        let lateResolved = RemoteAttentionPushEnvelope(
            eventID: "late-resolved",
            kind: .approval,
            state: .resolved,
            requestID: "request",
            issuedAt: now.addingTimeInterval(-120),
            expiresAt: now.addingTimeInterval(-60)
        )
        XCTAssertFalse(lateResolved.isFresh(lastIssuedAt: nil, now: now))
    }

    func testLiveActivityCreatesUpdatesEndsAndRejectsStaleReplay() {
        let first = LiveActivityLifecycleCursor(sequence: 10, updatedAt: Date(timeIntervalSince1970: 10))
        let create = LiveActivityLifecycle.transition(
            current: nil,
            incoming: first,
            hasActivity: false,
            hasActiveContent: true,
            createIfNeeded: true
        )
        XCTAssertEqual(create.decision, .create)

        let second = LiveActivityLifecycleCursor(sequence: 11, updatedAt: Date(timeIntervalSince1970: 11))
        let update = LiveActivityLifecycle.transition(
            current: create.cursor,
            incoming: second,
            hasActivity: true,
            hasActiveContent: true,
            createIfNeeded: false
        )
        XCTAssertEqual(update.decision, .update)

        let resolved = LiveActivityLifecycleCursor(sequence: 12, updatedAt: Date(timeIntervalSince1970: 12))
        let end = LiveActivityLifecycle.transition(
            current: update.cursor,
            incoming: resolved,
            hasActivity: true,
            hasActiveContent: false,
            createIfNeeded: false
        )
        XCTAssertEqual(end.decision, .end)

        let staleReplay = LiveActivityLifecycle.transition(
            current: end.cursor,
            incoming: second,
            hasActivity: false,
            hasActiveContent: true,
            createIfNeeded: true
        )
        XCTAssertEqual(staleReplay.decision, .ignore)

        let nextRequest = LiveActivityLifecycle.transition(
            current: end.cursor,
            incoming: LiveActivityLifecycleCursor(sequence: 13, updatedAt: Date(timeIntervalSince1970: 13)),
            hasActivity: false,
            hasActiveContent: true,
            createIfNeeded: true
        )
        XCTAssertEqual(nextRequest.decision, .create)
    }

    func testIdleActivityCanBeCreatedOnlyByExplicitUserStart() {
        let cursor = LiveActivityLifecycleCursor(sequence: 1, updatedAt: Date())
        let automatic = LiveActivityLifecycle.transition(
            current: nil,
            incoming: cursor,
            hasActivity: false,
            hasActiveContent: false,
            createIfNeeded: true
        )
        XCTAssertEqual(automatic.decision, .ignore)

        let explicit = LiveActivityLifecycle.transition(
            current: nil,
            incoming: cursor,
            hasActivity: false,
            hasActiveContent: false,
            createIfNeeded: true,
            allowIdleCreation: true
        )
        XCTAssertEqual(explicit.decision, .create)
    }

    func testNewMacProcessSequenceEpochIsAcceptedButOldNetworkReplayIsNot() {
        let current = LiveActivityLifecycleCursor(
            sequence: 900,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let oldReplay = LiveActivityLifecycle.transition(
            current: current,
            incoming: LiveActivityLifecycleCursor(
                sequence: 899,
                updatedAt: Date(timeIntervalSince1970: 99)
            ),
            hasActivity: true,
            hasActiveContent: true,
            createIfNeeded: false
        )
        XCTAssertEqual(oldReplay.decision, .ignore)

        let afterMacRestart = LiveActivityLifecycle.transition(
            current: current,
            incoming: LiveActivityLifecycleCursor(
                sequence: 1,
                updatedAt: Date(timeIntervalSince1970: 103)
            ),
            hasActivity: true,
            hasActiveContent: true,
            createIfNeeded: false
        )
        XCTAssertEqual(afterMacRestart.decision, .update)
        XCTAssertEqual(afterMacRestart.cursor.sequence, 1)
    }
}
