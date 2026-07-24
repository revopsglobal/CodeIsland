import Auth
import Foundation
import XCTest
@testable import CodeIslandCompanion

@MainActor
final class AgentOpsAuthStoreTests: XCTestCase {
    func testRecognizesOnlyTheExistingCodeIslandAuthCallback() {
        XCTAssertTrue(AgentOpsAuthStore.isAuthCallback(
            URL(string: "codeisland://auth/callback?code=one-time-code")!
        ))
        XCTAssertFalse(AgentOpsAuthStore.isAuthCallback(
            URL(string: "codeisland://agentops/callback?code=one-time-code")!
        ))
        XCTAssertFalse(AgentOpsAuthStore.isAuthCallback(
            URL(string: "https://auth/callback?code=one-time-code")!
        ))
        XCTAssertFalse(AgentOpsAuthStore.isAuthCallback(
            URL(string: "codeisland://auth/other?code=one-time-code")!
        ))
    }

    func testCallbackPublishesAuthenticatedIdentityWithoutPublishingTokens() async {
        let provider = MockAgentOpsAuthProvider()
        await provider.setCallbackSession(.fixture(accessToken: "callback-secret"))
        let store = AgentOpsAuthStore(provider: provider)
        let callback = URL(string: "codeisland://auth/callback?code=one-time-code")!

        let handled = await store.openAuthCallback(callback)
        XCTAssertTrue(handled)
        XCTAssertEqual(
            store.state,
            .authenticated(
                userID: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
                email: "greg@revopsglobal.com"
            )
        )
        let callbacks = await provider.acceptedCallbacks()
        XCTAssertEqual(callbacks, [callback])
        XCTAssertFalse(String(reflecting: store.state).contains("callback-secret"))
    }

    func testRestoresRefreshesAndDeletesSessionOnLogout() async throws {
        let provider = MockAgentOpsAuthProvider()
        await provider.setCurrentSession(.fixture(accessToken: "first-secret"))
        await provider.setRefreshSession(.fixture(accessToken: "fresh-secret"))
        let store = AgentOpsAuthStore(provider: provider)

        await store.restore()
        let firstToken = try await store.accessToken()
        XCTAssertEqual(firstToken, "first-secret")
        let refreshedToken = try await store.refreshAccessToken()
        XCTAssertEqual(refreshedToken, "fresh-secret")
        let refreshCount = await provider.refreshCount()
        XCTAssertEqual(refreshCount, 1)

        await store.forceSignOut()
        XCTAssertEqual(store.state, .signedOut)
        let signOutCount = await provider.signOutCount()
        XCTAssertEqual(signOutCount, 1)
    }

    func testSupabaseAuthStoragePersistsOnlyInKeychainAndDeletes() throws {
        let service = "com.revopsglobal.codeisland.tests.\(UUID().uuidString)"
        let storage = KeychainLocalStorage(service: service)
        let key = "agentops-test-session"
        let value = Data("opaque-session-data".utf8)
        defer { try? storage.remove(key: key) }

        try storage.store(key: key, value: value)
        XCTAssertEqual(try storage.retrieve(key: key), value)
        try storage.remove(key: key)
        XCTAssertNil(try storage.retrieve(key: key))
    }

    func testAgentOpsAuthSourceContainsNoSessionPersistenceOrCredentialLogging() throws {
        let testsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceRoot = testsURL
            .deletingLastPathComponent()
            .appendingPathComponent("CodeIslandCompanion/AgentOps", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        )
        let files = (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let source = try files
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        XCTAssertFalse(source.contains("UserDefaults"))
        XCTAssertFalse(source.contains("print("))
        XCTAssertFalse(source.contains("Logger("))
        XCTAssertFalse(source.contains("eyJhbGci"))
        XCTAssertFalse(source.contains("sb_secret_"))

        let plist = try String(
            contentsOf: sourceRoot
                .deletingLastPathComponent()
                .appendingPathComponent("Info.plist"),
            encoding: .utf8
        )
        XCTAssertFalse(plist.contains("access_token"))
        XCTAssertFalse(plist.contains("refresh_token"))
    }
}

private actor MockAgentOpsAuthProvider: AgentOpsAuthProviding {
    private var current: AgentOpsAuthSession?
    private var callback: AgentOpsAuthSession = .fixture(accessToken: "callback")
    private var refreshed: AgentOpsAuthSession = .fixture(accessToken: "refreshed")
    private var callbacks: [URL] = []
    private var refreshes = 0
    private var signOuts = 0

    func setCurrentSession(_ session: AgentOpsAuthSession?) {
        current = session
    }

    func setCallbackSession(_ session: AgentOpsAuthSession) {
        callback = session
    }

    func setRefreshSession(_ session: AgentOpsAuthSession) {
        refreshed = session
    }

    func acceptedCallbacks() -> [URL] { callbacks }
    func refreshCount() -> Int { refreshes }
    func signOutCount() -> Int { signOuts }

    func currentSession() async throws -> AgentOpsAuthSession? { current }

    func requestMagicLink(email: String) async throws {}

    func acceptCallback(_ url: URL) async throws -> AgentOpsAuthSession {
        callbacks.append(url)
        current = callback
        return callback
    }

    func refreshSession() async throws -> AgentOpsAuthSession {
        refreshes += 1
        current = refreshed
        return refreshed
    }

    func signOut() async throws {
        signOuts += 1
        current = nil
    }
}

private extension AgentOpsAuthSession {
    static func fixture(accessToken: String) -> AgentOpsAuthSession {
        AgentOpsAuthSession(
            accessToken: accessToken,
            userID: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
            email: "greg@revopsglobal.com",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }
}
