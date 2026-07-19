import Foundation
import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class CodexRemoteTaskRunnerTests: XCTestCase {
    func testStartCorrelatesThreadAndTurnAndUsesIdempotencyKey() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.makeTask()

        try fixture.runner.start(
            taskID: task.id,
            workspaceURL: fixture.workspaceURL,
            prompt: "Implement and test",
            attachments: []
        )
        XCTAssertEqual(fixture.sender.requests.map(\.method), ["thread/start"])

        fixture.runner.handle(response(id: .int(1), result: ["thread": ["id": "thread-1"]]))
        XCTAssertEqual(fixture.sender.requests.map(\.method), ["thread/start", "turn/start"])
        let turnParams = try XCTUnwrap(fixture.sender.requests.last?.params as? [String: Any])
        XCTAssertEqual(turnParams["clientUserMessageId"] as? String, task.request.idempotencyKey.uuidString.lowercased())

        fixture.runner.handle(response(id: .int(2), result: [
            "turn": ["id": "turn-1", "items": [], "status": "inProgress"]
        ]))
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.state, .working)
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.providerSessionID, "thread-1")
    }

    func testUnknownResponseDoesNotMutateTask() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.makeTask()

        fixture.runner.handle(response(id: .int(999), result: ["thread": ["id": "wrong"]]))

        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.state, .queued)
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.lastReceiptSequence, 1)
        XCTAssertTrue(fixture.sender.requests.isEmpty)
    }

    func testCorrelatedAppServerErrorFailsOnlyItsTask() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.makeTask()
        try fixture.runner.start(
            taskID: task.id,
            workspaceURL: fixture.workspaceURL,
            prompt: task.request.prompt,
            attachments: []
        )

        fixture.runner.handle(error(id: .int(1), code: -32603, message: "launch failed"))

        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.state, .failed)
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.latestSummary, "Codex app-server error: launch failed")
    }

    func testCommandApprovalAllowsTestsButRoutesCommitToAttention() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.startedTask()

        fixture.runner.handle(request(id: .string("allow"), method: "item/commandExecution/requestApproval", params: [
            "threadId": "thread-1", "turnId": "turn-1", "itemId": "item-1",
            "startedAtMs": 1, "cwd": fixture.workspaceURL.path, "command": "swift test"
        ]))
        XCTAssertEqual(fixture.sender.decision(for: .string("allow")), "accept")

        fixture.runner.handle(request(id: .string("commit"), method: "item/commandExecution/requestApproval", params: [
            "threadId": "thread-1", "turnId": "turn-1", "itemId": "item-2",
            "startedAtMs": 2, "cwd": fixture.workspaceURL.path, "command": "git commit -m done"
        ]))
        XCTAssertNil(fixture.sender.decision(for: .string("commit")))
        XCTAssertEqual(fixture.attention.last?.kind, .approval)
        XCTAssertEqual(fixture.attention.last?.taskID, task.id)
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.state, .needsYou)

        try fixture.runner.resolveApproval(requestID: .string("commit"), decision: .approve)
        XCTAssertEqual(fixture.sender.decision(for: .string("commit")), "accept")
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.state, .working)
    }

    func testCommandOutsideSelectedWorkspaceIsDeclinedAndCannotBeApproved() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.startedTask()
        let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        fixture.runner.handle(request(id: .string("outside"), method: "item/commandExecution/requestApproval", params: [
            "threadId": "thread-1", "turnId": "turn-1", "itemId": "item-out",
            "startedAtMs": 1, "cwd": outside.path, "command": "swift test"
        ]))

        XCTAssertEqual(fixture.sender.decision(for: .string("outside")), "decline")
        XCTAssertEqual(fixture.attention.last?.taskID, task.id)
        XCTAssertThrowsError(
            try fixture.runner.resolveApproval(requestID: .string("outside"), decision: .approve)
        )
    }

    func testFileChangesAutoAcceptAndPermissionsAndQuestionsNeedAttention() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.startedTask()

        fixture.runner.handle(request(id: .string("file"), method: "item/fileChange/requestApproval", params: [
            "threadId": "thread-1", "turnId": "turn-1", "itemId": "item-f", "startedAtMs": 1
        ]))
        XCTAssertEqual(fixture.sender.decision(for: .string("file")), "accept")

        fixture.runner.handle(request(id: .string("permission"), method: "item/permissions/requestApproval", params: [
            "threadId": "thread-1", "turnId": "turn-1", "itemId": "item-p",
            "startedAtMs": 2, "cwd": fixture.workspaceURL.path, "permissions": ["network": ["enabled": true]]
        ]))
        fixture.runner.handle(request(id: .string("question"), method: "item/tool/requestUserInput", params: [
            "threadId": "thread-1", "turnId": "turn-1", "itemId": "item-q",
            "questions": [["id": "q1", "header": "Choice", "question": "Which option?"]]
        ]))

        XCTAssertEqual(fixture.attention.map(\.kind), [.permissions, .question])
        XCTAssertEqual(fixture.attention.map(\.taskID), [task.id, task.id])
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.state, .needsYou)
    }

    func testItemReceiptsAndTerminalTurnStatus() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.startedTask()

        fixture.runner.handle(notification(method: "item/completed", params: [
            "threadId": "thread-1", "turnId": "turn-1", "completedAtMs": 1,
            "item": ["id": "file-1", "type": "fileChange", "status": "completed", "changes": []]
        ]))
        fixture.runner.handle(notification(method: "item/completed", params: [
            "threadId": "thread-1", "turnId": "turn-1", "completedAtMs": 2,
            "item": ["id": "cmd-1", "type": "commandExecution", "status": "completed",
                     "command": "swift test", "commandActions": [], "cwd": fixture.workspaceURL.path,
                     "exitCode": 0, "durationMs": 140]
        ]))
        fixture.runner.handle(notification(method: "turn/completed", params: [
            "threadId": "thread-1",
            "turn": ["id": "turn-1", "items": [], "status": "completed"]
        ]))

        let summary = try XCTUnwrap(fixture.store.task(id: task.id)?.summary)
        XCTAssertEqual(summary.state, .verified)
        XCTAssertEqual(summary.lastReceiptSequence, 5)
        XCTAssertEqual(summary.evidence?.checks.last?.command, "swift test")
        XCTAssertEqual(summary.evidence?.checks.last?.exitCode, 0)
    }

    func testFollowUpInterruptAndInterruptedCompletion() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.startedTask()

        try fixture.runner.followUp(taskID: task.id, text: "Also run UI tests", attachments: [])
        XCTAssertEqual(fixture.sender.requests.last?.method, "turn/start")
        let params = try XCTUnwrap(fixture.sender.requests.last?.params as? [String: Any])
        XCTAssertNil(params["clientUserMessageId"])
        fixture.runner.handle(response(id: .int(3), result: [
            "turn": ["id": "turn-2", "items": [], "status": "inProgress"]
        ]))

        try fixture.runner.stop(taskID: task.id)
        XCTAssertEqual(fixture.sender.requests.last?.method, "turn/interrupt")
        fixture.runner.handle(notification(method: "turn/completed", params: [
            "threadId": "thread-1",
            "turn": ["id": "turn-2", "items": [], "status": "interrupted"]
        ]))

        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.state, .cancelled)
    }
}

