import Combine
import Foundation
import Network

struct RemoteTaskTransportResponse: Equatable {
    let statusCode: Int
    let data: Data
}

@MainActor
protocol RemoteTaskTransport: AnyObject {
    func data(for request: URLRequest) async throws -> RemoteTaskTransportResponse
}

@MainActor
final class URLSessionRemoteTaskTransport: RemoteTaskTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> RemoteTaskTransportResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return RemoteTaskTransportResponse(statusCode: response.statusCode, data: data)
    }
}

enum RemoteTaskSyncResult: Equatable {
    case success
    case pairingRequired
    case conflict
    case offline
    case deferred
}

@MainActor
final class RemoteTaskClient: ObservableObject {
    @Published private(set) var tasks: [RemoteTaskSummary] = []
    @Published private(set) var workspaces: [RemoteWorkspaceSummary] = []
    @Published private(set) var localDrafts: [RemoteTaskDraft]
    @Published private(set) var lastError: String?
    @Published private(set) var syncing = false

    private enum ClientError: LocalizedError {
        case unauthorized
        case superseded
        case conflict
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Pairing expired"
            case .superseded: return "Pairing changed while the task request was in flight"
            case .conflict: return "The task changed on the Mac"
            case .invalidResponse: return "Mac returned an invalid task response"
            case .server(let message): return message
            }
        }
    }

    private let store: RemoteTaskDraftStore
    private let transport: RemoteTaskTransport
    private let pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.codeisland.buddy.remote-task-reachability")
    private var retryAttempt = 0
    private var nextRetryAt: Date = .distantPast
    private var lastBaseURL: URL?
    private var lastBearerToken: String?
    private var connectionGeneration: UInt64 = 0

    convenience init(monitorReachability: Bool = true) {
        self.init(
            store: RemoteTaskDraftStore(),
            transport: URLSessionRemoteTaskTransport(),
            monitorReachability: monitorReachability
        )
    }

    init(
        store: RemoteTaskDraftStore,
        transport: RemoteTaskTransport,
        monitorReachability: Bool = true
    ) {
        self.store = store
        self.transport = transport
        localDrafts = store.drafts
        if monitorReachability {
            let monitor = NWPathMonitor()
            pathMonitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in
                    await self?.retryFromReachability()
                }
            }
            monitor.start(queue: monitorQueue)
        } else {
            pathMonitor = nil
        }
    }

    deinit {
        pathMonitor?.cancel()
    }

    @discardableResult
    func enqueue(_ input: RemoteTaskDraftInput) throws -> RemoteTaskDraft {
        let draft = try store.enqueue(input)
        localDrafts = store.drafts
        nextRetryAt = .distantPast
        return draft
    }

    func sync(baseURL: URL, bearerToken: String, force: Bool = false) async -> RemoteTaskSyncResult {
        let scope = beginConnectionScope(baseURL: baseURL, bearerToken: bearerToken)
        guard !syncing else { return .deferred }
        guard force || Date() >= nextRetryAt else { return .deferred }
        syncing = true
        defer { syncing = false }

        do {
            try await flushOutbox(baseURL: baseURL, bearerToken: bearerToken, scope: scope)
            try await refreshSnapshot(baseURL: baseURL, bearerToken: bearerToken, scope: scope)
            retryAttempt = 0
            nextRetryAt = .distantPast
            lastError = nil
            return .success
        } catch ClientError.superseded {
            return .deferred
        } catch ClientError.unauthorized {
            lastError = ClientError.unauthorized.localizedDescription
            return .pairingRequired
        } catch ClientError.conflict {
            do {
                try await refreshSnapshot(baseURL: baseURL, bearerToken: bearerToken, scope: scope)
            } catch ClientError.superseded {
                return .deferred
            } catch ClientError.unauthorized {
                lastError = ClientError.unauthorized.localizedDescription
                return .pairingRequired
            } catch {
                lastError = error.localizedDescription
            }
            lastError = ClientError.conflict.localizedDescription
            return .conflict
        } catch {
            retryAttempt = min(retryAttempt + 1, 6)
            nextRetryAt = Date().addingTimeInterval(min(pow(2, Double(retryAttempt)), 60))
            lastError = error.localizedDescription
            return .offline
        }
    }

    func resetForActivation() {
        nextRetryAt = .distantPast
    }

    func refreshWorkspaces(baseURL: URL, bearerToken: String) async -> RemoteTaskSyncResult {
        let scope = beginConnectionScope(baseURL: baseURL, bearerToken: bearerToken)
        do {
            let request = try authenticatedRequest(
                baseURL: baseURL,
                path: "/api/tasks/workspaces",
                method: "GET",
                bearerToken: bearerToken
            )
            let response = try await scopedData(for: request, scope: scope)
            try validate(response)
            workspaces = try Self.decoder.decode(RemoteWorkspaceSnapshot.self, from: response.data).workspaces
            return .success
        } catch ClientError.superseded {
            return .deferred
        } catch ClientError.unauthorized {
            return .pairingRequired
        } catch ClientError.conflict {
            return .conflict
        } catch {
            lastError = error.localizedDescription
            return .offline
        }
    }

    func followUp(
        taskID: UUID,
        text: String,
        baseURL: URL,
        bearerToken: String
    ) async -> RemoteTaskSyncResult {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .deferred }
        let scope = beginConnectionScope(baseURL: baseURL, bearerToken: bearerToken)
        do {
            let payload = RemoteTaskFollowUpRequest(
                taskID: taskID,
                idempotencyKey: UUID(),
                text: value
            )
            let request = try jsonRequest(
                baseURL: baseURL,
                path: "/api/tasks/\(taskID.uuidString.lowercased())/follow-up",
                method: "POST",
                value: payload,
                bearerToken: bearerToken
            )
            let response = try await scopedData(for: request, scope: scope)
            try validate(response)
            let summary = try Self.decoder.decode(RemoteTaskSummary.self, from: response.data)
            tasks = replacing(summary, in: tasks)
            return .success
        } catch {
            return result(for: error)
        }
    }

    func cancel(taskID: UUID, baseURL: URL, bearerToken: String) async -> RemoteTaskSyncResult {
        let scope = beginConnectionScope(baseURL: baseURL, bearerToken: bearerToken)
        do {
            let request = try authenticatedRequest(
                baseURL: baseURL,
                path: "/api/tasks/\(taskID.uuidString.lowercased())/cancel",
                method: "POST",
                body: Data(),
                contentType: "application/json",
                bearerToken: bearerToken
            )
            let response = try await scopedData(for: request, scope: scope)
            try validate(response)
            let summary = try Self.decoder.decode(RemoteTaskSummary.self, from: response.data)
            tasks = replacing(summary, in: tasks)
            return .success
        } catch {
            return result(for: error)
        }
    }

    func prepareAction(
        _ intent: RemoteTaskActionIntent,
        baseURL: URL,
        bearerToken: String
    ) async throws -> RemoteTaskPreparedAction {
        let scope = beginConnectionScope(baseURL: baseURL, bearerToken: bearerToken)
        let request = try jsonRequest(
            baseURL: baseURL,
            path: "/api/tasks/\(intent.taskID.uuidString.lowercased())/actions/prepare",
            method: "POST",
            value: intent,
            bearerToken: bearerToken
        )
        let response = try await scopedData(for: request, scope: scope)
        try validate(response)
        return try Self.decoder.decode(RemoteTaskPreparedAction.self, from: response.data)
    }

    func executeAction(
        _ prepared: RemoteTaskPreparedAction,
        baseURL: URL,
        bearerToken: String
    ) async -> RemoteTaskSyncResult {
        let scope = beginConnectionScope(baseURL: baseURL, bearerToken: bearerToken)
        do {
            let payload = RemoteTaskActionExecutionRequest(
                intent: prepared.intent,
                actionToken: prepared.actionToken
            )
            let request = try jsonRequest(
                baseURL: baseURL,
                path: "/api/tasks/\(prepared.intent.taskID.uuidString.lowercased())/actions/execute",
                method: "POST",
                value: payload,
                bearerToken: bearerToken
            )
            let response = try await scopedData(for: request, scope: scope)
            try validate(response)
            let summary = try Self.decoder.decode(RemoteTaskSummary.self, from: response.data)
            tasks = replacing(summary, in: tasks)
            return .success
        } catch {
            return result(for: error)
        }
    }

    func clearConnection() {
        connectionGeneration &+= 1
        lastBaseURL = nil
        lastBearerToken = nil
        retryAttempt = 0
        nextRetryAt = .distantPast
        tasks = []
        workspaces = []
        lastError = nil
    }

    private func retryFromReachability() async {
        guard let lastBaseURL, let lastBearerToken else { return }
        nextRetryAt = .distantPast
        _ = await sync(baseURL: lastBaseURL, bearerToken: lastBearerToken, force: true)
    }

    private func result(for error: Error) -> RemoteTaskSyncResult {
        if case ClientError.superseded = error { return .deferred }
        lastError = error.localizedDescription
        switch error {
        case ClientError.unauthorized: return .pairingRequired
        case ClientError.conflict: return .conflict
        default: return .offline
        }
    }

    private func flushOutbox(
        baseURL: URL,
        bearerToken: String,
        scope: AuthenticatedConnectionScope
    ) async throws {
        guard isCurrent(scope) else { throw ClientError.superseded }
        for initialDraft in store.drafts {
            var draft = initialDraft
            if draft.hostTaskID == nil {
                var request = try jsonRequest(
                    baseURL: baseURL,
                    path: "/api/tasks",
                    method: "POST",
                    value: draft.request,
                    bearerToken: bearerToken
                )
                request.timeoutInterval = 20
                let response = try await scopedData(for: request, scope: scope)
                try validate(response)
                let summary = try Self.decoder.decode(RemoteTaskSummary.self, from: response.data)
                guard summary.clientTaskID == draft.request.clientTaskID,
                      summary.idempotencyKey == draft.request.idempotencyKey
                else { throw ClientError.invalidResponse }
                try store.markAccepted(draftID: draft.id, hostTaskID: summary.id)
                tasks = replacing(summary, in: tasks)
                localDrafts = store.drafts
                guard let accepted = store.drafts.first(where: { $0.id == draft.id }) else {
                    throw ClientError.invalidResponse
                }
                draft = accepted
            }

            guard let hostTaskID = draft.hostTaskID else { throw ClientError.invalidResponse }
            for attachment in draft.attachments where !attachment.uploaded {
                let attachmentURL = try store.attachmentURL(
                    draftID: draft.id,
                    attachmentID: attachment.id
                )
                let data = try Data(contentsOf: attachmentURL, options: [.mappedIfSafe])
                let path = "/api/tasks/\(hostTaskID.uuidString.lowercased())/attachments/\(attachment.id)"
                var upload = try authenticatedRequest(
                    baseURL: baseURL,
                    path: path,
                    method: "PUT",
                    body: data,
                    contentType: "application/octet-stream",
                    bearerToken: bearerToken
                )
                upload.timeoutInterval = 60
                let response = try await scopedData(for: upload, scope: scope)
                try validate(response)
                try store.markAttachmentUploaded(draftID: draft.id, attachmentID: attachment.id)
                localDrafts = store.drafts
            }
            try store.finishIfUploaded(draftID: draft.id)
            localDrafts = store.drafts
        }
    }

    private func refreshSnapshot(
        baseURL: URL,
        bearerToken: String,
        scope: AuthenticatedConnectionScope
    ) async throws {
        guard isCurrent(scope) else { throw ClientError.superseded }
        let request = try authenticatedRequest(
            baseURL: baseURL,
            path: "/api/tasks",
            method: "GET",
            bearerToken: bearerToken
        )
        let response = try await scopedData(for: request, scope: scope)
        try validate(response)
        let snapshot = try Self.decoder.decode(RemoteTaskSnapshot.self, from: response.data)
        tasks = snapshot.tasks

        // A response can be lost after the Mac accepted a create. Reconcile by
        // the durable client ID, but keep attachment drafts until every upload
        // is individually acknowledged.
        for draft in store.drafts where draft.hostTaskID == nil {
            guard let host = snapshot.tasks.first(where: { $0.clientTaskID == draft.request.clientTaskID }) else {
                continue
            }
            try store.markAccepted(draftID: draft.id, hostTaskID: host.id)
            try store.finishIfUploaded(draftID: draft.id)
        }
        localDrafts = store.drafts
    }

    private func replacing(_ summary: RemoteTaskSummary, in tasks: [RemoteTaskSummary]) -> [RemoteTaskSummary] {
        var updated = tasks.filter { $0.clientTaskID != summary.clientTaskID }
        updated.append(summary)
        return updated.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func beginConnectionScope(
        baseURL: URL,
        bearerToken: String
    ) -> AuthenticatedConnectionScope {
        if lastBaseURL != baseURL || lastBearerToken != bearerToken {
            connectionGeneration &+= 1
        }
        lastBaseURL = baseURL
        lastBearerToken = bearerToken
        return AuthenticatedConnectionScope(
            generation: connectionGeneration,
            credential: bearerToken,
            baseURL: baseURL.absoluteString
        )
    }

    private func isCurrent(_ scope: AuthenticatedConnectionScope) -> Bool {
        scope.isCurrent(
            generation: connectionGeneration,
            credential: lastBearerToken,
            baseURL: lastBaseURL?.absoluteString
        )
    }

    private func scopedData(
        for request: URLRequest,
        scope: AuthenticatedConnectionScope
    ) async throws -> RemoteTaskTransportResponse {
        do {
            let response = try await transport.data(for: request)
            guard isCurrent(scope) else { throw ClientError.superseded }
            return response
        } catch {
            guard isCurrent(scope) else { throw ClientError.superseded }
            throw error
        }
    }

    private func jsonRequest<T: Encodable>(
        baseURL: URL,
        path: String,
        method: String,
        value: T,
        bearerToken: String
    ) throws -> URLRequest {
        try authenticatedRequest(
            baseURL: baseURL,
            path: path,
            method: method,
            body: Self.encoder.encode(value),
            contentType: "application/json",
            bearerToken: bearerToken
        )
    }

    private func authenticatedRequest(
        baseURL: URL,
        path: String,
        method: String,
        body: Data? = nil,
        contentType: String? = nil,
        bearerToken: String
    ) throws -> URLRequest {
        guard let url = endpoint(baseURL: baseURL, path: path) else { throw ClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue(contentType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func endpoint(baseURL: URL, path: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false
        else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let root = components.url else { return nil }
        return path.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    private func validate(_ response: RemoteTaskTransportResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw ClientError.unauthorized
        case 409:
            throw ClientError.conflict
        default:
            let message = (try? Self.decoder.decode(ErrorPayload.self, from: response.data).error)
                ?? "Mac returned HTTP \(response.statusCode)"
            throw ClientError.server(message)
        }
    }

    private struct ErrorPayload: Decodable { let error: String }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        value.outputFormatting = [.sortedKeys]
        return value
    }()

    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()
}
