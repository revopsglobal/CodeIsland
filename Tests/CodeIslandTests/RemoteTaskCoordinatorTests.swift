import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class RemoteTaskCoordinatorTests: XCTestCase {
    func testAutoUsesWorkspaceAffinityThenFallsBackDeterministically() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        _ = try fixture.store.create(
            fixture.request(provider: .claude),
            deviceID: "iphone"
        )
        let affinityTask = try fixture.coordinator.create(
            request: fixture.request(provider: .auto),
            deviceID: "iphone"
        )

        XCTAssertEqual(affinityTask.summary.provider, .claude)
        XCTAssertEqual(fixture.claude.starts.map(\.taskID), [affinityTask.id])

        let secondWorkspace = fixture.root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: secondWorkspace, withIntermediateDirectories: true)
        let secondCatalog = RemoteWorkspaceCatalog(
            allowedRoots: [fixture.root],
            candidates: [.init(url: secondWorkspace, source: .saved)]
        )
        let fallback = RemoteTaskCoordinator(
            store: fixture.store,
            workspaceCatalog: secondCatalog,
            attachmentStore: fixture.attachments,
            codex: fixture.codex.adapter,
            claude: fixture.claude.adapter
        )
        let fallbackTask = try fallback.create(
            request: fixture.request(provider: .auto, workspaceID: secondCatalog.entries[0].id),
            deviceID: "iphone"
        )

        XCTAssertEqual(fallbackTask.summary.provider, .codex)
        XCTAssertEqual(fixture.codex.starts.last?.taskID, fallbackTask.id)
    }

    func testUnavailableExplicitProviderNeedsYouInsteadOfSilentlyFallingBack() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.codex.available = false

        let task = try fixture.coordinator.create(
            request: fixture.request(provider: .codex),
            deviceID: "iphone"
        )
        try fixture.coordinator.registerWorkspaces([
            .init(url: fixture.workspace, source: .recentSession, lastUsedAt: Date())
        ])
        try fixture.coordinator.registerWorkspaces([
            .init(url: fixture.workspace, source: .recentSession, lastUsedAt: Date())
        ])

        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.state, .needsYou)
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.latestSummary, "Codex is unavailable on this Mac")
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.lastReceiptSequence, 2)
        XCTAssertTrue(fixture.claude.starts.isEmpty)
    }

    func testRestartRecoveryCancelsAlreadyStartedTasksInsteadOfLeavingNeedsYouStuck() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let codexTask = try fixture.store.create(fixture.request(provider: .codex), deviceID: "iphone")
        _ = try fixture.store.markExecutionStarted(taskID: codexTask.id)
        try fixture.append(
            taskID: codexTask.id,
            provider: .codex,
            providerSessionID: "thread-1",
            state: .working,
            summary: "Codex working"
        )
        let claudeTask = try fixture.store.create(fixture.request(provider: .claude), deviceID: "iphone")
        _ = try fixture.store.markExecutionStarted(taskID: claudeTask.id)
        try fixture.append(
            taskID: claudeTask.id,
            provider: .claude,
            providerSessionID: "session-1",
            state: .working,
            summary: "Claude working"
        )
        let uncertain = try fixture.store.create(fixture.request(provider: .codex), deviceID: "iphone")

        try fixture.coordinator.recover()
        try fixture.coordinator.recover()

        XCTAssertTrue(fixture.codex.restores.isEmpty)
        XCTAssertTrue(fixture.claude.restores.isEmpty)
        XCTAssertEqual(fixture.store.task(id: codexTask.id)?.summary.state, .cancelled)
        XCTAssertEqual(fixture.store.task(id: claudeTask.id)?.summary.state, .cancelled)
        XCTAssertEqual(
            fixture.store.task(id: codexTask.id)?.summary.latestSummary,
            "Task stopped when the Mac restarted; start a new task to retry safely"
        )
        XCTAssertEqual(fixture.codex.starts.map(\.taskID), [uncertain.id])
        XCTAssertTrue(fixture.claude.starts.isEmpty)
    }

    func testLateWorkspaceRegistrationStartsAnUnstartedTaskExactlyOnce() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let lateWorkspace = fixture.root.appendingPathComponent("late", isDirectory: true)
        try FileManager.default.createDirectory(at: lateWorkspace, withIntermediateDirectories: true)
        let identityCatalog = RemoteWorkspaceCatalog(
            allowedRoots: [lateWorkspace],
            candidates: [.init(url: lateWorkspace, source: .recentSession)],
            homeDirectory: fixture.root.appendingPathComponent("home")
        )
        let task = try fixture.store.create(
            fixture.request(provider: .codex, workspaceID: identityCatalog.entries[0].id),
            deviceID: "iphone"
        )

        try fixture.coordinator.recover()
        try fixture.coordinator.registerWorkspaces([
            .init(url: lateWorkspace, source: .recentSession, lastUsedAt: Date())
        ])
        try fixture.coordinator.registerWorkspaces([
            .init(url: lateWorkspace, source: .recentSession, lastUsedAt: Date())
        ])

        XCTAssertEqual(fixture.codex.starts.map(\.taskID).filter { $0 == task.id }, [task.id])
        XCTAssertEqual(fixture.store.task(id: task.id)?.executionStarted, true)
    }

    func testFollowUpTargetsTheExactProviderSession() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.coordinator.create(
            request: fixture.request(provider: .claude),
            deviceID: "iphone"
        )

        try fixture.coordinator.followUp(taskID: task.id, text: "Also test dark mode", attachments: [])

        XCTAssertEqual(fixture.claude.followUps.map(\.taskID), [task.id])
        XCTAssertEqual(fixture.claude.followUps.first?.text, "Also test dark mode")
        XCTAssertTrue(fixture.codex.followUps.isEmpty)
    }

    func testConsequentialActionTokenIsTaskActionDeviceAndSequenceBoundAndSingleUse() throws {
        let fixture = try Fixture(token: "exact-token")
        defer { fixture.remove() }
        let task = try fixture.coordinator.create(
            request: fixture.request(provider: .codex),
            deviceID: "iphone-a"
        )
        let sequence = try XCTUnwrap(fixture.store.task(id: task.id)?.summary.lastReceiptSequence)
        let intent = RemoteTaskActionIntent(
            taskID: task.id,
            action: .commit,
            arguments: ["message": "Finish feature"],
            expectedReceiptSequence: sequence
        )

        let prepared = try fixture.coordinator.prepareAction(intent, deviceID: "iphone-a")

        XCTAssertEqual(prepared.actionToken, "exact-token")
        XCTAssertThrowsError(
            try fixture.coordinator.authorizeAction(
                RemoteTaskActionIntent(taskID: task.id, action: .push, expectedReceiptSequence: sequence),
                actionToken: prepared.actionToken,
                deviceID: "iphone-a"
            )
        )
        XCTAssertThrowsError(
            try fixture.coordinator.authorizeAction(intent, actionToken: prepared.actionToken, deviceID: "iphone-b")
        )
        XCTAssertNoThrow(
            try fixture.coordinator.authorizeAction(intent, actionToken: prepared.actionToken, deviceID: "iphone-a")
        )
        XCTAssertThrowsError(
            try fixture.coordinator.authorizeAction(intent, actionToken: prepared.actionToken, deviceID: "iphone-a")
        )
    }

    func testCancellationIsIdempotent() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.coordinator.create(
            request: fixture.request(provider: .codex),
            deviceID: "iphone"
        )

        try fixture.coordinator.cancel(taskID: task.id)
        try fixture.coordinator.cancel(taskID: task.id)

        XCTAssertEqual(fixture.codex.cancellations, [task.id])
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.state, .cancelled)
    }

    func testFailedTaskCanBeDismissedWithoutCancellingProviderAgain() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.coordinator.create(
            request: fixture.request(provider: .codex),
            deviceID: "iphone"
        )
        try fixture.append(
            taskID: task.id,
            provider: .codex,
            providerSessionID: "thread-failed",
            state: .failed,
            summary: "Codex app-server failed"
        )

        try fixture.coordinator.cancel(taskID: task.id)
        try fixture.coordinator.cancel(taskID: task.id)

        XCTAssertTrue(fixture.codex.cancellations.isEmpty)
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.state, .cancelled)
        XCTAssertEqual(fixture.store.task(id: task.id)?.summary.latestSummary, "Failure dismissed")
    }
}

