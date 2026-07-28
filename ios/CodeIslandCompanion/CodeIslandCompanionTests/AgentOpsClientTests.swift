import Foundation
import XCTest
@testable import CodeIslandCompanion

@MainActor
final class AgentOpsClientTests: XCTestCase {
    func testUnauthorizedRefreshesAndRetriesExactlyOnce() async throws {
        let credentials = MockAgentOpsCredentials()
        let transport = MockAgentOpsTransport(responses: [
            .init(statusCode: 401, data: Data()),
            .json(status: 200, WorkEnvelope.empty),
        ])
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: credentials,
            transport: transport
        )

        let response: WorkEnvelope = try await client.request(path: "v1/work")

        XCTAssertEqual(response, .empty)
        XCTAssertEqual(credentials.refreshes, 1)
        XCTAssertEqual(credentials.signOuts, 0)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer expired")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer refreshed")
    }

    func testSecondUnauthorizedSignsOutWithoutThirdAttempt() async {
        let credentials = MockAgentOpsCredentials()
        let transport = MockAgentOpsTransport(responses: [
            .init(statusCode: 401, data: Data()),
            .init(statusCode: 401, data: Data()),
        ])
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: credentials,
            transport: transport
        )

        do {
            let _: WorkEnvelope = try await client.request(path: "v1/work")
            XCTFail("Expected unauthorized")
        } catch {
            XCTAssertEqual(error as? AgentOpsClientError, .unauthorized)
        }

        XCTAssertEqual(credentials.refreshes, 1)
        XCTAssertEqual(credentials.signOuts, 1)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)
    }

    func testBackgroundCancelsOnlyTheInFlightNetworkWait() async {
        let credentials = MockAgentOpsCredentials()
        let transport = MockAgentOpsTransport(responses: [], waitsForCancellation: true)
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: credentials,
            transport: transport
        )

        let requestTask = Task { () throws -> WorkEnvelope in
            try await client.request(path: "v1/work")
        }
        while await transport.capturedRequests().isEmpty {
            await Task.yield()
        }

        client.cancelNonessentialNetworkWork()

        do {
            _ = try await requestTask.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected. No server-side cancel route was called.
        } catch {
            XCTFail("Expected CancellationError, got \(type(of: error))")
        }
        let paths = await transport.capturedRequests().map(\.url?.path)
        XCTAssertEqual(paths, ["/v1/work"])
    }

    func testWorkApprovalAndEventModelsIgnoreAdditiveServerFields() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let work = try decoder.decode(AgentOpsWorkListResponse.self, from: Data(workJSON.utf8))
        XCTAssertEqual(work.tasks.first?.routing.mode, .locked)
        XCTAssertEqual(work.tasks.first?.proof.handles.first?.label, "PR 123")

        let approvals = try decoder.decode(
            AgentOpsApprovalListResponse.self,
            from: Data(approvalJSON.utf8)
        )
        XCTAssertEqual(approvals.approvals.first?.requiresExplicitTap, true)

        let event = try decoder.decode(AgentOpsEvent.self, from: Data(eventJSON.utf8))
        XCTAssertEqual(event.version, 9)
        XCTAssertEqual(event.payload["private"], .bool(true))
    }

    func testAgentOpsBaseURLIsNonSecretBuildConfiguration() throws {
        let testsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let project = testsURL
            .deletingLastPathComponent()
            .appendingPathComponent("project.yml")
        let source = try String(contentsOf: project, encoding: .utf8)
        XCTAssertTrue(source.contains("AGENTOPS_BASE_URL"))
        XCTAssertTrue(source.contains("https://voice.agentops.revopsglobal.com"))
        XCTAssertFalse(source.contains("AGENTOPS_ACCESS_TOKEN"))
        XCTAssertFalse(source.contains("AGENTOPS_REFRESH_TOKEN"))
    }

    func testEventStreamRequestUsesBearerCursorAndSSEAcceptHeader() async throws {
        let credentials = MockAgentOpsCredentials()
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: credentials
        )
        let cursor = "v1:1784846400000:33333333-3333-4333-8333-333333333333"

        let request = try await client.eventStreamRequest(
            cursor: cursor,
            refreshCredentials: true
        )

        XCTAssertEqual(request.url?.path, "/v1/events")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer refreshed"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Last-Event-ID"),
            cursor
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Accept"),
            "text/event-stream"
        )
        XCTAssertEqual(credentials.refreshes, 1)
    }

    func testResolveApprovalPostsExactDigestAndTapInteraction() async throws {
        let credentials = MockAgentOpsCredentials()
        let approvalID = UUID(
            uuidString: "22222222-2222-4222-8222-222222222222"
        )!
        let transport = MockAgentOpsTransport(responses: [
            .json(
                status: 200,
                AgentOpsApprovalResolutionResponse(
                    approvalId: approvalID,
                    status: .approved,
                    resolved: true
                )
            ),
        ])
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: credentials,
            transport: transport
        )
        let resolution = AgentOpsApprovalResolutionRequest(
            actionDigest: String(repeating: "a", count: 64),
            resolution: .approved,
            interaction: .onScreenTap,
            decisionNote: nil
        )

        _ = try await client.resolveApproval(
            id: approvalID,
            request: resolution
        )

        let requests = await transport.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.path,
            "/v1/approvals/\(approvalID.uuidString.lowercased())/resolve"
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                AgentOpsApprovalResolutionRequest.self,
                from: try XCTUnwrap(request.httpBody)
            ),
            resolution
        )
    }

    func testResolveApprovalReconcilesMatchingTerminalState() async throws {
        let approval = AgentOpsApprovalCard.testFixture(status: .approved)
        let transport = MockAgentOpsTransport(responses: [
            .json(
                status: 409,
                AgentOpsAPIError(
                    error: "approval_already_resolved",
                    retryable: false
                )
            ),
            .json(status: 200, ["approval": approval]),
        ])
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: MockAgentOpsCredentials(),
            transport: transport
        )
        let request = AgentOpsApprovalResolutionRequest(
            actionDigest: approval.actionDigest,
            resolution: .approved,
            interaction: .onScreenTap,
            decisionNote: nil
        )

        let response = try await client.resolveApproval(
            id: approval.id,
            request: request
        )

        XCTAssertEqual(response.status, .approved)
        XCTAssertTrue(response.resolved)
        let paths = await transport.capturedRequests().map(\.url?.path)
        XCTAssertEqual(paths, [
            "/v1/approvals/\(approval.id.uuidString.lowercased())/resolve",
            "/v1/approvals/\(approval.id.uuidString.lowercased())",
        ])
    }

    func testResolveApprovalKeepsPendingDecisionRetryable() async {
        let approval = AgentOpsApprovalCard.testFixture(status: .pending)
        let transport = MockAgentOpsTransport(responses: [
            .json(
                status: 503,
                AgentOpsAPIError(
                    error: "approval_resolution_unavailable",
                    retryable: true
                )
            ),
            .json(status: 200, ["approval": approval]),
        ])
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: MockAgentOpsCredentials(),
            transport: transport
        )
        let request = AgentOpsApprovalResolutionRequest(
            actionDigest: approval.actionDigest,
            resolution: .approved,
            interaction: .onScreenTap,
            decisionNote: nil
        )

        do {
            _ = try await client.resolveApproval(
                id: approval.id,
                request: request
            )
            XCTFail("Expected retryable pending decision")
        } catch {
            XCTAssertEqual(
                error as? AgentOpsClientError,
                .server(
                    code: "approval_resolution_not_recorded",
                    retryable: true
                )
            )
        }
    }

    func testResolveApprovalPreservesOppositeTerminalConflict() async {
        let approval = AgentOpsApprovalCard.testFixture(status: .rejected)
        let transport = MockAgentOpsTransport(responses: [
            .json(
                status: 409,
                AgentOpsAPIError(
                    error: "approval_already_resolved",
                    retryable: false
                )
            ),
            .json(status: 200, ["approval": approval]),
        ])
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: MockAgentOpsCredentials(),
            transport: transport
        )
        let request = AgentOpsApprovalResolutionRequest(
            actionDigest: approval.actionDigest,
            resolution: .approved,
            interaction: .onScreenTap,
            decisionNote: nil
        )

        do {
            _ = try await client.resolveApproval(
                id: approval.id,
                request: request
            )
            XCTFail("Expected confirmed terminal conflict")
        } catch {
            XCTAssertEqual(
                error as? AgentOpsClientError,
                .server(
                    code: "approval_already_resolved",
                    retryable: false
                )
            )
        }
    }

    func testResolveApprovalPreservesDeterministicDigestMismatch() async {
        let approval = AgentOpsApprovalCard.testFixture(status: .pending)
        let transport = MockAgentOpsTransport(responses: [
            .json(
                status: 409,
                AgentOpsAPIError(
                    error: "approval_digest_mismatch",
                    retryable: false
                )
            ),
        ])
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: MockAgentOpsCredentials(),
            transport: transport
        )
        let request = AgentOpsApprovalResolutionRequest(
            actionDigest: approval.actionDigest,
            resolution: .approved,
            interaction: .onScreenTap,
            decisionNote: nil
        )

        do {
            _ = try await client.resolveApproval(
                id: approval.id,
                request: request
            )
            XCTFail("Expected deterministic digest mismatch")
        } catch {
            XCTAssertEqual(
                error as? AgentOpsClientError,
                .server(
                    code: "approval_digest_mismatch",
                    retryable: false
                )
            )
        }
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testBoundedVoiceUsesAuthenticatedTranscriptionAndSpeechRoutes() async throws {
        let credentials = MockAgentOpsCredentials()
        let speech = Data([0x49, 0x44, 0x33, 0x04])
        let transport = MockAgentOpsTransport(responses: [
            .json(status: 200, ["text": "Canonical AgentOps request."]),
            .init(statusCode: 200, data: speech),
        ])
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: credentials,
            transport: transport
        )
        let recording = Data([1, 2, 3, 4])

        let transcript = try await client.transcribeVoice(
            recording,
            contentType: "audio/m4a"
        )
        let spoken = try await client.synthesizeVoice(
            "AgentOps owns durable task state."
        )

        XCTAssertEqual(transcript, "Canonical AgentOps request.")
        XCTAssertEqual(spoken, speech)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/v1/voice/transcriptions")
        XCTAssertEqual(requests[0].httpBody, recording)
        XCTAssertEqual(
            requests[0].value(forHTTPHeaderField: "Content-Type"),
            "audio/m4a"
        )
        XCTAssertEqual(
            requests[0].value(forHTTPHeaderField: "Authorization"),
            "Bearer expired"
        )
        XCTAssertEqual(requests[1].url?.path, "/v1/voice/speech")
        XCTAssertEqual(
            requests[1].value(forHTTPHeaderField: "Accept"),
            "audio/mpeg"
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                VoiceSpeechRequest.self,
                from: try XCTUnwrap(requests[1].httpBody)
            ).text,
            "AgentOps owns durable task state."
        )
    }

    func testBoundedVoiceRejectsEmptyAudioAndSpeechBeforeNetwork() async {
        let transport = MockAgentOpsTransport(responses: [])
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: MockAgentOpsCredentials(),
            transport: transport
        )

        do {
            _ = try await client.transcribeVoice(
                Data(),
                contentType: "audio/m4a"
            )
            XCTFail("Expected invalid recording")
        } catch {
            XCTAssertEqual(error as? AgentOpsClientError, .invalidRequest)
        }
        do {
            _ = try await client.synthesizeVoice("  ")
            XCTFail("Expected invalid speech")
        } catch {
            XCTAssertEqual(error as? AgentOpsClientError, .invalidRequest)
        }
        let requests = await transport.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }
}

