import Foundation
import XCTest
@testable import CodeIslandCompanion

@MainActor
final class AgentOpsTurnToolTests: XCTestCase {
    func testToolBuildsCanonicalTurnRequestAndReturnsModelSafeJSON() async throws {
        let credentials = TurnToolCredentials()
        let response = AgentOpsTurnResult(
            kind: .durableWork,
            speechText: "Captured task 11111111-1111-4111-8111-111111111111.",
            displayText: "Captured.",
            sources: [],
            routingIntent: .init(
                mode: .locked,
                implementer: .codex,
                reviewer: "claude",
                allowFallback: false,
                fallbackRuntime: nil,
                reason: "Explicit request"
            ),
            approvalTier: .routineVoice,
            executionBrief: nil,
            task: .init(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
                title: "Ship native voice",
                status: "queued"
            ),
            unavailableSources: []
        )
        let transport = TurnToolTransport(result: response)
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: credentials,
            transport: transport
        )
        let tool = AgentOpsTurnTool(
            client: client,
            sessionID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            clientMetadata: .init(
                platform: "ios",
                appVersion: "1.0.0",
                build: "4",
                locale: "en-US"
            ),
            uuid: {
                UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
            }
        )

        let execution = try await tool.execute(
            callId: "call-1",
            argumentsJSON: #"{"transcript":"Use Codex to ship native voice"}"#
        )

        XCTAssertEqual(execution.result, response)
        XCTAssertTrue(execution.outputJSON.contains(#""kind":"durable_work""#))
        let capturedRequest = await transport.capturedRequest()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.path, "/v1/turn")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder.agentOps.decode(
            AgentOpsTurnRequest.self,
            from: body
        )
        XCTAssertEqual(
            decoded.sessionID,
            UUID(uuidString: "22222222-2222-4222-8222-222222222222")
        )
        XCTAssertEqual(
            decoded.turnID,
            UUID(uuidString: "33333333-3333-4333-8333-333333333333")
        )
        XCTAssertEqual(decoded.turnID, decoded.idempotencyKey)
        XCTAssertEqual(decoded.transcript, "Use Codex to ship native voice")
        XCTAssertEqual(decoded.conversation, [])
    }

    func testInvalidOrEmptyTranscriptFailsBeforeNetwork() async {
        let transport = TurnToolTransport(result: .fixtureAnswer)
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: TurnToolCredentials(),
            transport: transport
        )
        let tool = AgentOpsTurnTool(
            client: client,
            sessionID: UUID(),
            clientMetadata: .current()
        )

        do {
            _ = try await tool.execute(
                callId: "call-2",
                argumentsJSON: #"{"transcript":"   "}"#
            )
            XCTFail("Expected invalid arguments")
        } catch {
            XCTAssertEqual(error as? AgentOpsTurnToolError, .invalidArguments)
        }
        let captured = await transport.capturedRequest()
        XCTAssertNil(captured)
    }

    func testCompiledVoiceSourcesContainNoLegacyTaskSurface() throws {
        let testsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let voiceRoot = testsURL
            .deletingLastPathComponent()
            .appendingPathComponent("CodeIslandCompanion/AgentOps/Voice")
        let files = try FileManager.default.contentsOfDirectory(
            at: voiceRoot,
            includingPropertiesForKeys: nil
        )
        let source = try files
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        for forbidden in [
            "HermesTask",
            "hermesSessionId",
            "delegate_to_hermes",
            "get_hermes_task_status",
            "/v1/tasks",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }
}

@MainActor
private final class TurnToolCredentials: AgentOpsCredentialProviding {
    func accessToken() async throws -> String { "access-token" }
    func refreshAccessToken() async throws -> String { "refreshed-token" }
    func forceSignOut() async {}
}

private actor TurnToolTransport: AgentOpsTransport {
    private var request: URLRequest?
    private let result: AgentOpsTurnResult

    init(result: AgentOpsTurnResult) {
        self.result = result
    }

    func data(for request: URLRequest) async throws -> AgentOpsTransportResponse {
        self.request = request
        return AgentOpsTransportResponse(
            statusCode: 200,
            data: try JSONEncoder.agentOps.encode(result)
        )
    }

    func capturedRequest() -> URLRequest? {
        request
    }
}

private extension AgentOpsTurnResult {
    static let fixtureAnswer = AgentOpsTurnResult(
        kind: .answer,
        speechText: "Answer.",
        displayText: "Answer.",
        sources: [],
        routingIntent: .init(
            mode: .auto,
            implementer: nil,
            reviewer: nil,
            allowFallback: true,
            fallbackRuntime: nil,
            reason: "No named worker"
        ),
        approvalTier: .routineVoice,
        executionBrief: nil,
        task: nil,
        unavailableSources: []
    )
}
