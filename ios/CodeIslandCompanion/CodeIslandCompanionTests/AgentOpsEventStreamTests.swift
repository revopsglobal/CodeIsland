import Foundation
import XCTest
@testable import CodeIslandCompanion

@MainActor
final class AgentOpsEventStreamTests: XCTestCase {
    func testResumesFromCursorAndSuppressesDuplicateTaskEventVersion() async throws {
        let event = AgentOpsEvent.fixture(version: 7)
        let cursor = "v1:1784846400000:33333333-3333-4333-8333-333333333333"
        let transport = EventStreamTransport(
            responses: [
                .sse(cursor: cursor, events: [event, event], staysOpen: true),
                .sse(cursor: cursor, events: [], staysOpen: true),
            ]
        )
        let cursorStore = MemoryEventCursorStore()
        var received: [AgentOpsEvent] = []
        let stream = AgentOpsEventStream(
            requestProvider: { cursor, _ in
                var request = URLRequest(
                    url: URL(string: "https://voice.agentops.test/v1/events")!
                )
                if let cursor {
                    request.setValue(cursor, forHTTPHeaderField: "Last-Event-ID")
                }
                return request
            },
            transport: transport,
            cursorStore: cursorStore,
            onEvent: { received.append($0) }
        )

        stream.start()
        await eventually { received.count == 1 }
        XCTAssertEqual(received, [event])
        XCTAssertEqual(cursorStore.load(), cursor)

        stream.setForeground(false)
        stream.setForeground(true)
        await eventually { await transport.openCount() == 2 }

        let requests = await transport.requests()
        XCTAssertEqual(
            requests.last?.value(forHTTPHeaderField: "Last-Event-ID"),
            cursor
        )
        stream.stop()
    }

    func testBackgroundStopsAndForegroundReconnectsWithoutLosingCursor() async {
        let transport = EventStreamTransport(
            responses: [
                .sse(
                    cursor: "v1:1784846400000:33333333-3333-4333-8333-333333333333",
                    events: [.fixture(version: 1)],
                    staysOpen: true
                ),
                .sse(
                    cursor: "v1:1784846401000:44444444-4444-4444-8444-444444444444",
                    events: [.fixture(version: 2)],
                    staysOpen: true
                ),
            ]
        )
        var versions: [Int] = []
        let stream = AgentOpsEventStream(
            requestProvider: { _, _ in
                URLRequest(url: URL(string: "https://voice.agentops.test/v1/events")!)
            },
            transport: transport,
            cursorStore: MemoryEventCursorStore(),
            onEvent: { versions.append($0.version) }
        )

        stream.start()
        await eventually { versions == [1] }
        stream.setForeground(false)
        let opensWhileBackgrounded = await transport.openCount()
        try? await Task.sleep(for: .milliseconds(50))
        let opensAfterWait = await transport.openCount()
        XCTAssertEqual(opensAfterWait, opensWhileBackgrounded)

        stream.setForeground(true)
        await eventually { versions == [1, 2] }
        stream.stop()
    }

    func testSecondUnauthorizedStopsStreamAndForcesSignOut() async {
        let transport = EventStreamTransport(
            responses: [
                .init(
                    statusCode: 401,
                    lines: AsyncThrowingStream { $0.finish() }
                ),
                .init(
                    statusCode: 401,
                    lines: AsyncThrowingStream { $0.finish() }
                ),
            ]
        )
        var refreshRequests: [Bool] = []
        var unauthorizedCount = 0
        let stream = AgentOpsEventStream(
            requestProvider: { _, refreshCredentials in
                refreshRequests.append(refreshCredentials)
                return URLRequest(
                    url: URL(string: "https://voice.agentops.test/v1/events")!
                )
            },
            transport: transport,
            cursorStore: MemoryEventCursorStore(),
            retryDelay: .milliseconds(1),
            onUnauthorized: { unauthorizedCount += 1 },
            onEvent: { _ in XCTFail("Unauthorized stream emitted an event") }
        )

        stream.start()
        await eventually { unauthorizedCount == 1 }
        try? await Task.sleep(for: .milliseconds(25))

        XCTAssertEqual(refreshRequests, [false, true])
        let openCount = await transport.openCount()
        XCTAssertEqual(openCount, 2)
        XCTAssertEqual(unauthorizedCount, 1)
    }
}

private final class MemoryEventCursorStore: AgentOpsEventCursorStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func load() -> String? {
        lock.withLock { value }
    }

    func save(_ cursor: String) {
        lock.withLock { value = cursor }
    }
}

private actor EventStreamTransport: AgentOpsEventStreamingTransport {
    private var queued: [AgentOpsEventStreamResponse]
    private var opened: [URLRequest] = []

    init(responses: [AgentOpsEventStreamResponse]) {
        queued = responses
    }

    func open(_ request: URLRequest) async throws -> AgentOpsEventStreamResponse {
        opened.append(request)
        guard !queued.isEmpty else {
            throw URLError(.cannotConnectToHost)
        }
        return queued.removeFirst()
    }

    func openCount() -> Int { opened.count }
    func requests() -> [URLRequest] { opened }
}

private extension AgentOpsEventStreamResponse {
    static func sse(
        cursor: String,
        events: [AgentOpsEvent],
        staysOpen: Bool
    ) -> AgentOpsEventStreamResponse {
        let encodedEvents = events.compactMap {
            try? JSONEncoder.agentOps.encode($0)
        }
        let lines = AsyncThrowingStream<String, Error> { continuation in
            let producer = Task<Void, Never> {
                for data in encodedEvents {
                    continuation.yield("id: \(cursor)")
                    continuation.yield("event: agentops")
                    continuation.yield("data: \(String(decoding: data, as: UTF8.self))")
                    continuation.yield("")
                }
                if staysOpen {
                    try? await Task.sleep(for: .seconds(30))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
        return AgentOpsEventStreamResponse(statusCode: 200, lines: lines)
    }
}

private extension AgentOpsEvent {
    static func fixture(version: Int) -> AgentOpsEvent {
        AgentOpsEvent(
            id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            taskId: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            eventType: "task_updated",
            version: version,
            createdAt: Date(timeIntervalSince1970: 1_784_846_400),
            payload: ["proofState": .string("pending")]
        )
    }
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () async -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}
