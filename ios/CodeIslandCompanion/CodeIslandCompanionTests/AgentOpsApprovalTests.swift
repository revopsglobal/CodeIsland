import Foundation
import XCTest
@testable import CodeIslandCompanion

@MainActor
final class AgentOpsApprovalTests: XCTestCase {
    func testCardPreservesExactTargetConsequenceTaskDigestAndExpiry() {
        let card = AgentOpsApprovalCard.fixture()
        let model = AgentOpsApprovalViewModel(
            approval: card,
            now: { Date(timeIntervalSince1970: 1_784_846_400) },
            resolve: { _ in .fixture(status: .approved) }
        )

        XCTAssertEqual(model.approval.target, "voice.agentops.revopsglobal.com")
        XCTAssertEqual(
            model.approval.consequence,
            "Deploy the verified voice gateway to production."
        )
        XCTAssertEqual(
            model.approval.taskId.uuidString.lowercased(),
            "e7e843c5-733d-4492-a863-1c337684653b"
        )
        XCTAssertEqual(model.approval.actionDigest, String(repeating: "a", count: 64))
        XCTAssertEqual(model.approval.expiresAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testOnlyFirstVisibleTapCanApproveAndUsesExactDigest() async {
        let recorder = ApprovalResolverRecorder()
        let card = AgentOpsApprovalCard.fixture()
        let model = AgentOpsApprovalViewModel(
            approval: card,
            now: { Date(timeIntervalSince1970: 1_784_846_400) },
            resolve: { request in
                await recorder.resolve(request)
            }
        )

        await model.resolveFromVisibleTap(.approved)
        await model.resolveFromVisibleTap(.approved)

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.actionDigest, card.actionDigest)
        XCTAssertEqual(requests.first?.interaction, .onScreenTap)
        XCTAssertEqual(model.state, .resolved(.approved))
    }

    func testExpiredCardAndWrongDigestResponseRemainUnresolved() async {
        let expiredRecorder = ApprovalResolverRecorder()
        let expired = AgentOpsApprovalViewModel(
            approval: .fixture(expiresAt: Date(timeIntervalSince1970: 1)),
            now: { Date(timeIntervalSince1970: 2) },
            resolve: { request in await expiredRecorder.resolve(request) }
        )
        await expired.resolveFromVisibleTap(.approved)
        XCTAssertEqual(expired.state, .failed("This approval expired. Refresh Attention."))
        let expiredRequests = await expiredRecorder.requests
        XCTAssertEqual(expiredRequests.count, 0)

        let mismatch = AgentOpsApprovalViewModel(
            approval: .fixture(),
            now: { Date(timeIntervalSince1970: 1_784_846_400) },
            resolve: { _ in
                throw AgentOpsClientError.server(
                    code: "approval_digest_mismatch",
                    retryable: false
                )
            }
        )
        await mismatch.resolveFromVisibleTap(.approved)
        XCTAssertEqual(
            mismatch.state,
            .failed("This approval changed. Refresh Attention before deciding.")
        )
    }

    func testDenialIsExplicitAndIncludesSuppliedReason() async {
        let recorder = ApprovalResolverRecorder()
        let model = AgentOpsApprovalViewModel(
            approval: .fixture(),
            now: { Date(timeIntervalSince1970: 1_784_846_400) },
            resolve: { request in await recorder.resolve(request) }
        )

        await model.resolveFromVisibleTap(
            .rejected,
            decisionNote: "Wait for the sandbox proof."
        )

        let request = await recorder.requests.first
        XCTAssertEqual(request?.resolution, .rejected)
        XCTAssertEqual(request?.decisionNote, "Wait for the sandbox proof.")
        XCTAssertEqual(model.state, .resolved(.rejected))
    }

    func testRetryablePendingFailureCanBeRetried() async {
        let resolver = RetryingApprovalResolver()
        let model = AgentOpsApprovalViewModel(
            approval: .fixture(),
            now: { Date(timeIntervalSince1970: 1_784_846_400) },
            resolve: { request in
                try await resolver.resolve(request)
            }
        )

        await model.resolveFromVisibleTap(.approved)

        XCTAssertEqual(
            model.state,
            .failed("That didn’t go through. Try again.")
        )
        XCTAssertTrue(model.canResolve)

        await model.resolveFromVisibleTap(.approved)

        XCTAssertEqual(model.state, .resolved(.approved))
        let requests = await resolver.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testRootStoreRemovesConfirmedApproval() async {
        let approval = AgentOpsApprovalCard.fixture()
        let transport = ApprovalListTransport(
            response: AgentOpsApprovalListResponse(
                approvals: [approval],
                nextCursor: nil
            )
        )
        let client = AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: ApprovalTestCredentials(),
            transport: transport
        )
        let store = AgentOpsRootStore(
            auth: .unconfigured(),
            client: client
        )
        await store.refreshApprovals()
        XCTAssertEqual(store.approvals.map(\.id), [approval.id])

        store.markApprovalResolved(id: approval.id, status: .approved)

        XCTAssertTrue(store.approvals.isEmpty)
    }

    func testFollowedTaskBecomesVerifiedOnlyFromAgentOpsProof() {
        let pendingProof = AgentOpsWorkSummary.fixture(
            lifecycle: "verified",
            proof: "checks_passed"
        )
        let verifiedProof = AgentOpsWorkSummary.fixture(
            lifecycle: "verified",
            proof: "verified"
        )

        XCTAssertEqual(
            LiveActivityController.agentOpsState(for: pendingProof),
            .working
        )
        XCTAssertEqual(
            LiveActivityController.agentOpsState(for: verifiedProof),
            .verified
        )
    }

    func testRealtimeVoiceSurfaceHasNoApprovalResolutionCapability() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let voice = tests
            .deletingLastPathComponent()
            .appendingPathComponent("CodeIslandCompanion/AgentOps/Voice")
        let source = try FileManager.default.contentsOfDirectory(
            at: voice,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")

        XCTAssertFalse(source.contains("resolveApproval"))
        XCTAssertFalse(source.contains("on_screen_tap"))
        XCTAssertFalse(source.contains("resolveFromVisibleTap"))
    }
}

private actor ApprovalResolverRecorder {
    private(set) var requests: [AgentOpsApprovalResolutionRequest] = []

    func resolve(
        _ request: AgentOpsApprovalResolutionRequest
    ) -> AgentOpsApprovalResolutionResponse {
        requests.append(request)
        return .fixture(status: request.resolution)
    }
}

private actor RetryingApprovalResolver {
    private(set) var requests: [AgentOpsApprovalResolutionRequest] = []

    func resolve(
        _ request: AgentOpsApprovalResolutionRequest
    ) throws -> AgentOpsApprovalResolutionResponse {
        requests.append(request)
        if requests.count == 1 {
            throw AgentOpsClientError.server(
                code: "approval_resolution_not_recorded",
                retryable: true
            )
        }
        return .fixture(status: request.resolution)
    }
}

@MainActor
private final class ApprovalTestCredentials: AgentOpsCredentialProviding {
    func accessToken() async throws -> String { "test-token" }
    func refreshAccessToken() async throws -> String { "test-token" }
    func forceSignOut() async {}
}

private actor ApprovalListTransport: AgentOpsTransport {
    private let data: Data

    init(response: AgentOpsApprovalListResponse) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        data = (try? encoder.encode(response)) ?? Data()
    }

