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

@MainActor
final class PersonalHubAttentionSnapshotTests: XCTestCase {
    func testAgentModuleShowsAttentionBeforeRoutineAndKeepsTotalsSecondary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandAttentionSnapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = PersonalHubConfigurationStore(
            stateURL: directory.appendingPathComponent("configuration.json")
        )
        let appState = AppState()

        var routine = SessionSnapshot(startTime: Date(timeIntervalSince1970: 100))
        routine.status = .running
        routine.lastActivity = Date(timeIntervalSince1970: 300)
        routine.source = "codex"
        var approval = SessionSnapshot(startTime: Date(timeIntervalSince1970: 90))
        approval.status = .waitingApproval
        approval.lastActivity = Date(timeIntervalSince1970: 200)
        approval.source = "claude"
        appState.sessions = ["routine": routine, "approval": approval]

        let snapshot = PersonalHubService(configurationStore: configuration).snapshot(
            appState: appState,
            requestedMode: .code,
            serverName: "Attention Test Mac"
        )
        let agents = try XCTUnwrap(snapshot.modules.first(where: { $0.id == .agents }))

        XCTAssertEqual(agents.items.map(\.id), ["approval", "routine"])
        XCTAssertEqual(agents.items.first?.subtitle, "Needs approval · Claude")
        XCTAssertEqual(agents.detail, "2 total sessions")
    }
}
