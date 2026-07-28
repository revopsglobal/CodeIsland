import Foundation
import XCTest
@testable import CodeIslandCompanion

@MainActor
final class AgentOpsPushCoordinatorTests: XCTestCase {
    func testRegistrationUploadsAndClearsContentFreePhysicalReceipts() async throws {
        let defaults = isolatedDefaults()
        let receiptID = UUID(
            uuidString: "99999999-9999-4999-8999-999999999999"
        )!
        let observedAt = Date(timeIntervalSince1970: 1_785_260_083)
        let journal = AgentOpsMobileReceiptJournal(
            defaults: defaults,
            notificationCenter: NotificationCenter(),
            now: { observedAt },
            uuid: { receiptID },
            clientProvider: {
                AgentOpsMobileClientSnapshot(
                    appVersion: "1.0.0",
                    build: "20260728035630",
                    osVersion: "26.5",
                    deviceModel: "iPhone17,1"
                )
            }
        )
        journal.record(.appForegrounded)
        let tokenStore = AgentOpsPushTokenStore(
            defaults: defaults,
            notificationCenter: NotificationCenter(),
            receiptJournal: journal,
            deviceID: { "greg-iphone-test" }
        )
        let transport = PushMockTransport(responses: [
            .json(
                status: 200,
                AgentOpsDeviceRegistrationEnvelope(
                    device: .init(
                        id: UUID(),
                        deviceId: "greg-iphone-test",
                        lastSeenAt: observedAt
                    )
                )
            ),
        ])
        let coordinator = AgentOpsPushCoordinator(
            client: client(transport: transport),
            tokenStore: tokenStore,
            environment: .production,
            notificationAuthorizer: PushNotificationAuthorizerStub(),
            notificationCenter: NotificationCenter(),
            receiptJournal: journal
        )

        await coordinator.registerPendingTokens()

        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        let body = try JSONDecoder.agentOps.decode(
            AgentOpsDeviceRegistrationRequest.self,
            from: try XCTUnwrap(request.httpBody)
        )
        XCTAssertEqual(body.client, journal.client)
        XCTAssertEqual(body.receipts.map(\.id), [receiptID])
        XCTAssertEqual(body.receipts.map(\.kind), [.appForegrounded])
        XCTAssertTrue(journal.pending.isEmpty)
    }

