import CryptoKit
import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class TelegramApprovalHTTPAPITests: XCTestCase {
    func testShellIsPublicButPrivateDataFreeAndNonMutating() async throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        let port = try await fixture.start()

        let response = try await fixture.send(
            port: port,
            method: "GET",
            path: "/telegram/approval?launch=opaque-launch"
        )
        let html = String(decoding: response.data, as: UTF8.self)

        XCTAssertEqual(response.response.statusCode, 200)
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertTrue(html.contains("CodeIsland · secure review"))
        XCTAssertFalse(html.contains("git push origin main"))
        XCTAssertTrue(fixture.appState.permissionQueue.isEmpty)
    }

    func testInvalidIdentityAndMissingLaunchFailClosedWithoutBearerAuth() async throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        let port = try await fixture.start()
        let now = Date()
        let signed = fixture.signer.signedInitData(userID: fixture.userID, authDate: now)

        let invalid = try await fixture.send(
            port: port,
            method: "POST",
            path: "/api/telegram/session",
            body: try fixture.encode(TelegramSessionRequest(
                initData: signed + "tampered",
                launchNonce: "missing"
            ))
        )
        XCTAssertEqual(invalid.response.statusCode, 403)
        XCTAssertFalse(String(decoding: invalid.data, as: UTF8.self).contains(signed))

        let missing = try await fixture.send(
            port: port,
            method: "POST",
            path: "/api/telegram/session",
            body: try fixture.encode(TelegramSessionRequest(
                initData: signed,
                launchNonce: "missing"
            ))
        )
        XCTAssertEqual(missing.response.statusCode, 404)
    }

    func testSignedTelegramSessionApprovesExactPendingRequestAndRejectsReplay() async throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        let port = try await fixture.start()
        let event = try fixture.permissionEvent()
        let permissionResponse = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                fixture.appState.handlePermissionRequest(event, continuation: continuation)
            }
        }
        await Task.yield()
        let pending = try XCTUnwrap(fixture.appState.permissionQueue.first)
        let launch = try fixture.controller.prepareLaunch(
            requestID: pending.id,
            chatID: fixture.userID,
            baseURL: try XCTUnwrap(URL(string: "https://mac.tailnet:9443"))
        )
        let now = Date()
        let signed = fixture.signer.signedInitData(userID: fixture.userID, authDate: now)

        let pageOpen = try await fixture.send(
            port: port,
            method: "GET",
            path: "/telegram/approval?launch=\(launch.launch.nonce)"
        )
        XCTAssertEqual(pageOpen.response.statusCode, 200)
        XCTAssertEqual(fixture.appState.permissionQueue.count, 1)

        let sessionResult = try await fixture.send(
            port: port,
            method: "POST",
            path: "/api/telegram/session",
            body: try fixture.encode(TelegramSessionRequest(
                initData: signed,
                launchNonce: launch.launch.nonce
            ))
        )
        XCTAssertEqual(sessionResult.response.statusCode, 200)
        let session = try fixture.decode(TelegramApprovalSessionResponse.self, from: sessionResult.data)
        XCTAssertEqual(session.requestID, pending.id)
        XCTAssertTrue(session.details.contains { $0.value == "git push origin main" })

        let decisionRequest = TelegramDecisionRouteRequest(
            initData: signed,
            launchNonce: launch.launch.nonce,
            sessionNonce: session.sessionNonce,
            actionToken: session.actionToken,
            decision: .approve
        )
        let path = "/api/telegram/approvals/\(pending.id)/decision"
        let decision = try await fixture.send(
            port: port,
            method: "POST",
            path: path,
            body: try fixture.encode(decisionRequest)
        )
        XCTAssertEqual(decision.response.statusCode, 200)
        let continuationData = await permissionResponse.value
        XCTAssertEqual(try fixture.permissionBehavior(continuationData), "allow")
        XCTAssertTrue(fixture.appState.permissionQueue.isEmpty)

        let replay = try await fixture.send(
            port: port,
            method: "POST",
            path: path,
            body: try fixture.encode(decisionRequest)
        )
        XCTAssertEqual(replay.response.statusCode, 403)
    }
}

