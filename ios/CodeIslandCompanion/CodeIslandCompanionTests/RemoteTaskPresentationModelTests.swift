import XCTest
@testable import CodeIslandCompanion

final class RemoteTaskPresentationModelTests: XCTestCase {
    func testSignalRankingMatchesAttentionContract() {
        let now = Date()
        let tasks = [
            task(id: "10000000-0000-0000-0000-000000000001", state: .working, updatedAt: now),
            task(id: "10000000-0000-0000-0000-000000000002", state: .verified, updatedAt: now),
            task(id: "10000000-0000-0000-0000-000000000003", state: .failed, updatedAt: now),
            task(id: "10000000-0000-0000-0000-000000000004", state: .needsYou, updatedAt: now),
        ]

        let candidates = RemoteTaskPresentationModel.candidates(
            approvalIDs: ["approval-z"],
            questionIDs: ["question-a"],
            tasks: tasks,
            drafts: [],
            followedTaskID: tasks[0].id,
            reviewedVerifiedTaskIDs: []
        )

        XCTAssertEqual(candidates.map(\.kind), [
            .approval, .question, .needsYou, .failed, .followed, .verified,
        ])
    }

    func testEqualPrioritySelectionIsStickyAcrossRoutinePollReordering() {
        let tasks = [
            task(id: "10000000-0000-0000-0000-000000000002", state: .working),
            task(id: "10000000-0000-0000-0000-000000000001", state: .working),
        ]
        let first = RemoteTaskPresentationModel.candidates(
            approvalIDs: [],
            questionIDs: [],
            tasks: tasks,
            drafts: [],
            followedTaskID: nil,
            reviewedVerifiedTaskIDs: []
        )

        XCTAssertEqual(first.map(\.id), [
            "task:10000000-0000-0000-0000-000000000001",
            "task:10000000-0000-0000-0000-000000000002",
        ])
        XCTAssertEqual(
            RemoteTaskPresentationModel.selection(previousID: first[1].id, candidates: first.reversed()),
            first[1].id
        )
    }

    func testHigherPrioritySignalPreemptsRoutineSelection() {
        let routine = RemoteTaskAttentionCandidate(id: "task:routine", kind: .working, priority: 40)
        let failed = RemoteTaskAttentionCandidate(id: "task:failed", kind: .failed, priority: 80)

        XCTAssertEqual(
            RemoteTaskPresentationModel.selection(previousID: routine.id, candidates: [routine, failed]),
            failed.id
        )
    }

    func testWaitingDraftIsVisibleButDoesNotOutrankFailure() {
        let input = RemoteTaskCreateRequest(
            clientTaskID: UUID(),
            idempotencyKey: UUID(),
            prompt: "Waiting task",
            workspaceID: "workspace",
            provider: .auto,
            authority: .editAndTest
        )
        let draft = RemoteTaskDraft(
            id: input.clientTaskID,
            request: input,
            attachments: [],
            hostTaskID: nil,
            localState: .waitingForMac,
            updatedAt: Date()
        )
        let failed = task(id: "10000000-0000-0000-0000-000000000003", state: .failed)

        let candidates = RemoteTaskPresentationModel.candidates(
            approvalIDs: [],
            questionIDs: [],
            tasks: [failed],
            drafts: [draft],
            followedTaskID: nil,
            reviewedVerifiedTaskIDs: []
        )

        XCTAssertEqual(candidates.map(\.kind), [.failed, .waitingForMac])
    }

    func testImmediateAttentionCountExcludesRoutineFollowedVerifiedAndWaitingWork() {
        let candidates = [
            RemoteTaskAttentionCandidate(id: "approval", kind: .approval, priority: 100),
            RemoteTaskAttentionCandidate(id: "question", kind: .question, priority: 100),
            RemoteTaskAttentionCandidate(id: "needs-you", kind: .needsYou, priority: 90),
            RemoteTaskAttentionCandidate(id: "failed", kind: .failed, priority: 80),
            RemoteTaskAttentionCandidate(id: "followed", kind: .followed, priority: 70),
            RemoteTaskAttentionCandidate(id: "verified", kind: .verified, priority: 60),
            RemoteTaskAttentionCandidate(id: "waiting", kind: .waitingForMac, priority: 50),
            RemoteTaskAttentionCandidate(id: "working", kind: .working, priority: 40),
        ]

        XCTAssertEqual(RemoteTaskPresentationModel.immediateAttentionCount(in: candidates), 4)
    }

    func testReviewedVerifiedTaskPersistenceRoundTripsAndRejectsMalformedValues() {
        let first = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let encoded = RemoteTaskReviewPersistence.encode([second, first])

        XCTAssertEqual(RemoteTaskReviewPersistence.decode(encoded), [first, second])
        XCTAssertEqual(RemoteTaskReviewPersistence.decode("not-json"), [])
    }

    private func task(
        id: String,
        state: RemoteTaskState,
        updatedAt: Date = Date()
    ) -> RemoteTaskSummary {
        let uuid = UUID(uuidString: id)!
        return RemoteTaskSummary(
            id: uuid,
            clientTaskID: uuid,
            idempotencyKey: UUID(),
            title: state.rawValue,
            workspaceID: "workspace",
            workspaceName: "CodeIsland",
            provider: .codex,
            authority: .editAndTest,
            state: state,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            lastReceiptSequence: 1
        )
    }
}
