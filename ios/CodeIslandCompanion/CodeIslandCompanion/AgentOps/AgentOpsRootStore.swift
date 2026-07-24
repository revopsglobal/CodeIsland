import Combine
import Foundation

@MainActor
final class AgentOpsRootStore: ObservableObject {
    let auth: AgentOpsAuthStore
    let client: AgentOpsClient?

    @Published private(set) var work: [AgentOpsWorkSummary] = []
    @Published private(set) var approvals: [AgentOpsApprovalCard] = []
    @Published private(set) var latestTurnResult: AgentOpsTurnResult?
    @Published private(set) var refreshError: String?

    private(set) var isActive = true
    private var authObserver: AnyCancellable?

    init(auth: AgentOpsAuthStore, client: AgentOpsClient?) {
        self.auth = auth
        self.client = client
        authObserver = auth.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
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
        return AgentOpsRootStore(
            auth: auth,
            client: AgentOpsClient(
                baseURL: configuration.baseURL,
                credentials: auth
            )
        )
    }

    func start() async {
        await auth.restore()
    }

    func openURL(_ url: URL) {
        guard AgentOpsAuthStore.isAuthCallback(url) else { return }
        Task { await auth.openAuthCallback(url) }
    }

    func setActive(_ active: Bool) {
        isActive = active
        if !active {
            client?.cancelNonessentialNetworkWork()
        }
    }

    func refreshWork() async {
        guard isActive, let client else { return }
        do {
            work = try await client.listWork()
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

    private var safeRefreshMessage: String {
        "AgentOps could not refresh. Pull to try again."
    }
}
