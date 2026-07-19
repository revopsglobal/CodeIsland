import CryptoKit
import Darwin
import Foundation
import Network
import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class RemoteTaskHTTPAPITests: XCTestCase {
    func testAuthenticatedTaskLifecycleIsDeviceBoundAndIdempotentOverRealListener() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let service = fixture.makeService()
        service.start(appState: fixture.appState)
        defer { service.stop() }
        let port = try await waitForPort(service)
        let first = try await pair(service: service, port: port, name: "Greg iPhone")
        let request = fixture.request(provider: .codex)

        let unauthorized = try await send(port: port, method: "GET", path: "/api/tasks")
        XCTAssertEqual(unauthorized.status, 401)

        let workspaces = try await send(
            port: port,
            method: "GET",
            path: "/api/tasks/workspaces",
            token: first.deviceToken
        )
        XCTAssertEqual(workspaces.status, 200)
        XCTAssertEqual(
            try decode(RemoteWorkspaceSnapshot.self, from: workspaces.data).workspaces.map(\.name),
            [fixture.workspace.lastPathComponent]
        )

        let created = try await send(
            port: port,
            method: "POST",
            path: "/api/tasks",
            token: first.deviceToken,
            body: encode(request)
        )
        XCTAssertEqual(created.status, 201)
        let task = try decode(RemoteTaskSummary.self, from: created.data)
        XCTAssertEqual(task.clientTaskID, request.clientTaskID)
        XCTAssertEqual(task.provider, .codex)

        let replay = try await send(
            port: port,
            method: "POST",
            path: "/api/tasks",
            token: first.deviceToken,
            body: encode(request)
        )
        XCTAssertEqual(replay.status, 200)
        XCTAssertEqual(try decode(RemoteTaskSummary.self, from: replay.data).id, task.id)
        XCTAssertEqual(fixture.codex.starts.count, 1)

        let list = try await send(port: port, method: "GET", path: "/api/tasks", token: first.deviceToken)
        XCTAssertEqual(list.status, 200)
        XCTAssertEqual(try decode(RemoteTaskSnapshot.self, from: list.data).tasks.map(\.id), [task.id])

        let detail = try await send(
            port: port,
            method: "GET",
            path: "/api/tasks/\(task.id.uuidString.lowercased())",
            token: first.deviceToken
        )
        XCTAssertEqual(detail.status, 200)

        service.rotatePairingCode()
        let second = try await pair(service: service, port: port, name: "Other device")
        let forbidden = try await send(
            port: port,
            method: "GET",
            path: "/api/tasks/\(task.id.uuidString.lowercased())",
            token: second.deviceToken
        )
        XCTAssertEqual(forbidden.status, 403)

        let followUp = RemoteTaskFollowUpRequest(
            taskID: task.id,
            idempotencyKey: UUID(),
            text: "Also verify dark mode"
        )
        for expectedStatus in [200, 200] {
            let response = try await send(
                port: port,
                method: "POST",
                path: "/api/tasks/\(task.id.uuidString.lowercased())/follow-up",
                token: first.deviceToken,
                body: encode(followUp)
            )
            XCTAssertEqual(response.status, expectedStatus)
        }
        XCTAssertEqual(fixture.codex.followUps, ["Also verify dark mode"])

        let currentSequence = try XCTUnwrap(fixture.store.task(id: task.id)?.summary.lastReceiptSequence)
        let intent = RemoteTaskActionIntent(
            taskID: task.id,
            action: .commit,
            arguments: ["message": "Finish"],
            expectedReceiptSequence: currentSequence
        )
        let preparedResponse = try await send(
            port: port,
            method: "POST",
            path: "/api/tasks/\(task.id.uuidString.lowercased())/actions/prepare",
            token: first.deviceToken,
            body: encode(intent)
        )
        XCTAssertEqual(preparedResponse.status, 200)
        let prepared = try decode(RemoteTaskPreparedAction.self, from: preparedResponse.data)
        let execution = RemoteTaskActionExecutionRequest(intent: intent, actionToken: prepared.actionToken)
        let executed = try await send(
            port: port,
            method: "POST",
            path: "/api/tasks/\(task.id.uuidString.lowercased())/actions/execute",
            token: first.deviceToken,
            body: encode(execution)
        )
        XCTAssertEqual(executed.status, 200)
        let replayedAction = try await send(
            port: port,
            method: "POST",
            path: "/api/tasks/\(task.id.uuidString.lowercased())/actions/execute",
            token: first.deviceToken,
            body: encode(execution)
        )
        XCTAssertEqual(replayedAction.status, 403)

        let cancelled = try await send(
            port: port,
            method: "POST",
            path: "/api/tasks/\(task.id.uuidString.lowercased())/cancel",
            token: first.deviceToken,
            body: Data()
        )
        XCTAssertEqual(cancelled.status, 200)
        let cancelledAgain = try await send(
            port: port,
            method: "POST",
            path: "/api/tasks/\(task.id.uuidString.lowercased())/cancel",
            token: first.deviceToken,
            body: Data()
        )
        XCTAssertEqual(cancelledAgain.status, 200)
        XCTAssertEqual(fixture.codex.cancellations, [task.id])

        let missing = try await send(
            port: port,
            method: "GET",
            path: "/api/tasks/\(UUID().uuidString.lowercased())",
            token: first.deviceToken
        )
        XCTAssertEqual(missing.status, 404)
        let method = try await send(
            port: port,
            method: "DELETE",
            path: "/api/tasks/\(task.id.uuidString.lowercased())",
            token: first.deviceToken
        )
        XCTAssertEqual(method.status, 405)
    }

    func testAttachmentUploadValidatesIdentityHashAndStartsExactlyOnce() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let service = fixture.makeService()
        service.start(appState: fixture.appState)
        defer { service.stop() }
        let port = try await waitForPort(service)
        let paired = try await pair(service: service, port: port, name: "Greg iPhone")
        let bytes = Data("private fixture context".utf8)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let descriptor = RemoteTaskAttachmentDescriptor(
            id: "context-1",
            displayName: "context.txt",
            byteCount: Int64(bytes.count),
            mediaType: "text/plain",
            sha256: digest
        )
        let request = fixture.request(provider: .claude, attachments: [descriptor])
        let created = try await send(
            port: port,
            method: "POST",
            path: "/api/tasks",
            token: paired.deviceToken,
            body: encode(request)
        )
        let task = try decode(RemoteTaskSummary.self, from: created.data)
        XCTAssertTrue(fixture.claude.starts.isEmpty)

        let wrong = try await send(
            port: port,
            method: "PUT",
            path: "/api/tasks/\(task.id.uuidString.lowercased())/attachments/context-1",
            token: paired.deviceToken,
            contentType: "application/octet-stream",
            body: Data("wrong".utf8)
        )
        XCTAssertEqual(wrong.status, 409)
        XCTAssertTrue(fixture.claude.starts.isEmpty)

        for _ in 0..<2 {
            let uploaded = try await send(
                port: port,
                method: "PUT",
                path: "/api/tasks/\(task.id.uuidString.lowercased())/attachments/context-1",
                token: paired.deviceToken,
                contentType: "application/octet-stream",
                body: bytes
            )
            XCTAssertEqual(uploaded.status, 200)
        }
        XCTAssertEqual(fixture.claude.starts.count, 1)
        XCTAssertEqual(fixture.claude.starts.first?.attachments.count, 1)
        let delivered = try XCTUnwrap(fixture.claude.starts.first?.attachments.first)
        XCTAssertTrue(RemoteCwdFilter.contains(delivered, in: fixture.workspace))
        XCTAssertTrue(delivered.path.contains("/.codeisland/remote-task-attachments/"))
    }

    func testPathAwareBodyLimitsRejectBeforeBufferingAndDetectDishonestLengths() async throws {
        let server = try RemoteApprovalHTTPServer(port: 0) { request in
            .json(status: 200, object: ["bytes": request.body.count])
        }
        let ready = expectation(description: "server ready")
        server.start { _ in ready.fulfill() }
        await fulfillment(of: [ready], timeout: 3)
        defer { server.stop() }
        let port = try XCTUnwrap(server.boundPort)

        let ordinaryBody = Data(repeating: 0x61, count: 70_000)
        let ordinary = try await rawRequest(
            port: port,
            head: "POST /api/tasks HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(ordinaryBody.count)\r\n\r\n",
            body: ordinaryBody
        )
        XCTAssertEqual(ordinary.status, 413)

        let allowed = try await rawRequest(
            port: port,
            head: "PUT /api/tasks/00000000-0000-0000-0000-000000000000/attachments/a HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(ordinaryBody.count)\r\n\r\n",
            body: ordinaryBody
        )
        XCTAssertEqual(allowed.status, 200)

        let oversized = try await rawRequest(
            port: port,
            head: "PUT /api/tasks/00000000-0000-0000-0000-000000000000/attachments/a HTTP/1.1\r\nHost: localhost\r\nContent-Length: 26214401\r\n\r\n"
        )
        XCTAssertEqual(oversized.status, 413)

        let missing = try await rawRequest(
            port: port,
            head: "PUT /api/tasks/00000000-0000-0000-0000-000000000000/attachments/a HTTP/1.1\r\nHost: localhost\r\n\r\n"
        )
        XCTAssertEqual(missing.status, 400)
        let negative = try await rawRequest(
            port: port,
            head: "POST /api/tasks HTTP/1.1\r\nHost: localhost\r\nContent-Length: -1\r\n\r\n"
        )
        XCTAssertEqual(negative.status, 400)
        let extra = try await rawRequest(
            port: port,
            head: "POST /api/tasks HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2\r\n\r\n",
            body: Data("four".utf8)
        )
        XCTAssertEqual(extra.status, 400)
    }
}