private struct VoiceSpeechRequest: Decodable {
    let text: String
}

private extension AgentOpsApprovalCard {
    static func testFixture(
        status: AgentOpsApprovalStatus
    ) -> AgentOpsApprovalCard {
        AgentOpsApprovalCard(
            id: UUID(
                uuidString: "22222222-2222-4222-8222-222222222222"
            )!,
            taskId: UUID(
                uuidString: "11111111-1111-4111-8111-111111111111"
            )!,
            type: "production_data",
            status: status,
            target: "Selected production rows",
            consequence: "Updates only the selected production rows.",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            actionDigest: String(repeating: "a", count: 64),
            requiresExplicitTap: true
        )
    }
}

@MainActor
private final class MockAgentOpsCredentials: AgentOpsCredentialProviding {
    var refreshes = 0
    var signOuts = 0

    func accessToken() async throws -> String { "expired" }

    func refreshAccessToken() async throws -> String {
        refreshes += 1
        return "refreshed"
    }

    func forceSignOut() async {
        signOuts += 1
    }
}

private actor MockAgentOpsTransport: AgentOpsTransport {
    private var responses: [AgentOpsTransportResponse]
    private var requests: [URLRequest] = []
    private let waitsForCancellation: Bool

    init(
        responses: [AgentOpsTransportResponse],
        waitsForCancellation: Bool = false
    ) {
        self.responses = responses
        self.waitsForCancellation = waitsForCancellation
    }

    func data(for request: URLRequest) async throws -> AgentOpsTransportResponse {
        requests.append(request)
        if waitsForCancellation {
            try await Task.sleep(for: .seconds(60))
            throw AgentOpsClientError.invalidResponse
        }
        guard !responses.isEmpty else {
            throw AgentOpsClientError.invalidResponse
        }
        return responses.removeFirst()
    }

    func capturedRequests() -> [URLRequest] { requests }
}

