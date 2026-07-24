import Foundation

struct AgentOpsEventStreamResponse: Sendable {
    let statusCode: Int
    let lines: AsyncThrowingStream<String, Error>
}

protocol AgentOpsEventStreamingTransport: Sendable {
    func open(_ request: URLRequest) async throws -> AgentOpsEventStreamResponse
}

struct URLSessionAgentOpsEventTransport: AgentOpsEventStreamingTransport {
    func open(_ request: URLRequest) async throws -> AgentOpsEventStreamResponse {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentOpsClientError.invalidResponse
        }
        let lines = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return AgentOpsEventStreamResponse(
            statusCode: httpResponse.statusCode,
            lines: lines
        )
    }
}

protocol AgentOpsEventCursorStoring: Sendable {
    func load() -> String?
    func save(_ cursor: String)
}

final class UserDefaultsAgentOpsEventCursorStore:
    AgentOpsEventCursorStoring,
    @unchecked Sendable
{
    private static let key = "agentops.native.events.cursor.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> String? {
        lock.withLock { defaults.string(forKey: Self.key) }
    }

    func save(_ cursor: String) {
        lock.withLock { defaults.set(cursor, forKey: Self.key) }
    }
}

@MainActor
final class AgentOpsEventStream {
    typealias RequestProvider =
        @MainActor (_ cursor: String?, _ refreshCredentials: Bool) async throws
            -> URLRequest
    typealias EventHandler = @MainActor (AgentOpsEvent) -> Void
    typealias UnauthorizedHandler = @MainActor () async -> Void

    private let requestProvider: RequestProvider
    private let transport: any AgentOpsEventStreamingTransport
    private let cursorStore: any AgentOpsEventCursorStoring
    private let onEvent: EventHandler
    private let onUnauthorized: UnauthorizedHandler
    private let retryDelay: Duration
    private let decoder: JSONDecoder

    private var loopTask: Task<Void, Never>?
    private var wantsEvents = false
    private var isForeground = true
    private var seenKeys: Set<String> = []
    private var seenOrder: [String] = []
    private var cursor: String?

    init(
        requestProvider: @escaping RequestProvider,
        transport: any AgentOpsEventStreamingTransport =
            URLSessionAgentOpsEventTransport(),
        cursorStore: any AgentOpsEventCursorStoring =
            UserDefaultsAgentOpsEventCursorStore(),
        retryDelay: Duration = .seconds(2),
        onUnauthorized: @escaping UnauthorizedHandler = {},
        onEvent: @escaping EventHandler
    ) {
        self.requestProvider = requestProvider
        self.transport = transport
        self.cursorStore = cursorStore
        self.retryDelay = retryDelay
        self.onUnauthorized = onUnauthorized
        self.onEvent = onEvent
        cursor = cursorStore.load()
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    deinit {
        loopTask?.cancel()
    }

    func start() {
        wantsEvents = true
        restartIfNeeded()
    }

    func stop() {
        wantsEvents = false
        loopTask?.cancel()
        loopTask = nil
    }

    func setForeground(_ foreground: Bool) {
        isForeground = foreground
        if foreground {
            restartIfNeeded()
        } else {
            loopTask?.cancel()
            loopTask = nil
        }
    }

    private func restartIfNeeded() {
        guard wantsEvents, isForeground, loopTask == nil else { return }
        loopTask = Task { @MainActor [weak self] in
            await self?.run()
        }
    }

    private func run() async {
        defer { loopTask = nil }
        var refreshCredentials = false
        while wantsEvents, isForeground, !Task.isCancelled {
            do {
                let request = try await requestProvider(
                    cursor,
                    refreshCredentials
                )
                let response = try await transport.open(request)
                if response.statusCode == 401, !refreshCredentials {
                    refreshCredentials = true
                    continue
                }
                if response.statusCode == 401 {
                    wantsEvents = false
                    await onUnauthorized()
                    return
                }
                guard (200..<300).contains(response.statusCode) else {
                    throw AgentOpsClientError.invalidResponse
                }
                refreshCredentials = false
                var parser = AgentOpsSSEParser()
                for try await line in response.lines {
                    try Task.checkCancellation()
                    if let message = parser.consume(line: line) {
                        consume(message)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                refreshCredentials = false
            }
            guard wantsEvents, isForeground, !Task.isCancelled else { return }
            try? await Task.sleep(for: retryDelay)
        }
    }

    private func consume(_ message: AgentOpsSSEMessage) {
        guard
            message.event == nil || message.event == "agentops",
            Self.isValidCursor(message.id),
            let data = message.data.data(using: .utf8),
            let event = try? decoder.decode(AgentOpsEvent.self, from: data)
        else { return }

        cursor = message.id.lowercased()
        cursorStore.save(message.id.lowercased())
        let key = [
            event.taskId.uuidString.lowercased(),
            event.eventType,
            String(event.version),
        ].joined(separator: ":")
        guard seenKeys.insert(key).inserted else { return }
        seenOrder.append(key)
        if seenOrder.count > 4_096 {
            let removalCount = seenOrder.count - 2_048
            let removed = Array(seenOrder.prefix(removalCount))
            seenOrder.removeFirst(removalCount)
            seenKeys.subtract(removed)
        }
        onEvent(event)
    }

    private static func isValidCursor(_ value: String) -> Bool {
        value.range(
            of: #"^v1:[0-9]{13}:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"#,
            options: .regularExpression
        ) != nil
    }
}

private struct AgentOpsSSEMessage {
    let id: String
    let event: String?
    let data: String
}

private struct AgentOpsSSEParser {
    private var id: String?
    private var event: String?
    private var dataLines: [String] = []

    mutating func consume(line: String) -> AgentOpsSSEMessage? {
        if line.isEmpty {
            defer { reset() }
            guard let id, !dataLines.isEmpty else { return nil }
            return AgentOpsSSEMessage(
                id: id,
                event: event,
                data: dataLines.joined(separator: "\n")
            )
        }
        guard !line.hasPrefix(":") else { return nil }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let field = parts.first else { return nil }
        let rawValue = parts.count == 2 ? String(parts[1]) : ""
        let value = rawValue.first == " " ? String(rawValue.dropFirst()) : rawValue
        switch field {
        case "id":
            if !value.contains("\u{0000}") { id = value }
        case "event":
            event = value
        case "data":
            dataLines.append(value)
        default:
            break
        }
        return nil
    }

    private mutating func reset() {
        id = nil
        event = nil
        dataLines.removeAll(keepingCapacity: true)
    }
}
