import XCTest
@testable import CodeIsland
import CodeIslandCore

final class APNSNotificationSenderTests: XCTestCase {
    func testDeliveryBatchContinuesAfterTargetFailureAndBoundsDiagnostics() async {
        var attemptedTargets: [Int] = []

        let result = await APNSDeliveryBatchRunner.run([1, 2, 3, 4, 5]) { target in
            attemptedTargets.append(target)
            guard target == 2 else {
                throw NSError(
                    domain: "APNSNotificationSenderTests",
                    code: target,
                    userInfo: [NSLocalizedDescriptionKey: "target failed"]
                )
            }
        }

        XCTAssertEqual(attemptedTargets, [1, 2, 3, 4, 5])
        XCTAssertEqual(result.successfulTargetCount, 1)
        XCTAssertEqual(result.failedTargetCount, 4)
        XCTAssertEqual(result.reportedFailureDescriptions, Array(repeating: "delivery failed", count: 3))
    }

    func testTaskNeedsYouPayloadIsGenericAndDeepLinkSafe() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let id = UUID()
        let envelope = RemoteAttentionPushEnvelope(
            kind: .task,
            state: .pending,
            requestID: id.uuidString.lowercased(),
            taskState: .needsYou,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(600)
        )
        let data = try APNSNotificationPayloadBuilder.data(
            for: envelope,
            pairingDeviceID: "paired-device-task"
        )
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let aps = try XCTUnwrap(object["aps"] as? [String: Any])
        XCTAssertNotNil(aps["alert"])
        XCTAssertEqual(object["ciTaskState"] as? String, "needs-you")
        XCTAssertEqual(object["ciPairingDeviceId"] as? String, "paired-device-task")
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("workspace"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("prompt"))

        let start = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: APNSNotificationPayloadBuilder.liveActivityStartData(
                for: envelope,
                pairingDeviceID: "paired-device-task"
            )
        ) as? [String: Any])
        let startAPS = try XCTUnwrap(start["aps"] as? [String: Any])
        let startAttributes = try XCTUnwrap(startAPS["attributes"] as? [String: Any])
        XCTAssertEqual(startAttributes["pairingDeviceID"] as? String, "paired-device-task")
        let content = try XCTUnwrap(startAPS["content-state"] as? [String: Any])
        XCTAssertEqual(content["taskID"] as? String, id.uuidString.lowercased())
        XCTAssertEqual(content["taskState"] as? String, "needs-you")
    }

    func testNormalAndPushToStartPayloadsAreScopedPerTargetDevice() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = RemoteAttentionPushEnvelope(
            kind: .approval,
            state: .pending,
            requestID: "approval-device-scope",
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(600)
        )

        let normalA = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: APNSNotificationPayloadBuilder.data(for: envelope, pairingDeviceID: "device-a")
        ) as? [String: Any])
        let normalB = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: APNSNotificationPayloadBuilder.data(for: envelope, pairingDeviceID: "device-b")
        ) as? [String: Any])
        XCTAssertEqual(normalA["ciPairingDeviceId"] as? String, "device-a")
        XCTAssertEqual(normalB["ciPairingDeviceId"] as? String, "device-b")

        let startA = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: APNSNotificationPayloadBuilder.liveActivityStartData(
                for: envelope,
                pairingDeviceID: "device-a"
            )
        ) as? [String: Any])
        let startB = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: APNSNotificationPayloadBuilder.liveActivityStartData(
                for: envelope,
                pairingDeviceID: "device-b"
            )
        ) as? [String: Any])
        let attributesA = try XCTUnwrap((startA["aps"] as? [String: Any])?["attributes"] as? [String: Any])
        let attributesB = try XCTUnwrap((startB["aps"] as? [String: Any])?["attributes"] as? [String: Any])
        XCTAssertEqual(attributesA["pairingDeviceID"] as? String, "device-a")
        XCTAssertEqual(attributesB["pairingDeviceID"] as? String, "device-b")
    }

    func testTaskVerifiedPayloadIsVisibleOnlyBecauseHostTargetsFollowedDevice() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = RemoteAttentionPushEnvelope(
            kind: .task,
            state: .resolved,
            requestID: UUID().uuidString.lowercased(),
            taskState: .verified,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(300)
        )
        XCTAssertTrue(APNSNotificationPayloadBuilder.isVisibleAlert(envelope))
        XCTAssertFalse(APNSNotificationPayloadBuilder.shouldPushToStart(envelope))
        XCTAssertEqual(APNSNotificationPayloadBuilder.pushType(for: envelope), "alert")
    }

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
                with: APNSNotificationPayloadBuilder.liveActivityStartData(
                    for: envelope,
                    pairingDeviceID: "paired-device-question"
                )
            ) as? [String: Any]
        )
        let aps = try XCTUnwrap(object["aps"] as? [String: Any])
        XCTAssertEqual(aps["event"] as? String, "start")
        XCTAssertEqual(aps["attributes-type"] as? String, "CodeIslandActivityAttributes")
        XCTAssertEqual((aps["input-push-token"] as? NSNumber)?.intValue, 1)
        let attributes = try XCTUnwrap(aps["attributes"] as? [String: Any])
        XCTAssertEqual(attributes["sessionId"] as? String, "opaque-question-id")
        XCTAssertEqual(attributes["pairingDeviceID"] as? String, "paired-device-question")
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

}