@MainActor
private final class Fixture {
    let appState = AppState()
    let root: URL
    let workspace: URL
    let store: RemoteTaskStore
    let catalog: RemoteWorkspaceCatalog
    let attachments: RemoteTaskAttachmentStore
    let codex = MockRunner(provider: .codex)
    let claude = MockRunner(provider: .claude)
    let coordinator: RemoteTaskCoordinator

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandTaskHTTP-\(UUID().uuidString)", isDirectory: true)
        workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        store = RemoteTaskStore(
            snapshotURL: root.appendingPathComponent("tasks.json"),
            receiptsURL: root.appendingPathComponent("receipts.jsonl"),
            serverName: "Test Mac"
        )
        catalog = RemoteWorkspaceCatalog(
            allowedRoots: [root],
            candidates: [.init(url: workspace, source: .saved)],
            homeDirectory: root.appendingPathComponent("home")
        )
        attachments = RemoteTaskAttachmentStore(baseURL: root.appendingPathComponent("attachments"))
        coordinator = RemoteTaskCoordinator(
            store: store,
            workspaceCatalog: catalog,
            attachmentStore: attachments,
            codex: codex.adapter,
            claude: claude.adapter
        )
    }

    func makeService() -> RemoteApprovalService {
        RemoteApprovalService(
            deviceStore: RemoteApprovalDeviceStore(stateURL: root.appendingPathComponent("devices.json")),
            coordinator: RemoteApprovalCoordinator(auditURL: root.appendingPathComponent("audit.jsonl")),
            localPortOverride: 0,
            enabledOverride: true,
            remoteTasksEnabled: true,
            remoteTaskCoordinatorOverride: coordinator,
            tailscaleConfigurator: { _, _ in "https://codeisland-task-test.invalid" }
        )
    }

    func request(
        provider: RemoteTaskProvider,
        attachments: [RemoteTaskAttachmentDescriptor] = []
    ) -> RemoteTaskCreateRequest {
        RemoteTaskCreateRequest(
            clientTaskID: UUID(),
            idempotencyKey: UUID(),
            prompt: "Implement and test",
            workspaceID: catalog.entries[0].id,
            provider: provider,
            authority: .editAndTest,
            attachments: attachments
        )
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
private final class MockRunner {
    struct Start { let taskID: UUID; let attachments: [URL] }
    let provider: RemoteTaskProvider
    var starts: [Start] = []
    var followUps: [String] = []
    var cancellations: [UUID] = []

    init(provider: RemoteTaskProvider) { self.provider = provider }

    var adapter: RemoteTaskProviderRunner {
        RemoteTaskProviderRunner(
            provider: provider,
            isAvailable: { true },
            start: { [weak self] taskID, _, _, attachments in
                self?.starts.append(.init(taskID: taskID, attachments: attachments))
            },
            restore: { _, _, _ in },
            followUp: { [weak self] _, text, _ in self?.followUps.append(text) },
            cancel: { [weak self] taskID in self?.cancellations.append(taskID) }
        )
    }
}

private struct HTTPResult {
    let status: Int
    let data: Data
}

@MainActor
private func waitForPort(_ service: RemoteApprovalService) async throws -> UInt16 {
    let deadline = ContinuousClock.now + .seconds(3)
    while ContinuousClock.now < deadline {
        if let port = service.boundLocalPort, port > 0 { return port }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw URLError(.cannotConnectToHost)
}

@MainActor
private func pair(service: RemoteApprovalService, port: UInt16, name: String) async throws -> RemotePairResponse {
    let result = try await send(
        port: port,
        method: "POST",
        path: "/api/pair",
        body: encode(RemotePairRequest(code: service.pairingCode, deviceName: name))
    )
    XCTAssertEqual(result.status, 201)
    return try decode(RemotePairResponse.self, from: result.data)
}

private func send(
    port: UInt16,
    method: String,
    path: String,
    token: String? = nil,
    contentType: String = "application/json",
    body: Data? = nil
) async throws -> HTTPResult {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    request.httpMethod = method
    request.timeoutInterval = 5
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body {
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    return HTTPResult(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
}

private func encode<T: Encodable>(_ value: T) -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return (try? encoder.encode(value)) ?? Data()
}

private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: data)
}

private func rawRequest(port: UInt16, head: String, body: Data = Data()) async throws -> HTTPResult {
    try await Task.detached {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.ECONNREFUSED) }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }
        var request = Data(head.utf8)
        request.append(body)
        try request.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.send(descriptor, bytes.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
                guard count > 0 else { throw POSIXError(.EPIPE) }
                sent += count
            }
        }
        shutdown(descriptor, SHUT_WR)
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = recv(descriptor, &buffer, buffer.count, 0)
            if count <= 0 { break }
            response.append(buffer, count: count)
        }
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = response.range(of: separator),
              let header = String(data: response[..<headerRange.lowerBound], encoding: .utf8),
              let status = Int(header.components(separatedBy: " ").dropFirst().first ?? "")
        else { throw URLError(.badServerResponse) }
        return HTTPResult(status: status, data: response.subdata(in: headerRange.upperBound..<response.count))
    }.value
}
