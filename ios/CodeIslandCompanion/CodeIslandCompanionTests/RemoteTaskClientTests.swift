import Foundation
import XCTest
@testable import CodeIslandCompanion

@MainActor
final class RemoteTaskClientTests: XCTestCase {
    func testSyncAcceptsDraftUploadsAttachmentOnceAndPreservesClientIdentity() async throws {
        let fixture = try ClientFixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("context.txt")
        try Data("context".utf8).write(to: source)
        let draft = try fixture.client.enqueue(.init(
            prompt: "Implement and test",
            workspaceID: "workspace-a",
            provider: .codex,
            attachments: [.init(url: source, displayName: "context.txt", mediaType: "text/plain")]
        ))
        let host = fixture.summary(clientTaskID: draft.request.clientTaskID, idempotencyKey: draft.request.idempotencyKey)
        fixture.transport.responses = [
            .json(status: 201, host),
            .json(status: 200, host),
            .json(status: 200, fixture.snapshot([host])),
            .json(status: 200, fixture.snapshot([host])),
        ]

        XCTAssertEqual(fixture.client.localDrafts.first?.localState, .waitingForMac)
        let firstSync = await fixture.client.sync(baseURL: fixture.baseURL, bearerToken: "secret")
        XCTAssertEqual(firstSync, .success)
        XCTAssertTrue(fixture.client.localDrafts.isEmpty)
        XCTAssertEqual(fixture.client.tasks.first?.clientTaskID, draft.visibleID)

        let secondSync = await fixture.client.sync(
            baseURL: fixture.baseURL,
            bearerToken: "secret",
            force: true
        )
        XCTAssertEqual(secondSync, .success)
        let requests = fixture.transport.requests
        XCTAssertEqual(requests.filter { $0.httpMethod == "PUT" }.count, 1)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret" })
        let create = try XCTUnwrap(requests.first(where: { $0.httpMethod == "POST" }))
        let decoded = try fixture.decoder.decode(RemoteTaskCreateRequest.self, from: try XCTUnwrap(create.httpBody))
        XCTAssertEqual(decoded.idempotencyKey, draft.request.idempotencyKey)
    }

    func testUnauthorizedRequestsPairingRecoveryWithoutDeletingDraft() async throws {
        let fixture = try ClientFixture()
        defer { fixture.remove() }
        let draft = try fixture.client.enqueue(.init(
            prompt: "Keep this offline",
            workspaceID: "workspace-a",
            provider: .auto
        ))
        fixture.transport.responses = [.json(status: 401, ErrorPayload(error: "expired"))]

        let result = await fixture.client.sync(baseURL: fixture.baseURL, bearerToken: "expired")

        XCTAssertEqual(result, .pairingRequired)
        XCTAssertEqual(fixture.client.localDrafts.map(\.id), [draft.id])
        XCTAssertEqual(fixture.store.drafts.first?.request.idempotencyKey, draft.request.idempotencyKey)
    }

    func testConflictRefreshesHostSnapshotWithoutInventingDraftSuccess() async throws {
        let fixture = try ClientFixture()
        defer { fixture.remove() }
        let draft = try fixture.client.enqueue(.init(
            prompt: "Reconcile me",
            workspaceID: "workspace-a",
            provider: .claude
        ))
        let current = fixture.summary(
            clientTaskID: draft.request.clientTaskID,
            idempotencyKey: draft.request.idempotencyKey,
            state: .needsYou
        )
        fixture.transport.responses = [
            .json(status: 409, ErrorPayload(error: "stale")),
            .json(status: 200, fixture.snapshot([current])),
        ]

        let result = await fixture.client.sync(baseURL: fixture.baseURL, bearerToken: "secret")

        XCTAssertEqual(result, .conflict)
        XCTAssertEqual(fixture.client.tasks.first?.state, .needsYou)
        // The 409 itself does not claim success. The subsequent authenticated
        // snapshot confirms the matching client ID and replaces the draft with
        // the Mac's actual Needs You state.
        XCTAssertTrue(fixture.client.localDrafts.isEmpty)
    }

    func testRetryReusesPersistedIdempotencyKeyAfterTransportFailure() async throws {
        let fixture = try ClientFixture()
        defer { fixture.remove() }
        let draft = try fixture.client.enqueue(.init(
            prompt: "Retry safely",
            workspaceID: "workspace-a",
            provider: .codex
        ))
        fixture.transport.failuresRemaining = 1

        let failedSync = await fixture.client.sync(baseURL: fixture.baseURL, bearerToken: "secret")
        XCTAssertEqual(failedSync, .offline)
        let host = fixture.summary(clientTaskID: draft.visibleID, idempotencyKey: draft.request.idempotencyKey)
        fixture.transport.responses = [
            .json(status: 201, host),
            .json(status: 200, fixture.snapshot([host])),
        ]
        let retried = await fixture.client.sync(
            baseURL: fixture.baseURL,
            bearerToken: "secret",
            force: true
        )
        XCTAssertEqual(retried, .success)

        let posted = fixture.transport.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(posted.count, 2)
        for request in posted {
            let body = try XCTUnwrap(request.httpBody)
            XCTAssertEqual(
                try fixture.decoder.decode(RemoteTaskCreateRequest.self, from: body).idempotencyKey,
                draft.request.idempotencyKey
            )
        }
    }

