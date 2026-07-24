import CryptoKit
import Foundation
import XCTest
@testable import CodeIslandCompanion

@MainActor
final class VoiceTurnDraftStoreTests: XCTestCase {
    func testLiveKeychainBackedEncryptionKeyIsAvailable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AgentOpsVoiceDraftKeychain-\(UUID().uuidString)",
                isDirectory: true
            )
        let snapshot = root.appendingPathComponent("turns.enc")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        let store: VoiceTurnDraftStore
        do {
            store = try VoiceTurnDraftStore(snapshotURL: snapshot)
        } catch VoiceTurnDraftStoreError.encryptionUnavailable {
            throw XCTSkip(
                "The unsigned simulator test host has no Keychain entitlement."
            )
        }
        try store.save(.fixture())
        let reloaded = try VoiceTurnDraftStore(snapshotURL: snapshot)

        XCTAssertEqual(
            reloaded.drafts.first?.request.idempotencyKey,
            AgentOpsTurnRequest.fixture().idempotencyKey
        )
    }

    func testDraftIsEncryptedAndReloadsWithOriginalIdempotencyKey() throws {
        let fixture = try VoiceDraftFixture()
        defer { fixture.remove() }
        let request = AgentOpsTurnRequest.fixture()

        try fixture.store.save(request)

        let persisted = try Data(contentsOf: fixture.snapshot)
        XCTAssertFalse(
            String(decoding: persisted, as: UTF8.self).contains(request.transcript)
        )
        let reloaded = try fixture.reload()
        XCTAssertEqual(reloaded.drafts.map(\.request), [request])
        XCTAssertEqual(
            reloaded.drafts.first?.request.idempotencyKey,
            request.idempotencyKey
        )
    }

    func testRetryKeepsOriginalIdempotencyKeyAndDeletesOnlyAfterCompletedResult() throws {
        let fixture = try VoiceDraftFixture()
        defer { fixture.remove() }
        let request = AgentOpsTurnRequest.fixture()
        try fixture.store.save(request)
        let draft = try XCTUnwrap(fixture.store.drafts.first)

        XCTAssertEqual(fixture.store.replayRequest(for: draft.id), request)
        XCTAssertThrowsError(
            try fixture.store.finish(
                draftID: draft.id,
                result: .fixtureDurable(task: nil)
            )
        )
        XCTAssertEqual(fixture.store.drafts.count, 1)

        let taskID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        try fixture.store.finish(
            draftID: draft.id,
            result: .fixtureDurable(task: taskID)
        )
        XCTAssertTrue(fixture.store.drafts.isEmpty)
        XCTAssertTrue(try fixture.reload().drafts.isEmpty)
    }

    func testRepeatedSaveDeduplicatesByIdempotencyKey() throws {
        let fixture = try VoiceDraftFixture()
        defer { fixture.remove() }
        let request = AgentOpsTurnRequest.fixture()

        try fixture.store.save(request)
        try fixture.store.save(request)

        XCTAssertEqual(fixture.store.drafts.count, 1)
    }

    func testGatewayOutageKeepsDraftAndReplayUsesOriginalIdentity() async throws {
        let fixture = try VoiceDraftFixture()
        defer { fixture.remove() }
        let request = AgentOpsTurnRequest.fixture()
        let transport = DraftReplayTransport(
            responses: [
                .failure(URLError(.cannotConnectToHost)),
                .success(.fixtureDurable(
                    task: UUID(uuidString: "44444444-4444-4444-8444-444444444444")
                )),
            ]
        )
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: DraftReplayCredentials(),
            transport: transport
        )
        let tool = AgentOpsTurnTool(
            client: client,
            sessionID: request.sessionID,
            clientMetadata: request.client,
            draftStore: fixture.store,
            uuid: { request.turnID }
        )

        do {
            _ = try await tool.execute(
                callId: "offline-call",
                argumentsJSON: #"{"transcript":"Create a durable AgentOps task from this offline request."}"#
            )
            XCTFail("Expected the gateway outage")
        } catch {
            XCTAssertEqual(fixture.store.drafts.count, 1)
        }

        let saved = try XCTUnwrap(fixture.store.drafts.first)
        let replay = try await tool.replay(saved)
        XCTAssertEqual(replay.request.idempotencyKey, request.idempotencyKey)
        XCTAssertTrue(fixture.store.drafts.isEmpty)
        let bodies = await transport.requestBodies()
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(
            bodies.compactMap {
                try? JSONDecoder.agentOps.decode(
                    AgentOpsTurnRequest.self,
                    from: $0
                ).idempotencyKey
            },
            [request.idempotencyKey, request.idempotencyKey]
        )
    }
}

@MainActor
private final class VoiceDraftFixture {
    let root: URL
    let snapshot: URL
    let key = SymmetricKey(data: Data(repeating: 0x7a, count: 32))
    let store: VoiceTurnDraftStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentOpsVoiceDraft-\(UUID().uuidString)", isDirectory: true)
        snapshot = root.appendingPathComponent("turns.enc")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        store = try VoiceTurnDraftStore(snapshotURL: snapshot, key: key)
    }

    func reload() throws -> VoiceTurnDraftStore {
        try VoiceTurnDraftStore(snapshotURL: snapshot, key: key)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private extension AgentOpsTurnRequest {
    static func fixture() -> AgentOpsTurnRequest {
        let turnID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        return AgentOpsTurnRequest(
            sessionID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            turnID: turnID,
            idempotencyKey: turnID,
            transcript: "Create a durable AgentOps task from this offline request.",
            conversation: [],
            client: .init(
                platform: "ios",
                appVersion: "1.0",
                build: "4",
                locale: "en-US"
            )
        )
    }
}

private extension AgentOpsTurnResult {
    static func fixtureDurable(task id: UUID?) -> AgentOpsTurnResult {
        AgentOpsTurnResult(
            kind: .durableWork,
            speechText: "Captured.",
            displayText: "Captured.",
            sources: [],
            routingIntent: .init(
                mode: .auto,
                implementer: .claude,
                reviewer: "ringer",
                allowFallback: true,
                fallbackRuntime: .codex,
                reason: "Durable work"
            ),
            approvalTier: .routineVoice,
            executionBrief: nil,
            task: id.map {
                AgentOpsTurnTaskSummary(id: $0, title: "Task", status: "queued")
            },
            unavailableSources: []
        )
    }
}

@MainActor
private final class DraftReplayCredentials: AgentOpsCredentialProviding {
    func accessToken() async throws -> String { "access-token" }
    func refreshAccessToken() async throws -> String { "refreshed-token" }
    func forceSignOut() async {}
}

private actor DraftReplayTransport: AgentOpsTransport {
    private var responses: [Result<AgentOpsTurnResult, Error>]
    private var bodies: [Data] = []

    init(responses: [Result<AgentOpsTurnResult, Error>]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> AgentOpsTransportResponse {
        if let body = request.httpBody {
            bodies.append(body)
        }
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        switch responses.removeFirst() {
        case .success(let result):
            return AgentOpsTransportResponse(
                statusCode: 200,
                data: try JSONEncoder.agentOps.encode(result)
            )
        case .failure(let error):
            throw error
        }
    }

    func requestBodies() -> [Data] { bodies }
}
