import Foundation
import Network

struct RemoteHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: body)
    }
}

struct RemoteHTTPResponse {
    let status: Int
    var headers: [String: String]
    let body: Data

    static func html(_ html: String) -> RemoteHTTPResponse {
        RemoteHTTPResponse(
            status: 200,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: Data(html.utf8)
        )
    }

    static func json(status: Int, object: [String: Any], extraHeaders: [String: String] = [:]) -> RemoteHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            ?? Data(#"{"error":"encoding failure"}"#.utf8)
        return RemoteHTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"].merging(extraHeaders) { _, new in new },
            body: data
        )
    }

    static func json<T: Encodable>(status: Int, encodable: T) -> RemoteHTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(encodable))
            ?? Data(#"{"error":"encoding failure"}"#.utf8)
        return RemoteHTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }

    fileprivate func serialized() -> Data {
        var allHeaders = headers
        allHeaders["Content-Length"] = String(body.count)
        allHeaders["Connection"] = "close"
        allHeaders["Cache-Control"] = allHeaders["Cache-Control"] ?? "no-store"
        allHeaders["X-Content-Type-Options"] = "nosniff"
        allHeaders["X-Frame-Options"] = "DENY"
        allHeaders["Referrer-Policy"] = "no-referrer"
        allHeaders["Content-Security-Policy"] = allHeaders["Content-Security-Policy"]
            ?? "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"

        let reason: String
        switch status {
        case 200: reason = "OK"
        case 201: reason = "Created"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 409: reason = "Conflict"
        case 413: reason = "Content Too Large"
        case 429: reason = "Too Many Requests"
        case 503: reason = "Service Unavailable"
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for (key, value) in allHeaders.sorted(by: { $0.key < $1.key }) {
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}

@MainActor
final class RemoteApprovalHTTPServer {
    enum ServerError: LocalizedError {
        case invalidPort
        case requestTooLarge

        var errorDescription: String? {
            switch self {
            case .invalidPort: return "Remote approval server port is invalid"
            case .requestTooLarge: return "Remote approval request exceeded 64 KB"
            }
        }
    }

    private static let maximumRequestBytes = 65_536
    private let listener: NWListener
    private let route: @MainActor (RemoteHTTPRequest) -> RemoteHTTPResponse
    private var didReportReady = false
    private var connections: [UUID: RemoteHTTPConnection] = [:]

    var boundPort: UInt16? {
        listener.port?.rawValue
    }

    init(port: UInt16, route: @escaping @MainActor (RemoteHTTPRequest) -> RemoteHTTPResponse) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw ServerError.invalidPort }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: endpointPort)
        listener = try NWListener(using: parameters)
        self.route = route
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.accept(connection)
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready where !self.didReportReady:
                    self.didReportReady = true
                    completion(.success(()))
                case .failed(let error):
                    completion(.failure(error))
                default:
                    break
                }
            }
        }
        listener.start(queue: .main)
    }

    func stop() {
        let activeConnections = Array(connections.values)
        connections.removeAll()
        for connection in activeConnections {
            connection.cancel()
        }
        listener.cancel()
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        let handler = RemoteHTTPConnection(
            connection: connection,
            maximumBytes: Self.maximumRequestBytes,
            route: route,
            onFinish: { [weak self] in
                self?.connections.removeValue(forKey: id)
            }
        )
        connections[id] = handler
        handler.start()
    }
}

@MainActor
private final class RemoteHTTPConnection {
    private let connection: NWConnection
    private let maximumBytes: Int
    private let route: @MainActor (RemoteHTTPRequest) -> RemoteHTTPResponse
    private let onFinish: @MainActor () -> Void
    private var buffer = Data()
    private var finished = false

    init(
        connection: NWConnection,
        maximumBytes: Int,
        route: @escaping @MainActor (RemoteHTTPRequest) -> RemoteHTTPResponse,
        onFinish: @escaping @MainActor () -> Void
    ) {
        self.connection = connection
        self.maximumBytes = maximumBytes
        self.route = route
        self.onFinish = onFinish
    }

    func start() {
        connection.start(queue: .main)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let content { self.buffer.append(content) }
                if self.buffer.count > self.maximumBytes {
                    self.send(.json(status: 413, object: ["error": "request too large"]))
                    return
                }
                if let request = Self.parse(self.buffer) {
                    self.send(self.route(request))
                    return
                }
                if isComplete || error != nil {
                    self.send(.json(status: 400, object: ["error": "malformed request"]))
                    return
                }
                self.receive()
            }
        }
    }

    private func send(_ response: RemoteHTTPResponse) {
        connection.send(content: response.serialized(), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in
                self?.finish()
            }
        })
    }

    func cancel() {
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        connection.cancel()
        onFinish()
    }

    private static func parse(_ data: Data) -> RemoteHTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else { return nil }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard contentLength >= 0 else { return nil }
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        let rawTarget = String(parts[1])
        let path = URLComponents(string: rawTarget)?.path ?? rawTarget.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawTarget
        return RemoteHTTPRequest(
            method: String(parts[0]).uppercased(),
            path: path,
            headers: headers,
            body: body
        )
    }
}
