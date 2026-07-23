import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class ClaudeRemoteTaskRunnerTests: XCTestCase {
    func testStartUsesStructuredStreamingAndForcesToolRequestsThroughStdioPolicy() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.makeTask()

        try fixture.runner.start(
            taskID: task.id,
            workspaceURL: fixture.workspaceURL,
            prompt: "Implement and test",
            attachments: []
        )

        let configuration = try XCTUnwrap(fixture.launcher.configurations.first)
        XCTAssertEqual(configuration.executableURL.path, "/usr/local/bin/claude")
        XCTAssertEqual(configuration.currentDirectoryURL, fixture.workspaceURL)
        XCTAssertTrue(configuration.arguments.contains("--permission-prompt-tool"))
        XCTAssertTrue(configuration.arguments.contains("stdio"))
        XCTAssertTrue(configuration.arguments.contains("--permission-mode"))
        XCTAssertTrue(configuration.arguments.contains("acceptEdits"))
        XCTAssertTrue(configuration.arguments.contains("--include-hook-events"))
        XCTAssertTrue(configuration.arguments.contains("--session-id"))
        XCTAssertFalse(configuration.arguments.contains("--dangerously-skip-permissions"))
        XCTAssertFalse(configuration.arguments.contains("bypassPermissions"))

        let settingsIndex = try XCTUnwrap(configuration.arguments.firstIndex(of: "--settings"))
        let settings = configuration.arguments[settingsIndex + 1]
        XCTAssertTrue(settings.contains("\"ask\""))
        XCTAssertTrue(settings.contains("Bash"))
        XCTAssertTrue(settings.contains("Edit"))

        let firstMessage = try fixture.handle.decodedLines().first
        let message = try XCTUnwrap(firstMessage?["message"] as? [String: Any])
        let content = try XCTUnwrap(message["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["text"] as? String, "Implement and test")

        fixture.emit(.initialization(sessionID: fixture.sessionID, cwd: fixture.workspaceURL.path))
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.state, .working)
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.providerSessionID, fixture.sessionID)
    }

    func testSafeToolsAutoContinueConsequentialActionNeedsApprovalAndOutsideEditIsDenied() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.startedTask()

        fixture.emit(.controlRequest(.init(
            requestID: "safe",
            toolName: "Bash",
            input: ["command": .string("swift test")],
            toolUseID: "tool-safe",
            blockedPath: nil,
            decisionReason: "Rule requires host review",
            requiresUserInteraction: false
        )))
        XCTAssertEqual(try fixture.handle.permissionBehavior(requestID: "safe"), "allow")

        fixture.emit(.controlRequest(.init(
            requestID: "commit",
            toolName: "Bash",
            input: ["command": .string("git commit -m done")],
            toolUseID: "tool-commit",
            blockedPath: nil,
            decisionReason: "Rule requires host review",
            requiresUserInteraction: false
        )))
        XCTAssertNil(try fixture.handle.permissionBehavior(requestID: "commit"))
        XCTAssertEqual(fixture.attention.last?.kind, .approval)
        XCTAssertEqual(fixture.attention.last?.taskID, task.id)
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.state, .needsYou)

        try fixture.runner.resolveApproval(requestID: "commit", decision: .approve)
        XCTAssertEqual(try fixture.handle.permissionBehavior(requestID: "commit"), "allow")
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.state, .working)

        let outside = fixture.root.appendingPathComponent("outside.swift")
        fixture.emit(.controlRequest(.init(
            requestID: "outside",
            toolName: "Edit",
            input: ["file_path": .string(outside.path)],
            toolUseID: "tool-outside",
            blockedPath: outside.path,
            decisionReason: "Outside working directory",
            requiresUserInteraction: false
        )))
        XCTAssertEqual(try fixture.handle.permissionBehavior(requestID: "outside"), "deny")
        XCTAssertThrowsError(
            try fixture.runner.resolveApproval(requestID: "outside", decision: .approve)
        )
    }

    func testSuccessfulResultVerifiesOnceAndCleansContext() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.startedTask()
        let file = fixture.workspaceURL.appendingPathComponent("App.swift")

        fixture.emit(.assistant(
            text: nil,
            toolUses: [
                .init(id: "edit-1", name: "Edit", input: ["file_path": .string(file.path)]),
                .init(id: "test-1", name: "Bash", input: ["command": .string("swift test")]),
            ],
            sessionID: fixture.sessionID
        ))
        fixture.emit(.toolResults([
            .init(toolUseID: "edit-1", isError: false, content: "Updated", exitCode: nil),
            .init(toolUseID: "test-1", isError: false, content: "Passed", exitCode: 0),
        ], sessionID: fixture.sessionID))
        let result = ClaudeResultEvent(
            subtype: "success",
            isError: false,
            result: "Done",
            sessionID: fixture.sessionID,
            permissionDenials: []
        )
        fixture.emit(.result(result))
        fixture.emit(.result(result))

        let summary = try XCTUnwrap(fixture.store.task(id: task.id)?.summary)
        XCTAssertEqual(summary.state, .verified)
        XCTAssertEqual(summary.latestSummary, "Claude completed the requested Edit & Test turn")
        XCTAssertEqual(summary.lastReceiptSequence, 5)
        XCTAssertEqual(summary.evidence?.checks.last?.command, "swift test")
        XCTAssertEqual(summary.evidence?.checks.last?.exitCode, 0)
        XCTAssertThrowsError(
            try fixture.runner.followUp(taskID: task.id, text: "duplicate", attachments: [])
        )
    }

    func testFollowUpUsesOpenStreamAndResumeUsesPersistedSessionAfterTermination() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.startedTask()

        try fixture.runner.followUp(taskID: task.id, text: "Also check the UI", attachments: [])
        XCTAssertEqual(fixture.launcher.configurations.count, 1)
        XCTAssertEqual(try fixture.handle.lastUserText(), "Also check the UI")

        fixture.launcher.terminateLatest(exitCode: 0)
        try fixture.runner.followUp(taskID: task.id, text: "Resume and finish", attachments: [])

        XCTAssertEqual(fixture.launcher.configurations.count, 2)
        let resumed = fixture.launcher.configurations[1].arguments
        let resumeIndex = try XCTUnwrap(resumed.firstIndex(of: "--resume"))
        XCTAssertEqual(resumed[resumeIndex + 1], fixture.sessionID)
        XCTAssertFalse(resumed.contains("--session-id"))
        XCTAssertEqual(try fixture.launcher.handles[1].lastUserText(), "Resume and finish")
    }

    func testMalformedUnknownAndUncorrelatedEventsDoNotAdvanceLedger() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.makeTask()
        try fixture.runner.start(
            taskID: task.id,
            workspaceURL: fixture.workspaceURL,
            prompt: task.request.prompt,
            attachments: []
        )

        fixture.launcher.emitStdout("not json")
        fixture.launcher.emitStdout(#"{"type":"future_event"}"#)

        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.state, .queued)
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.lastReceiptSequence, 1)
    }
}

