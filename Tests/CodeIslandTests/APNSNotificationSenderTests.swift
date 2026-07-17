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
    }
}
