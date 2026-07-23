import Foundation
import XCTest
@testable import CodeIsland
import CodeIslandCore

/// End-to-end coverage of the permission surface debounce over the real wire.
///
/// These run an actual `HookServer` on a real unix socket and drive it with the
/// real `codeisland-bridge` binary — the same client the OpenCode plugin shells
/// out to for blocking events — using the payload shapes the plugin emits for
/// `permission.asked` / `permission.replied`, at the ~3ms spacing observed in
/// `~/.local/share/opencode/log/opencode.log`. Timing is wall-clock, not
/// simulated, so the settling window is exercised as it ships.
@MainActor
final class HookServerPermissionDebounceE2ETests: XCTestCase {
    private var socketPath: String!
    private var previousSocketPath: String?
    private var previousPluginSessionMode: Any?
    private var server: HookServer?

    override func setUp() async throws {
        try await super.setUp()
        previousSocketPath = ProcessInfo.processInfo.environment["CODEISLAND_SOCKET_PATH"]
        socketPath = "/tmp/codeisland-e2e-\(UUID().uuidString.prefix(8)).sock"
        setenv("CODEISLAND_SOCKET_PATH", socketPath, 1)
        // "hide" would auto-allow plugin events in HookServer before AppState ever
        // sees them, which silently turns these into no-ops. Pin the default.
        previousPluginSessionMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("separate", forKey: SettingsKey.pluginSessionMode)
    }

    override func tearDown() async throws {
        server?.stop()
        server = nil
        unlink(socketPath)
        if let previousSocketPath {
            setenv("CODEISLAND_SOCKET_PATH", previousSocketPath, 1)
        } else {
            unsetenv("CODEISLAND_SOCKET_PATH")
        }
        if let previousPluginSessionMode {
            UserDefaults.standard.set(previousPluginSessionMode, forKey: SettingsKey.pluginSessionMode)
        } else {
            UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
        }
        try await super.tearDown()
    }

    /// The reported flicker, replayed: a burst of asks that each get replied to a
    /// few milliseconds later. Not one of them may reach the UI.
    func testOpenCodeAskThenInstantReplyBurstNeverSurfacesACard() async throws {
        let bridge = try XCTUnwrap(bridgeBinaryPath(), "codeisland-bridge not built")
        let appState = try await startServer()
        let sessionId = "opencode-e2e-burst"

        var surfacedDuringBurst = 0
        var behaviors: [String] = []

        for index in 0..<8 {
            // `permission.asked` — blocking, so the plugin routes it through the
            // bridge binary and waits on the response.
            async let response = runBridge(bridge, payload: [
                "hook_event_name": "PermissionRequest",
                "session_id": sessionId,
                "tool_name": "External_directory",
                "tool_input": ["patterns": ["/private/tmp/ringer/work"], "metadata": NSNull()],
                "_source": "opencode",
                "_opencode_request_id": "per_e2e_\(index)"
            ])

            // Wait for the ask to land (subprocess spawn dominates here; in the real
            // plugin the ask is already on the wire before OpenCode replies).
            try await waitUntil("ask \(index) reaches the server") {
                !appState.stagedPermissions.isEmpty || !appState.permissionQueue.isEmpty
            }
            XCTAssertEqual(appState.stagedPermissions.count, 1, "ask \(index) must be settling, not queued")

            // OpenCode grants it ~3ms later; the plugin forwards `permission.replied`
            // as a PostToolUse over its own socket (non-blocking events skip the bridge).
            try await Task.sleep(nanoseconds: 3_000_000)
            try sendEvent([
                "hook_event_name": "PostToolUse",
                "session_id": sessionId,
                "_source": "opencode"
            ])

            let asked = try await response
            behaviors.append(try behavior(asked))

            // Sampled right where the card would be drawn from.
            if !appState.permissionQueue.isEmpty { surfacedDuringBurst += 1 }
            if appState.sessions[sessionId]?.status == .waitingApproval { surfacedDuringBurst += 1 }
            if case .approvalCard = appState.surface { surfacedDuringBurst += 1 }
        }

        // Guard against a false pass: the events must actually have reached AppState
        // rather than being short-circuited somewhere in HookServer.
        let seen = appState.recentHookEvents.filter { $0.sessionId == sessionId }
        XCTAssertEqual(seen.filter { $0.eventName == "PermissionRequest" }.count, 8)
        XCTAssertEqual(seen.filter { $0.eventName == "PostToolUse" }.count, 8)

        XCTAssertEqual(surfacedDuringBurst, 0, "no approval card may be drawn for auto-resolved asks")
        XCTAssertEqual(behaviors.count, 8)
        XCTAssertTrue(behaviors.allSatisfy { $0 == "allow" }, "every waiter is released, got \(behaviors)")

        // And nothing appears once every settling window has elapsed.
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(appState.permissionQueue.isEmpty)
        XCTAssertTrue(appState.stagedPermissions.isEmpty)
        XCTAssertEqual(appState.surface, .collapsed)
        XCTAssertNotEqual(appState.sessions[sessionId]?.status, .waitingApproval)
    }

