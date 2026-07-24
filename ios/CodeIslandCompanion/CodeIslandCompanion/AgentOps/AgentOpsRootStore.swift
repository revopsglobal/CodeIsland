import Combine
import Foundation

@MainActor
final class AgentOpsRootStore: ObservableObject {
    let auth: AgentOpsAuthStore
    let client: AgentOpsClient?
    let draftStore: VoiceTurnDraftStore?
    private(set) var pushCoordinator: AgentOpsPushCoordinator?

    @Published private(set) var work: [AgentOpsWorkSummary] = []
    @Published private(set) var approvals: [AgentOpsApprovalCard] = []
    @Published private(set) var latestTurnResult: AgentOpsTurnResult?
    @Published private(set) var refreshError: String?
    @Published private(set) var navigationTarget: AgentOpsNavigationTarget?

    private(set) var isActive = true
    private var authObserver: AnyCancellable?
    private var eventStream: AgentOpsEventStream?

    var onWorkUpdated: (([AgentOpsWorkSummary]) -> Void)?

    init(
        auth: AgentOpsAuthStore,
        client: AgentOpsClient?,
        draftStore: VoiceTurnDraftStore? = nil
    ) {
        self.auth = auth
        self.client = client
        self.draftStore = draftStore
        authObserver = auth.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        if let client {
            pushCoordinator = AgentOpsPushCoordinator(
                client: client,
                tokenStore: .shared,
                onWork: { [weak self] authoritative in
                    self?.acceptPush(work: authoritative)
                },
                onApproval: { [weak self] authoritative in
                    self?.acceptPush(approval: authoritative)
                },
                onOpen: { [weak self] target in
                    self?.navigationTarget = target
                }
            )
            eventStream = AgentOpsEventStream(
                requestProvider: { cursor, refresh in
                    try await client.eventStreamRequest(
                        cursor: cursor,
                        refreshCredentials: refresh
                    )
                },
                onUnauthorized: { [weak auth] in
                    await auth?.forceSignOut()
                },
                onEvent: { [weak self] event in
                    Task { @MainActor in
                        await self?.consume(event)
                    }
                }
            )
        }
    }

    static func live(bundle: Bundle = .main) -> AgentOpsRootStore {
        guard let configuration = try? AgentOpsConfiguration.load(bundle: bundle) else {
            return AgentOpsRootStore(
                auth: AgentOpsAuthStore.unconfigured(),
                client: nil
            )
        }
        let auth = AgentOpsAuthStore.live(configuration: configuration)
        guard let draftStore = try? VoiceTurnDraftStore() else {
            return AgentOpsRootStore(auth: auth, client: nil)
        }
        return AgentOpsRootStore(
            auth: auth,
            client: AgentOpsClient(
                baseURL: configuration.baseURL,
                credentials: auth
            ),
            draftStore: draftStore
        )
    }

    func start() async {
        await auth.restore()
        guard isAuthenticated else { return }
        eventStream?.start()
        pushCoordinator?.invalidateRegistrationScope()
        pushCoordinator?.start()
        await refreshAll()
        await retrySavedTurns()
    }

    func openURL(_ url: URL) {
        guard AgentOpsAuthStore.isAuthCallback(url) else { return }
        Task {
            let handled = await auth.openAuthCallback(url)
            guard handled, isAuthenticated else { return }
            eventStream?.start()
            pushCoordinator?.invalidateRegistrationScope()
            pushCoordinator?.start()
            await refreshAll()
            await retrySavedTurns()
        }
    }

    func openAgentOpsURL(_ url: URL) {
        guard let target = AgentOpsNavigationTarget(url: url) else { return }
        navigationTarget = target
        Task { await refresh(target) }
    }

    func setActive(_ active: Bool) {
        isActive = active
        if !active {
            client?.cancelNonessentialNetworkWork()
            eventStream?.setForeground(false)
        } else if isAuthenticated {
            eventStream?.setForeground(true)
            pushCoordinator?.start()
            Task {
                await refreshAll()
                await retrySavedTurns()
            }
        }
    }

    func refreshWork() async {
        guard isActive, let client else { return }
        do {
            work = try await client.listWork()
            onWorkUpdated?(work)
            refreshError = nil
        } catch is CancellationError {
            return
        } catch {
            refreshError = safeRefreshMessage
        }
    }

    func refreshApprovals() async {
        guard isActive, let client else { return }
        do {
            approvals = try await client.listApprovals()
            refreshError = nil
        } catch is CancellationError {
            return
        } catch {
            refreshError = safeRefreshMessage
        }
    }

    func recordTurnResult(_ result: AgentOpsTurnResult) {
        latestTurnResult = result
    }

    func retrySavedTurns() async {
        guard
            isActive,
            let client,
            let draftStore,
            !draftStore.drafts.isEmpty
        else { return }
        for draft in draftStore.drafts {
            do {
                try draftStore.markAttempted(draftID: draft.id)
                let result = try await client.performTurn(draft.request)
                try draftStore.finish(draftID: draft.id, result: result)
                recordTurnResult(result)
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }
        await refreshWork()
    }

    private func refreshAll() async {
        await refreshWork()
        await refreshApprovals()
    }

    private func refresh(_ target: AgentOpsNavigationTarget) async {
        guard isAuthenticated, let client else { return }
        do {
            switch target {
            case .task(let id):
                acceptPush(work: try await client.work(id: id))
            case .approval(let id):
                acceptPush(approval: try await client.approval(id: id))
            }
            refreshError = nil
        } catch is CancellationError {
            return
        } catch {
            refreshError = safeRefreshMessage
        }
    }

    private func acceptPush(work authoritative: AgentOpsWorkSummary) {
        if let index = work.firstIndex(where: { $0.id == authoritative.id }) {
            work[index] = authoritative
        } else {
            work.insert(authoritative, at: 0)
        }
        onWorkUpdated?(work)
    }

    private func acceptPush(approval authoritative: AgentOpsApprovalCard) {
        if let index = approvals.firstIndex(where: {
            $0.id == authoritative.id
        }) {
            approvals[index] = authoritative
        } else {
            approvals.insert(authoritative, at: 0)
        }
    }

    private func consume(_ event: AgentOpsEvent) async {
        guard isActive, let client else { return }
        do {
            let authoritative = try await client.work(id: event.taskId)
            acceptPush(work: authoritative)
            if event.eventType.localizedCaseInsensitiveContains("approval") {
                await refreshApprovals()
            }
            refreshError = nil
        } catch is CancellationError {
            return
        } catch {
            refreshError = safeRefreshMessage
        }
    }

    private var isAuthenticated: Bool {
        if case .authenticated = auth.state {
            return true
        }
        return false
    }

    private var safeRefreshMessage: String {
        "AgentOps could not refresh. Pull to try again."
    }
}
