import Foundation
import Security
import UIKit

@MainActor
final class RemoteApprovalClient: ObservableObject {
    enum ConnectionState: Equatable {
        case unpaired
        case connecting
        case connected
        case offline(String)

        var label: String {
            switch self {
            case .unpaired: return "Pairing required"
            case .connecting: return "Connecting"
            case .connected: return "Connected"
            case .offline: return "Mac offline"
            }
        }
    }

    @Published private(set) var approvals: [RemoteApprovalItem] = []
    @Published private(set) var state: ConnectionState = .unpaired
    @Published private(set) var serverName: String?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var busyRequestIDs: Set<String> = []
    @Published private(set) var highlightedApprovalID: String?
    @Published private(set) var hubSnapshot: PersonalHubSnapshot?
    @Published private(set) var hubError: String?
    @Published private(set) var hubActionInFlight = false
    @Published private(set) var hubActionMessage: String?
    @Published var preparedAction: PersonalHubPreparedAction?
    @Published var selectedMode: PersonalHubMode {
        didSet {
            UserDefaults.standard.set(selectedMode.rawValue, forKey: Self.selectedModeKey)
            Task { await refreshHub() }
        }
    }
    @Published var serverURLText: String

    private static let defaultServerURL = "https://gregs-macbook-air.tail62f27c.ts.net:9443"
    private static let serverURLKey = "codeisland.remote.serverURL.v1"
    private static let tokenService = "com.revopsglobal.codeisland.buddy.remote"
    private static let tokenAccount = "device-token"
    private static let pendingPushTokenKey = "codeisland.remote.pendingPushToken"
    private static let pendingApprovalIDKey = "codeisland.remote.pendingApprovalID"
    private static let selectedModeKey = "codeisland.hub.selectedMode.v1"

    private var deviceToken: String?
    private var pollTask: Task<Void, Never>?
    private var isActive = true
    private var notificationObservers: [NSObjectProtocol] = []

