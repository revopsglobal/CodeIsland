import Foundation
import XCTest
@testable import CodeIsland
import CodeIslandCore

final class SessionAttentionRouterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testEqualPriorityWorkDoesNotCarouselBetweenSessions() {
        let candidates = [
            SessionAttentionCandidate(id: "codex", status: .running, lastActivity: now),
            SessionAttentionCandidate(id: "claude", status: .running, lastActivity: now.addingTimeInterval(30)),
        ]

        XCTAssertEqual(
            SessionAttentionRouter.preferredSessionID(
                candidates: candidates,
                currentSessionID: "codex",
                selectedSessionID: "codex"
            ),
            "codex"
        )
    }

    func testApprovalImmediatelyPreemptsRoutineWork() {
        let candidates = [
            SessionAttentionCandidate(id: "codex", status: .running, lastActivity: now),
            SessionAttentionCandidate(id: "claude", status: .waitingApproval, lastActivity: now.addingTimeInterval(-30)),
        ]

        XCTAssertEqual(
            SessionAttentionRouter.preferredSessionID(
                candidates: candidates,
                currentSessionID: "codex",
                selectedSessionID: "codex"
            ),
            "claude"
        )
    }

    func testQuestionAndApprovalRemainPinnedUntilResolved() {
        let candidates = [
            SessionAttentionCandidate(id: "approval", status: .waitingApproval, lastActivity: now),
            SessionAttentionCandidate(id: "question", status: .waitingQuestion, lastActivity: now.addingTimeInterval(60)),
        ]

        XCTAssertEqual(
            SessionAttentionRouter.preferredSessionID(
                candidates: candidates,
                currentSessionID: "approval",
                selectedSessionID: "question"
            ),
            "approval"
        )
    }

    func testSelectedRoutineSessionIsUsedAfterAttentionItemResolves() {
        let candidates = [
            SessionAttentionCandidate(id: "codex", status: .running, lastActivity: now),
            SessionAttentionCandidate(id: "claude", status: .processing, lastActivity: now.addingTimeInterval(60)),
        ]

        XCTAssertEqual(
            SessionAttentionRouter.preferredSessionID(
                candidates: candidates,
                currentSessionID: "resolved-approval",
                selectedSessionID: "codex"
            ),
            "codex"
        )
    }
}
