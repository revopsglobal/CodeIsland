import Foundation
import XCTest
@testable import CodeIsland

final class RemoteTaskExecutionPolicyTests: XCTestCase {
    func testAllowsOnlyBoundedReadEditTestFormatAndGitInspectionActions() throws {
        let fixture = try PolicyFixture()
        defer { fixture.remove() }
        let policy = fixture.policy()
        let allowed: [[String]] = [
            ["cat", "Sources/App.swift"],
            ["rg", "RemoteTask", "Sources"],
            ["swift", "test"],
            ["xcodebuild", "test", "-scheme", "CodeIsland"],
            ["npm", "test"],
            ["npm", "run", "test:unit"],
            ["pnpm", "test"],
            ["pytest", "Tests/test_remote.py"],
            ["cargo", "test"],
            ["go", "test", "./..."],
            ["swiftformat", "Sources"],
            ["prettier", "--write", "Sources/App.swift"],
            ["git", "status", "--short"],
            ["git", "diff", "--", "Sources/App.swift"],
            ["git", "log", "-3", "--oneline"],
        ]

        for command in allowed {
            XCTAssertEqual(
                policy.decision(for: .command(executable: command[0], arguments: Array(command.dropFirst()))),
                .allow,
                command.joined(separator: " ")
            )
        }
        XCTAssertEqual(
            policy.decision(for: .fileChange(url: fixture.workspace.appendingPathComponent("Sources/New.swift"))),
            .allow
        )
    }

    func testQuotedAbsoluteAndWrapperVariantsAreParsedStructurally() throws {
        let fixture = try PolicyFixture()
        defer { fixture.remove() }
        let policy = fixture.policy()

        XCTAssertEqual(policy.decision(for: .shell(#""/usr/bin/git" status --short"#)), .allow)
        XCTAssertEqual(policy.decision(for: .shell(#"/usr/bin/env git diff -- "Sources/App File.swift""#)), .allow)
        XCTAssertEqual(policy.decision(for: .shell("command swift test --filter RemoteTask")), .allow)
        XCTAssertEqual(policy.decision(for: .shell("xcrun xcodebuild test -scheme CodeIsland")), .allow)
    }

    func testConsequentialAndEnvironmentChangingCommandsNeedApproval() throws {
        let fixture = try PolicyFixture()
        defer { fixture.remove() }
        let policy = fixture.policy()
        let commands = [
            "git commit -m ship", "git push origin main", "git merge feature",
            "gh pr create --fill", "gh pr merge 42", "vercel deploy --prod",
            "fastlane release", "psql production -c 'delete from users'",
            "security add-generic-password -a greg", "gh auth login",
            "sendmail greg@example.com", "curl -X POST https://api.telegram.org",
            "brew install jq", "npm install left-pad", "pnpm add package",
            "pip install package", "cargo install tool", "tailscale up",
            "ssh deploy@example.com", "sudo swift test",
        ]

        for command in commands {
            XCTAssertEqual(policy.decision(for: .shell(command)), .needsApproval, command)
        }
    }

    func testCompoundAliasAndNewlineCommandsNeverAutoAllow() throws {
        let fixture = try PolicyFixture()
        defer { fixture.remove() }
        let policy = fixture.policy()
        let commands = [
            "swift test && git status",
            "git status; git diff",
            "pytest | tee results.txt",
            "git status\ngit diff",
            "FOO=bar swift test",
            "sh -c 'swift test'",
            "bash -lc \"git status\"",
        ]

        for command in commands {
            XCTAssertEqual(policy.decision(for: .shell(command)), .needsApproval, command)
        }
    }

    func testDenyCoversBroadDeletionOutsideWritesPhoneShellAndPermissionBypass() throws {
        let fixture = try PolicyFixture()
        defer { fixture.remove() }
        let policy = fixture.policy()

        XCTAssertEqual(policy.decision(for: .shell("rm -rf /")), .deny)
        XCTAssertEqual(policy.decision(for: .shell("/bin/rm -fr ~")), .deny)
        XCTAssertEqual(
            policy.decision(for: .fileChange(url: fixture.root.appendingPathComponent("outside.txt"))),
            .deny
        )
        XCTAssertEqual(policy.decision(for: .shell("swift test", origin: .phone)), .deny)
        XCTAssertEqual(
            policy.decision(for: .shell("claude --dangerously-skip-permissions -p fix")),
            .deny
        )
        XCTAssertEqual(
            policy.decision(for: .shell("claude --permission-mode bypassPermissions -p fix")),
            .deny
        )
    }

    func testWorkspaceBindingResolvesSymlinksAndComponentBoundaries() throws {
        let fixture = try PolicyFixture()
        defer { fixture.remove() }
        let outside = try fixture.directory("outside")
        let linked = fixture.workspace.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        let sibling = try fixture.directory("workspace-escape")
        let policy = fixture.policy()

        XCTAssertEqual(policy.decision(for: .fileRead(url: linked.appendingPathComponent("secret.txt"))), .deny)
        XCTAssertEqual(policy.decision(for: .fileChange(url: sibling.appendingPathComponent("changed.txt"))), .deny)
        XCTAssertEqual(policy.decision(for: .shell("cat ../outside/secret.txt")), .deny)
    }

    func testCodexRemoteSecurityConfigurationCannotInheritDangerousUserDefaults() throws {
        let fixture = try PolicyFixture()
        defer { fixture.remove() }
        let configuration = fixture.policy().codexConfiguration

        XCTAssertEqual(configuration.sandboxMode, "workspace-write")
        XCTAssertEqual(configuration.approvalPolicy, "on-request")
        XCTAssertFalse(configuration.networkAccessEnabled)
        XCTAssertTrue(configuration.developerInstructions.contains("commit"))
        XCTAssertEqual(
            CodexPermissionRules.remoteTaskDecision(
                command: "git status --short",
                workspaceURL: fixture.workspace
            ),
            .allow
        )
    }
}

private final class PolicyFixture {
    let root: URL
    let workspace: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandPolicy-\(UUID().uuidString)", isDirectory: true)
        workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    func policy() -> RemoteTaskExecutionPolicy {
        RemoteTaskExecutionPolicy(workspaceURL: workspace)
    }

    func directory(_ path: String) throws -> URL {
        let result = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