    init() {
        serverURLText = UserDefaults.standard.string(forKey: Self.serverURLKey) ?? Self.defaultServerURL
        selectedMode = PersonalHubMode(
            rawValue: UserDefaults.standard.string(forKey: Self.selectedModeKey) ?? ""
        ) ?? .auto
        deviceToken = Self.readKeychainToken()
        state = deviceToken == nil ? .unpaired : .connecting

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .codeIslandPushTokenAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.registerPendingPushToken() }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .codeIslandRemoteApprovalOpened,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.highlightedApprovalID = notification.userInfo?["approvalId"] as? String
                await self?.refresh()
            }
        })
    }

    deinit {
        pollTask?.cancel()
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.isActive, self.deviceToken != nil {
                    await self.refresh()
                }
                try? await Task.sleep(for: .seconds(4))
            }
        }
        Task {
            if let pendingID = UserDefaults.standard.string(forKey: Self.pendingApprovalIDKey) {
                highlightedApprovalID = pendingID
                UserDefaults.standard.removeObject(forKey: Self.pendingApprovalIDKey)
            }
            await refresh()
            await registerPendingPushToken()
        }
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active {
            Task { await refresh() }
        }
    }

    func pair(code: String, deviceName: String = UIDevice.current.name) async {
        let trimmedCode = code.filter(\.isNumber)
        guard trimmedCode.count == 6 else {
            state = .offline("Enter the six-digit code from the Mac")
            return
        }
        guard let requestURL = endpoint("/api/pair") else {
            state = .offline("Enter a valid Tailscale HTTPS URL")
            return
        }
        state = .connecting
        do {
            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(RemotePairRequest(code: trimmedCode, deviceName: deviceName))
            let response: RemotePairResponse = try await perform(request, authenticated: false)
            try Self.saveKeychainToken(response.deviceToken)
            deviceToken = response.deviceToken
            serverName = response.serverName
            UserDefaults.standard.set(normalizedServerURL?.absoluteString, forKey: Self.serverURLKey)
            state = .connected
            await registerPendingPushToken()
            await refresh()
        } catch {
            state = .offline(error.localizedDescription)
        }
    }

    func unpair() {
        Self.deleteKeychainToken()
        deviceToken = nil
        approvals = []
        serverName = nil
        hubSnapshot = nil
        hubError = nil
        preparedAction = nil
        state = .unpaired
    }

    func resolve(_ approval: RemoteApprovalItem, decision: RemoteApprovalDecision) async {
        guard !busyRequestIDs.contains(approval.id),
              let url = endpoint("/api/approvals/\(approval.id)/decision")
        else { return }
        busyRequestIDs.insert(approval.id)
        defer { busyRequestIDs.remove(approval.id) }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(
                RemoteDecisionRequest(decision: decision, actionToken: approval.actionToken)
            )
            let _: RemoteDecisionResponse = try await perform(request, authenticated: true)
            highlightedApprovalID = nil
            await refresh()
        } catch {
            state = .offline(error.localizedDescription)
            await refresh()
        }
    }

    func refresh() async {
        guard deviceToken != nil else {
            state = .unpaired
            approvals = []
            return
        }
        guard let url = endpoint("/api/approvals") else {
            state = .offline("Enter a valid Tailscale HTTPS URL")
            return
        }
        if approvals.isEmpty { state = .connecting }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let snapshot: RemoteApprovalSnapshot = try await perform(request, authenticated: true)
            approvals = snapshot.approvals
            serverName = snapshot.serverName
            lastUpdatedAt = Date()
            state = .connected
            await refreshHub()
        } catch RemoteClientError.unauthorized {
            unpair()
        } catch {
            state = .offline(error.localizedDescription)
        }
    }

    func refreshHub() async {
        guard deviceToken != nil else {
            hubSnapshot = nil
            return
        }
        guard let url = endpoint("/api/hub/snapshot") else {
            hubError = "Enter a valid Tailscale HTTPS URL"
            return
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(
                PersonalHubSnapshotRequest(requestedMode: selectedMode)
            )
            let snapshot: PersonalHubSnapshot = try await perform(request, authenticated: true)
            hubSnapshot = snapshot
            hubError = nil
        } catch RemoteClientError.unauthorized {
            unpair()
        } catch {
            hubError = error.localizedDescription
        }
    }

    func prepareHubAction(_ intent: PersonalHubActionIntent) async {
        guard !hubActionInFlight,
              let url = endpoint("/api/hub/actions/prepare")
        else { return }
        hubActionInFlight = true
        defer { hubActionInFlight = false }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(
                PersonalHubPrepareActionRequest(intent: intent)
            )
            preparedAction = try await perform(request, authenticated: true)
            hubActionMessage = nil
        } catch RemoteClientError.unauthorized {
            unpair()
        } catch {
            hubActionMessage = error.localizedDescription
        }
    }

    func reportHubClientAction(_ message: String) {
        hubActionMessage = message
    }

    func executeHubAction(_ prepared: PersonalHubPreparedAction) async {
        guard !hubActionInFlight,
              let url = endpoint("/api/hub/actions/execute")
        else { return }
        hubActionInFlight = true
        defer { hubActionInFlight = false }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(
                PersonalHubExecuteActionRequest(
                    intent: prepared.intent,
                    actionToken: prepared.actionToken
                )
            )
            let response: PersonalHubActionResponse = try await perform(request, authenticated: true)
            preparedAction = nil
            hubActionMessage = response.message
            await refreshHub()
        } catch RemoteClientError.unauthorized {
            unpair()
        } catch {
            preparedAction = nil
            hubActionMessage = error.localizedDescription
            await refreshHub()
        }
    }

    private func registerPendingPushToken() async {
        guard deviceToken != nil,
              let pushToken = UserDefaults.standard.string(forKey: Self.pendingPushTokenKey),
              let url = endpoint("/api/push-token")
        else { return }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
#if DEBUG
            let environment = "development"
#else
            let environment = "production"
#endif
            request.httpBody = try Self.encoder.encode(
                RemotePushRegistrationRequest(token: pushToken, environment: environment)
            )
            let _: RegistrationResponse = try await perform(request, authenticated: true)
            UserDefaults.standard.removeObject(forKey: Self.pendingPushTokenKey)
        } catch {
            // Keep the token queued; foreground polling still works and registration
            // retries on the next launch / APNs callback.
        }
    }

    private var normalizedServerURL: URL? {
        var raw = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "https://\(raw)" }
        guard var components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false
        else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func endpoint(_ path: String) -> URL? {
        guard let base = normalizedServerURL else { return nil }
        let components = path.split(separator: "/").map(String.init)
        return components.reduce(base) { partial, component in
            partial.appendingPathComponent(component)
        }
    }

    private func perform<T: Decodable>(_ request: URLRequest, authenticated: Bool) async throws -> T {
        var request = request
        request.timeoutInterval = 12
        if authenticated {
            guard let deviceToken else { throw RemoteClientError.unauthorized }
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RemoteClientError.invalidResponse }
        if http.statusCode == 401 { throw RemoteClientError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? Self.decoder.decode(ErrorResponse.self, from: data)
            throw RemoteClientError.server(error?.error ?? "Mac returned HTTP \(http.statusCode)")
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    private enum RemoteClientError: LocalizedError {
        case unauthorized
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Pairing expired"
            case .invalidResponse: return "Mac returned an invalid response"
            case .server(let message): return message
            }
        }
    }

    private struct ErrorResponse: Decodable { let error: String }
    private struct RegistrationResponse: Decodable { let registered: Bool }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func saveKeychainToken(_ token: String) throws {
        deleteKeychainToken()
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw RemoteClientError.server("Couldn't save pairing token (\(status))")
        }
    }

    private static func readKeychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychainToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension Notification.Name {
    static let codeIslandPushTokenAvailable = Notification.Name("codeisland.push-token-available")
    static let codeIslandRemoteApprovalOpened = Notification.Name("codeisland.remote-approval-opened")
}
