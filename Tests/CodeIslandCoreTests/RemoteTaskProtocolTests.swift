import Foundation
import XCTest
@testable import CodeIslandCore

final class RemoteTaskProtocolTests: XCTestCase {
    func testTaskLifecycleExposesOnlySupportedUserStates() {
        XCTAssertEqual(
            Set(RemoteTaskState.allCases),
            Set([.waitingForMac, .queued, .working, .needsYou, .verified, .failed, .cancelled])
        )
        XCTAssertEqual(RemoteTaskAuthority.allCases, [.editAndTest])
    }

    func testTaskActionBindingIsStableAcrossKeyOrder() {
        let taskID = UUID(uuidString: "2A26D59E-87DD-47F7-A7D5-A1A17CDBB6C6")!
        let first = RemoteTaskActionIntent(
            taskID: taskID,
            action: .commit,
            arguments: ["message": "Ship it", "branch": "codex/example"]
        )
        let second = RemoteTaskActionIntent(
            taskID: taskID,
            action: .commit,
            arguments: ["branch": "codex/example", "message": "Ship it"]
        )

        XCTAssertEqual(first.bindingID, second.bindingID)
        XCTAssertFalse(first.bindingID.isEmpty)
    }

    func testReceiptSequenceRejectsOlderState() throws {
        let taskID = UUID(uuidString: "6FDE42F1-B39A-488A-9FC8-4A747F0D7A03")!
        let idempotencyKey = UUID(uuidString: "B2C9ED95-7D0E-40F0-BC72-93B88F39A52E")!
        let base = RemoteTaskSummary(
            id: taskID,
            clientTaskID: taskID,
            idempotencyKey: idempotencyKey,
            title: "Update the tests",
            workspaceID: "workspace-1",
            workspaceName: "CodeIsland",
            provider: .codex,
            authority: .editAndTest,
            state: .working,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 110),
            lastReceiptSequence: 4
        )
        let stale = RemoteTaskReceipt(
            taskID: taskID,
            sequence: 3,
            kind: .failed,
            state: .failed,
            summary: "Old failure",
            observedAt: Date(timeIntervalSince1970: 105)
        )
        let current = RemoteTaskReceipt(
            taskID: taskID,
            sequence: 5,
            kind: .tested,
            state: .verified,
            summary: "Tests passed",
            observedAt: Date(timeIntervalSince1970: 120)
        )

        XCTAssertEqual(base.applying(stale), base)
        let updated = base.applying(current)
        XCTAssertEqual(updated.state, .verified)
        XCTAssertEqual(updated.lastReceiptSequence, 5)
        XCTAssertEqual(updated.updatedAt, current.observedAt)
    }

    func testTaskDeepLinkRoundTripsTaskAndNewTaskRoutes() throws {
        let taskID = UUID(uuidString: "9D27F862-A4DC-42BD-9A45-BE169EDBB48D")!
        let taskRoute = PersonalHubDeepLink.task(id: taskID)
        XCTAssertEqual(PersonalHubDeepLink(url: taskRoute.url), taskRoute)

        let newTask = PersonalHubDeepLink.newTask(text: "Fix calendar access", provider: .codex)
        XCTAssertEqual(PersonalHubDeepLink(url: newTask.url), newTask)
        XCTAssertEqual(
            newTask.url.absoluteString,
            "codeisland://new-task?text=Fix%20calendar%20access&provider=codex"
        )

        XCTAssertEqual(PersonalHubDeepLink(url: PersonalHubDeepLink.needsYou.url), .needsYou)
        XCTAssertEqual(PersonalHubDeepLink(url: PersonalHubDeepLink.sessions.url), .sessions)

        XCTAssertNil(PersonalHubDeepLink(url: URL(string: "codeisland://tasks/not-a-uuid")!))
        XCTAssertNil(PersonalHubDeepLink(url: URL(string: "codeisland://needs-you/unknown")!))
    }

    func testPushSummaryNeverIncludesPromptOrAttachmentName() throws {
        let taskID = UUID(uuidString: "AC8532BF-15A8-4934-B397-E8CEAB68C543")!
        let request = RemoteTaskCreateRequest(
            clientTaskID: taskID,
            idempotencyKey: UUID(uuidString: "D1BBD587-A8B8-42D1-8CC0-7AB794558385")!,
            prompt: "Fix the private payroll calculation",
            workspaceID: "workspace-1",
            provider: .auto,
            authority: .editAndTest,
            attachments: [
                RemoteTaskAttachmentDescriptor(
                    id: "attachment-1",
                    displayName: "private-payroll.csv",
                    byteCount: 42,
                    mediaType: "text/csv",
                    sha256: String(repeating: "a", count: 64)
                )
            ],
            requestedProof: "Run focused tests",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let summary = RemoteTaskPushSummary(taskID: request.clientTaskID, state: .needsYou)
        let data = try JSONEncoder().encode(summary)
        let encoded = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(encoded.contains(request.prompt))
        XCTAssertFalse(encoded.contains("private-payroll.csv"))
        XCTAssertFalse(encoded.contains("workspace-1"))
        XCTAssertTrue(encoded.contains(taskID.uuidString))
    }
}
