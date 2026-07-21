import XCTest
@testable import CodeIsland
import CodeIslandCore

final class TelegramApprovalPresentationTests: XCTestCase {
    func testBashPushIsSummaryFirstWithExpandableExactCommand() throws {
        let fixture = Fixture()
        let presentation = try fixture.presentation(
            tool: "Bash",
            input: ["command": "git push origin main"]
        )

        XCTAssertEqual(presentation.headline, "Codex wants to push changes to GitHub")
        XCTAssertEqual(presentation.agent, "Codex")
        XCTAssertEqual(presentation.workspace, "CodeIsland")
        XCTAssertEqual(presentation.risk, .writes)
        XCTAssertFalse(presentation.summary.localizedCaseInsensitiveContains("git push"))
        XCTAssertTrue(presentation.details.contains { $0.label == "Command" && $0.value == "git push origin main" })
        XCTAssertEqual(presentation.changedScope, ["Branch: main", "Remote: origin"])
    }

    func testDestructiveCommandHasExplicitRiskReason() throws {
        let fixture = Fixture()
        let presentation = try fixture.presentation(
            tool: "Bash",
            input: ["command": "git push --force origin main"]
        )

        XCTAssertEqual(presentation.risk, .destructive)
        XCTAssertTrue(presentation.riskReason.localizedCaseInsensitiveContains("overwrite"))
    }

    func testWriteScopeIsStableAndSorted() throws {
        let fixture = Fixture()
        let presentation = try fixture.presentation(
            tool: "Write",
            input: [
                "path": "/tmp/z-last.txt",
                "file_path": "/tmp/a-first.txt",
                "content": "updated"
            ]
        )

        XCTAssertEqual(
            presentation.changedScope,
            ["File: /tmp/a-first.txt", "File: /tmp/z-last.txt"]
        )
    }

    func testCredentialValuesAreRedactedButBoundaryRemainsVisible() throws {
        let fixture = Fixture()
        let presentation = try fixture.presentation(
            tool: "Bash",
            input: [
                "command": "curl -H 'Authorization: Bearer abc123' https://example.com",
                "api_key": "super-secret-value"
            ]
        )
        let renderedDetails = presentation.details.map { "\($0.label): \($0.value)" }.joined(separator: "\n")

        XCTAssertFalse(renderedDetails.contains("abc123"))
        XCTAssertFalse(renderedDetails.contains("super-secret-value"))
        XCTAssertTrue(renderedDetails.contains("[REDACTED]"))
        XCTAssertTrue(renderedDetails.contains("Api key"))
    }

    func testPresentationCapsFieldsAndAggregatePayload() throws {
        let fixture = Fixture()
        var input: [String: Any] = ["content": String(repeating: "x", count: 30_000)]
        for index in 0..<80 {
            input["field_\(index)"] = String(repeating: "y", count: 1_000)
        }

        let presentation = try fixture.presentation(tool: "UnknownTool", input: input)
        let aggregate = presentation.details.reduce(0) { $0 + $1.label.count + $1.value.count }

        XCTAssertLessThanOrEqual(presentation.details.count, 30)
        XCTAssertTrue(presentation.details.allSatisfy { $0.label.count <= 80 && $0.value.count <= 4_000 })
        XCTAssertLessThanOrEqual(aggregate, 12_000)
    }

    func testFingerprintIsStableForSameActionAndChangesForDifferentRequest() throws {
        let fixture = Fixture()
        let first = try fixture.presentation(
            requestID: "request-1",
            tool: "Bash",
            input: ["command": "npm install yams"]
        )
        let repeated = try fixture.presentation(
            requestID: "request-1",
            tool: "Bash",
            input: ["command": "npm install yams"]
        )
        let different = try fixture.presentation(
            requestID: "request-2",
            tool: "Bash",
            input: ["command": "npm install yams"]
        )

        XCTAssertEqual(first.fingerprint, repeated.fingerprint)
        XCTAssertNotEqual(first.fingerprint, different.fingerprint)
    }
}

private struct Fixture {
    func presentation(
        requestID: String = "request-1",
        tool: String,
        input: [String: Any]
    ) throws -> TelegramApprovalPresentation {
        var payload: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": "session-1",
            "tool_name": tool,
            "tool_input": input,
            "_source": "codex"
        ]
        payload["tool_description"] = "Requested action"
        let data = try JSONSerialization.data(withJSONObject: payload)
        let event = try XCTUnwrap(HookEvent(from: data))
        let approval = RemoteApprovalItem(
            id: requestID,
            sessionId: "session-1",
            source: "Codex",
            tool: tool,
            detail: "Requested action",
            workspace: "CodeIsland",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            actionToken: "action-token",
            actionExpiresAt: Date(timeIntervalSince1970: 1_800_000_120),
            risk: CommandRiskClassifier.classify(
                toolName: tool,
                toolInput: input.mapValues { String(describing: $0) }
            )
        )
        return TelegramApprovalPresentationBuilder.build(
            requestID: requestID,
            event: event,
            approval: approval
        )
    }
}