@MainActor
private final class Fixture {
    let root: URL
    let workspace: URL
    let store: RemoteTaskStore
    let catalog: RemoteWorkspaceCatalog
    let attachments: RemoteTaskAttachmentStore
    let codex = MockProviderRunner(provider: .codex)
    let claude = MockProviderRunner(provider: .claude)
    let coordinator: RemoteTaskCoordinator

    init(token: String = UUID().uuidString) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandCoordinator-\(UUID().uuidString)", isDirectory: true)
        workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        store = RemoteTaskStore(
            snapshotURL: root.appendingPathComponent("tasks.json"),
            receiptsURL: root.appendingPathComponent("receipts.jsonl"),
            serverName: "Test Mac"
        )
        catalog = RemoteWorkspaceCatalog(
            allowedRoots: [root],
            candidates: [.init(url: workspace, source: .recentSession, lastUsedAt: Date())],
            homeDirectory: root.appendingPathComponent("home")
        )
        attachments = RemoteTaskAttachmentStore(baseURL: root.appendingPathComponent("attachments"))
        coordinator = RemoteTaskCoordinator(
            store: store,
            workspaceCatalog: catalog,
            attachmentStore: attachments,
            codex: codex.adapter,
            claude: claude.adapter,
            actionTokens: RemoteActionTokenVault(tokenGenerator: { token })
        )
    }

    func request(
        provider: RemoteTaskProvider,
        workspaceID: String? = nil
    ) -> RemoteTaskCreateRequest {
        RemoteTaskCreateRequest(
            clientTaskID: UUID(),
            idempotencyKey: UUID(),
            prompt: "Implement and test",
            workspaceID: workspaceID ?? catalog.entries[0].id,
            provider: provider,
            authority: .editAndTest
        )
    }

    func append(
        taskID: UUID,
        provider: RemoteTaskProvider,
        providerSessionID: String,
        state: RemoteTaskState,
        summary: String
    ) throws {
        let sequence = try XCTUnwrap(store.task(id: taskID)?.summary.lastReceiptSequence).advanced(by: 1)
        try store.append(RemoteTaskReceipt(
            taskID: taskID,
            sequence: sequence,
            kind: .started,
            state: state,
            summary: summary,
            provider: provider,
            providerSessionID: providerSessionID
        ))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class MockProviderRunner {
    struct Start { let taskID: UUID; let workspace: URL }
    struct Restore { let taskID: UUID; let sessionID: String }
    struct FollowUp { let taskID: UUID; let text: String }

    let provider: RemoteTaskProvider
    var available = true
    var starts: [Start] = []
    var restores: [Restore] = []
    var followUps: [FollowUp] = []
    var cancellations: [UUID] = []

    init(provider: RemoteTaskProvider) {
        self.provider = provider
    }

    var adapter: RemoteTaskProviderRunner {
        RemoteTaskProviderRunner(
            provider: provider,
            isAvailable: { [weak self] in self?.available == true },
            start: { [weak self] taskID, workspace, _, _ in
                self?.starts.append(.init(taskID: taskID, workspace: workspace))
            },
            restore: { [weak self] taskID, _, sessionID in
                self?.restores.append(.init(taskID: taskID, sessionID: sessionID))
            },
            followUp: { [weak self] taskID, text, _ in
                self?.followUps.append(.init(taskID: taskID, text: text))
            },
            cancel: { [weak self] taskID in self?.cancellations.append(taskID) }
        )
    }
}
