import Foundation
import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class RemoteTaskStoreTests: XCTestCase {
    func testCreateReturnsExistingTaskForRepeatedIdempotencyKey() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let store = RemoteTaskStore(
            snapshotURL: fixture.snapshotURL,
            receiptsURL: fixture.receiptsURL,
            serverName: "Test Mac"
        )
        let request = makeRequest(prompt: "Add the task store")

        let first = try store.create(request, deviceID: "iphone-1")
        let repeated = try store.create(request, deviceID: "iphone-1")

        XCTAssertEqual(repeated.id, first.id)
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(try ledgerLines(at: fixture.receiptsURL).count, 1)
    }

    func testCreateReturnsCanonicalTaskForRepeatedAgentOpsTaskIDAcrossReload() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let agentOpsTaskID = UUID(uuidString: "59D447B5-46B7-455A-8D3C-48866F3B2519")!
        let firstStore = fixture.makeStore()
        let first = try firstStore.create(
            makeRequest(prompt: "First delivery", agentOpsTaskID: agentOpsTaskID),
            deviceID: "iphone-1"
        )
        let restarted = fixture.makeStore()
        let repeated = try restarted.create(
            makeRequest(prompt: "Retry delivery", agentOpsTaskID: agentOpsTaskID),
            deviceID: "iphone-1"
        )

        XCTAssertEqual(repeated.id, first.id)
        XCTAssertEqual(repeated.request.prompt, "First delivery")
        XCTAssertEqual(repeated.summary.agentOpsTaskID, agentOpsTaskID)
        XCTAssertEqual(restarted.tasks.count, 1)
        XCTAssertEqual(try ledgerLines(at: fixture.receiptsURL).count, 1)
    }

    func testReceiptSequenceIsMonotonicAndAppendOnly() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        let record = try store.create(makeRequest(), deviceID: "iphone-1")
        try store.append(receipt(taskID: record.id, sequence: 2, state: .working, kind: .started))

        XCTAssertThrowsError(
            try store.append(receipt(taskID: record.id, sequence: 2, state: .failed, kind: .failed))
        )
        XCTAssertEqual(try ledgerLines(at: fixture.receiptsURL).count, 2)
        XCTAssertEqual(store.task(id: record.id)?.summary.lastReceiptSequence, 2)
    }

    func testReloadRestoresTerminalAndNonTerminalTasks() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let initial = fixture.makeStore()
        let terminal = try initial.create(makeRequest(prompt: "Finish me"), deviceID: "iphone-1")
        let active = try initial.create(makeRequest(prompt: "Keep working"), deviceID: "iphone-1")
        try initial.append(receipt(taskID: terminal.id, sequence: 2, state: .verified, kind: .finished))

        let restarted = fixture.makeStore()

        XCTAssertEqual(restarted.task(id: terminal.id)?.summary.state, .verified)
        XCTAssertEqual(restarted.task(id: active.id)?.summary.state, .queued)
        XCTAssertEqual(restarted.tasks.count, 2)
    }

    func testOutOfOrderReceiptCannotRegressTaskState() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        let record = try store.create(makeRequest(), deviceID: "iphone-1")
        try store.append(receipt(taskID: record.id, sequence: 2, state: .working, kind: .started))

        XCTAssertThrowsError(
            try store.append(receipt(taskID: record.id, sequence: 1, state: .failed, kind: .failed))
        )
        XCTAssertEqual(store.task(id: record.id)?.summary.state, .working)
        XCTAssertEqual(store.task(id: record.id)?.summary.lastReceiptSequence, 2)
    }

    func testStoreNeverPersistsBearerOrActionTokens() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        let bearer = "private-bearer-123456"
        let actionToken = "private-action-654321"
        let record = try store.create(
            makeRequest(prompt: "Inspect with Bearer \(bearer) and actionToken=\(actionToken)"),
            deviceID: "iphone-1"
        )
        try store.append(
            RemoteTaskReceipt(
                taskID: record.id,
                sequence: 2,
                kind: .failed,
                state: .failed,
                summary: "Bearer \(bearer); action-token: \(actionToken)"
            )
        )

        let persisted = try String(contentsOf: fixture.snapshotURL, encoding: .utf8)
            + String(contentsOf: fixture.receiptsURL, encoding: .utf8)
        XCTAssertFalse(persisted.contains(bearer))
        XCTAssertFalse(persisted.contains(actionToken))
        XCTAssertTrue(persisted.contains("[REDACTED]"))
    }

    func testCorruptSnapshotIsQuarantinedWithoutDeletingReceiptLog() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        try Data("not-json".utf8).write(to: fixture.snapshotURL)
        let ledger = "{\"durable\":true}\n"
        try Data(ledger.utf8).write(to: fixture.receiptsURL)

        let store = fixture.makeStore()

        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertEqual(try String(contentsOf: fixture.receiptsURL, encoding: .utf8), ledger)
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
        XCTAssertTrue(names.contains(where: { $0.hasPrefix("tasks.json.corrupt-") }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.snapshotURL.path))
    }

    private func makeRequest(
        prompt: String = "Update focused tests",
        agentOpsTaskID: UUID? = nil
    ) -> RemoteTaskCreateRequest {
        RemoteTaskCreateRequest(
            clientTaskID: UUID(),
            idempotencyKey: UUID(),
            agentOpsTaskID: agentOpsTaskID,
            prompt: prompt,
            workspaceID: "workspace-1",
            provider: .codex,
            authority: .editAndTest,
            requestedProof: "Run the focused test"
        )
    }

    private func receipt(
        taskID: UUID,
        sequence: UInt64,
        state: RemoteTaskState,
        kind: RemoteTaskReceiptKind
    ) -> RemoteTaskReceipt {
        RemoteTaskReceipt(
            taskID: taskID,
            sequence: sequence,
            kind: kind,
            state: state,
            summary: state.rawValue
        )
    }

    private func ledgerLines(at url: URL) throws -> [Substring] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    }

    private func makeFixture() throws -> StoreFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandRemoteTaskStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return StoreFixture(root: root)
    }
}

private struct StoreFixture {
    let root: URL

    var snapshotURL: URL { root.appendingPathComponent("tasks.json") }
    var receiptsURL: URL { root.appendingPathComponent("receipts.jsonl") }

    @MainActor
    func makeStore() -> RemoteTaskStore {
        RemoteTaskStore(snapshotURL: snapshotURL, receiptsURL: receiptsURL, serverName: "Test Mac")
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