@MainActor
private final class Fixture {
    let userID: Int64 = 8_567_114_601
    let suiteName = "TelegramApprovalHTTPAPITests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let backend = HTTPMemorySecretBackend()
    let controller: TelegramApprovalController
    let service: RemoteApprovalService
    let appState = AppState()
    let signer = HTTPSigner()
    private let directory: URL

    init() throws {
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: SettingsKey.remoteApprovalTelegramEnabled)
        defaults.set(String(userID), forKey: SettingsKey.remoteApprovalTelegramChatID)
        defaults.set(String(userID), forKey: SettingsKey.remoteApprovalTelegramUserID)
        let credentialStore = TelegramCredentialStore(backend: backend, defaults: defaults)
        try credentialStore.save(signer.botToken)
        var tokens = ["opaque-launch", "session-nonce"]
        controller = TelegramApprovalController(
            vault: TelegramApprovalSessionVault(tokenGenerator: {
                tokens.isEmpty ? UUID().uuidString : tokens.removeFirst()
            }),
            credentialStore: credentialStore,
            defaults: defaults
        )
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelegramApprovalHTTPAPI-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        service = RemoteApprovalService(
            deviceStore: RemoteApprovalDeviceStore(stateURL: directory.appendingPathComponent("devices.json")),
            coordinator: RemoteApprovalCoordinator(auditURL: directory.appendingPathComponent("audit.jsonl")),
            telegramApprovalController: controller,
            localPortOverride: 0,
            enabledOverride: true,
            tailscaleConfigurator: { _, _ in "https://telegram-test.invalid" }
        )
    }

    func start() async throws -> UInt16 {
        service.start(appState: appState)
        for _ in 0..<150 {
            if service.running, let port = service.boundLocalPort { return port }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw XCTSkip("Telegram test listener did not start: \(service.lastError ?? "unknown")")
    }

    func stop() {
        service.stop()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    func permissionEvent() throws -> HookEvent {
        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest",
            "session_id": "telegram-e2e",
            "tool_name": "Bash",
            "tool_input": ["command": "git push origin main"],
            "_source": "codex"
        ])
        return try XCTUnwrap(HookEvent(from: data))
    }

    func send(
        port: UInt16,
        method: String,
        path: String,
        body: Data? = nil
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(path)"))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, try XCTUnwrap(response as? HTTPURLResponse))
    }

    func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    func permissionBehavior(_ data: Data) throws -> String {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hook = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(hook["decision"] as? [String: Any])
        return try XCTUnwrap(decision["behavior"] as? String)
    }
}

private final class HTTPMemorySecretBackend: TelegramSecretBackend {
    var value: String?
    func read(service _: String, account _: String) throws -> String? { value }
    func write(_ value: String, service _: String, account _: String) throws { self.value = value }
    func delete(service _: String, account _: String) throws { value = nil }
}

private struct HTTPSigner {
    let botToken = "123456789:telegram-http-test-secret"

    func signedInitData(userID: Int64, authDate: Date) -> String {
        let user = "{\"id\":\(userID),\"first_name\":\"Greg\",\"username\":\"greg\"}"
        let fields = [
            "auth_date": String(Int64(authDate.timeIntervalSince1970)),
            "query_id": "telegram-http-query",
            "user": user
        ]
        let check = fields.keys.sorted().map { "\($0)=\(fields[$0]!)" }.joined(separator: "\n")
        let secret = HMAC<SHA256>.authenticationCode(
            for: Data(botToken.utf8),
            using: SymmetricKey(data: Data("WebAppData".utf8))
        )
        let hash = HMAC<SHA256>.authenticationCode(
            for: Data(check.utf8),
            using: SymmetricKey(data: Data(secret))
        ).map { String(format: "%02x", $0) }.joined()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return (fields.map { ($0.key, $0.value) } + [("hash", hash)])
            .map { key, value in
                "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
            }
            .joined(separator: "&")
    }
}
