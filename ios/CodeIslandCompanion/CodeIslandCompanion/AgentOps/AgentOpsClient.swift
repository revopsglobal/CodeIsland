import Foundation

struct AgentOpsTransportResponse: Sendable {
    let statusCode: Int
    let data: Data
}

protocol AgentOpsTransport: Sendable {
    func data(for request: URLRequest) async throws -> AgentOpsTransportResponse
}

struct URLSessionAgentOpsTransport: AgentOpsTransport {
    func data(for request: URLRequest) async throws -> AgentOpsTransportResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentOpsClientError.invalidResponse
        }
        return AgentOpsTransportResponse(
            statusCode: httpResponse.statusCode,
            data: data
        )
    }
}

enum AgentOpsClientError: LocalizedError, Equatable {
    case invalidRequest
    case invalidResponse
    case unauthorized
    case server(code: String, retryable: Bool)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "The AgentOps request was invalid."
        case .invalidResponse:
            return "AgentOps returned an invalid response."
        case .unauthorized:
            return "Your AgentOps session expired. Sign in again."
        case .server(_, let retryable):
            return retryable
                ? "AgentOps is temporarily unavailable. Try again."
                : "AgentOps could not complete that request."
        }
    }
}

@MainActor
final class AgentOpsClient {
    private let baseURL: URL
    private let credentials: any AgentOpsCredentialProviding
    private let transport: any AgentOpsTransport
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var activeRequests: [UUID: Task<AgentOpsTransportResponse, Error>] = [:]

    init(
        baseURL: URL,
        credentials: any AgentOpsCredentialProviding,
        transport: any AgentOpsTransport = URLSessionAgentOpsTransport()
    ) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.transport = transport
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    func listWork() async throws -> [AgentOpsWorkSummary] {
        let response: AgentOpsWorkListResponse = try await request(path: "v1/work")
        return response.tasks
    }

    func work(id: UUID) async throws -> AgentOpsWorkSummary {
        struct Response: Decodable { let task: AgentOpsWorkSummary }
        let response: Response = try await request(path: "v1/work/\(id.uuidString.lowercased())")
        return response.task
    }

    func listApprovals() async throws -> [AgentOpsApprovalCard] {
        let response: AgentOpsApprovalListResponse = try await request(path: "v1/approvals")
        return response.approvals
    }

    func approval(id: UUID) async throws -> AgentOpsApprovalCard {
        struct Response: Decodable { let approval: AgentOpsApprovalCard }
        let response: Response = try await request(
            path: "v1/approvals/\(id.uuidString.lowercased())"
        )
        return response.approval
    }

    func cancelNonessentialNetworkWork() {
        let tasks = activeRequests.values
        activeRequests.removeAll()
        for task in tasks {
            task.cancel()
        }
    }

    func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Response {
        let firstToken = try await credentials.accessToken()
        var urlRequest = try makeRequest(
            path: path,
            method: method,
            body: body,
            accessToken: firstToken
        )
        var response = try await execute(urlRequest)

        if response.statusCode == 401 {
            let refreshedToken: String
            do {
                refreshedToken = try await credentials.refreshAccessToken()
            } catch {
                throw AgentOpsClientError.unauthorized
            }
            urlRequest.setValue(
                "Bearer \(refreshedToken)",
                forHTTPHeaderField: "Authorization"
            )
            response = try await execute(urlRequest)
            if response.statusCode == 401 {
                await credentials.forceSignOut()
                throw AgentOpsClientError.unauthorized
            }
        }

        guard (200..<300).contains(response.statusCode) else {
            if let payload = try? decoder.decode(AgentOpsAPIError.self, from: response.data) {
                throw AgentOpsClientError.server(
                    code: payload.error,
                    retryable: payload.retryable ?? false
                )
            }
            throw AgentOpsClientError.invalidResponse
        }

        do {
            return try decoder.decode(Response.self, from: response.data)
        } catch {
            throw AgentOpsClientError.invalidResponse
        }
    }

    func encode<Request: Encodable>(_ value: Request) throws -> Data {
        try encoder.encode(value)
    }

    private func makeRequest(
        path: String,
        method: String,
        body: Data?,
        accessToken: String
    ) throws -> URLRequest {
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        guard
            !segments.isEmpty,
            segments.allSatisfy({ $0 != "." && $0 != ".." }),
            ["GET", "POST", "PUT", "PATCH", "DELETE"].contains(method)
        else {
            throw AgentOpsClientError.invalidRequest
        }
        let url = segments.reduce(baseURL) { partial, segment in
            partial.appendingPathComponent(String(segment))
        }
        guard url.scheme == "https", url.host == baseURL.host else {
            throw AgentOpsClientError.invalidRequest
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 125
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func execute(_ request: URLRequest) async throws -> AgentOpsTransportResponse {
        let id = UUID()
        let transport = self.transport
        let task = Task {
            try Task.checkCancellation()
            return try await transport.data(for: request)
        }
        activeRequests[id] = task
        defer { activeRequests[id] = nil }
        return try await task.value
    }
}