    func testRegistersAPNsPushToStartAndTaskUpdateTokensWithBearerAuth() async throws {
        let defaults = isolatedDefaults()
        let tokenStore = AgentOpsPushTokenStore(
            defaults: defaults,
            deviceID: { "greg-iphone-test" }
        )
        tokenStore.storeAPNsToken(Data(repeating: 0xab, count: 32))
        tokenStore.storePushToStartToken(Data(repeating: 0xcd, count: 32))
        tokenStore.storeLiveActivityToken(
            Data(repeating: 0xef, count: 32),
            taskID: testTaskID
        )
        let transport = PushMockTransport(responses: [
            .json(
                status: 200,
                AgentOpsDeviceRegistrationEnvelope(
                    device: .init(
                        id: UUID(),
                        deviceId: "greg-iphone-test",
                        lastSeenAt: Date(timeIntervalSince1970: 1_784_846_400)
                    )
                )
            ),
        ])
        let client = client(transport: transport)
        let coordinator = AgentOpsPushCoordinator(
            client: client,
            tokenStore: tokenStore,
            environment: .sandbox,
            notificationAuthorizer: PushNotificationAuthorizerStub()
        )

        await coordinator.registerPendingTokens()

        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/v1/devices")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer valid-token"
        )
        let body = try JSONDecoder.agentOps.decode(
            AgentOpsDeviceRegistrationRequest.self,
            from: try XCTUnwrap(request.httpBody)
        )
        XCTAssertEqual(body.deviceId, "greg-iphone-test")
        XCTAssertEqual(body.apnsToken, String(repeating: "ab", count: 32))
        XCTAssertEqual(body.pushToStartToken, String(repeating: "cd", count: 32))
        XCTAssertEqual(
            body.liveActivityTokens[testTaskID.uuidString.lowercased()],
            String(repeating: "ef", count: 32)
        )
        XCTAssertFalse(tokenStore.needsRegistration(tokenStore.snapshot()))
    }

    func testTaskEventVersionDeduplicatesBeforeSecondDetailFetch() async throws {
        let transport = PushMockTransport(responses: [
            .json(status: 200, WorkResponse(task: .fixture(status: "in_progress"))),
        ])
        let journal = makeReceiptJournal()
        let coordinator = coordinator(
            transport: transport,
            receiptJournal: journal
        )
        let envelope = AgentOpsPushEnvelope.fixture(
            eventType: .taskWorking,
            version: 4
        )

        let first = await coordinator.process(envelope, userTapped: false)
        let duplicate = await coordinator.process(envelope, userTapped: false)

        XCTAssertEqual(first, .acceptedSilent)
        XCTAssertEqual(duplicate, .rejectedStale)
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.url?.path), [
            "/v1/work/\(testTaskID.uuidString.lowercased())",
        ])
        XCTAssertEqual(
            journal.pending.map(\.kind),
            [.pushAcceptedSilent, .pushRejectedStale]
        )
    }

    func testLaterActivityTokenRegistrationPreservesExistingAPNsToken() async throws {
        let tokenStore = AgentOpsPushTokenStore(
            defaults: isolatedDefaults(),
            deviceID: { "greg-iphone-test" }
        )
        tokenStore.storeAPNsToken(Data(repeating: 0xab, count: 32))
        let response = AgentOpsDeviceRegistrationEnvelope(
            device: .init(
                id: UUID(),
                deviceId: "greg-iphone-test",
                lastSeenAt: Date(timeIntervalSince1970: 1_784_846_400)
            )
        )
        let transport = PushMockTransport(responses: [
            .json(status: 200, response),
            .json(status: 200, response),
        ])
        let coordinator = AgentOpsPushCoordinator(
            client: client(transport: transport),
            tokenStore: tokenStore,
            environment: .sandbox,
            notificationAuthorizer: PushNotificationAuthorizerStub()
        )

        await coordinator.registerPendingTokens()
        tokenStore.storeLiveActivityToken(
            Data(repeating: 0xcd, count: 32),
            taskID: testTaskID
        )
        await coordinator.registerPendingTokens()

        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 2)
        let body = try JSONDecoder.agentOps.decode(
            AgentOpsDeviceRegistrationRequest.self,
            from: try XCTUnwrap(requests.last?.httpBody)
        )
        XCTAssertEqual(body.apnsToken, String(repeating: "ab", count: 32))
        XCTAssertEqual(
            body.liveActivityTokens[testTaskID.uuidString.lowercased()],
            String(repeating: "cd", count: 32)
        )
    }

    func testContentFreeApprovalPushFetchesCurrentCardBeforePresentation() async throws {
        let approval = AgentOpsApprovalCard.fixture()
        let transport = PushMockTransport(responses: [
            .json(status: 200, WorkResponse(task: .fixture(status: "blocked"))),
            .json(status: 200, ApprovalResponse(approval: approval)),
        ])
        var publishedApproval: AgentOpsApprovalCard?
        let coordinator = coordinator(
            transport: transport,
            onApproval: { publishedApproval = $0 }
        )
        let envelope = AgentOpsPushEnvelope.fixture(
            eventType: .approvalRequired,
            version: 8,
            approvalID: approval.id
        )

        let outcome = await coordinator.process(envelope, userTapped: false)

        XCTAssertEqual(outcome, .acceptedVisible)
        XCTAssertEqual(publishedApproval, approval)
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.url?.path), [
            "/v1/work/\(testTaskID.uuidString.lowercased())",
            "/v1/approvals/\(approval.id.uuidString.lowercased())",
        ])
        XCTAssertTrue(envelope.customPayloadIsContentFree)
    }

    func testRegressiveStateAfterVerifiedProofIsIgnored() async {
        let transport = PushMockTransport(responses: [
            .json(
                status: 200,
                WorkResponse(
                    task: .fixture(status: "verified", proof: "verified")
                )
            ),
            .json(status: 200, WorkResponse(task: .fixture(status: "in_progress"))),
        ])
        let journal = makeReceiptJournal()
        let coordinator = coordinator(
            transport: transport,
            receiptJournal: journal
        )

        let verified = await coordinator.process(
            .fixture(eventType: .taskVerified, version: 10),
            userTapped: false
        )
        let regressive = await coordinator.process(
            .fixture(eventType: .taskWorking, version: 11),
            userTapped: false
        )

        XCTAssertEqual(verified, .acceptedVisible)
        XCTAssertEqual(regressive, .rejectedRegressive)
        XCTAssertEqual(
            journal.pending.map(\.kind),
            [.pushAcceptedVisible, .pushRejectedRegressive]
        )
    }

    func testTerminalProjectionEndsOnlyTheMatchingFollowedTask() {
        XCTAssertTrue(
            LiveActivityController.shouldEndAgentOpsActivity(
                followedTaskID: testTaskID,
                eventTaskID: testTaskID,
                state: .verified
            )
        )
        XCTAssertFalse(
            LiveActivityController.shouldEndAgentOpsActivity(
                followedTaskID: UUID(),
                eventTaskID: testTaskID,
                state: .verified
            )
        )
        XCTAssertFalse(
            LiveActivityController.shouldEndAgentOpsActivity(
                followedTaskID: testTaskID,
                eventTaskID: testTaskID,
                state: .working
            )
        )
    }

    func testApprovalTapOpensExactFullCardWithoutResolvingIt() async {
        let approval = AgentOpsApprovalCard.fixture()
        let transport = PushMockTransport(responses: [
            .json(status: 200, WorkResponse(task: .fixture(status: "blocked"))),
            .json(status: 200, ApprovalResponse(approval: approval)),
        ])
        var opened: AgentOpsNavigationTarget?
        let coordinator = coordinator(
            transport: transport,
            onOpen: { opened = $0 }
        )

        let outcome = await coordinator.process(
            .fixture(
                eventType: .approvalRequired,
                version: 9,
                approvalID: approval.id
            ),
            userTapped: true
        )

        XCTAssertEqual(outcome, .acceptedVisible)
        XCTAssertEqual(opened, .approval(approval.id))
        XCTAssertTrue(
            AgentOpsPushCoordinator.notificationActions(
                for: .approvalRequired
            ).isEmpty
        )
        let requests = await transport.requests()
        XCTAssertFalse(
            requests.contains {
                $0.url?.path.contains("/resolve") == true
            }
        )
    }

    func testTapStillOpensAfterSamePushWasAlreadyPresented() async {
        let approval = AgentOpsApprovalCard.fixture()
        let work = WorkResponse(task: .fixture(status: "blocked"))
        let approvalResponse = ApprovalResponse(approval: approval)
        let transport = PushMockTransport(responses: [
            .json(status: 200, work),
            .json(status: 200, approvalResponse),
            .json(status: 200, work),
            .json(status: 200, approvalResponse),
        ])
        var opened: AgentOpsNavigationTarget?
        let coordinator = coordinator(
            transport: transport,
            onOpen: { opened = $0 }
        )
        let envelope = AgentOpsPushEnvelope.fixture(
            eventType: .approvalRequired,
            version: 12,
            approvalID: approval.id
        )

        let presented = await coordinator.process(
            envelope,
            userTapped: false
        )
        XCTAssertEqual(presented, .acceptedVisible)
        XCTAssertNil(opened)
        let tapped = await coordinator.process(envelope, userTapped: true)
        XCTAssertEqual(tapped, .rejectedStale)
        XCTAssertEqual(opened, .approval(approval.id))
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 4)
    }

    func testExplicitNotificationOptInOwnsPermissionRequest() async {
        let authorizer = PushNotificationAuthorizerStub()
        let coordinator = AgentOpsPushCoordinator(
            client: client(transport: PushMockTransport(responses: [])),
            tokenStore: AgentOpsPushTokenStore(
                defaults: isolatedDefaults(),
                deviceID: { "test-device" }
            ),
            environment: .sandbox,
            notificationAuthorizer: authorizer
        )

        let initialRequests = await authorizer.requestCount()
        XCTAssertEqual(initialRequests, 0)
        await coordinator.requestNotificationAccess()
        let requests = await authorizer.requestCount()
        let registrations = await authorizer.registrationCount()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(registrations, 1)
    }

    func testLegacyBuddyEnvelopeIsNotClaimedByAgentOpsParser() {
        let legacy: [String: Any] = [
            "requestId": "legacy-approval",
            "kind": "approval",
            "state": "pending",
            "issuedAt": "2026-07-23T12:00:00Z",
        ]

        XCTAssertNil(AgentOpsPushEnvelope(payloadFields: legacy))
    }

    private func coordinator(
        transport: PushMockTransport,
        receiptJournal: AgentOpsMobileReceiptJournal? = nil,
        onApproval: @escaping @MainActor (AgentOpsApprovalCard) -> Void = { _ in },
        onOpen: @escaping @MainActor (AgentOpsNavigationTarget) -> Void = { _ in }
    ) -> AgentOpsPushCoordinator {
        let defaults = isolatedDefaults()
        let notificationCenter = NotificationCenter()
        let receiptJournal = receiptJournal ?? AgentOpsMobileReceiptJournal(
            defaults: defaults,
            notificationCenter: notificationCenter
        )
        return AgentOpsPushCoordinator(
            client: client(transport: transport),
            tokenStore: AgentOpsPushTokenStore(
                defaults: defaults,
                notificationCenter: notificationCenter,
                receiptJournal: receiptJournal,
                deviceID: { "greg-iphone-test" }
            ),
            environment: .sandbox,
            notificationAuthorizer: PushNotificationAuthorizerStub(),
            notificationCenter: notificationCenter,
            receiptJournal: receiptJournal,
            onWork: { _ in },
            onApproval: onApproval,
            onOpen: onOpen
        )
    }

    private func client(transport: PushMockTransport) -> AgentOpsClient {
        AgentOpsClient(
            baseURL: URL(string: "https://voice.agentops.test")!,
            credentials: PushCredentials(),
            transport: transport
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "AgentOpsPushCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeReceiptJournal() -> AgentOpsMobileReceiptJournal {
        AgentOpsMobileReceiptJournal(
            defaults: isolatedDefaults(),
            notificationCenter: NotificationCenter()
        )
    }
}

