import XCTest
@testable import CodeIsland

final class ClaudeStreamEventTests: XCTestCase {
    func testParsesInitializationAssistantAndToolUse() throws {
        let initLine = #"{"type":"system","subtype":"init","cwd":"/tmp/work","session_id":"session-1"}"#
        XCTAssertEqual(
            ClaudeStreamEvent.parse(line: initLine),
            .initialization(sessionID: "session-1", cwd: "/tmp/work")
        )

        let assistantLine = #"{"type":"assistant","session_id":"session-1","message":{"role":"assistant","content":[{"type":"text","text":"Working"},{"type":"tool_use","id":"tool-1","name":"Edit","input":{"file_path":"/tmp/work/App.swift","old_string":"a","new_string":"b"}}]}}"#
        XCTAssertEqual(
            ClaudeStreamEvent.parse(line: assistantLine),
            .assistant(
                text: "Working",
                toolUses: [
                    ClaudeToolUse(
                        id: "tool-1",
                        name: "Edit",
                        input: [
                            "file_path": .string("/tmp/work/App.swift"),
                            "old_string": .string("a"),
                            "new_string": .string("b"),
                        ]
                    )
                ],
                sessionID: "session-1"
            )
        )
    }

    func testParsesPermissionControlRequestAndEncodesResponses() throws {
        let line = #"{"type":"control_request","request_id":"request-1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"swift test"},"decision_reason_type":"rule","tool_use_id":"tool-1"}}"#
        XCTAssertEqual(
            ClaudeStreamEvent.parse(line: line),
            .controlRequest(
                ClaudeControlPermissionRequest(
                    requestID: "request-1",
                    toolName: "Bash",
                    input: ["command": .string("swift test")],
                    toolUseID: "tool-1",
                    blockedPath: nil,
                    decisionReason: nil,
                    requiresUserInteraction: false
                )
            )
        )

        let allow = try ClaudeControlPermissionResponse.allow(
            requestID: "request-1",
            toolUseID: "tool-1"
        ).jsonLine()
        let allowObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(allow.utf8)) as? [String: Any]
        )
        let allowEnvelope = try XCTUnwrap(allowObject["response"] as? [String: Any])
        let allowResult = try XCTUnwrap(allowEnvelope["response"] as? [String: Any])
        XCTAssertEqual(allowEnvelope["subtype"] as? String, "success")
        XCTAssertEqual(allowEnvelope["request_id"] as? String, "request-1")
        XCTAssertEqual(allowResult["behavior"] as? String, "allow")
        XCTAssertEqual(allowResult["toolUseID"] as? String, "tool-1")

        let deny = try ClaudeControlPermissionResponse.deny(
            requestID: "request-1",
            toolUseID: "tool-1",
            message: "Outside workspace"
        ).jsonLine()
        let denyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(deny.utf8)) as? [String: Any]
        )
        let denyEnvelope = try XCTUnwrap(denyObject["response"] as? [String: Any])
        let denyResult = try XCTUnwrap(denyEnvelope["response"] as? [String: Any])
        XCTAssertEqual(denyResult["behavior"] as? String, "deny")
        XCTAssertEqual(denyResult["message"] as? String, "Outside workspace")
    }

    func testParsesToolResultHooksPermissionDenialAndResult() throws {
        let toolResult = #"{"type":"user","session_id":"session-1","message":{"role":"user","content":[{"tool_use_id":"tool-1","type":"tool_result","content":"Exit code 0\nAll tests passed","is_error":false}]},"tool_use_result":{"stdout":"All tests passed","stderr":"","exitCode":0}}"#
        XCTAssertEqual(
            ClaudeStreamEvent.parse(line: toolResult),
            .toolResults([
                ClaudeToolResult(
                    toolUseID: "tool-1",
                    isError: false,
                    content: "Exit code 0\nAll tests passed",
                    exitCode: 0
                )
            ], sessionID: "session-1")
        )

        let hook = #"{"type":"system","subtype":"hook_started","hook_name":"PreToolUse:Bash","session_id":"session-1"}"#
        XCTAssertEqual(
            ClaudeStreamEvent.parse(line: hook),
            .hook(subtype: "hook_started", hookName: "PreToolUse:Bash", sessionID: "session-1")
        )

        let denied = #"{"type":"system","subtype":"permission_denied","tool_name":"Bash","tool_use_id":"tool-2","message":"Denied","session_id":"session-1"}"#
        XCTAssertEqual(
            ClaudeStreamEvent.parse(line: denied),
            .permissionDenied(
                toolName: "Bash",
                toolUseID: "tool-2",
                message: "Denied",
                sessionID: "session-1"
            )
        )

        let result = #"{"type":"result","subtype":"success","is_error":false,"result":"Done","session_id":"session-1","permission_denials":[]}"#
        XCTAssertEqual(
            ClaudeStreamEvent.parse(line: result),
            .result(
                ClaudeResultEvent(
                    subtype: "success",
                    isError: false,
                    result: "Done",
                    sessionID: "session-1",
                    permissionDenials: []
                )
            )
        )
    }

    func testMalformedAndUnknownLinesAreExplicitAndDoNotMasqueradeAsEvents() {
        XCTAssertEqual(ClaudeStreamEvent.parse(line: "not json"), .malformed)
        XCTAssertEqual(
            ClaudeStreamEvent.parse(line: #"{"type":"future_event","subtype":"new"}"#),
            .unknown(type: "future_event", subtype: "new")
        )
    }
}
