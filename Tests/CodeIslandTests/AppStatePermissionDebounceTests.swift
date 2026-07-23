import XCTest
@testable import CodeIsland
import CodeIslandCore

/// Coverage for the permission surface debounce.
///
/// Some CLIs ask for a permission they are about to grant themselves. OpenCode
/// emits `permission.asked` and replies milliseconds later when the permission is
/// preconfigured to "allow" — a Ringer swarm run on 2026-07-23 produced 297 such
/// `external_directory` asks in a single run, each of which drew and immediately
/// tore down a "Blocked / Approval 1/1" card. The debounce holds an incoming
/// request out of the UI for a short settling window so those never render, while
/// a request nobody answers still surfaces promptly.
@MainActor
final class AppStatePermissionDebounceTests: XCTestCase {

    /// The flicker case: ask, then a reply arrives a few ms later. Nothing is ever
    /// queued, the session never flips to `.waitingApproval`, no card opens — and
    /// the waiting CLI is still resumed.
    func testRequestResolvedInsideWindowNeverSurfaces() async throws {
        let appState = makeTestAppState(permissionSurfaceDebounce: 0.3)
        let sessionId = "s-opencode"

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(
                    try! makePermissionEvent(sessionId: sessionId, toolName: "External_directory"),
                    continuation: continuation
                )
            }
        }
        await Task.yield()

        XCTAssertEqual(appState.stagedPermissions.count, 1, "request should be settling, not queued")
        XCTAssertTrue(appState.permissionQueue.isEmpty)
        XCTAssertNotEqual(appState.sessions[sessionId]?.status, .waitingApproval)
        XCTAssertEqual(appState.surface, .collapsed)

        // OpenCode's `permission.replied` reaches CodeIsland as a PostToolUse.
        appState.handleEvent(try makeActivityEvent(name: "PostToolUse", sessionId: sessionId))

        let response = await responseTask.value
        XCTAssertEqual(try behavior(response), "allow")
        XCTAssertTrue(appState.stagedPermissions.isEmpty, "no stale staged entry left behind")
        XCTAssertTrue(appState.permissionQueue.isEmpty)
        XCTAssertEqual(appState.surface, .collapsed)

        // Nothing must surface after the window elapses either.
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(appState.permissionQueue.isEmpty, "cancelled request must not surface late")
        XCTAssertNotEqual(appState.sessions[sessionId]?.status, .waitingApproval)
        XCTAssertEqual(appState.surface, .collapsed)
    }

    /// A request nobody answers is a real block and must show up on its own.
    func testUnresolvedRequestSurfacesAfterWindow() async throws {
        let appState = makeTestAppState(permissionSurfaceDebounce: 0.25)
        let sessionId = "s-blocking"

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(
                    try! makePermissionEvent(sessionId: sessionId, toolName: "Bash"),
                    continuation: continuation
                )
            }
        }
        await Task.yield()
        XCTAssertTrue(appState.permissionQueue.isEmpty)

        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(appState.stagedPermissions.isEmpty)
        XCTAssertEqual(appState.permissionQueue.count, 1)
        XCTAssertEqual(appState.sessions[sessionId]?.status, .waitingApproval)
        XCTAssertEqual(appState.surface, .approvalCard(sessionId: sessionId))

        appState.approvePermission()
        let approved = await responseTask.value
        XCTAssertEqual(try behavior(approved), "allow")
    }

    /// Correlated resolution (PostToolUse carrying the same tool_use_id) also has to
    /// reach into the settling window, not just the visible queue.
    func testCorrelatedResolutionInsideWindowNeverSurfaces() async throws {
        let appState = makeTestAppState(permissionSurfaceDebounce: 0.3)
        let sessionId = "s-correlated"

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(
                    try! makePermissionEvent(sessionId: sessionId, toolName: "Bash", toolUseId: "toolu_dbnc"),
                    continuation: continuation
                )
            }
        }
        await Task.yield()
        XCTAssertEqual(appState.stagedPermissions.count, 1)

        appState.handleEvent(try makeActivityEvent(
            name: "PostToolUse", sessionId: sessionId, toolUseId: "toolu_dbnc"))

        let denied = await responseTask.value
        XCTAssertEqual(try behavior(denied), "deny")
        XCTAssertTrue(appState.stagedPermissions.isEmpty)

        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(appState.permissionQueue.isEmpty)
        XCTAssertEqual(appState.surface, .collapsed)
    }

    /// Session teardown while a request is still settling must resume the parked
    /// continuation instead of leaking it (the CLI would hang forever otherwise).
    func testSessionTeardownDrainsSettlingRequest() async throws {
        let appState = makeTestAppState(permissionSurfaceDebounce: 0.3)
        let sessionId = "s-teardown"

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(
                    try! makePermissionEvent(sessionId: sessionId, toolName: "Bash"),
                    continuation: continuation
                )
            }
        }
        await Task.yield()
        XCTAssertEqual(appState.stagedPermissions.count, 1)

        appState.handlePeerDisconnect(sessionId: sessionId)

        let denied = await responseTask.value
        XCTAssertEqual(try behavior(denied), "deny")
        XCTAssertTrue(appState.stagedPermissions.isEmpty)

        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(appState.permissionQueue.isEmpty)
    }

    /// A replay landing mid-window swaps the continuation in place; it must not
    /// enqueue a second card and must not restart the settling window.
    func testReplayInsideWindowMergesWithoutExtendingIt() async throws {
        let appState = makeTestAppState(permissionSurfaceDebounce: 0.25)
        let sessionId = "s-replay"

        let firstTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(
                    try! makePermissionEvent(sessionId: sessionId, toolName: "Bash", toolUseId: "toolu_replay"),
                    continuation: continuation
                )
            }
        }
        await Task.yield()
        let stagedId = try XCTUnwrap(appState.stagedPermissions.first?.id)

        let secondTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(
                    try! makePermissionEvent(sessionId: sessionId, toolName: "Bash", toolUseId: "toolu_replay"),
                    continuation: continuation
                )
            }
        }

        let supersededResponse = await firstTask.value
        XCTAssertEqual(try behavior(supersededResponse), "deny", "superseded waiter is released")
        XCTAssertEqual(appState.stagedPermissions.count, 1, "replay must not stage a second card")
        XCTAssertEqual(appState.stagedPermissions.first?.id, stagedId, "slot keeps its original deadline")

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(appState.permissionQueue.count, 1)

        appState.approvePermission()
        let replayResponse = await secondTask.value
        XCTAssertEqual(try behavior(replayResponse), "allow")
    }

    // MARK: - Helpers

    private func makePermissionEvent(
        sessionId: String,
        toolName: String,
        toolUseId: String? = nil
    ) throws -> HookEvent {
        var payload: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": sessionId,
            "tool_name": toolName,
            "tool_input": ["command": "echo test"],
            "_source": "opencode"
        ]
        if let toolUseId {
            payload["tool_use_id"] = toolUseId
        }
        return try makeEvent(payload)
    }

    private func makeActivityEvent(
        name: String,
        sessionId: String,
        toolUseId: String? = nil
    ) throws -> HookEvent {
        var payload: [String: Any] = [
            "hook_event_name": name,
            "session_id": sessionId,
            "tool_name": "Bash",
            "_source": "opencode"
        ]
        if let toolUseId {
            payload["tool_use_id"] = toolUseId
        }
        return try makeEvent(payload)
    }

    private func makeEvent(_ payload: [String: Any]) throws -> HookEvent {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let event = HookEvent(from: data) else {
            XCTFail("Failed to parse HookEvent")
            throw NSError(domain: "AppStatePermissionDebounceTests", code: 1)
        }
        return event
    }

    private func behavior(_ responseData: Data) throws -> String {
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        let hookSpecificOutput = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(hookSpecificOutput["decision"] as? [String: Any])
        return try XCTUnwrap(decision["behavior"] as? String)
    }
}