@MainActor
private final class PushCredentials: AgentOpsCredentialProviding {
    func accessToken() async throws -> String { "valid-token" }
    func refreshAccessToken() async throws -> String { "refreshed-token" }
    func forceSignOut() async {}
}

private actor PushMockTransport: AgentOpsTransport {
    private var queued: [AgentOpsTransportResponse]
    private var captured: [URLRequest] = []

    init(responses: [AgentOpsTransportResponse]) {
        queued = responses
    }

    func data(for request: URLRequest) async throws -> AgentOpsTransportResponse {
        captured.append(request)
        guard !queued.isEmpty else {
            throw AgentOpsClientError.invalidResponse
        }
        return queued.removeFirst()
    }

    func requests() -> [URLRequest] { captured }
}

private actor PushNotificationAuthorizerStub:
    AgentOpsNotificationAuthorizing
{
    private var requests = 0
    private var registrations = 0
    private var settingsOpens = 0

    func authorizationGranted() async -> Bool? { nil }

    func requestAuthorization() async throws -> Bool {
        requests += 1
        return true
    }

    func registerForRemoteNotifications() async {
        registrations += 1
    }

    func openNotificationSettings() async {
        settingsOpens += 1
    }

    func requestCount() -> Int { requests }
    func registrationCount() -> Int { registrations }
}

