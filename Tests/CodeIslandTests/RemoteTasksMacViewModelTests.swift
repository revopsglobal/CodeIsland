import CodeIslandCore
import Foundation
import XCTest
@testable import CodeIsland

final class RemoteTasksMacViewModelTests: XCTestCase {
    func testPortfolioRanksNeedsYouBeforeActiveAndCompletedWithoutChangingTaskIdentity() {
        let needsYou = task(state: .needsYou, seconds: 3)
        let failed = task(state: .failed, seconds: 4)
        let working = task(state: .working, seconds: 2)
        let verified = task(state: .verified, seconds: 1)

        let portfolio = RemoteTaskMacPortfolio.build(from: [verified, working, needsYou, failed])

        XCTAssertEqual(portfolio.needsYou.map(\.id), [failed.id, needsYou.id])
        XCTAssertEqual(portfolio.active.map(\.id), [working.id])
        XCTAssertEqual(portfolio.completed.map(\.id), [verified.id])
        XCTAssertEqual(Set((portfolio.needsYou + portfolio.active + portfolio.completed).map(\.id)),
                       Set([needsYou.id, failed.id, working.id, verified.id]))
    }

    func testExactProviderSessionWinsOverNewerWorkspaceCandidate() {
        let exact = RemoteTaskSessionCandidate(
            id: "codex-thread-exact",
            provider: "codex",
            workspacePath: "/work/app",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = RemoteTaskSessionCandidate(
            id: "codex-thread-newer",
            provider: "codex",
            workspacePath: "/work/app",
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            RemoteTaskOpenTargetResolver.resolve(
                providerSessionID: exact.id,
                provider: .codex,
                workspacePath: "/work/app",
                candidates: [newer, exact]
            ),
            exact.id
        )
    }

    func testWorkspaceFallbackNeverOpensAnotherProviderOrWorkspace() {
        let candidates = [
            RemoteTaskSessionCandidate(
                id: "claude-wrong-provider",
                provider: "claude",
                workspacePath: "/work/app",
                updatedAt: Date(timeIntervalSince1970: 200)
            ),
            RemoteTaskSessionCandidate(
                id: "codex-wrong-workspace",
                provider: "codex",
                workspacePath: "/work/other",
                updatedAt: Date(timeIntervalSince1970: 300)
            ),
            RemoteTaskSessionCandidate(
                id: "codex-correct",
                provider: "codex",
                workspacePath: "/work/app",
                updatedAt: Date(timeIntervalSince1970: 10)
            ),
        ]

        XCTAssertEqual(
            RemoteTaskOpenTargetResolver.resolve(
                providerSessionID: "missing",
                provider: .codex,
                workspacePath: "/work/app",
                candidates: candidates
            ),
            "codex-correct"
        )
        XCTAssertNil(RemoteTaskOpenTargetResolver.resolve(
            providerSessionID: "missing",
            provider: .codex,
            workspacePath: "/work/unknown",
            candidates: candidates
        ))
    }

    private func task(state: RemoteTaskState, seconds: TimeInterval) -> RemoteTaskSummary {
        let id = UUID()
        return RemoteTaskSummary(
            id: id,
            clientTaskID: id,
            idempotencyKey: UUID(),
            title: "Task \(state.rawValue)",
            workspaceID: "workspace",
            workspaceName: "CodeIsland",
            provider: .codex,
            authority: .editAndTest,
            state: state,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: seconds),
            lastReceiptSequence: 1
        )
    }
}
