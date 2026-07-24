import Combine
import Foundation

@MainActor
final class AgentOpsRootStore: ObservableObject {
    let auth: AgentOpsAuthStore
    let client: AgentOpsClient?

    private(set) var isActive = true

    init(auth: AgentOpsAuthStore, client: AgentOpsClient?) {
        self.auth = auth
        self.client = client
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
}