private struct WorkResponse: Encodable {
    let task: AgentOpsWorkSummary
}

private struct ApprovalResponse: Encodable {
    let approval: AgentOpsApprovalCard
}

private extension AgentOpsTransportResponse {
    static func json<T: Encodable>(
        status: Int,
        _ value: T
    ) -> AgentOpsTransportResponse {
        AgentOpsTransportResponse(
            statusCode: status,
            data: (try? JSONEncoder.agentOps.encode(value)) ?? Data()
        )
    }
}

private extension AgentOpsPushEnvelope {
    static func fixture(
        eventType: AgentOpsMobileEventType,
        version: Int,
        approvalID: UUID? = nil
    ) -> AgentOpsPushEnvelope {
        AgentOpsPushEnvelope(
            taskID: testTaskID,
            approvalID: approvalID,
            eventType: eventType,
            version: version,
            deepLink: approvalID.map {
                URL(
                    string:
                        "codeisland://agentops/approvals/\($0.uuidString.lowercased())?taskId=\(testTaskID.uuidString.lowercased())"
                )!
            } ?? URL(
                string:
                    "codeisland://agentops/tasks/\(testTaskID.uuidString.lowercased())"
            )!
        )
    }
}

private extension AgentOpsWorkSummary {
    static func fixture(
        status: String,
        proof: String = "pending"
    ) -> AgentOpsWorkSummary {
        AgentOpsWorkSummary(
            id: testTaskID,
            title: "Private task title",
            lifecycle: .init(
                status: status,
                updatedAt: Date(timeIntervalSince1970: 1_784_846_400),
                completedAt: status == "verified"
                    ? Date(timeIntervalSince1970: 1_784_846_400)
                    : nil
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

private extension AgentOpsApprovalCard {
    static func fixture() -> AgentOpsApprovalCard {
        AgentOpsApprovalCard(
            id: testApprovalID,
            taskId: testTaskID,
            type: "production_deploy",
            status: .pending,
            target: "voice.agentops.revopsglobal.com",
            consequence: "Deploy a verified production release.",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            actionDigest: String(repeating: "a", count: 64),
            requiresExplicitTap: true
        )
    }
}

private let testTaskID = UUID(
    uuidString: "11111111-1111-4111-8111-111111111111"
)!
private let testApprovalID = UUID(
    uuidString: "22222222-2222-4222-8222-222222222222"
)!