    /// The case that must still work: an ask nobody answers is a real block, and it
    /// has to reach the UI promptly rather than being swallowed by the debounce.
    func testUnansweredAskStillSurfacesPromptly() async throws {
        let bridge = try XCTUnwrap(bridgeBinaryPath(), "codeisland-bridge not built")
        let appState = try await startServer()
        let sessionId = "opencode-e2e-blocking"

        async let response = runBridge(bridge, payload: [
            "hook_event_name": "PermissionRequest",
            "session_id": sessionId,
            "tool_name": "Bash",
            "tool_input": ["command": "rm -rf build"],
            "_source": "opencode",
            "_opencode_request_id": "per_e2e_blocking"
        ])

        // Measure from arrival, not from spawning the client — the debounce is the
        // only delay the product adds.
        try await waitUntil("the ask to reach the server") { !appState.stagedPermissions.isEmpty }
        let arrived = Date()

        var surfacedAfter: TimeInterval?
        while Date().timeIntervalSince(arrived) < 2.0 {
            if !appState.permissionQueue.isEmpty {
                surfacedAfter = Date().timeIntervalSince(arrived)
                break
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        let latency = try XCTUnwrap(surfacedAfter, "a blocking request never surfaced")
        XCTAssertGreaterThanOrEqual(latency, AppState.defaultPermissionSurfaceDebounce - 0.05)
        XCTAssertLessThan(latency, 1.0, "blocking approvals must still appear promptly")
        XCTAssertEqual(appState.sessions[sessionId]?.status, .waitingApproval)
        XCTAssertEqual(appState.permissionQueue.count, 1)

        appState.approvePermission()
        let approved = try await response
        XCTAssertEqual(try behavior(approved), "allow")
        print("blocking ask surfaced \(String(format: "%.3f", latency))s after arriving")
    }

    // MARK: - Harness

    private func startServer() async throws -> AppState {
        // Production debounce — this is the shipped configuration under test.
        let appState = AppState()
        XCTAssertEqual(appState.permissionSurfaceDebounce, AppState.defaultPermissionSurfaceDebounce)
        let server = HookServer(appState: appState)
        server.start()
        self.server = server

        var attempts = 0
        var statBuf = stat()
        while stat(socketPath, &statBuf) != 0 && attempts < 100 {
            try await Task.sleep(nanoseconds: 20_000_000)
            attempts += 1
        }
        XCTAssertEqual(stat(socketPath, &statBuf), 0, "HookServer never bound \(socketPath!)")
        return appState
    }

    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("timed out waiting for \(what)")
    }

    /// Fire-and-forget event over the raw socket, matching how the OpenCode plugin
    /// forwards non-blocking events (its node client writes and half-closes; only
    /// blocking permission/question events go through the bridge binary).
    private nonisolated func sendEvent(_ payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let path = ProcessInfo.processInfo.environment["CODEISLAND_SOCKET_PATH"] ?? ""
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EBADF) }
        defer { close(fd) }
        // Never let the harness itself block: this is a fire-and-forget event.
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                _ = path.withCString { strncpy(destination, $0, capacity - 1) }
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }

        try data.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let n = send(fd, buffer.baseAddress!.advanced(by: sent), buffer.count - sent, 0)
                guard n > 0 else { throw POSIXError(.EIO) }
                sent += n
            }
        }
        shutdown(fd, SHUT_WR)
        // Drain the (empty) response so the server sees a clean close.
        var scratch = [UInt8](repeating: 0, count: 256)
        while recv(fd, &scratch, scratch.count, 0) > 0 {}
    }

    /// Run the real bridge client with `payload` on stdin, returning its stdout.
    private nonisolated func runBridge(_ binary: String, payload: [String: Any]) async throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let socketPath = ProcessInfo.processInfo.environment["CODEISLAND_SOCKET_PATH"] ?? ""
        // Blocking permission events wait forever by design, so the child must die
        // with the test — otherwise one harness error hangs the whole suite.
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                box.adopt(process)
                process.executableURL = URL(fileURLWithPath: binary)
                var environment = ProcessInfo.processInfo.environment
                environment["CODEISLAND_SOCKET_PATH"] = socketPath
                process.environment = environment
                let input = Pipe()
                let output = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                input.fileHandleForWriting.write(data)
                try? input.fileHandleForWriting.close()
                let stdout = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: stdout)
            }
            }
        } onCancel: {
            box.terminate()
        }
    }

    /// Holds the spawned child so a cancelled task can terminate it.
    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func adopt(_ process: Process) {
            lock.lock()
            defer { lock.unlock() }
            if cancelled {
                DispatchQueue.global().async { if process.isRunning { process.terminate() } }
                return
            }
            self.process = process
        }

        func terminate() {
            lock.lock()
            let target = process
            cancelled = true
            lock.unlock()
            if let target, target.isRunning { target.terminate() }
        }
    }

    private nonisolated func bridgeBinaryPath() -> String? {
        // Tests/CodeIslandTests/<file> -> package root -> .build/debug/codeisland-bridge
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for build in ["debug", "release"] {
            let candidate = packageRoot
                .appendingPathComponent(".build/\(build)/codeisland-bridge")
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private nonisolated func behavior(_ responseData: Data) throws -> String {
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        let hookSpecificOutput = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(hookSpecificOutput["decision"] as? [String: Any])
        return try XCTUnwrap(decision["behavior"] as? String)
    }
}
