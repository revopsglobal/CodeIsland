import XCTest
@testable import CodeIsland
import CodeIslandCore

final class APNSNotificationSenderTests: XCTestCase {
    func testPendingPayloadIsGenericAndOpaque() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = RemoteAttentionPushEnvelope(
            eventID: "event-approval",
            kind: .approval,
            state: .pending,
            requestID: "opaque-approval-id",
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(600)
        )

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: APNSNotificationPayloadBuilder.data(for: envelope)
            ) as? [String: Any]
        )
        let aps = try XCTUnwrap(object["aps"] as? [String: Any])
        let alert = try XCTUnwrap(aps["alert"] as? [String: String])
        XCTAssertEqual(alert["body"], "Open Buddy to review it privately.")
        XCTAssertEqual(object["ciRequestId"] as? String, "opaque-approval-id")
        XCTAssertEqual(object["approvalId"] as? String, "opaque-approval-id")
        XCTAssertNil(object["source"])
        XCTAssertNil(object["tool"])
        XCTAssertNil(object["detail"])
        XCTAssertNil(object["question"])
        XCTAssertEqual(APNSNotificationPayloadBuilder.pushType(for: envelope), "alert")
        XCTAssertEqual(APNSNotificationPayloadBuilder.priority(for: envelope), "10")
        XCTAssertTrue(
            APNSNotificationPayloadBuilder.usesVisibleNotificationFallback(
                for: envelope,
                hasPushToStartToken: false
            )
        )
        XCTAssertFalse(
            APNSNotificationPayloadBuilder.usesVisibleNotificationFallback(
                for: envelope,
                hasPushToStartToken: true
            ),
            "A push-to-start alert and a normal alert must never both notify the user"
        )
    }

    func testResolvedPayloadIsSilentAndSharesCollapseIdentity() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let pending = RemoteAttentionPushEnvelope(
            eventID: "event-pending",
            kind: .question,
            state: .pending,
            requestID: "opaque-question-id",
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(600)
        )
        let resolved = RemoteAttentionPushEnvelope(
            eventID: "event-resolved",
            kind: .question,
            state: .resolved,
            requestID: "opaque-question-id",
            issuedAt: issuedAt.addingTimeInterval(30),
            expiresAt: issuedAt.addingTimeInterval(90)
        )

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: APNSNotificationPayloadBuilder.data(for: resolved)
            ) as? [String: Any]
        )
        let aps = try XCTUnwrap(object["aps"] as? [String: Any])
        XCTAssertEqual((aps["content-available"] as? NSNumber)?.intValue, 1)
        XCTAssertNil(aps["alert"])
        XCTAssertEqual(
            APNSNotificationPayloadBuilder.collapseID(for: pending),
            APNSNotificationPayloadBuilder.collapseID(for: resolved)
        )
        XCTAssertEqual(APNSNotificationPayloadBuilder.pushType(for: resolved), "background")
        XCTAssertEqual(APNSNotificationPayloadBuilder.priority(for: resolved), "5")
        XCTAssertFalse(
            APNSNotificationPayloadBuilder.usesVisibleNotificationFallback(
                for: resolved,
                hasPushToStartToken: false
            )
        )
    }

    func testPushToStartLiveActivityPayloadIsPrivateAndDecodable() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = RemoteAttentionPushEnvelope(
            eventID: "event-question",
            kind: .question,
            state: .pending,
            requestID: "opaque-question-id",
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(600)
        )

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: APNSNotificationPayloadBuilder.liveActivityStartData(for: envelope)
            ) as? [String: Any]
        )
        let aps = try XCTUnwrap(object["aps"] as? [String: Any])
        XCTAssertEqual(aps["event"] as? String, "start")
        XCTAssertEqual(aps["attributes-type"] as? String, "CodeIslandActivityAttributes")
        XCTAssertEqual((aps["input-push-token"] as? NSNumber)?.intValue, 1)
        let attributes = try XCTUnwrap(aps["attributes"] as? [String: Any])
        XCTAssertEqual(attributes["sessionId"] as? String, "opaque-question-id")
        let content = try XCTUnwrap(aps["content-state"] as? [String: Any])
        XCTAssertEqual(content["status"] as? String, "waitingQuestion")
        XCTAssertEqual(content["pendingAction"] as? String, "question")

        let text = try XCTUnwrap(String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8))
        XCTAssertFalse(text.contains("workspace"))
        XCTAssertFalse(text.contains("command"))
        XCTAssertFalse(text.contains("transcript"))
    }

    func testLiveActivityResolutionEndsAndDismissesTheMatchingActivity() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = RemoteAttentionPushEnvelope(
            eventID: "event-resolved",
            kind: .approval,
            state: .resolved,
            requestID: "opaque-approval-id",
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(60)
        )
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: APNSNotificationPayloadBuilder.liveActivityEndData(for: envelope)
            ) as? [String: Any]
        )
        let aps = try XCTUnwrap(object["aps"] as? [String: Any])
        XCTAssertEqual(aps["event"] as? String, "end")
        XCTAssertNotNil(aps["dismissal-date"])
        let content = try XCTUnwrap(aps["content-state"] as? [String: Any])
        XCTAssertEqual(content["status"] as? String, "idle")
    }

    func testTelegramFallbackMessageIsAttentionOnlyAndRedacted() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = RemoteAttentionPushEnvelope(
            eventID: "event-approval",
            kind: .approval,
            state: .pending,
            requestID: "opaque-approval-id",
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(600)
        )

        let message = TelegramAttentionMessageBuilder.message(
            for: envelope,
            remoteURL: URL(string: "https://gregs-mac.tailnet.example"),
            buddyURL: PersonalHubDeepLink.pendingApproval(id: nil).url,
            testFlightURL: URL(string: "itms-beta://")
        )

        XCTAssertTrue(message.contains("CodeIsland needs your approval."))
        XCTAssertTrue(message.contains("Buddy: codeisland://approvals/pending"))
        XCTAssertTrue(message.contains("Web fallback: https://gregs-mac.tailnet.example"))
        XCTAssertTrue(message.contains("If Buddy is stale: update CodeIsland Buddy in TestFlight itms-beta://"))
        XCTAssertFalse(message.contains("opaque-approval-id"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("command"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("transcript"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("workspace"))
    }

    func testTelegramFallbackMessageDoesNotRequireLink() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = RemoteAttentionPushEnvelope(
            eventID: "event-question",
            kind: .question,
            state: .pending,
            requestID: "opaque-question-id",
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(600)
        )

        let message = TelegramAttentionMessageBuilder.message(
            for: envelope,
            remoteURL: nil,
            buddyURL: PersonalHubDeepLink.pendingQuestion(id: nil).url,
            testFlightURL: URL(string: "itms-beta://")
        )

        XCTAssertEqual(
            message,
            """
            CodeIsland needs your answer.
            Open Buddy to review the private details.
            Buddy: codeisland://questions/pending
            If Buddy is stale: update CodeIsland Buddy in TestFlight itms-beta://
            """
        )
    }

    func testTelegramFallbackTestMessageUsesSameRedactedShape() throws {
        let message = TelegramAttentionMessageBuilder.testMessage(
            remoteURL: URL(string: "https://gregs-mac.tailnet.example"),
            buddyURL: PersonalHubDeepLink.pendingQuestion(id: nil).url,
            testFlightURL: URL(string: "itms-beta://")
        )

        XCTAssertTrue(message.contains("CodeIsland needs your answer."))
        XCTAssertTrue(message.contains("Open Buddy to review the private details."))
        XCTAssertTrue(message.contains("Buddy: codeisland://questions/pending"))
        XCTAssertTrue(message.contains("Web fallback: https://gregs-mac.tailnet.example"))
        XCTAssertTrue(message.contains("If Buddy is stale: update CodeIsland Buddy in TestFlight itms-beta://"))
        XCTAssertFalse(message.contains("telegram-test"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("command"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("transcript"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("workspace"))
    }
}
