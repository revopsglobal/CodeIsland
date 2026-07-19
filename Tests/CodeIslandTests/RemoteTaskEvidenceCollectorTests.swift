import XCTest
@testable import CodeIsland
import CodeIslandCore

final class RemoteTaskEvidenceCollectorTests: XCTestCase {
    func testCollectsRelativeGitBranchChangesAndChecks() throws {
        let runner = FakeEvidenceCommandRunner(result: .init(
            exitCode: 0,
            stdout: "## codex/example...origin/main\n M Sources/App.swift\n?? Tests/NewTests.swift\nR  Old.swift -> New.swift\n",
            stderr: ""
        ))
        let collector = RemoteTaskEvidenceCollector(commandRunner: runner)

        let evidence = try collector.collect(
            workspaceURL: URL(fileURLWithPath: "/tmp/workspace"),
            reportedChecks: [.init(command: "swift test", exitCode: 0, summary: "12 passed")]
        )

        XCTAssertEqual(evidence.branch, "codex/example")
        XCTAssertEqual(evidence.changedFiles, [
            .init(path: "Sources/App.swift", kind: .modified),
            .init(path: "Tests/NewTests.swift", kind: .added),
            .init(path: "New.swift", kind: .renamed, previousPath: "Old.swift"),
        ])
        XCTAssertEqual(evidence.checks.first?.exitCode, 0)
        XCTAssertEqual(evidence.sourceState, .edited)
        XCTAssertEqual(runner.invocations.first?.executable, "/usr/bin/git")
        XCTAssertEqual(runner.invocations.first?.arguments, ["-C", "/tmp/workspace", "status", "--porcelain=v1", "--branch"])
    }

    func testRedactsSecretsAndCapsProviderEvidence() throws {
        let runner = FakeEvidenceCommandRunner(result: .init(exitCode: 0, stdout: "## main\n", stderr: ""))
        let collector = RemoteTaskEvidenceCollector(commandRunner: runner, maximumTextLength: 64)
        let secret = "Authorization: Bearer super-secret-token " + String(repeating: "x", count: 300)

        let evidence = try collector.collect(
            workspaceURL: URL(fileURLWithPath: "/tmp/workspace"),
            reportedChecks: [.init(command: secret, exitCode: 1, summary: secret)],
            warnings: ["action_token=private-value " + String(repeating: "w", count: 300)]
        )

        let encoded = String(data: try JSONEncoder().encode(evidence), encoding: .utf8) ?? ""
        XCTAssertFalse(encoded.contains("super-secret-token"))
        XCTAssertFalse(encoded.contains("private-value"))
        XCTAssertLessThanOrEqual(evidence.checks[0].command.count, 64)
        XCTAssertLessThanOrEqual(evidence.checks[0].summary.count, 64)
        XCTAssertLessThanOrEqual(evidence.warnings[0].count, 64)
    }

    func testDoesNotCollapseCommittedPushedMergedOrDeployedIntoDone() throws {
        let runner = FakeEvidenceCommandRunner(result: .init(exitCode: 0, stdout: "## main\n", stderr: ""))
        let collector = RemoteTaskEvidenceCollector(commandRunner: runner)

        for state in [RemoteTaskSourceState.committed, .pushed, .merged, .deployed] {
            let evidence = try collector.collect(
                workspaceURL: URL(fileURLWithPath: "/tmp/workspace"),
                sourceState: state
            )
            XCTAssertEqual(evidence.sourceState, state)
        }
    }
}

private final class FakeEvidenceCommandRunner: RemoteTaskEvidenceCommandRunning {
    struct Invocation: Equatable {
        let executable: String
        let arguments: [String]
    }

    let result: RemoteTaskEvidenceCommandResult
    var invocations: [Invocation] = []

    init(result: RemoteTaskEvidenceCommandResult) {
        self.result = result
    }

    func run(executable: String, arguments: [String], currentDirectoryURL: URL) throws -> RemoteTaskEvidenceCommandResult {
        invocations.append(.init(executable: executable, arguments: arguments))
        return result
    }
}
