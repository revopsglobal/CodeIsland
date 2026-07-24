import Auth
import Combine
import Foundation

struct AgentOpsAuthSession: Equatable, Sendable {
    let accessToken: String
    let userID: UUID
    let email: String?
    let expiresAt: Date
}

protocol AgentOpsAuthProviding: Sendable {
    func currentSession() async throws -> AgentOpsAuthSession?
    func requestMagicLink(email: String) async throws
    func acceptCallback(_ url: URL) async throws -> AgentOpsAuthSession
    func refreshSession() async throws -> AgentOpsAuthSession
    func signOut() async throws
}

@MainActor
protocol AgentOpsCredentialProviding: AnyObject {
    func accessToken() async throws -> String
    func refreshAccessToken() async throws -> String
    func forceSignOut() async
}

enum AgentOpsAuthError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidCallback
    case sessionMissing

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "AgentOps sign-in is not configured in this build."
        case .invalidCallback:
            return "That AgentOps sign-in link is invalid."
        case .sessionMissing:
            return "Sign in to AgentOps to continue."
        }
    }
}

struct AgentOpsConfiguration: Equatable, Sendable {
    let baseURL: URL
    let supabaseURL: URL
    let supabaseAnonKey: String

    static func load(bundle: Bundle = .main) throws -> AgentOpsConfiguration {
        guard
            let baseURLText = bundle.object(forInfoDictionaryKey: "AgentOpsBaseURL") as? String,
            let baseURL = validatedHTTPSURL(baseURLText),
            let supabaseURLText = bundle.object(forInfoDictionaryKey: "AgentOpsSupabaseURL") as? String,
            let supabaseURL = validatedHTTPSURL(supabaseURLText),
            let anonKey = bundle.object(forInfoDictionaryKey: "AgentOpsSupabaseAnonKey") as? String,
            !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !anonKey.contains("$(")
        else {
            throw AgentOpsAuthError.invalidConfiguration
        }
        return AgentOpsConfiguration(
            baseURL: baseURL,
            supabaseURL: supabaseURL,
            supabaseAnonKey: anonKey
        )
    }

    private static func validatedHTTPSURL(_ value: String) -> URL? {
        guard
            !value.contains("$("),
            let url = URL(string: value),
            url.scheme == "https",
            url.user == nil,
            url.password == nil,
            url.host != nil
        else { return nil }
        return url
    }
}

actor SupabaseAgentOpsAuthProvider: AgentOpsAuthProviding {
    private let auth: AuthClient
    private let callbackURL = URL(string: "codeisland://auth/callback")!

    init(configuration: AgentOpsConfiguration) {
        let authURL = configuration.supabaseURL
            .appendingPathComponent("auth", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        auth = AuthClient(
            url: authURL,
            headers: [
                "apikey": configuration.supabaseAnonKey,
                "Authorization": "Bearer \(configuration.supabaseAnonKey)",
            ],
            flowType: .pkce,
            redirectToURL: callbackURL,
            storageKey: "agentops-auth-session-v1",
            localStorage: KeychainLocalStorage(
                service: "com.revopsglobal.codeisland.buddy.agentops-auth"
            ),
            logger: nil,
            autoRefreshToken: true,
            emitLocalSessionAsInitialSession: true
        )
    }

    func currentSession() async throws -> AgentOpsAuthSession? {
        guard auth.currentSession != nil else { return nil }
        return map(try await auth.session)
    }

    func requestMagicLink(email: String) async throws {
        try await auth.signInWithOTP(
            email: email,
            redirectTo: callbackURL,
            shouldCreateUser: false
        )
    }

    func acceptCallback(_ url: URL) async throws -> AgentOpsAuthSession {
        map(try await auth.session(from: url))
    }

    func refreshSession() async throws -> AgentOpsAuthSession {
        map(try await auth.refreshSession())
    }

    func signOut() async throws {
        try await auth.signOut(scope: .global)
    }

    private func map(_ session: Session) -> AgentOpsAuthSession {
        AgentOpsAuthSession(
            accessToken: session.accessToken,
            userID: session.user.id,
            email: session.user.email,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt)
        )
    }
}

private actor UnavailableAgentOpsAuthProvider: AgentOpsAuthProviding {
    func currentSession() async throws -> AgentOpsAuthSession? { nil }
    func requestMagicLink(email: String) async throws {
        throw AgentOpsAuthError.invalidConfiguration
    }
    func acceptCallback(_ url: URL) async throws -> AgentOpsAuthSession {
        throw AgentOpsAuthError.invalidConfiguration
    }
    func refreshSession() async throws -> AgentOpsAuthSession {
        throw AgentOpsAuthError.invalidConfiguration
    }
    func signOut() async throws {}
}

@MainActor
final class AgentOpsAuthStore: ObservableObject, AgentOpsCredentialProviding {
    enum State: Equatable {
        case restoring
        case signedOut
        case linkSent(email: String)
        case authenticated(userID: UUID, email: String?)
        case failed(message: String)
    }

    @Published private(set) var state: State = .restoring

    private let provider: any AgentOpsAuthProviding

    init(provider: any AgentOpsAuthProviding) {
        self.provider = provider
    }

    static func live(configuration: AgentOpsConfiguration) -> AgentOpsAuthStore {
        AgentOpsAuthStore(provider: SupabaseAgentOpsAuthProvider(configuration: configuration))
    }

    static func unconfigured() -> AgentOpsAuthStore {
        AgentOpsAuthStore(provider: UnavailableAgentOpsAuthProvider())
    }

    func restore() async {
        do {
            guard let session = try await provider.currentSession() else {
                state = .signedOut
                return
            }
            publish(session)
        } catch {
            state = .signedOut
        }
    }

    func sendMagicLink(to email: String) async {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.contains("@"), normalized.count <= 254 else {
            state = .failed(message: "Enter a valid work email.")
            return
        }
        do {
            try await provider.requestMagicLink(email: normalized)
            state = .linkSent(email: normalized)
        } catch {
            state = .failed(message: safeMessage(for: error))
        }
    }

    @discardableResult
    func openAuthCallback(_ url: URL) async -> Bool {
        guard Self.isAuthCallback(url) else { return false }
        do {
            publish(try await provider.acceptCallback(url))
        } catch {
            state = .failed(message: safeMessage(for: error))
        }
        return true
    }

    nonisolated static func isAuthCallback(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "codeisland"
            && url.host?.lowercased() == "auth"
            && url.path == "/callback"
    }

    func accessToken() async throws -> String {
        guard let session = try await provider.currentSession() else {
            state = .signedOut
            throw AgentOpsAuthError.sessionMissing
        }
        publish(session)
        return session.accessToken
    }

    func refreshAccessToken() async throws -> String {
        do {
            let session = try await provider.refreshSession()
            publish(session)
            return session.accessToken
        } catch {
            await forceSignOut()
            throw error
        }
    }

    func forceSignOut() async {
        try? await provider.signOut()
        state = .signedOut
    }

    private func publish(_ session: AgentOpsAuthSession) {
        state = .authenticated(userID: session.userID, email: session.email)
    }

    private func safeMessage(for error: Error) -> String {
        if let authError = error as? AgentOpsAuthError {
            return authError.localizedDescription
        }
        return "AgentOps sign-in could not be completed. Try again."
    }
}