private struct WorkEnvelope: Codable, Equatable {
    let tasks: [String]
    let nextCursor: String?

    static let empty = WorkEnvelope(tasks: [], nextCursor: nil)
}

private extension AgentOpsTransportResponse {
    static func json<T: Encodable>(status: Int, _ value: T) -> AgentOpsTransportResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return AgentOpsTransportResponse(
            statusCode: status,
            data: (try? encoder.encode(value)) ?? Data()
        )
    }
}

private let workJSON = """
{
  "tasks": [{
    "id": "11111111-1111-4111-8111-111111111111",
    "title": "Ship native voice",
    "lifecycle": {
      "status": "in_progress",
      "updatedAt": "2026-07-23T12:00:00Z",
      "completedAt": null,
      "futureLifecycleField": "ignored"
    },
    "routing": {
      "mode": "locked",
      "implementer": "claude",
      "reviewer": "ringer",
      "allowFallback": false,
      "fallbackRuntime": null,
      "futureRoutingField": true
    },
    "blocker": null,
    "proof": {
      "state": "coded",
      "handles": [{
        "kind": "pull_request",
        "label": "PR 123",
        "url": "https://github.com/example/repo/pull/123",
        "futureSourceField": "ignored"
      }],
      "futureProofField": 1
    },
    "source": {
      "system": "agentops_voice",
      "key": "turn-1",
      "url": "https://agentops.revopsglobal.com/fleet/tasks/11111111-1111-4111-8111-111111111111",
      "threadRef": {"origin": "ios"},
      "futureSourceField": []
    },
    "futureTaskField": {"safe": true}
  }],
  "nextCursor": null,
  "futureEnvelopeField": "ignored"
}
"""

private let approvalJSON = """
{
  "approvals": [{
    "id": "22222222-2222-4222-8222-222222222222",
    "taskId": "11111111-1111-4111-8111-111111111111",
    "type": "production_change",
    "status": "pending",
    "target": "Deploy voice gateway",
    "consequence": "Changes the production request path",
    "expiresAt": "2026-07-24T12:00:00Z",
    "actionDigest": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "requiresExplicitTap": true,
    "futureApprovalField": "ignored"
  }],
  "nextCursor": null,
  "futureEnvelopeField": "ignored"
}
"""

private let eventJSON = """
{
  "id": "33333333-3333-4333-8333-333333333333",
  "taskId": "11111111-1111-4111-8111-111111111111",
  "eventType": "task.updated",
  "version": 9,
  "createdAt": "2026-07-23T12:01:00Z",
  "payload": {"private": true},
  "futureEventField": "ignored"
}
"""