@MainActor
private final class Fixture {
    let root: URL
    let workspaceURL: URL
    let store: RemoteTaskStore
    let launcher = TestClaudeProcessLauncher()
    var attention: [ClaudeRemoteTaskAttention] = []
    lazy var runner = ClaudeRemoteTaskRunner(
        launcher: launcher,
        store: store,
        executablePath: "/usr/local/bin/claude",
        sessionID: { [sessionID] in sessionID },
        onAttention: { [weak self] in self?.attention.append($0) }
    )
    let sessionID = "48baeb8e-a226-4670-8c64-badc83ce8566"

    var handle: TestClaudeProcessHandle { launcher.handles[0] }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandClaudeRunner-\(UUID().uuidString)", isDirectory: true)
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
                provider: .claude,
                authority: .editAndTest
            ),
            deviceID: "iphone-1"
        )
    }

    func startedTask() throws -> RemoteTaskRecord {
        let task = try makeTask()
        try runner.start(
            taskID: task.id,
            workspaceURL: workspaceURL,
            prompt: task.request.prompt,
            attachments: []
        )
        emit(.initialization(sessionID: sessionID, cwd: workspaceURL.path))
        return task
    }

    func emit(_ event: ClaudeStreamEvent) {
        runner.handle(event, taskID: store.tasks[0].id)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class TestClaudeProcessLauncher: ClaudeProcessLaunching {
    var configurations: [ClaudeProcessConfiguration] = []
    var handles: [TestClaudeProcessHandle] = []
    private var stdoutHandlers: [(String) -> Void] = []
    private var stderrHandlers: [(String) -> Void] = []
    private var terminationHandlers: [(Int32) -> Void] = []

    func launch(
        configuration: ClaudeProcessConfiguration,
        onStdoutLine: @escaping (String) -> Void,
        onStderrLine: @escaping (String) -> Void,
        onTermination: @escaping (Int32) -> Void
    ) throws -> ClaudeProcessHandling {
        configurations.append(configuration)
        let handle = TestClaudeProcessHandle()
        handles.append(handle)
        stdoutHandlers.append(onStdoutLine)
        stderrHandlers.append(onStderrLine)
        terminationHandlers.append(onTermination)
        return handle
    }

    func emitStdout(_ line: String, processIndex: Int = 0) {
        stdoutHandlers[processIndex](line)
    }

    func terminateLatest(exitCode: Int32) {
        let index = handles.count - 1
        handles[index].running = false
        terminationHandlers[index](exitCode)
    }
}

@MainActor
private final class TestClaudeProcessHandle: ClaudeProcessHandling {
    var lines: [String] = []
    var running = true

    var isRunning: Bool { running }

    func send(line: String) throws {
        lines.append(line)
    }

    func terminate() {
        running = false
    }

    func decodedLines() throws -> [[String: Any]] {
        try lines.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }

    func permissionBehavior(requestID: String) throws -> String? {
        for object in try decodedLines().reversed() {
            guard object["type"] as? String == "control_response",
                  let envelope = object["response"] as? [String: Any],
                  envelope["request_id"] as? String == requestID,
                  let result = envelope["response"] as? [String: Any]
            else { continue }
            return result["behavior"] as? String
        }
        return nil
    }

    func lastUserText() throws -> String? {
        for object in try decodedLines().reversed() where object["type"] as? String == "user" {
            let message = object["message"] as? [String: Any]
            let content = message?["content"] as? [[String: Any]]
            return content?.first?["text"] as? String
        }
        return nil
    }
}