    func testWorkspaceAndTaskOperationsUseAuthenticatedBoundRoutes() async throws {
        let fixture = try ClientFixture()
        defer { fixture.remove() }
        let task = fixture.summary(clientTaskID: UUID(), idempotencyKey: UUID(), state: .needsYou)
        let intent = RemoteTaskActionIntent(
            taskID: task.id,
            action: .commit,
            arguments: ["message": "Finish"],
            expectedReceiptSequence: task.lastReceiptSequence
        )
        let prepared = RemoteTaskPreparedAction(
            intent: intent,
            actionToken: "single-use-token",
            expiresAt: Date().addingTimeInterval(60),
            confirmationSummary: "Commit Finish"
        )
        fixture.transport.responses = [
            .json(status: 200, RemoteWorkspaceSnapshot(workspaces: [
                RemoteWorkspaceSummary(id: "workspace-a", name: "CodeIsland")
            ])),
            .json(status: 200, task),
            .json(status: 200, task),
            .json(status: 200, prepared),
            .json(status: 200, task),
        ]

        let workspaceResult = await fixture.client.refreshWorkspaces(baseURL: fixture.baseURL, bearerToken: "secret")
        XCTAssertEqual(workspaceResult, .success)
        XCTAssertEqual(fixture.client.workspaces.map(\.name), ["CodeIsland"])
        let followUpResult = await fixture.client.followUp(
            taskID: task.id,
            text: "Continue",
            baseURL: fixture.baseURL,
            bearerToken: "secret"
        )
        XCTAssertEqual(followUpResult, .success)
        let cancelResult = await fixture.client.cancel(
            taskID: task.id,
            baseURL: fixture.baseURL,
            bearerToken: "secret"
        )
        XCTAssertEqual(cancelResult, .success)
        let receivedPrepared = try await fixture.client.prepareAction(
            intent,
            baseURL: fixture.baseURL,
            bearerToken: "secret"
        )
        XCTAssertEqual(receivedPrepared, prepared)
        let executeResult = await fixture.client.executeAction(
            prepared,
            baseURL: fixture.baseURL,
            bearerToken: "secret"
        )
        XCTAssertEqual(executeResult, .success)

        XCTAssertEqual(fixture.transport.requests.map { $0.url?.path }, [
            "/api/tasks/workspaces",
            "/api/tasks/\(task.id.uuidString.lowercased())/follow-up",
            "/api/tasks/\(task.id.uuidString.lowercased())/cancel",
            "/api/tasks/\(task.id.uuidString.lowercased())/actions/prepare",
            "/api/tasks/\(task.id.uuidString.lowercased())/actions/execute",
        ])
        XCTAssertTrue(fixture.transport.requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret"
        })
    }
}

private struct ErrorPayload: Codable { let error: String }

@MainActor
private final class ClientFixture {
    let root: URL
    let store: RemoteTaskDraftStore
    let transport = MockTaskTransport()
    let client: RemoteTaskClient
    let baseURL = URL(string: "https://codeisland.test")!
    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandTaskClient-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = RemoteTaskDraftStore(
            snapshotURL: root.appendingPathComponent("drafts.json"),
            attachmentDirectory: root.appendingPathComponent("attachments")
        )
        client = RemoteTaskClient(store: store, transport: transport, monitorReachability: false)
    }

    func summary(
        clientTaskID: UUID,
        idempotencyKey: UUID,
        state: RemoteTaskState = .queued
    ) -> RemoteTaskSummary {
        RemoteTaskSummary(
            id: UUID(),
            clientTaskID: clientTaskID,
            idempotencyKey: idempotencyKey,
            title: "Implement and test",
            workspaceID: "workspace-a",
            workspaceName: "CodeIsland",
            provider: .codex,
            authority: .editAndTest,
            state: state,
            createdAt: Date(),
            updatedAt: Date(),
            lastReceiptSequence: 1,
            latestSummary: "Accepted by Mac"
        )
    }

    func snapshot(_ tasks: [RemoteTaskSummary]) -> RemoteTaskSnapshot {
        RemoteTaskSnapshot(serverName: "Test Mac", tasks: tasks)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
private final class MockTaskTransport: RemoteTaskTransport {
    var requests: [URLRequest] = []
    var responses: [RemoteTaskTransportResponse] = []
    var failuresRemaining = 0

    func data(for request: URLRequest) async throws -> RemoteTaskTransportResponse {
        requests.append(request)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw URLError(.notConnectedToInternet)
        }
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return responses.removeFirst()
    }
}

private extension RemoteTaskTransportResponse {
    static func json<T: Encodable>(status: Int, _ value: T) -> RemoteTaskTransportResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return RemoteTaskTransportResponse(statusCode: status, data: (try? encoder.encode(value)) ?? Data())
    }
}