    func data(
        for request: URLRequest
    ) async throws -> AgentOpsTransportResponse {
        AgentOpsTransportResponse(statusCode: 200, data: data)
    }
}

private extension AgentOpsApprovalCard {
    static func fixture(
        expiresAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> AgentOpsApprovalCard {
        AgentOpsApprovalCard(
            id: UUID(uuidString: "b5ef124a-5b67-4e5e-b8f2-dd0de5f40114")!,
            taskId: UUID(uuidString: "e7e843c5-733d-4492-a863-1c337684653b")!,
            type: "production_deploy",
            status: .pending,
            target: "voice.agentops.revopsglobal.com",
            consequence: "Deploy the verified voice gateway to production.",
            expiresAt: expiresAt,
            actionDigest: String(repeating: "a", count: 64),
            requiresExplicitTap: true
        )
    }
}

private extension AgentOpsApprovalResolutionResponse {
    static func fixture(
        status: AgentOpsApprovalStatus
    ) -> AgentOpsApprovalResolutionResponse {
        AgentOpsApprovalResolutionResponse(
            approvalId: UUID(uuidString: "b5ef124a-5b67-4e5e-b8f2-dd0de5f40114")!,
            status: status,
            resolved: true
        )
    }
}

private extension AgentOpsWorkSummary {
    static func fixture(
        lifecycle: String,
        proof: String
    ) -> AgentOpsWorkSummary {
        AgentOpsWorkSummary(
            id: UUID(uuidString: "e7e843c5-733d-4492-a863-1c337684653b")!,
            title: "Ship native voice",
            lifecycle: .init(
                status: lifecycle,
                updatedAt: Date(timeIntervalSince1970: 1_784_846_400),
                completedAt: nil
            ),
            routing: .init(
                mode: .auto,
                implementer: .claude,
                reviewer: "ringer",
                allowFallback: true,
                fallbackRuntime: .codex
            ),
            blocker: nil,
            proof: .init(state: proof, handles: []),
            source: .init(
                system: "agentops_voice",
                key: "turn-1",
                url: nil,
                threadRef: nil
            )
        )
    }
}
