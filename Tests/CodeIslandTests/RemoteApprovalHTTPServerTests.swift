import Foundation
import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class RemoteApprovalHTTPServerTests: XCTestCase {
    func testWebFallbackServesInstallableIdentityAssets() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandWebAssets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let service = RemoteApprovalService(
            deviceStore: RemoteApprovalDeviceStore(
                stateURL: temporaryDirectory.appendingPathComponent("devices.json")
            ),
            coordinator: RemoteApprovalCoordinator(
                auditURL: temporaryDirectory.appendingPathComponent("audit.jsonl")
            ),
            localPortOverride: 0,
            enabledOverride: true,
            tailscaleConfigurator: { _, _ in "https://codeisland-web-assets.invalid" }
        )
        let appState = AppState()
        service.start(appState: appState)
        defer { service.stop() }
        let port = try await waitForPort(service)

        let manifest = try await send(port: port, method: "GET", path: "/manifest.webmanifest")
        XCTAssertEqual(manifest.response.statusCode, 200)
        XCTAssertEqual(
            manifest.response.value(forHTTPHeaderField: "Content-Type"),
            "application/manifest+json; charset=utf-8"
        )
        XCTAssertTrue(String(decoding: manifest.data, as: UTF8.self).contains("/app-icon.svg"))

        let icon = try await send(port: port, method: "GET", path: "/app-icon.svg")
        XCTAssertEqual(icon.response.statusCode, 200)
        XCTAssertEqual(
            icon.response.value(forHTTPHeaderField: "Content-Type"),
            "image/svg+xml; charset=utf-8"
        )
        XCTAssertTrue(String(decoding: icon.data, as: UTF8.self).contains("<svg"))
    }

    func testDelayedActivityStartedReceiptDoesNotRegressDismissedSummary() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandReceiptOrdering-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let store = RemoteApprovalDeviceStore(
            stateURL: temporaryDirectory.appendingPathComponent("devices.json")
        )
        let pair = try XCTUnwrap(store.pair(.init(code: store.pairingCode, deviceName: "iPhone")))
        let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let dismissed = RemoteLiveActivityReceipt(
            eventId: "dismissed-receipt",
            source: .activityStateChanged,
            requestId: "request-id",
            kind: .question,
            activityState: .dismissed,
            observedAt: observedAt,
            activitiesEnabled: true,
            activeActivityCount: 0,
            activeRequestIds: []
        )
        let delayedStart = RemoteLiveActivityReceipt(
            eventId: "delayed-start-receipt",
            source: .activityStarted,
            requestId: "request-id",
            kind: .question,
            state: .pending,
            activityState: .active,
            observedAt: observedAt,
            activitiesEnabled: true,
            activeActivityCount: 0,
            activeRequestIds: []
        )

        XCTAssertEqual(store.registerPushToken(
            .init(environment: "production", liveActivityReceipts: [dismissed]),
            deviceID: pair.deviceId
        ), [dismissed])
        XCTAssertEqual(store.registerPushToken(
            .init(environment: "production", liveActivityReceipts: [delayedStart]),
            deviceID: pair.deviceId
        ), [delayedStart])

        XCTAssertEqual(store.devices.first?.lastLiveActivityReceipt, dismissed)
        XCTAssertEqual(
            store.devices.first?.recentLiveActivityReceiptIDs,
            [dismissed.eventId, delayedStart.eventId]
        )
    }

    func testTerminalLiveActivityReceiptPrunesItsUpdateToken() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandReceiptTokenCleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let store = RemoteApprovalDeviceStore(
            stateURL: temporaryDirectory.appendingPathComponent("devices.json")
        )
        let pair = try XCTUnwrap(store.pair(.init(code: store.pairingCode, deviceName: "iPhone")))
        _ = store.registerPushToken(
            .init(
                environment: "production",
                liveActivityUpdateTokens: ["request-id": String(repeating: "d", count: 64)]
            ),
            deviceID: pair.deviceId
        )
        XCTAssertNotNil(store.devices.first?.liveActivityUpdateTokens?["request-id"])

        let dismissed = RemoteLiveActivityReceipt(
            eventId: "dismissed-receipt",
            source: .activityStateChanged,
            requestId: "request-id",
            kind: .question,
            activityState: .dismissed,
            observedAt: Date(timeIntervalSince1970: 1_800_000_000),
            activitiesEnabled: true,
            activeActivityCount: 0,
            activeRequestIds: []
        )
        _ = store.registerPushToken(
            .init(environment: "production", liveActivityReceipts: [dismissed]),
            deviceID: pair.deviceId
        )

        XCTAssertNil(store.devices.first?.liveActivityUpdateTokens)
    }

    func testServerRetainsConnectionUntilResponseCompletes() async throws {
        let ready = expectation(description: "listener ready")
        var startupError: Error?
        let server = try RemoteApprovalHTTPServer(port: 0) { request in
            guard request.method == "GET", request.path == "/health" else {
                return .json(status: 404, object: ["error": "not found"])
            }
            return .json(status: 200, object: ["running": true])
        }
        defer { server.stop() }

        server.start { result in
            if case .failure(let error) = result {
                startupError = error
            }
            ready.fulfill()
        }
        await fulfillment(of: [ready], timeout: 3)
        if let startupError { throw startupError }

        let port = try XCTUnwrap(server.boundPort)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/health"))
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Bool])
        XCTAssertEqual(object["running"], true)
    }

    func testAuthenticatedRecentDownloadTransfersToPairedDevice() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandDownloadE2E-\(UUID().uuidString)", isDirectory: true)
        let downloadsDirectory = temporaryDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let completedFile = downloadsDirectory.appendingPathComponent("morning-handoff.txt")
        let oversizedFile = downloadsDirectory.appendingPathComponent("over-limit.dmg")
        let expectedBody = Data("CodeIsland mobile download E2E".utf8)
        try expectedBody.write(to: completedFile)
        _ = FileManager.default.createFile(atPath: oversizedFile.path, contents: Data())
        let oversizedHandle = try FileHandle(forWritingTo: oversizedFile)
        try oversizedHandle.truncate(
            atOffset: UInt64(PersonalUtilitiesModel.maximumRemoteTransferBytes + 1)
        )
        try oversizedHandle.close()

        let utilities = PersonalUtilitiesModel(downloadsURL: downloadsDirectory) { _ in -1 }
        let hub = PersonalHubService(utilities: utilities)
        let service = RemoteApprovalService(
            deviceStore: RemoteApprovalDeviceStore(
                stateURL: temporaryDirectory.appendingPathComponent("devices.json")
            ),
            coordinator: RemoteApprovalCoordinator(
                auditURL: temporaryDirectory.appendingPathComponent("audit.jsonl")
            ),
            personalHub: hub,
            localPortOverride: 0,
            enabledOverride: true,
            tailscaleConfigurator: { _, _ in "https://codeisland-download-e2e.invalid" }
        )
        let appState = AppState()
        utilities.start()
        let scanDeadline = ContinuousClock.now + .seconds(10)
        while !utilities.downloadsScanComplete, ContinuousClock.now < scanDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(utilities.downloadsScanComplete, "Downloads scan did not complete")
        XCTAssertEqual(
            Set(utilities.recentDownloads.map(\.name)),
            Set([completedFile.lastPathComponent, oversizedFile.lastPathComponent])
        )

        service.start(appState: appState)
        defer {
            service.stop()
            utilities.stop()
        }
        let port = try await waitForPort(service)

        let paired = try await send(
            port: port,
            method: "POST",
            path: "/api/pair",
            body: try encode(RemotePairRequest(code: service.pairingCode, deviceName: "Download E2E iPhone"))
        )
        let pair = try decode(RemotePairResponse.self, from: paired.data)

        let result = try await send(
            port: port,
            method: "POST",
            path: "/api/hub/snapshot",
            bearer: pair.deviceToken,
            body: try encode(PersonalHubSnapshotRequest(requestedMode: .work))
        )
        let snapshot = try decode(PersonalHubSnapshot.self, from: result.data)
        let downloadModule = try XCTUnwrap(snapshot.modules.first(where: { $0.id == .downloads }))
        let item = try XCTUnwrap(
            downloadModule.items.first(where: { $0.title == completedFile.lastPathComponent })
        )
        XCTAssertEqual(item.actions.first(where: { $0.id == "downloadToDevice" })?.role, .primary)
        let oversizedItem = try XCTUnwrap(
            downloadModule.items.first(where: { $0.title == oversizedFile.lastPathComponent })
        )
        XCTAssertNil(oversizedItem.actions.first(where: { $0.id == "downloadToDevice" }))

        var pathAllowed = CharacterSet.urlPathAllowed
        pathAllowed.remove(charactersIn: "/")
        let encodedID = try XCTUnwrap(item.id.addingPercentEncoding(withAllowedCharacters: pathAllowed))
        let filePath = "/api/hub/downloads/\(encodedID)/file"

        let unauthenticated = try await send(port: port, method: "GET", path: filePath)
        XCTAssertEqual(unauthenticated.response.statusCode, 401)

        let transferred = try await send(
            port: port,
            method: "GET",
            path: filePath,
            bearer: pair.deviceToken
        )
        XCTAssertEqual(transferred.response.statusCode, 200)
        XCTAssertEqual(transferred.data, expectedBody)
        XCTAssertTrue(
            transferred.response.value(forHTTPHeaderField: "Content-Disposition")?
                .contains("morning-handoff.txt") == true
        )

        let oversizedID = try XCTUnwrap(
            oversizedItem.id.addingPercentEncoding(withAllowedCharacters: pathAllowed)
        )
        let oversizedTransfer = try await send(
            port: port,
            method: "GET",
            path: "/api/hub/downloads/\(oversizedID)/file",
            bearer: pair.deviceToken
        )
        XCTAssertEqual(oversizedTransfer.response.statusCode, 404)

        let outsideID = try XCTUnwrap("/etc/hosts".addingPercentEncoding(withAllowedCharacters: pathAllowed))
        let traversal = try await send(
            port: port,
            method: "GET",
            path: "/api/hub/downloads/\(outsideID)/file",
            bearer: pair.deviceToken
        )
        XCTAssertEqual(traversal.response.statusCode, 404)
    }

    func testAuthenticatedShelfTransferIsPrivateAndSuppressesOverLimitAction() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandShelfE2E-\(UUID().uuidString)", isDirectory: true)
        let shelfDirectory = temporaryDirectory.appendingPathComponent("Shelf", isDirectory: true)
        let desktopDirectory = temporaryDirectory.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: shelfDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: desktopDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let suite = "RemoteApprovalHTTPServerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let capture = ShelfCaptureController(
            storageDirectory: shelfDirectory,
            screenshotDirectory: desktopDirectory
        )
        let data = PersonalHubDataModel(defaults: defaults, shelfCaptureController: capture)
        let expectedBody = Data("private Shelf handoff".utf8)
        let transferable = shelfDirectory.appendingPathComponent("handoff.txt")
        try expectedBody.write(to: transferable)
        try capture.completeCapture(at: transferable, source: .drop)
        let oversized = shelfDirectory.appendingPathComponent("over-limit.mov")
        _ = FileManager.default.createFile(atPath: oversized.path, contents: Data())
        let oversizedHandle = try FileHandle(forWritingTo: oversized)
        try oversizedHandle.truncate(
            atOffset: UInt64(PersonalUtilitiesModel.maximumRemoteTransferBytes + 1)
        )
        try oversizedHandle.close()
        try capture.completeCapture(at: oversized, source: .recording)

        let hub = PersonalHubService(data: data)
        let service = RemoteApprovalService(
            deviceStore: RemoteApprovalDeviceStore(
                stateURL: temporaryDirectory.appendingPathComponent("devices.json")
            ),
            coordinator: RemoteApprovalCoordinator(
                auditURL: temporaryDirectory.appendingPathComponent("audit.jsonl")
            ),
            personalHub: hub,
            localPortOverride: 0,
            enabledOverride: true,
            tailscaleConfigurator: { _, _ in "https://codeisland-shelf-e2e.invalid" }
        )
        let appState = AppState()
        service.start(appState: appState)
        defer { service.stop() }
        let port = try await waitForPort(service)

        let paired = try await send(
            port: port,
            method: "POST",
            path: "/api/pair",
            body: try encode(RemotePairRequest(code: service.pairingCode, deviceName: "Shelf E2E iPhone"))
        )
        let pair = try decode(RemotePairResponse.self, from: paired.data)
        let result = try await send(
            port: port,
            method: "POST",
            path: "/api/hub/snapshot",
            bearer: pair.deviceToken,
            body: try encode(PersonalHubSnapshotRequest(requestedMode: .code))
        )
        let snapshot = try decode(PersonalHubSnapshot.self, from: result.data)
        let shelf = try XCTUnwrap(snapshot.modules.first(where: { $0.id == .shelf }))
        let transferableItem = try XCTUnwrap(shelf.items.first(where: { $0.title == "handoff.txt" }))
        let oversizedItem = try XCTUnwrap(shelf.items.first(where: { $0.title == "over-limit.mov" }))
        XCTAssertNotNil(transferableItem.actions.first(where: { $0.id == "downloadToDevice" }))
        XCTAssertNil(oversizedItem.actions.first(where: { $0.id == "downloadToDevice" }))

        var pathAllowed = CharacterSet.urlPathAllowed
        pathAllowed.remove(charactersIn: "/")
        let encodedID = try XCTUnwrap(
            transferableItem.id.addingPercentEncoding(withAllowedCharacters: pathAllowed)
        )
        let transferred = try await send(
            port: port,
            method: "GET",
            path: "/api/hub/shelf/\(encodedID)/file",
            bearer: pair.deviceToken
        )
        XCTAssertEqual(transferred.response.statusCode, 200)
        XCTAssertEqual(transferred.data, expectedBody)

        let oversizedID = try XCTUnwrap(
            oversizedItem.id.addingPercentEncoding(withAllowedCharacters: pathAllowed)
        )
        let rejected = try await send(
            port: port,
            method: "GET",
            path: "/api/hub/shelf/\(oversizedID)/file",
            bearer: pair.deviceToken
        )
        XCTAssertEqual(rejected.response.statusCode, 413)

        let outsideID = try XCTUnwrap("/etc/hosts".addingPercentEncoding(withAllowedCharacters: pathAllowed))
        let traversal = try await send(
            port: port,
            method: "GET",
            path: "/api/hub/shelf/\(outsideID)/file",
            bearer: pair.deviceToken
        )
        XCTAssertEqual(traversal.response.statusCode, 404)
    }

    func testAuthenticatedHostLifecycleOverRealListener() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandRemoteE2E-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let stateURL = temporaryDirectory.appendingPathComponent("devices.json")
        let auditURL = temporaryDirectory.appendingPathComponent("audit.jsonl")
        let configurationURL = temporaryDirectory.appendingPathComponent("hub-configuration.json")
        let deviceStore = RemoteApprovalDeviceStore(stateURL: stateURL)
        let configurationStore = PersonalHubConfigurationStore(stateURL: configurationURL)
        let personalHub = PersonalHubService(configurationStore: configurationStore)
        let service = RemoteApprovalService(
            deviceStore: deviceStore,
            coordinator: RemoteApprovalCoordinator(auditURL: auditURL),
            personalHub: personalHub,
            localPortOverride: 0,
            enabledOverride: true,
            tailscaleConfigurator: { _, _ in "https://codeisland-e2e.invalid" }
        )
        let appState = AppState()
        service.start(appState: appState)
        defer { service.stop() }

        let port = try await waitForPort(service)

        let root = try await send(port: port, method: "GET", path: "/")
        XCTAssertEqual(root.response.statusCode, 200)
        XCTAssertEqual(root.response.value(forHTTPHeaderField: "X-Frame-Options"), "DENY")
        XCTAssertEqual(root.response.value(forHTTPHeaderField: "X-Content-Type-Options"), "nosniff")
        XCTAssertTrue(
            root.response.value(forHTTPHeaderField: "Content-Security-Policy")?.contains("frame-ancestors 'none'") == true
        )
        let webApp = try XCTUnwrap(String(data: root.data, encoding: .utf8))
        XCTAssertTrue(webApp.contains("id=\"hubConfig\""))
        XCTAssertTrue(webApp.contains("setModeRack"))
        XCTAssertTrue(webApp.contains("setDashboard"))

        let unauthenticated = try await send(port: port, method: "GET", path: "/api/hub")
        XCTAssertEqual(unauthenticated.response.statusCode, 401)
        XCTAssertEqual(unauthenticated.response.value(forHTTPHeaderField: "WWW-Authenticate"), "Bearer")

        let rejectedPair = try await send(
            port: port,
            method: "POST",
            path: "/api/pair",
            body: try encode(RemotePairRequest(code: "000000", deviceName: "Unpaired iPhone"))
        )
        XCTAssertEqual(rejectedPair.response.statusCode, 403)

        let paired = try await send(
            port: port,
            method: "POST",
            path: "/api/pair",
            body: try encode(RemotePairRequest(code: service.pairingCode, deviceName: "E2E iPhone"))
        )
        XCTAssertEqual(paired.response.statusCode, 201)
        let pair = try decode(RemotePairResponse.self, from: paired.data)
        XCTAssertEqual(deviceStore.devices.map(\.name), ["E2E iPhone"])

        for mode in [PersonalHubMode.home, .work, .code] {
            let result = try await send(
                port: port,
                method: "POST",
                path: "/api/hub/snapshot",
                bearer: pair.deviceToken,
                body: try encode(PersonalHubSnapshotRequest(requestedMode: mode))
            )
            XCTAssertEqual(result.response.statusCode, 200)
            let snapshot = try decode(PersonalHubSnapshot.self, from: result.data)
            XCTAssertEqual(snapshot.requestedMode, mode)
            XCTAssertEqual(snapshot.resolvedMode, mode)
            XCTAssertEqual(snapshot.modules.map(\.id), PersonalHubCatalog.modules(for: mode))
            XCTAssertEqual(
                PersonalHubBuddyParity.validate(snapshot: snapshot).map(\.description),
                [],
                "Remote hub snapshot exposes actions without an explicit Buddy/iPhone/web parity disposition"
            )
        }

        let configuredWorkRack: [PersonalHubModuleID] = [.reminders, .calendar, .downloads]
        let rackIntent = PersonalHubActionIntent(
            moduleID: .quickToggles,
            actionID: "setModeRack",
            value: PersonalHubConfigurationMutation(
                mode: .work,
                modules: configuredWorkRack
            ).encodedActionValue()
        )
        let preparedRack = try decode(
            PersonalHubPreparedAction.self,
            from: try await send(
                port: port,
                method: "POST",
                path: "/api/hub/actions/prepare",
                bearer: pair.deviceToken,
                body: try encode(PersonalHubPrepareActionRequest(intent: rackIntent))
            ).data
        )
        let savedRack = try await send(
            port: port,
            method: "POST",
            path: "/api/hub/actions/execute",
            bearer: pair.deviceToken,
            body: try encode(PersonalHubExecuteActionRequest(
                intent: rackIntent,
                actionToken: preparedRack.actionToken
            ))
        )
        XCTAssertEqual(savedRack.response.statusCode, 200)

        let dashboardIntent = PersonalHubActionIntent(
            moduleID: .quickToggles,
            actionID: "setDashboard",
            value: PersonalHubConfigurationMutation(dashboardEnabled: false).encodedActionValue()
        )
        let preparedDashboard = try decode(
            PersonalHubPreparedAction.self,
            from: try await send(
                port: port,
                method: "POST",
                path: "/api/hub/actions/prepare",
                bearer: pair.deviceToken,
                body: try encode(PersonalHubPrepareActionRequest(intent: dashboardIntent))
            ).data
        )
        let savedDashboard = try await send(
            port: port,
            method: "POST",
            path: "/api/hub/actions/execute",
            bearer: pair.deviceToken,
            body: try encode(PersonalHubExecuteActionRequest(
                intent: dashboardIntent,
                actionToken: preparedDashboard.actionToken
            ))
        )
        XCTAssertEqual(savedDashboard.response.statusCode, 200)

        let configuredSnapshotResult = try await send(
            port: port,
            method: "POST",
            path: "/api/hub/snapshot",
            bearer: pair.deviceToken,
            body: try encode(PersonalHubSnapshotRequest(requestedMode: .work))
        )
        let configuredSnapshot = try decode(PersonalHubSnapshot.self, from: configuredSnapshotResult.data)
        XCTAssertEqual(configuredSnapshot.modules.map(\.id), configuredWorkRack)
        XCTAssertEqual(configuredSnapshot.configuration?.rack(for: .work), configuredWorkRack)
        XCTAssertEqual(configuredSnapshot.configuration?.dashboardEnabled, false)
        XCTAssertNotNil(configuredSnapshot.dayProgress)

        let reloadedConfiguration = PersonalHubConfigurationStore(stateURL: configurationURL).configuration
        XCTAssertEqual(reloadedConfiguration.rack(for: .work), configuredWorkRack)
        XCTAssertEqual(reloadedConfiguration.dashboardEnabled, false)

        let event = try makePermissionRequestEvent(sessionID: "remote-e2e", toolName: "Bash")
        let permissionResponse = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }
        await Task.yield()
        XCTAssertEqual(appState.permissionQueue.count, 1)

        let approvalsResult = try await send(
            port: port,
            method: "GET",
            path: "/api/approvals",
            bearer: pair.deviceToken
        )
        XCTAssertEqual(approvalsResult.response.statusCode, 200)
        let approvals = try decode(RemoteApprovalSnapshot.self, from: approvalsResult.data)
        let approval = try XCTUnwrap(approvals.approvals.first)
        XCTAssertEqual(approval.tool, "Bash")

        let decision = RemoteDecisionRequest(decision: .approve, actionToken: approval.actionToken)
        let decisionPath = "/api/approvals/\(approval.id)/decision"
        let resolved = try await send(
            port: port,
            method: "POST",
            path: decisionPath,
            bearer: pair.deviceToken,
            body: try encode(decision)
        )
        XCTAssertEqual(resolved.response.statusCode, 200)
        let permissionResponseData = await permissionResponse.value
        XCTAssertEqual(try extractPermissionBehavior(from: permissionResponseData), "allow")
        XCTAssertTrue(appState.permissionQueue.isEmpty)

        let approvalReplay = try await send(
            port: port,
            method: "POST",
            path: decisionPath,
            bearer: pair.deviceToken,
            body: try encode(decision)
        )
        XCTAssertEqual(approvalReplay.response.statusCode, 403)

        let questionEvent = try makeQuestionEvent(sessionID: "question-e2e")
        let questionResponse = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handleAskUserQuestion(questionEvent, continuation: continuation)
            }
        }
        await Task.yield()
        XCTAssertEqual(appState.questionQueue.count, 1)

        let questionsResult = try await send(
            port: port,
            method: "GET",
            path: "/api/approvals",
            bearer: pair.deviceToken
        )
        let questionsSnapshot = try decode(RemoteApprovalSnapshot.self, from: questionsResult.data)
        let question = try XCTUnwrap(questionsSnapshot.questions.first)
        XCTAssertFalse(question.requiresLocalResponse)
        XCTAssertEqual(question.prompts.first?.question, "Continue the E2E run?")
        XCTAssertEqual(question.prompts.first?.options, ["Continue", "Stop"])

        let questionPath = "/api/questions/\(question.id)/answer"
        let answered = try await send(
            port: port,
            method: "POST",
            path: questionPath,
            bearer: pair.deviceToken,
            body: try encode(RemoteQuestionAnswerRequest(
                answers: ["Continue"],
                actionToken: try XCTUnwrap(question.actionToken)
            ))
        )
        XCTAssertEqual(answered.response.statusCode, 200)
        let questionResponseData = await questionResponse.value
        XCTAssertEqual(try extractQuestionAnswer(from: questionResponseData), "Continue")
        XCTAssertTrue(appState.questionQueue.isEmpty)

        let questionReplay = try await send(
            port: port,
            method: "POST",
            path: questionPath,
            bearer: pair.deviceToken,
            body: try encode(RemoteQuestionAnswerRequest(
                answers: ["Continue"],
                actionToken: try XCTUnwrap(question.actionToken)
            ))
        )
        XCTAssertEqual(questionReplay.response.statusCode, 403)

        let intent = PersonalHubActionIntent(moduleID: .system, actionID: "refresh")
        let preparedResult = try await send(
            port: port,
            method: "POST",
            path: "/api/hub/actions/prepare",
            bearer: pair.deviceToken,
            body: try encode(PersonalHubPrepareActionRequest(intent: intent))
        )
        XCTAssertEqual(preparedResult.response.statusCode, 200)
        let prepared = try decode(PersonalHubPreparedAction.self, from: preparedResult.data)

        let alteredIntent = PersonalHubActionIntent(moduleID: .system, actionID: "refresh", value: "tampered")
        let alteredExecution = try await send(
            port: port,
            method: "POST",
            path: "/api/hub/actions/execute",
            bearer: pair.deviceToken,
            body: try encode(PersonalHubExecuteActionRequest(
                intent: alteredIntent,
                actionToken: prepared.actionToken
            ))
        )
        XCTAssertEqual(alteredExecution.response.statusCode, 403)

        let executeRequest = PersonalHubExecuteActionRequest(
            intent: intent,
            actionToken: prepared.actionToken
        )
        let executed = try await send(
            port: port,
            method: "POST",
            path: "/api/hub/actions/execute",
            bearer: pair.deviceToken,
            body: try encode(executeRequest)
        )
        XCTAssertEqual(executed.response.statusCode, 200)
        XCTAssertTrue(try decode(PersonalHubActionResponse.self, from: executed.data).executed)

        let actionReplay = try await send(
            port: port,
            method: "POST",
            path: "/api/hub/actions/execute",
            bearer: pair.deviceToken,
            body: try encode(executeRequest)
        )
        XCTAssertEqual(actionReplay.response.statusCode, 403)

        let buildRegistered = try await send(
            port: port,
            method: "POST",
            path: "/api/push-token",
            bearer: pair.deviceToken,
            body: try encode(RemotePushRegistrationRequest(
                environment: "production",
                clientVersion: "1.0.0",
                clientBuild: "20260718075059"
            ))
        )
        XCTAssertEqual(buildRegistered.response.statusCode, 200)
        XCTAssertEqual(deviceStore.devices.first?.clientVersion, "1.0.0")
        XCTAssertEqual(deviceStore.devices.first?.clientBuild, "20260718075059")
        let reloadedDeviceStore = RemoteApprovalDeviceStore(stateURL: stateURL)
        XCTAssertEqual(reloadedDeviceStore.devices.first?.clientVersion, "1.0.0")
        XCTAssertEqual(reloadedDeviceStore.devices.first?.clientBuild, "20260718075059")

        let incompleteBuildRegistration = try await send(
            port: port,
            method: "POST",
            path: "/api/push-token",
            bearer: pair.deviceToken,
            body: try encode(RemotePushRegistrationRequest(
                environment: "production",
                clientVersion: "1.0.0"
            ))
        )
        XCTAssertEqual(incompleteBuildRegistration.response.statusCode, 400)

        let pushToken = String(repeating: "a", count: 64)
        let registered = try await send(
            port: port,
            method: "POST",
            path: "/api/push-token",
            bearer: pair.deviceToken,
            body: try encode(RemotePushRegistrationRequest(token: pushToken, environment: "production"))
        )
        XCTAssertEqual(registered.response.statusCode, 200)
        XCTAssertEqual(deviceStore.devices.first?.pushToken, pushToken)
        XCTAssertEqual(deviceStore.devices.first?.pushEnvironment, "production")

        let rotatedPushToken = String(repeating: "b", count: 64)
        let rotated = try await send(
            port: port,
            method: "POST",
            path: "/api/push-token",
            bearer: pair.deviceToken,
            body: try encode(RemotePushRegistrationRequest(
                token: rotatedPushToken,
                environment: "development"
            ))
        )
        XCTAssertEqual(rotated.response.statusCode, 200)
        XCTAssertEqual(deviceStore.devices.first?.pushToken, rotatedPushToken)
        XCTAssertEqual(deviceStore.devices.first?.pushEnvironment, "development")

        let pushToStartToken = String(repeating: "c", count: 64)
        let activityUpdateToken = String(repeating: "d", count: 64)
        let activityRegistered = try await send(
            port: port,
            method: "POST",
            path: "/api/push-token",
            bearer: pair.deviceToken,
            body: try encode(RemotePushRegistrationRequest(
                environment: "production",
                liveActivityPushToStartToken: pushToStartToken,
                liveActivityUpdateTokens: ["request-id": activityUpdateToken]
            ))
        )
        XCTAssertEqual(activityRegistered.response.statusCode, 200)
        XCTAssertEqual(deviceStore.devices.first?.liveActivityPushToStartToken, pushToStartToken)
        XCTAssertEqual(deviceStore.devices.first?.liveActivityUpdateTokens?["request-id"], activityUpdateToken)

        let receipt = RemoteLiveActivityReceipt(
            eventId: "receipt-event-id",
            source: .activityStarted,
            requestId: "request-id",
            kind: .approval,
            state: .pending,
            activityState: .active,
            observedAt: Date(timeIntervalSince1970: 1_800_000_000),
            activitiesEnabled: true,
            activeActivityCount: 1,
            activeRequestIds: ["request-id"]
        )
        let receiptRegistered = try await send(
            port: port,
            method: "POST",
            path: "/api/push-token",
            bearer: pair.deviceToken,
            body: try encode(RemotePushRegistrationRequest(
                environment: "production",
                liveActivityReceipts: [receipt]
            ))
        )
        XCTAssertEqual(receiptRegistered.response.statusCode, 200)
        XCTAssertEqual(deviceStore.devices.first?.lastLiveActivityReceipt, receipt)

        let duplicateReceipt = try await send(
            port: port,
            method: "POST",
            path: "/api/push-token",
            bearer: pair.deviceToken,
            body: try encode(RemotePushRegistrationRequest(
                environment: "production",
                liveActivityReceipts: [receipt]
            ))
        )
        XCTAssertEqual(duplicateReceipt.response.statusCode, 200)
        XCTAssertEqual(deviceStore.devices.first?.recentLiveActivityReceiptIDs, [receipt.eventId])

        let invalidReceipt = RemoteLiveActivityReceipt(
            source: .snapshot,
            activitiesEnabled: true,
            activeActivityCount: 0,
            activeRequestIds: ["impossible-active-request"]
        )
        let rejectedReceipt = try await send(
            port: port,
            method: "POST",
            path: "/api/push-token",
            bearer: pair.deviceToken,
            body: try encode(RemotePushRegistrationRequest(
                environment: "production",
                liveActivityReceipts: [invalidReceipt]
            ))
        )
        XCTAssertEqual(rejectedReceipt.response.statusCode, 400)

        let audit = try String(contentsOf: auditURL, encoding: .utf8)
        XCTAssertTrue(audit.contains("\"event\":\"pair\""))
        XCTAssertTrue(audit.contains("\"event\":\"decision\""))
        XCTAssertTrue(audit.contains("\"outcome\":\"resolved\""))
        XCTAssertEqual(audit.components(separatedBy: "\"receiptEventID\":\"receipt-event-id\"").count - 1, 1)
        XCTAssertTrue(audit.contains("\"activeActivityCount\":1"))
    }

    private func waitForPort(_ service: RemoteApprovalService) async throws -> UInt16 {
        for _ in 0..<100 {
            if service.running, let port = service.boundLocalPort { return port }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw XCTSkip("Remote approval listener did not become ready: \(service.lastError ?? "unknown error")")
    }

    private func send(
        port: UInt16,
        method: String,
        path: String,
        bearer: String? = nil,
        body: Data? = nil
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(path)"))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, try XCTUnwrap(response as? HTTPURLResponse))
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private func makePermissionRequestEvent(sessionID: String, toolName: String) throws -> HookEvent {
        let payload: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": sessionID,
            "tool_name": toolName,
            "tool_input": ["command": "echo CodeIsland E2E"]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try XCTUnwrap(HookEvent(from: data))
    }

    private func makeQuestionEvent(sessionID: String) throws -> HookEvent {
        let payload: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": sessionID,
            "tool_name": "AskUserQuestion",
            "tool_input": [
                "questions": [[
                    "header": "E2E",
                    "question": "Continue the E2E run?",
                    "options": [
                        ["label": "Continue", "description": "Keep working"],
                        ["label": "Stop", "description": "End the run"]
                    ]
                ]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try XCTUnwrap(HookEvent(from: data))
    }

    private func extractPermissionBehavior(from responseData: Data) throws -> String {
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        let hookSpecificOutput = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(hookSpecificOutput["decision"] as? [String: Any])
        return try XCTUnwrap(decision["behavior"] as? String)
    }

    private func extractQuestionAnswer(from responseData: Data) throws -> String {
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        let hookSpecificOutput = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(hookSpecificOutput["decision"] as? [String: Any])
        let updatedInput = try XCTUnwrap(decision["updatedInput"] as? [String: Any])
        let answers = try XCTUnwrap(updatedInput["answers"] as? [String: Any])
        return try XCTUnwrap(answers["Continue the E2E run?"] as? String)
    }
}
