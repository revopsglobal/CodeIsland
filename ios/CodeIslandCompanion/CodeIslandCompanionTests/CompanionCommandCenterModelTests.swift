import XCTest
@testable import CodeIslandCompanion

final class CompanionCommandCenterModelTests: XCTestCase {
    func testAttentionSelectionKeepsTheVisibleItemAcrossReorderedPolls() {
        XCTAssertEqual(
            CompanionAttentionSelection.resolve(
                previousID: "approval-a",
                currentIDs: ["question-b", "approval-a"]
            ),
            "approval-a"
        )
    }

    func testAttentionSelectionFallsBackOnlyWhenTheVisibleItemIsGone() {
        XCTAssertEqual(
            CompanionAttentionSelection.resolve(
                previousID: "approval-a",
                currentIDs: ["question-b", "approval-c"]
            ),
            "question-b"
        )
        XCTAssertNil(
            CompanionAttentionSelection.resolve(
                previousID: "approval-a",
                currentIDs: []
            )
        )
    }

    func testMotionPolicyKeepsRoutinePollsVisuallyInert() {
        XCTAssertFalse(CompanionMotionPolicy.animatesRoutinePoll)
        XCTAssertTrue(
            CompanionMotionPolicy.shouldAnimateNewAttention(
                previousIDs: ["approval-a"],
                currentIDs: ["approval-a", "question-b"],
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            CompanionMotionPolicy.shouldAnimateNewAttention(
                previousIDs: ["approval-a", "question-b"],
                currentIDs: ["question-b", "approval-a"],
                reduceMotion: false
            ),
            "Reordering the same requests during a poll must not animate or rotate the stage"
        )
        XCTAssertFalse(
            CompanionMotionPolicy.shouldAnimateNewAttention(
                previousIDs: ["approval-a"],
                currentIDs: ["approval-a", "question-b"],
                reduceMotion: true
            )
        )
    }

    func testSessionOrderingDoesNotRotateRoutineHeartbeatUpdates() {
        let olderRunning = session(id: "codex", status: .running, updatedAt: 100)
        let newerRunning = session(id: "claude", status: .running, updatedAt: 200)

        XCTAssertEqual(
            CompanionSessionOrdering.ordered([newerRunning, olderRunning]).map(\.id),
            ["claude", "codex"]
        )
        XCTAssertEqual(
            CompanionSessionOrdering.ordered([olderRunning, newerRunning]).map(\.id),
            ["claude", "codex"],
            "Same-priority routine sessions must keep stable identity ordering instead of flipping when heartbeats alternate"
        )
    }

    func testSessionOrderingStillPrioritizesActionRequiredWork() {
        let running = session(id: "claude", status: .running, updatedAt: 300)
        let question = session(id: "question", status: .waitingQuestion, updatedAt: 100)
        let approval = session(id: "approval", status: .waitingApproval, updatedAt: 50)

        XCTAssertEqual(
            CompanionSessionOrdering.ordered([running, question, approval]).map(\.id),
            ["approval", "question", "claude"]
        )
    }

    private func session(id: String, status: CompanionStatus, updatedAt: TimeInterval) -> CompanionSessionPreview {
        CompanionSessionPreview(
            sessionId: id,
            source: id,
            status: status,
            toolName: nil,
            workspaceName: "ob1-app",
            message: nil,
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}