@MainActor
private final class Fixture {
    let root: URL
    let workspaceURL: URL
    let store: RemoteTaskStore
    let sender = TestCodexSender()
    var attention: [CodexRemoteTaskAttention] = []
    lazy var runner = CodexRemoteTaskRunner(
        sender: sender,
        store: store,
        onAttention: { [weak self] in self?.attention.append($0) }
    )

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandCodexRunner-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        store = RemoteTaskStore(
            snapshotURL: root.appendingPathComponent("tasks.json"),
            receiptsURL: root.appendingPathComponent("receipts.jsonl"),
            serverName: "Test Mac"
        )
    }

    func makeTask() throws -> RemoteTaskRecord {
        try store.create(
            RemoteTaskCreateRequest(
                clientTaskID: UUID(),
                idempotencyKey: UUID(),
                prompt: "Implement and test",
                workspaceID: "workspace-1",
                provider: .codex,
                authority: .editAndTest
            ),
            deviceID: "iphone-1"
        )
    }

    func startedTask() throws -> RemoteTaskRecord {
        let task = try makeTask()
        try runner.start(taskID: task.id, workspaceURL: workspaceURL, prompt: task.request.prompt, attachments: [])
        runner.handle(response(id: .int(1), result: ["thread": ["id": "thread-1"]]))
        runner.handle(response(id: .int(2), result: [
            "turn": ["id": "turn-1", "items": [], "status": "inProgress"]
        ]))
        return task
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class TestCodexSender: CodexAppServerSending {
    struct Request {
        let id: CodexRequestID
        let method: String
        let params: Any?
    }

    var requests: [Request] = []
    var responses: [(id: CodexRequestID, result: Any?)] = []

    func sendRequest(method: String, params: Any?) throws -> CodexRequestID {
        let id = CodexRequestID.int(Int64(requests.count + 1))
        requests.append(Request(id: id, method: method, params: params))
        return id
    }

    func sendResponse(id: CodexRequestID, result: Any?) throws {
        responses.append((id, result))
    }

    func decision(for id: CodexRequestID) -> String? {
        (responses.last { $0.id == id }?.result as? [String: Any])?["decision"] as? String
    }
}

private func response(id: CodexRequestID, result: [String: Any]) -> CodexJSONRPCMessage {
    message(["id": id.jsonValue, "result": result])
}

private func request(id: CodexRequestID, method: String, params: [String: Any]) -> CodexJSONRPCMessage {
    message(["jsonrpc": "2.0", "id": id.jsonValue, "method": method, "params": params])
}

private func notification(method: String, params: [String: Any]) -> CodexJSONRPCMessage {
    message(["jsonrpc": "2.0", "method": method, "params": params])
}

private func error(id: CodexRequestID, code: Int, message errorMessage: String) -> CodexJSONRPCMessage {
    message(["id": id.jsonValue, "error": ["code": code, "message": errorMessage]])
}

private func message(_ value: [String: Any]) -> CodexJSONRPCMessage {
    let data = try! JSONSerialization.data(withJSONObject: value)
    return CodexAppServerClient.parseMessage(data)!
}
