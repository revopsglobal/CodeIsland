import XCTest
@testable import CodeIslandCompanion

final class CompanionCommandCenterModelTests: XCTestCase {
    func testRemoteTaskDeepLinksMapToStableNavigationDestinations() throws {
        let taskID = UUID()
        XCTAssertEqual(
            RemoteTaskDeepLinkDestination(route: .task(id: taskID)),
            .detail(taskID)
        )
        XCTAssertEqual(
            RemoteTaskDeepLinkDestination(route: .newTask(text: "Fix calendar access")),
            .composer(text: "Fix calendar access", provider: nil)
        )
        XCTAssertEqual(
            RemoteTaskDeepLinkDestination(route: .newTask(text: nil)),
            .composer(text: nil, provider: nil)
        )
        XCTAssertEqual(RemoteTaskDeepLinkDestination(route: .needsYou), .needsYou)
        XCTAssertEqual(RemoteTaskDeepLinkDestination(route: .sessions), .sessions)
        XCTAssertNil(RemoteTaskDeepLinkDestination(route: .pendingApproval(id: nil)))
    }

    func testAttentionSummaryUsesAuthoritativeRemoteQueueCounts() {
        XCTAssertEqual(
            CompanionAttentionSummary.resolve(
                approvalCount: 2,
                questionCount: 1,
                fallbackPendingAction: nil,
                fallbackWeather: "61° Clear"
            ),
            CompanionAttentionSummary(
                needsAttention: true,
                title: "Needs you",
                subtitle: "2 approvals and 1 question need you"
            )
        )
    }

    func testAttentionSummaryFallsBackToLocalPendingActionWhenRemoteQueueIsEmpty() {
        XCTAssertEqual(
            CompanionAttentionSummary.resolve(
                approvalCount: 0,
                questionCount: 0,
                fallbackPendingAction: .question,
                fallbackWeather: nil
            ),
            CompanionAttentionSummary(
                needsAttention: true,
                title: "Needs you",
                subtitle: "An agent is waiting for an answer"
            )
        )
    }

    func testAttentionSummaryShowsCalmWeatherWhenNothingNeedsAction() {
        XCTAssertEqual(
            CompanionAttentionSummary.resolve(
                approvalCount: 0,
                questionCount: 0,
                fallbackPendingAction: nil,
                fallbackWeather: "61° Clear · Ridgefield"
            ),
            CompanionAttentionSummary(
                needsAttention: false,
                title: "Today",
                subtitle: "61° Clear · Ridgefield"
            )
        )
    }

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

    func testAttentionSelectionPrefersDeepLinkedItemOverPreviousRoutineSelection() {
        XCTAssertEqual(
            CompanionAttentionSelection.resolve(
                previousID: "approval-a",
                preferredID: "question-b",
                currentIDs: ["approval-a", "question-b"]
            ),
            "question-b",
            "A Telegram, push, or App Intent deep link must bring the requested attention item to the stage instead of preserving the old card."
        )
        XCTAssertEqual(
            CompanionAttentionSelection.resolve(
                previousID: "approval-a",
                preferredID: "missing-question",
                currentIDs: ["approval-a", "question-b"]
            ),
            "approval-a",
            "Stale deep links should not discard the currently visible valid attention item."
        )
    }

    func testGenericTelegramPendingDeepLinkTargetsFirstSnapshotItemAfterColdOpen() {
        XCTAssertEqual(
            RemoteApprovalClient.genericPendingDeepLinkTarget(
                kind: .approval,
                approvalIDs: ["approval-a", "approval-b"],
                questionIDs: ["question-a"]
            ),
            "approval-a"
        )
        XCTAssertEqual(
            RemoteApprovalClient.genericPendingDeepLinkTarget(
                kind: .question,
                approvalIDs: ["approval-a"],
                questionIDs: ["question-a", "question-b"]
            ),
            "question-a"
        )
        XCTAssertNil(
            RemoteApprovalClient.genericPendingDeepLinkTarget(
                kind: .approval,
                approvalIDs: [],
                questionIDs: ["question-a"]
            ),
            "Generic approval links should not jump to questions when the approval queue is empty."
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
