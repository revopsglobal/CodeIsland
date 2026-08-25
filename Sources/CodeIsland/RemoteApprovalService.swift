import AppKit
import Combine
import CryptoKit
import Foundation
import Network
import os.log
import Security
import CodeIslandCore

private let remoteApprovalLog = Logger(subsystem: "com.codeisland", category: "remote-approvals")

@MainActor
final class RemoteApprovalService: ObservableObject {
    static let shared = RemoteApprovalService()

    @Published private(set) var running = false
    @Published private(set) var lastError: String?
    @Published private(set) var tailnetURL: String = ""
    @Published private(set) var pairedDevices: [RemoteApprovalDevice] = []
    @Published private(set) var pairingCode: String = ""
    @Published private(set) var pairingExpiresAt: Date = .distantPast
    @Published private(set) var remoteTasks: [RemoteTaskSummary] = []
    @Published private(set) var remoteTaskWorkspaces: [RemoteWorkspaceSummary] = []

    private weak var appState: AppState?
    private var server: RemoteApprovalHTTPServer?
    private let deviceStore: RemoteApprovalDeviceStore
    private let coordinator: RemoteApprovalCoordinator
    private let personalHub: PersonalHubService
    private let localPortOverride: UInt16?
    private let enabledOverride: Bool?
    private let remoteTasksEnabled: Bool
    private let remoteTaskCoordinatorOverride: RemoteTaskCoordinator?
    private let tailscaleConfigurator: @Sendable (Int, Int) throws -> String
    private var pairAttemptLimiter = RemotePairAttemptLimiter()
    private var lastPendingIDs: Set<String> = []
    private var lastPendingQuestionIDs: Set<String> = []
    private var sleepActivity: NSObjectProtocol?
    private var remoteTaskCoordinator: RemoteTaskCoordinator?
    private var remoteTaskStore: RemoteTaskStore?
    private var codexTaskRunner: CodexRemoteTaskRunner?
    private var claudeTaskRunner: ClaudeRemoteTaskRunner?
    private var remoteTaskStoreCancellable: AnyCancellable?
    private var lastRemoteTaskStates: [UUID: RemoteTaskState] = [:]
    private static let remoteTaskWorkspaceRootsKey = "CodeIslandRemoteTaskWorkspaceRoots"

    init(
        deviceStore: RemoteApprovalDeviceStore? = nil,
        coordinator: RemoteApprovalCoordinator? = nil,
        personalHub: PersonalHubService? = nil,
        localPortOverride: UInt16? = nil,
        enabledOverride: Bool? = nil,
        remoteTasksEnabled: Bool? = nil,
        remoteTaskCoordinatorOverride: RemoteTaskCoordinator? = nil,
        tailscaleConfigurator: @escaping @Sendable (Int, Int) throws -> String = { localPort, tailscalePort in
            try TailscaleServeManager.configure(localPort: localPort, httpsPort: tailscalePort)
        }
    ) {
        self.deviceStore = deviceStore ?? RemoteApprovalDeviceStore()
        self.coordinator = coordinator ?? RemoteApprovalCoordinator()
        self.personalHub = personalHub ?? .shared
        self.localPortOverride = localPortOverride
        self.enabledOverride = enabledOverride
        self.remoteTasksEnabled = remoteTasksEnabled
            ?? (localPortOverride == nil && enabledOverride == nil)
        self.remoteTaskCoordinatorOverride = remoteTaskCoordinatorOverride
        self.tailscaleConfigurator = tailscaleConfigurator
        syncPublishedState()
    }

    var localPort: Int {
        if let localPortOverride { return Int(localPortOverride) }
        let value = UserDefaults.standard.integer(forKey: SettingsKey.remoteApprovalLocalPort)
        return value > 0 ? value : SettingsDefaults.remoteApprovalLocalPort
    }

    var boundLocalPort: UInt16? {
        server?.boundPort
    }

    var tailscalePort: Int {
        let value = UserDefaults.standard.integer(forKey: SettingsKey.remoteApprovalTailscalePort)
        return value > 0 ? value : SettingsDefaults.remoteApprovalTailscalePort
    }

    var displayURL: String {
        if !tailnetURL.isEmpty { return tailnetURL }
        return "https://this-mac.tailnet:(tailscalePort)"
    }

    func start(appState: AppState) {
        self.appState = appState
        let enabled = enabledOverride ?? (
            UserDefaults.standard.object(forKey: SettingsKey.remoteApprovalsEnabled) == nil
                ? SettingsDefaults.remoteApprovalsEnabled
                : UserDefaults.standard.bool(forKey: SettingsKey.remoteApprovalsEnabled)
        )
        guard enabled
        else {
            stop()
            return
        }

        do {
            let server = try RemoteApprovalHTTPServer(port: UInt16(localPort)) { [weak self] request in
                guard let self else {
                    return .json(status: 503, object: ["error": "service unavailable"])
                }
                return self.route(request)
            }
            self.server = server
            server.start { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.running = true
                        self.lastError = nil
                        self.startRemoteTaskCoordinatorIfNeeded()
                        self.refreshSleepActivity()
                        self.configureTailscaleServe()
                    case .failure(let error):
                        self.running = false
                        self.lastError = error.localizedDescription
                        self.refreshSleepActivity()
                    }
                }
            }
        } catch {
            running = false
            lastError = error.localizedDescription
        }
        stateDidChange()
    }

    func stop() {
        remoteTaskCoordinator?.shutdown()
        remoteTaskStoreCancellable?.cancel()
        remoteTaskStoreCancellable = nil
        remoteTaskCoordinator = nil
        remoteTaskStore = nil
        codexTaskRunner = nil
        claudeTaskRunner = nil
        appState?.codexRemoteTaskRunner = nil
        remoteTasks = []
        remoteTaskWorkspaces = []
        lastRemoteTaskStates = [:]
        server?.stop()
        server = nil
        running = false
        endSleepActivity()
    }

    private func startRemoteTaskCoordinatorIfNeeded() {
        guard remoteTasksEnabled, remoteTaskCoordinator == nil, let appState else { return }

        if let remoteTaskCoordinatorOverride {
            remoteTaskCoordinator = remoteTaskCoordinatorOverride
            refreshRemoteTaskPublishedState()
            do {
                try remoteTaskCoordinatorOverride.recover()
            } catch {
                lastError = "Remote task recovery failed: \(error.localizedDescription)"
            }
            return
        }

        appState.startCodexAppServerWatcher()
        let recent = appState.sessions.values.compactMap { session -> RemoteWorkspaceCandidate? in
            guard let cwd = session.cwd, !cwd.isEmpty else { return nil }
            return RemoteWorkspaceCandidate(
                url: URL(fileURLWithPath: cwd, isDirectory: true),
                source: .recentSession,
                lastUsedAt: session.lastActivity
            )
        }
        let saved = UserDefaults.standard
            .stringArray(forKey: Self.remoteTaskWorkspaceRootsKey)?
            .map {
                RemoteWorkspaceCandidate(
                    url: URL(fileURLWithPath: $0, isDirectory: true),
                    source: .saved
                )
            } ?? []
        let candidates = recent + saved
        let allowedRoots = candidates.map(\.url)
        let catalog = RemoteWorkspaceCatalog(
            allowedRoots: allowedRoots,
            candidates: candidates
        )
        let store = RemoteTaskStore()
        let attachments = RemoteTaskAttachmentStore()

        var codexAdapter: RemoteTaskProviderRunner?
        if let client = appState.codexAppServerClient {
            let runner = CodexRemoteTaskRunner(sender: client, store: store)
            codexTaskRunner = runner
            appState.codexRemoteTaskRunner = runner
            codexAdapter = runner.providerAdapter { [weak appState] in
                appState?.codexAppServerClient != nil
            }
        }

        let claude = ClaudeRemoteTaskRunner(store: store)
        claudeTaskRunner = claude
        let coordinator = RemoteTaskCoordinator(
            store: store,
            workspaceCatalog: catalog,
            attachmentStore: attachments,
            codex: codexAdapter,
            claude: claude.providerAdapter {
                ClaudeExecutableLocator.resolve(
                    explicitPath: UserDefaults.standard.string(
                        forKey: ClaudeExecutableLocator.defaultsKey
                    )
                ) != nil
            }
        )
        remoteTaskStore = store
        remoteTaskCoordinator = coordinator
        remoteTaskWorkspaces = coordinator.workspaces
        persistRemoteTaskWorkspaceRoots(
            coordinator.workspaces.compactMap { coordinator.workspaceURL(id: $0.id) }
        )
        do {
            try coordinator.recover()
        } catch {
            lastError = "Remote task recovery failed: \(error.localizedDescription)"
        }
        remoteTasks = store.tasks.map(\.summary)
        lastRemoteTaskStates = Dictionary(uniqueKeysWithValues: store.tasks.map { ($0.id, $0.summary.state) })
        remoteTaskStoreCancellable = store.$tasks
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] records in
                self?.remoteTaskRecordsDidChange(records)
            }
    }

    private func remoteTaskRecordsDidChange(_ records: [RemoteTaskRecord]) {
        remoteTasks = records.map(\.summary)
        let nextStates = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.summary.state) })
        for record in records {
            let prior = lastRemoteTaskStates[record.id]
            let next = record.summary.state
            guard prior != next else { continue }
            APNSNotificationSender.shared.notifyTask(
                taskID: record.id,
                state: next,
                devices: deviceStore.devices
            )
        }
        lastRemoteTaskStates = nextStates
    }

    @discardableResult
    func createLocalRemoteTask(
        prompt: String,
        workspaceID: String,
        provider: RemoteTaskProvider
    ) throws -> RemoteTaskSummary {
        guard let remoteTaskCoordinator else {
            throw RemoteTaskLocalError.unavailable
        }
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { throw RemoteTaskLocalError.emptyPrompt }
        let request = RemoteTaskCreateRequest(
            clientTaskID: UUID(),
            idempotencyKey: UUID(),
            prompt: cleanPrompt,
            workspaceID: workspaceID,
            provider: provider,
            authority: .editAndTest,
            requestedProof: "Run focused tests and report exact evidence"
        )
        let record = try remoteTaskCoordinator.create(request: request, deviceID: "local-mac")
        if let workspaceURL = remoteTaskCoordinator.workspaceURL(id: record.summary.workspaceID) {
            persistRemoteTaskWorkspaceRoots([workspaceURL])
        }
        refreshRemoteTaskPublishedState()
        return record.summary
    }

    func followUpLocalRemoteTask(id: UUID, text: String) throws {
        guard let remoteTaskCoordinator else { throw RemoteTaskLocalError.unavailable }
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { throw RemoteTaskLocalError.emptyPrompt }
        _ = try remoteTaskCoordinator.followUp(RemoteTaskFollowUpRequest(
            taskID: id,
            idempotencyKey: UUID(),
            text: cleanText
        ))
        refreshRemoteTaskPublishedState()
    }

    func cancelLocalRemoteTask(id: UUID) throws {
        guard let remoteTaskCoordinator else { throw RemoteTaskLocalError.unavailable }
        try remoteTaskCoordinator.cancel(taskID: id)
        refreshRemoteTaskPublishedState()
    }

    @discardableResult
    func openRemoteTaskOnMac(id: UUID) -> Bool {
        guard let appState,
              let remoteTaskCoordinator,
              let record = remoteTaskCoordinator.task(id: id)
        else { return false }

        let workspacePath = remoteTaskCoordinator
            .workspaceURL(id: record.summary.workspaceID)?
            .standardizedFileURL.path
        let candidates = appState.sessions.map { key, session in
            RemoteTaskSessionCandidate(
                id: key,
                provider: session.source,
                workspacePath: session.cwd.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
                updatedAt: session.lastActivity
            )
        }
        guard let targetID = RemoteTaskOpenTargetResolver.resolve(
            providerSessionID: record.summary.providerSessionID,
            provider: record.summary.provider,
            workspacePath: workspacePath,
            candidates: candidates
        ), let session = appState.sessions[targetID]
        else {
            if let workspaceURL = remoteTaskCoordinator.workspaceURL(id: record.summary.workspaceID) {
                NSWorkspace.shared.open(workspaceURL)
            }
            return false
        }

        appState.activeSessionId = targetID
        appState.surface = .sessionList
        TerminalActivator.activate(session: session, sessionId: targetID)
        return true
    }

    func refreshRemoteTaskPublishedState() {
        guard let remoteTaskCoordinator else {
            remoteTasks = []
            remoteTaskWorkspaces = []
            return
        }
        remoteTasks = remoteTaskCoordinator.snapshot.tasks
        remoteTaskWorkspaces = remoteTaskCoordinator.workspaces
    }

    enum RemoteTaskLocalError: LocalizedError {
        case unavailable
        case emptyPrompt

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Remote task service is not available"
            case .emptyPrompt: return "Describe the coding task first"
            }
        }
    }

    func restart() {
        guard let appState else { return }
        stop()
        start(appState: appState)
    }

    func rotatePairingCode() {
        deviceStore.rotatePairingCode()
        pairAttemptLimiter.reset()
        syncPublishedState()
    }

    /// Keeps the code shown in Settings usable. Pairing codes deliberately
    /// expire after ten minutes, but an expired value should never remain the
    /// primary code presented to the user.
    @discardableResult
    func ensureActivePairingCode(at date: Date = Date()) -> Bool {
        guard deviceStore.ensureActivePairingCode(at: date) else { return false }
        pairAttemptLimiter.reset()
        syncPublishedState()
        return true
    }

    func revokeDevice(id: String) {
        deviceStore.revoke(deviceID: id)
        syncPublishedState()
    }

    /// Called from AppState's single derived-state fanout after any queue change.
    /// Pushes only newly observed permission IDs. Remote availability owns a
    /// separate power assertion so the host is reachable before attention arrives.
    func stateDidChange() {
        guard let appState else { return }
        syncRemoteTaskWorkspaces(from: appState)
        let currentIDs = Set(appState.permissionQueue.map(\.id))
        let currentQuestionIDs = Set(appState.questionQueue.map(\.id))

        let newIDs = currentIDs.subtracting(lastPendingIDs)
        let resolvedIDs = lastPendingIDs.subtracting(currentIDs)
        let newQuestionIDs = currentQuestionIDs.subtracting(lastPendingQuestionIDs)
        let resolvedQuestionIDs = lastPendingQuestionIDs.subtracting(currentQuestionIDs)
        lastPendingIDs = currentIDs
        lastPendingQuestionIDs = currentQuestionIDs

        for request in appState.permissionQueue where newIDs.contains(request.id) {
            APNSNotificationSender.shared.notify(
                requestID: request.id,
                kind: .approval,
                state: .pending,
                devices: deviceStore.devices
            )
        }
        for request in appState.questionQueue where newQuestionIDs.contains(request.id) {
            APNSNotificationSender.shared.notify(
                requestID: request.id,
                kind: .question,
                state: .pending,
                devices: deviceStore.devices
            )
        }
        for requestID in resolvedIDs {
            APNSNotificationSender.shared.notify(
                requestID: requestID,
                kind: .approval,
                state: .resolved,
                devices: deviceStore.devices
            )
        }
        for requestID in resolvedQuestionIDs {
            APNSNotificationSender.shared.notify(
                requestID: requestID,
                kind: .question,
                state: .resolved,
                devices: deviceStore.devices
            )
        }
    }

    /// Login items frequently start before any CLI session exists. As sessions
    /// arrive, make their workspaces available to Buddy immediately and retain
    /// the canonical roots locally so durable tasks remain resolvable after the
    /// next Mac restart.
    private func syncRemoteTaskWorkspaces(from appState: AppState) {
        guard let remoteTaskCoordinator else { return }
        let candidates = appState.sessions.values.compactMap { session -> RemoteWorkspaceCandidate? in
            guard let cwd = session.cwd, !cwd.isEmpty else { return nil }
            return RemoteWorkspaceCandidate(
                url: URL(fileURLWithPath: cwd, isDirectory: true),
                source: .recentSession,
                lastUsedAt: session.lastActivity
            )
        }
        guard !candidates.isEmpty else { return }
        do {
            try remoteTaskCoordinator.registerWorkspaces(candidates)
            persistRemoteTaskWorkspaceRoots(
                remoteTaskCoordinator.workspaces.compactMap {
                    remoteTaskCoordinator.workspaceURL(id: $0.id)
                }
            )
            remoteTaskWorkspaces = remoteTaskCoordinator.workspaces
            refreshRemoteTaskPublishedState()
        } catch {
            lastError = "Remote workspace refresh failed: \(error.localizedDescription)"
        }
    }

    private func persistRemoteTaskWorkspaceRoots(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let defaults = UserDefaults.standard
        let existing = defaults.stringArray(forKey: Self.remoteTaskWorkspaceRootsKey) ?? []
        let merged = RemoteWorkspaceRootPersistence.merging(urls, into: existing)
        guard merged != existing else { return }
        defaults.set(merged, forKey: Self.remoteTaskWorkspaceRootsKey)
    }

    func refreshSleepActivity() {
        let preventSleep = UserDefaults.standard.object(forKey: SettingsKey.remoteApprovalPreventSleep) == nil
            ? SettingsDefaults.remoteApprovalPreventSleep
            : UserDefaults.standard.bool(forKey: SettingsKey.remoteApprovalPreventSleep)
        let shouldPreventSleep = Self.shouldPreventSystemSleep(
            serviceRunning: running,
            preferenceEnabled: preventSleep
        )
        if shouldPreventSleep, sleepActivity == nil {
            sleepActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated],
                reason: "CodeIsland remote access is enabled"
            )
        } else if !shouldPreventSleep, sleepActivity != nil {
            endSleepActivity()
        }
    }

    nonisolated static func shouldPreventSystemSleep(
        serviceRunning: Bool,
        preferenceEnabled: Bool
    ) -> Bool {
        serviceRunning && preferenceEnabled
    }

    private func endSleepActivity() {
        guard let sleepActivity else { return }
        ProcessInfo.processInfo.endActivity(sleepActivity)
        self.sleepActivity = nil
    }

    private func syncPublishedState() {
        pairedDevices = deviceStore.devices
        pairingCode = deviceStore.pairingCode
        pairingExpiresAt = deviceStore.pairingExpiresAt
    }

    private func configureTailscaleServe() {
        let localPort = localPort
        let tailscalePort = tailscalePort
        let configurator = tailscaleConfigurator
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> Result<String, Error> in
                do {
                    return .success(try configurator(localPort, tailscalePort))
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self else { return }
            switch result {
            case .success(let url):
                self.tailnetURL = url
                UserDefaults.standard.set(url, forKey: SettingsKey.remoteApprovalTailnetURL)
                self.lastError = nil
            case .failure(let error):
                self.lastError = "Local server is running; Tailscale Serve failed: \(error.localizedDescription)"
            }
        }
    }

    private func route(_ request: RemoteHTTPRequest) -> RemoteHTTPResponse {
        guard let appState else {
            return .json(status: 503, object: ["error": "approval state unavailable"])
        }

        switch (request.method, request.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            return .html(RemoteApprovalWebApp.html)
        case ("GET", "/manifest.webmanifest"):
            return RemoteHTTPResponse(
                status: 200,
                headers: ["Content-Type": "application/manifest+json; charset=utf-8"],
                body: Data(RemoteApprovalWebApp.manifest.utf8)
            )
        case ("GET", "/app-icon.svg"):
            return RemoteHTTPResponse(
                status: 200,
                headers: [
                    "Content-Type": "image/svg+xml; charset=utf-8",
                    "Cache-Control": "public, max-age=86400"
                ],
                body: Data(RemoteApprovalWebApp.iconSVG.utf8)
            )
        case ("GET", "/sw.js"):
            return RemoteHTTPResponse(
                status: 200,
                headers: [
                    "Content-Type": "application/javascript; charset=utf-8",
                    "Service-Worker-Allowed": "/"
                ],
                body: Data(RemoteApprovalWebApp.serviceWorker.utf8)
            )
        case ("GET", "/health"):
            let glances = GlancesModel.shared
            glances.refreshAuthorizationStatuses()
            let manualWeatherLocationConfigured = !SettingsManager.shared.glancesWeatherLocation
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            let status = RemoteServiceStatus(
                running: running,
                pendingCount: appState.permissionQueue.count,
                serverName: Host.current().localizedName ?? "CodeIsland Mac",
                hostVersion: AppVersion.current,
                launchAtLoginStatus: SettingsManager.shared.launchAtLoginStatusDescription,
                launchAtLoginError: SettingsManager.shared.lastLaunchAtLoginError,
                calendarAuthorizationStatus: GlancesModel.eventKitAuthorizationStatusName(
                    glances.calendarAuthorizationStatus
                ),
                remindersAuthorizationStatus: GlancesModel.eventKitAuthorizationStatusName(
                    glances.remindersAuthorizationStatus
                ),
                locationAuthorizationStatus: GlancesModel.locationAuthorizationStatusName(
                    glances.locationAuthorizationStatus
                ),
                manualWeatherLocationConfigured: manualWeatherLocationConfigured,
                reminderListSelectionConfigured: !SettingsManager.shared.glancesReminderCalendarIDs.isEmpty
            )
            return .json(status: 200, encodable: status)
        case ("POST", "/api/pair"):
            guard pairAttemptLimiter.canAttempt() else {
                return .json(status: 429, object: ["error": "too many pairing attempts; create a new code on the Mac"])
            }
            guard let pairRequest = request.decode(RemotePairRequest.self) else {
                return .json(status: 400, object: ["error": "invalid pairing request"])
            }
            guard let response = deviceStore.pair(pairRequest) else {
                pairAttemptLimiter.recordFailure()
                coordinator.recordPairFailure(deviceName: pairRequest.deviceName)
                return .json(status: 403, object: ["error": "pairing code is invalid or expired"])
            }
            pairAttemptLimiter.reset()
            syncPublishedState()
            coordinator.recordPairSuccess(deviceID: response.deviceId, deviceName: pairRequest.deviceName)
            return .json(status: 201, encodable: response)
        default:
            break
        }

        guard let authenticated = authenticate(request) else {
            return RemoteHTTPResponse.json(
                status: 401,
                object: ["error": "pair this device from CodeIsland Settings"],
                extraHeaders: ["WWW-Authenticate": "Bearer"]
            )
        }

        if request.path == "/api/tasks" || request.path.hasPrefix("/api/tasks/") {
            return routeRemoteTask(request, deviceID: authenticated.id)
        }

        if request.method == "GET", request.path == "/api/approvals" {
            let snapshot = coordinator.snapshot(
                appState: appState,
                deviceID: authenticated.id,
                companionSequence: AppleCompanionPublisher.shared.currentSequence
            )
            return .json(status: 200, encodable: snapshot)
        }

        if request.method == "GET", request.path == "/api/hub" {
            let snapshot = personalHub.snapshot(
                appState: appState,
                requestedMode: .auto
            )
            return .json(status: 200, encodable: snapshot)
        }

        if request.method == "POST", request.path == "/api/hub/snapshot" {
            guard let snapshotRequest = request.decode(PersonalHubSnapshotRequest.self) else {
                return .json(status: 400, object: ["error": "invalid hub snapshot request"])
            }
            let snapshot = personalHub.snapshot(
                appState: appState,
                requestedMode: snapshotRequest.requestedMode,
                calendarReferenceDate: snapshotRequest.calendarReferenceDate,
                calendarSelectedDate: snapshotRequest.calendarSelectedDate
            )
            return .json(status: 200, encodable: snapshot)
        }

        let shelfFilePrefix = "/api/hub/shelf/"
        let shelfFileSuffix = "/file"
        if request.method == "GET",
           request.path.hasPrefix(shelfFilePrefix),
           request.path.hasSuffix(shelfFileSuffix) {
            let start = request.path.index(request.path.startIndex, offsetBy: shelfFilePrefix.count)
            let end = request.path.index(request.path.endIndex, offsetBy: -shelfFileSuffix.count)
            let itemID = String(request.path[start..<end]).removingPercentEncoding ?? ""
            return downloadableFileResponse(
                fileURL: itemID.isEmpty ? nil : personalHub.shelfFileURL(id: itemID),
                unavailableMessage: "shelf file is no longer available"
            )
        }

        let downloadFilePrefix = "/api/hub/downloads/"
        let downloadFileSuffix = "/file"
        if request.method == "GET",
           request.path.hasPrefix(downloadFilePrefix),
           request.path.hasSuffix(downloadFileSuffix) {
            let start = request.path.index(request.path.startIndex, offsetBy: downloadFilePrefix.count)
            let end = request.path.index(request.path.endIndex, offsetBy: -downloadFileSuffix.count)
            let itemID = String(request.path[start..<end]).removingPercentEncoding ?? ""
            return downloadableFileResponse(
                fileURL: itemID.isEmpty ? nil : personalHub.recentDownloadFileURL(id: itemID),
                unavailableMessage: "download is no longer available or exceeds 100 MB"
            )
        }

        if request.method == "POST", request.path == "/api/hub/actions/prepare" {
            guard let prepareRequest = request.decode(PersonalHubPrepareActionRequest.self) else {
                return .json(status: 400, object: ["error": "invalid action intent"])
            }
            switch personalHub.prepare(
                intent: prepareRequest.intent,
                deviceID: authenticated.id
            ) {
            case .success(let prepared):
                return .json(status: 200, encodable: prepared)
            case .failure(let error):
                return .json(status: 400, object: ["error": error.localizedDescription])
            }
        }

        if request.method == "POST", request.path == "/api/hub/actions/execute" {
            guard let executeRequest = request.decode(PersonalHubExecuteActionRequest.self) else {
                return .json(status: 400, object: ["error": "invalid action confirmation"])
            }
            switch personalHub.execute(
                request: executeRequest,
                deviceID: authenticated.id
            ) {
            case .success(let response):
                stateDidChange()
                return .json(status: 200, encodable: response)
            case .failure(.expired):
                return .json(status: 409, object: ["error": "action confirmation expired; review it again"])
            case .failure(.unauthorized):
                return .json(status: 403, object: ["error": "action confirmation is invalid"])
            case .failure(let error):
                return .json(status: 400, object: ["error": error.localizedDescription])
            }
        }

        if request.method == "POST", request.path == "/api/push-token" {
            guard let registration = request.decode(RemotePushRegistrationRequest.self),
                  Self.validPushRegistration(registration)
            else {
                return .json(status: 400, object: ["error": "invalid push token"])
            }
            let acceptedReceipts = deviceStore.registerPushToken(
                registration,
                deviceID: authenticated.id
            )
            coordinator.recordLiveActivityReceipts(
                acceptedReceipts,
                deviceID: authenticated.id,
                deviceName: authenticated.name
            )
            syncPublishedState()
            return .json(
                status: 200,
                encodable: RemotePushRegistrationResponse(
                    registered: true,
                    deviceId: authenticated.id
                )
            )
        }

        let prefix = "/api/approvals/"
        let suffix = "/decision"
        if request.method == "POST",
           request.path.hasPrefix(prefix), request.path.hasSuffix(suffix) {
            let start = request.path.index(request.path.startIndex, offsetBy: prefix.count)
            let end = request.path.index(request.path.endIndex, offsetBy: -suffix.count)
            let requestID = String(request.path[start..<end]).removingPercentEncoding ?? ""
            guard !requestID.isEmpty,
                  let decisionRequest = request.decode(RemoteDecisionRequest.self)
            else {
                return .json(status: 400, object: ["error": "invalid decision request"])
            }

            let result = coordinator.resolve(
                appState: appState,
                requestID: requestID,
                actionToken: decisionRequest.actionToken,
                deviceID: authenticated.id,
                deviceName: authenticated.name,
                decision: decisionRequest.decision
            )
            switch result {
            case .resolved:
                stateDidChange()
                return .json(
                    status: 200,
                    encodable: RemoteDecisionResponse(
                        resolved: true,
                        requestId: requestID,
                        decision: decisionRequest.decision
                    )
                )
            case .expired:
                return .json(status: 409, object: ["error": "action token expired; refresh approvals"])
            case .stale:
                return .json(status: 409, object: ["error": "approval is no longer pending"])
            case .unauthorized:
                return .json(status: 403, object: ["error": "action token is invalid"])
            case .invalid:
                return .json(status: 400, object: ["error": "decision is invalid"])
            }
        }

        let questionPrefix = "/api/questions/"
        let questionSuffix = "/answer"
        if request.method == "POST",
           request.path.hasPrefix(questionPrefix), request.path.hasSuffix(questionSuffix) {
            let start = request.path.index(request.path.startIndex, offsetBy: questionPrefix.count)
            let end = request.path.index(request.path.endIndex, offsetBy: -questionSuffix.count)
            let requestID = String(request.path[start..<end]).removingPercentEncoding ?? ""
            guard !requestID.isEmpty,
                  let answerRequest = request.decode(RemoteQuestionAnswerRequest.self)
            else {
                return .json(status: 400, object: ["error": "invalid question answer"])
            }

            let result = coordinator.resolveQuestion(
                appState: appState,
                requestID: requestID,
                answers: answerRequest.answers,
                actionToken: answerRequest.actionToken,
                deviceID: authenticated.id,
                deviceName: authenticated.name
            )
            switch result {
            case .resolved:
                stateDidChange()
                return .json(
                    status: 200,
                    encodable: RemoteQuestionAnswerResponse(answered: true, requestId: requestID)
                )
            case .expired:
                return .json(status: 409, object: ["error": "action token expired; refresh questions"])
            case .stale:
                return .json(status: 409, object: ["error": "question is no longer pending"])
            case .unauthorized:
                return .json(status: 403, object: ["error": "action token is invalid"])
            case .invalid:
                return .json(status: 400, object: ["error": "answer each non-sensitive prompt on this device"])
            }
        }

        return .json(status: 404, object: ["error": "not found"])
    }

    private func routeRemoteTask(_ request: RemoteHTTPRequest, deviceID: String) -> RemoteHTTPResponse {
        guard let taskCoordinator = remoteTaskCoordinator else {
            return .json(status: 503, object: ["error": "remote tasks are unavailable"])
        }
        let components = request.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        if components == ["api", "tasks"] {
            switch request.method {
            case "GET":
                return .json(status: 200, encodable: taskCoordinator.snapshot(deviceID: deviceID))
            case "POST":
                guard let create = request.decode(RemoteTaskCreateRequest.self),
                      create.version == RemoteTaskCreateRequest.currentVersion,
                      !create.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      create.prompt.utf8.count <= 60_000
                else {
                    return .json(status: 400, object: ["error": "invalid task request"])
                }
                if let existing = taskCoordinator.task(idempotencyKey: create.idempotencyKey) {
                    guard existing.deviceID == deviceID else {
                        return .json(status: 403, object: ["error": "task belongs to another paired device"])
                    }
                    return .json(status: 200, encodable: existing.summary)
                }
                if let agentOpsTaskID = create.agentOpsTaskID,
                   let existing = taskCoordinator.task(agentOpsTaskID: agentOpsTaskID) {
                    guard existing.deviceID == deviceID else {
                        return .json(status: 403, object: ["error": "task belongs to another paired device"])
                    }
                    return .json(status: 200, encodable: existing.summary)
                }
                do {
                    let created = try taskCoordinator.create(request: create, deviceID: deviceID)
                    if let workspaceURL = taskCoordinator.workspaceURL(id: created.summary.workspaceID) {
                        persistRemoteTaskWorkspaceRoots([workspaceURL])
                    }
                    return .json(status: 201, encodable: created.summary)
                } catch {
                    return remoteTaskErrorResponse(error)
                }
            default:
                return .json(status: 405, object: ["error": "method not allowed"])
            }
        }

        if components == ["api", "tasks", "workspaces"] {
            guard request.method == "GET" else {
                return .json(status: 405, object: ["error": "method not allowed"])
            }
            return .json(
                status: 200,
                encodable: RemoteWorkspaceSnapshot(workspaces: taskCoordinator.workspaces)
            )
        }

        guard components.count >= 3,
              components[0] == "api", components[1] == "tasks",
              let taskID = UUID(uuidString: components[2])
        else {
            return .json(status: 404, object: ["error": "task not found"])
        }
        guard let record = taskCoordinator.task(id: taskID) else {
            return .json(status: 404, object: ["error": "task not found"])
        }
        guard record.deviceID == deviceID else {
            return .json(status: 403, object: ["error": "task belongs to another paired device"])
        }

        if components.count == 3 {
            guard request.method == "GET" else {
                return .json(status: 405, object: ["error": "method not allowed"])
            }
            return .json(status: 200, encodable: record.summary)
        }

        if components.count == 4, components[3] == "follow-up" {
            guard request.method == "POST" else {
                return .json(status: 405, object: ["error": "method not allowed"])
            }
            guard let followUp = request.decode(RemoteTaskFollowUpRequest.self),
                  followUp.version == RemoteTaskFollowUpRequest.currentVersion,
                  followUp.taskID == taskID,
                  !followUp.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  followUp.text.utf8.count <= 60_000
            else {
                return .json(status: 400, object: ["error": "invalid follow-up request"])
            }
            do {
                return .json(status: 200, encodable: try taskCoordinator.followUp(followUp).summary)
            } catch {
                return remoteTaskErrorResponse(error)
            }
        }

        if components.count == 4, components[3] == "cancel" {
            guard request.method == "POST" else {
                return .json(status: 405, object: ["error": "method not allowed"])
            }
            do {
                try taskCoordinator.cancel(taskID: taskID)
                return .json(status: 200, encodable: taskCoordinator.task(id: taskID)?.summary ?? record.summary)
            } catch {
                return remoteTaskErrorResponse(error)
            }
        }

        if components.count == 5, components[3] == "attachments" {
            guard request.method == "PUT" else {
                return .json(status: 405, object: ["error": "method not allowed"])
            }
            let attachmentID = components[4].removingPercentEncoding ?? ""
            guard !attachmentID.isEmpty else {
                return .json(status: 400, object: ["error": "invalid attachment identifier"])
            }
            do {
                let updated = try taskCoordinator.stageAttachment(
                    taskID: taskID,
                    attachmentID: attachmentID,
                    data: request.body
                )
                return .json(status: 200, encodable: updated.summary)
            } catch RemoteTaskCoordinator.CoordinatorError.attachmentMismatch {
                return .json(status: 409, object: ["error": "attachment size or SHA-256 mismatch"])
            } catch RemoteTaskCoordinator.CoordinatorError.unknownAttachment {
                return .json(status: 404, object: ["error": "attachment was not declared"])
            } catch {
                return remoteTaskErrorResponse(error)
            }
        }

        if components.count == 5, components[3] == "actions", components[4] == "prepare" {
            guard request.method == "POST" else {
                return .json(status: 405, object: ["error": "method not allowed"])
            }
            guard let intent = request.decode(RemoteTaskActionIntent.self),
                  intent.version == RemoteTaskActionIntent.currentVersion,
                  intent.taskID == taskID
            else {
                return .json(status: 400, object: ["error": "invalid action intent"])
            }
            do {
                return .json(
                    status: 200,
                    encodable: try taskCoordinator.prepareAction(intent, deviceID: deviceID)
                )
            } catch {
                return remoteTaskErrorResponse(error)
            }
        }

        if components.count == 5, components[3] == "actions", components[4] == "execute" {
            guard request.method == "POST" else {
                return .json(status: 405, object: ["error": "method not allowed"])
            }
            guard let execution = request.decode(RemoteTaskActionExecutionRequest.self),
                  execution.version == RemoteTaskActionExecutionRequest.currentVersion,
                  execution.intent.taskID == taskID
            else {
                return .json(status: 400, object: ["error": "invalid action confirmation"])
            }
            do {
                try taskCoordinator.authorizeAction(
                    execution.intent,
                    actionToken: execution.actionToken,
                    deviceID: deviceID
                )
                return .json(status: 200, encodable: taskCoordinator.task(id: taskID)?.summary ?? record.summary)
            } catch RemoteTaskCoordinator.CoordinatorError.invalidActionToken {
                return .json(status: 403, object: ["error": "action confirmation is invalid or expired"])
            } catch RemoteTaskCoordinator.CoordinatorError.staleAction {
                return .json(status: 409, object: ["error": "task changed; review the action again"])
            } catch {
                return remoteTaskErrorResponse(error)
            }
        }

        return .json(status: 405, object: ["error": "method not allowed"])
    }

    private func remoteTaskErrorResponse(_ error: Error) -> RemoteHTTPResponse {
        switch error {
        case RemoteTaskCoordinator.CoordinatorError.unknownTask:
            return .json(status: 404, object: ["error": "task not found"])
        case RemoteTaskCoordinator.CoordinatorError.invalidActionToken:
            return .json(status: 403, object: ["error": error.localizedDescription])
        case RemoteTaskCoordinator.CoordinatorError.staleAction,
             RemoteTaskCoordinator.CoordinatorError.attachmentMismatch:
            return .json(status: 409, object: ["error": error.localizedDescription])
        default:
            return .json(status: 400, object: ["error": error.localizedDescription])
        }
    }

    private func downloadableFileResponse(
        fileURL: URL?,
        unavailableMessage: String
    ) -> RemoteHTTPResponse {
        guard let fileURL,
              let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize else {
            return .json(status: 404, object: ["error": unavailableMessage])
        }
        guard fileSize <= PersonalUtilitiesModel.maximumRemoteTransferBytes else {
            return .json(status: 413, object: ["error": "private file transfers are limited to 100 MB"])
        }
        guard let body = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
            return .json(status: 404, object: ["error": "file could not be read"])
        }
        let encodedName = fileURL.lastPathComponent.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "._-"))
        ) ?? "CodeIsland-file"
        return RemoteHTTPResponse(
            status: 200,
            headers: [
                "Content-Type": "application/octet-stream",
                "Content-Disposition": "attachment; filename*=UTF-8''\(encodedName)"
            ],
            body: body
        )
    }

    private static func validPushRegistration(_ registration: RemotePushRegistrationRequest) -> Bool {
        let updateTokens = registration.liveActivityUpdateTokens ?? [:]
        let receipts = registration.liveActivityReceipts ?? []
        let tokens = [registration.token, registration.liveActivityPushToStartToken].compactMap { $0 }
            + Array(updateTokens.values)
        let hasClientMetadata = registration.clientVersion != nil || registration.clientBuild != nil
        if hasClientMetadata {
            guard let version = registration.clientVersion,
                  let build = registration.clientBuild,
                  validClientMetadata(version, maximumLength: 40),
                  validClientMetadata(build, maximumLength: 64)
            else { return false }
        }
        guard !tokens.isEmpty || !receipts.isEmpty || hasClientMetadata,
              tokens.allSatisfy({ $0.count >= 32 && $0.allSatisfy(\.isHexDigit) }),
              registration.liveActivityUpdateTokens?.keys.allSatisfy({ !$0.isEmpty && $0.count <= 200 }) ?? true,
              receipts.count <= 16,
              receipts.allSatisfy(\.isStructurallyValid)
        else { return false }
        return registration.environment == "production" || registration.environment == "development"
    }

    private static func validClientMetadata(_ value: String, maximumLength: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximumLength else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_+"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private func authenticate(_ request: RemoteHTTPRequest) -> RemoteApprovalDevice? {
        guard let authorization = request.headers["authorization"],
              authorization.lowercased().hasPrefix("bearer ")
        else { return nil }
        let token = String(authorization.dropFirst("Bearer ".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        let device = deviceStore.authenticate(token: token)
        if device != nil { syncPublishedState() }
        return device
    }
}

struct RemoteApprovalDevice: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    let tokenHash: String
    let pairedAt: Date
    var lastSeenAt: Date
    var pushToken: String?
    var pushEnvironment: String?
    var liveActivityPushToStartToken: String?
    var liveActivityUpdateTokens: [String: String]?
    var lastLiveActivityReceipt: RemoteLiveActivityReceipt?
    var recentLiveActivityReceiptIDs: [String]?
    var clientVersion: String?
    var clientBuild: String?
}

@MainActor
final class RemoteApprovalDeviceStore {
    private struct PersistedState: Codable {
        var devices: [RemoteApprovalDevice]
    }

    private(set) var devices: [RemoteApprovalDevice] = []
    private(set) var pairingCode = ""
    private(set) var pairingExpiresAt: Date = .distantPast
    private let stateURL: URL
    private var lastSavedSeenAt: [String: Date] = [:]

    init(stateURL: URL? = nil) {
        self.stateURL = stateURL ?? Self.applicationSupportDirectory()
            .appendingPathComponent("remote-approval-devices.json")
        load()
        rotatePairingCode()
    }

    func rotatePairingCode(at date: Date = Date()) {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            pairingCode = String(format: "%06d", Int.random(in: 0...999_999))
            pairingExpiresAt = date.addingTimeInterval(600)
            return
        }
        let value = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        pairingCode = String(format: "%06d", Int(value % 1_000_000))
        pairingExpiresAt = date.addingTimeInterval(600)
    }

    @discardableResult
    func ensureActivePairingCode(at date: Date = Date()) -> Bool {
        guard date >= pairingExpiresAt else { return false }
        rotatePairingCode(at: date)
        return true
    }

    func pair(_ request: RemotePairRequest) -> RemotePairResponse? {
        let code = request.code.filter(\.isNumber)
        guard Date() < pairingExpiresAt,
              code.count == 6,
              Self.constantTimeEqual(code, pairingCode)
        else { return nil }

        let token = Self.randomToken()
        let name = String(request.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let device = RemoteApprovalDevice(
            id: UUID().uuidString.lowercased(),
            name: name.isEmpty ? "iPhone" : name,
            tokenHash: Self.hash(token),
            pairedAt: Date(),
            lastSeenAt: Date(),
            pushToken: nil,
            pushEnvironment: nil,
            liveActivityPushToStartToken: nil,
            liveActivityUpdateTokens: nil,
            lastLiveActivityReceipt: nil,
            recentLiveActivityReceiptIDs: nil,
            clientVersion: nil,
            clientBuild: nil
        )
        devices.append(device)
        save()
        rotatePairingCode()
        return RemotePairResponse(
            deviceId: device.id,
            deviceToken: token,
            serverName: Host.current().localizedName ?? "CodeIsland Mac"
        )
    }

    func authenticate(token: String) -> RemoteApprovalDevice? {
        let hash = Self.hash(token)
        guard let index = devices.firstIndex(where: { Self.constantTimeEqual($0.tokenHash, hash) }) else {
            return nil
        }
        let now = Date()
        devices[index].lastSeenAt = now
        let lastSaved = lastSavedSeenAt[devices[index].id] ?? .distantPast
        if now.timeIntervalSince(lastSaved) > 60 {
            lastSavedSeenAt[devices[index].id] = now
            save()
        }
        return devices[index]
    }

    @discardableResult
    func registerPushToken(
        _ registration: RemotePushRegistrationRequest,
        deviceID: String
    ) -> [RemoteLiveActivityReceipt] {
        guard let originalIndex = devices.firstIndex(where: { $0.id == deviceID }) else { return [] }
        let environment = registration.environment.lowercased()
        let pushToken = registration.token?.lowercased()
        let pushToStartToken = registration.liveActivityPushToStartToken?.lowercased()

        // APNs and push-to-start routes identify one installed app instance in
        // one APNs environment. If that instance re-pairs, transfer ownership
        // of only those global routes to the new record and revoke stale bearer
        // credentials. Live Activity update tokens and receipts are pairing-ID
        // scoped and must never cross into the replacement device record.
        var stagedDevices = devices
        stagedDevices[originalIndex].pushEnvironment = environment
        if let pushToken { stagedDevices[originalIndex].pushToken = pushToken }
        if let pushToStartToken {
            stagedDevices[originalIndex].liveActivityPushToStartToken = pushToStartToken
        }
        let component = Self.globalRouteComponents(in: stagedDevices)
            .first(where: { $0.contains(originalIndex) }) ?? [originalIndex]
        let duplicateDevices = component
            .filter { $0 != originalIndex }
            .map { devices[$0] }
        let duplicateIDs = Set(duplicateDevices.map(\.id))
        if !duplicateIDs.isEmpty {
            devices.removeAll { duplicateIDs.contains($0.id) }
            for id in duplicateIDs { lastSavedSeenAt.removeValue(forKey: id) }
        }

        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return [] }
        devices[index].liveActivityUpdateTokens = Self.trimmedUpdateTokens(
            (devices[index].liveActivityUpdateTokens ?? [:]).mapValues { $0.lowercased() }
        )
        if devices[index].pushToken == nil {
            devices[index].pushToken = duplicateDevices
                .sorted(by: Self.newestDeviceFirst)
                .compactMap(\.pushToken)
                .first
        }
        if devices[index].liveActivityPushToStartToken == nil {
            devices[index].liveActivityPushToStartToken = duplicateDevices
                .sorted(by: Self.newestDeviceFirst)
                .compactMap(\.liveActivityPushToStartToken)
                .first
        }
        if let pushToken { devices[index].pushToken = pushToken }
        if let pushToStartToken { devices[index].liveActivityPushToStartToken = pushToStartToken }
        if let version = registration.clientVersion,
           let build = registration.clientBuild {
            devices[index].clientVersion = version
            devices[index].clientBuild = build
        }
        if let updates = registration.liveActivityUpdateTokens, !updates.isEmpty {
            var merged = devices[index].liveActivityUpdateTokens ?? [:]
            for (requestID, token) in updates {
                merged[requestID] = token.lowercased()
            }
            devices[index].liveActivityUpdateTokens = Self.trimmedUpdateTokens(merged)
        }
        var acceptedReceipts: [RemoteLiveActivityReceipt] = []
        var receiptIDs = devices[index].recentLiveActivityReceiptIDs ?? []
        var knownReceiptIDs = Set(receiptIDs)
        for receipt in registration.liveActivityReceipts ?? [] where knownReceiptIDs.insert(receipt.eventId).inserted {
            acceptedReceipts.append(receipt)
            receiptIDs.append(receipt.eventId)
            if Self.shouldReplaceLiveActivitySummary(
                devices[index].lastLiveActivityReceipt,
                with: receipt
            ) {
                devices[index].lastLiveActivityReceipt = receipt
            }
            if let requestID = receipt.requestId,
               Self.isTerminalLiveActivityReceipt(receipt) {
                devices[index].liveActivityUpdateTokens?.removeValue(forKey: requestID)
                if devices[index].liveActivityUpdateTokens?.isEmpty == true {
                    devices[index].liveActivityUpdateTokens = nil
                }
            }
        }
        if receiptIDs.count > 128 {
            receiptIDs = Array(receiptIDs.suffix(128))
        }
        if !receiptIDs.isEmpty {
            devices[index].recentLiveActivityReceiptIDs = receiptIDs
        }
        devices[index].pushEnvironment = environment
        devices[index].lastSeenAt = Date()
        save()
        return acceptedReceipts
    }

    private static func shouldReplaceLiveActivitySummary(
        _ current: RemoteLiveActivityReceipt?,
        with candidate: RemoteLiveActivityReceipt
    ) -> Bool {
        guard let current else { return true }

        if current.requestId != nil, current.requestId == candidate.requestId {
            let currentIsTerminal = isTerminalLiveActivityReceipt(current)
            let candidateIsTerminal = isTerminalLiveActivityReceipt(candidate)
            if currentIsTerminal != candidateIsTerminal {
                return candidateIsTerminal
            }
        }

        return candidate.observedAt >= current.observedAt
    }

    private static func isTerminalLiveActivityReceipt(_ receipt: RemoteLiveActivityReceipt) -> Bool {
        if receipt.state == .resolved { return true }
        return receipt.activityState == .ended || receipt.activityState == .dismissed
    }

    func revoke(deviceID: String) {
        devices.removeAll { $0.id == deviceID }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder.remoteApproval.decode(PersistedState.self, from: data)
        else { return }
        devices = Self.normalizedGlobalRoutes(state.devices)
        if devices != state.devices { save() }
    }

    private static func normalizedGlobalRoutes(
        _ source: [RemoteApprovalDevice]
    ) -> [RemoteApprovalDevice] {
        var replacements: [Int: RemoteApprovalDevice] = [:]
        var removedIndices = Set<Int>()

        for component in globalRouteComponents(in: source) where component.count > 1 {
            let ordered = component.sorted { oldestDeviceFirst(source[$0], source[$1]) }
            guard let oldestIndex = ordered.first else { continue }
            var merged = source[oldestIndex]
            for index in ordered.dropFirst() {
                merged = mergingGlobalRouteState(winner: source[index], loser: merged)
            }
            guard let winnerIndex = component.first(where: { source[$0].id == merged.id }) else {
                continue
            }
            replacements[winnerIndex] = merged
            removedIndices.formUnion(component.filter { $0 != winnerIndex })
        }

        return source.indices.compactMap { index in
            guard !removedIndices.contains(index) else { return nil }
            return replacements[index] ?? source[index]
        }
    }

    private static func globalRouteComponents(
        in devices: [RemoteApprovalDevice]
    ) -> [[Int]] {
        guard !devices.isEmpty else { return [] }
        var visited = Array(repeating: false, count: devices.count)
        var components: [[Int]] = []

        for start in devices.indices where !visited[start] {
            var component: [Int] = []
            var queue = [start]
            var cursor = 0
            visited[start] = true

            while cursor < queue.count {
                let current = queue[cursor]
                cursor += 1
                component.append(current)
                for candidate in devices.indices where !visited[candidate] {
                    if sharesGlobalRoute(devices[current], devices[candidate]) {
                        visited[candidate] = true
                        queue.append(candidate)
                    }
                }
            }
            components.append(component)
        }
        return components
    }

    private static func sharesGlobalRoute(
        _ lhs: RemoteApprovalDevice,
        _ rhs: RemoteApprovalDevice
    ) -> Bool {
        guard let lhsEnvironment = lhs.pushEnvironment?.lowercased(),
              let rhsEnvironment = rhs.pushEnvironment?.lowercased(),
              lhsEnvironment == rhsEnvironment
        else { return false }
        let sharesPush = lhs.pushToken.flatMap { token in
            token.isEmpty ? nil : rhs.pushToken.map { $0.caseInsensitiveCompare(token) == .orderedSame }
        } ?? false
        let sharesPushToStart = lhs.liveActivityPushToStartToken.flatMap { token in
            token.isEmpty ? nil : rhs.liveActivityPushToStartToken.map {
                $0.caseInsensitiveCompare(token) == .orderedSame
            }
        } ?? false
        return sharesPush || sharesPushToStart
    }

    private static func mergingGlobalRouteState(
        winner: RemoteApprovalDevice,
        loser: RemoteApprovalDevice
    ) -> RemoteApprovalDevice {
        var winner = winner
        if winner.pushToken == nil { winner.pushToken = loser.pushToken }
        if winner.liveActivityPushToStartToken == nil {
            winner.liveActivityPushToStartToken = loser.liveActivityPushToStartToken
        }
        winner.liveActivityUpdateTokens = trimmedUpdateTokens(
            (winner.liveActivityUpdateTokens ?? [:]).mapValues { $0.lowercased() }
        )
        return winner
    }

    private static func trimmedUpdateTokens(_ tokens: [String: String]) -> [String: String]? {
        guard !tokens.isEmpty else { return nil }
        var result = tokens
        if result.count > 128 {
            for key in result.keys.sorted().prefix(result.count - 128) {
                result.removeValue(forKey: key)
            }
        }
        return result
    }

    private static func newestDeviceFirst(
        _ lhs: RemoteApprovalDevice,
        _ rhs: RemoteApprovalDevice
    ) -> Bool {
        if lhs.pairedAt == rhs.pairedAt { return lhs.id > rhs.id }
        return lhs.pairedAt > rhs.pairedAt
    }

    private static func oldestDeviceFirst(
        _ lhs: RemoteApprovalDevice,
        _ rhs: RemoteApprovalDevice
    ) -> Bool {
        newestDeviceFirst(rhs, lhs)
    }

    private func save() {
        let state = PersistedState(devices: devices)
        guard let data = try? JSONEncoder.remoteApproval.encode(state) else { return }
        let directory = stateURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        do {
            try data.write(to: stateURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        } catch {
            remoteApprovalLog.error("device store save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func applicationSupportDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return root.appendingPathComponent("CodeIsland", isDirectory: true)
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

@MainActor
final class RemoteApprovalCoordinator {
    enum ResolutionResult {
        case resolved
        case expired
        case stale
        case unauthorized
        case invalid
    }

    private struct AuditEvent: Codable {
        let timestamp: Date
        let event: String
        let requestID: String?
        let sessionID: String?
        let deviceID: String?
        let deviceName: String?
        let decision: String?
        let outcome: String
        let source: String?
        let tool: String?
    }

    private struct LiveActivityReceiptAuditEvent: Codable {
        let timestamp: Date
        let event: String
        let receiptEventID: String
        let requestID: String?
        let deviceID: String
        let deviceName: String
        let outcome: String
        let source: String
        let attentionKind: String?
        let attentionState: String?
        let activityState: String?
        let observedAt: Date
        let activitiesEnabled: Bool
        let activeActivityCount: Int
        let activeRequestIDs: [String]
    }

    private var actionTokens = RemoteActionTokenVault()
    private let auditURL: URL

    init(auditURL: URL? = nil) {
        self.auditURL = auditURL ?? RemoteApprovalDeviceStore.applicationSupportDirectory()
            .appendingPathComponent("remote-approval-audit.jsonl")
    }

    func snapshot(
        appState: AppState,
        deviceID: String,
        companionSequence: UInt64? = nil
    ) -> RemoteApprovalSnapshot {
        let now = Date()

        let approvals = appState.permissionQueue.map { request -> RemoteApprovalItem in
            let action = actionTokens.issue(requestID: request.id, deviceID: deviceID, now: now)
            let sessionID = request.event.sessionId ?? "default"
            let workspace = appState.sessions[sessionID]?.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            return RemoteApprovalItem(
                id: request.id,
                sessionId: sessionID,
                source: AppState.sourceLabel(for: request.event),
                tool: String((request.event.toolName ?? "Approval").prefix(120)),
                detail: request.event.toolDescription.map { String($0.prefix(600)) },
                workspace: workspace,
                createdAt: request.createdAt,
                actionToken: action.rawValue,
                actionExpiresAt: action.expiresAt,
                // Classified on the Mac, where the full tool input lives. The
                // phone only ever receives the verdict, never the raw command,
                // which keeps the existing payload-minimisation property.
                risk: CommandRiskClassifier.classify(
                    toolName: request.event.toolName,
                    toolInput: (request.event.toolInput ?? [:]).mapValues { String(describing: $0) }
                )
            )
        }
        let questions = appState.questionQueue.map { request -> RemoteQuestionItem in
            let sessionID = request.event.sessionId ?? "default"
            let workspace = appState.sessions[sessionID]?.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            let source = AppState.sourceLabel(for: request.event)
            let items = request.askUserQuestionState?.items
            let containsSecret = items?.contains(where: { $0.payload.isSecret }) ?? request.question.isSecret

            if containsSecret {
                return RemoteQuestionItem(
                    id: request.id,
                    sessionId: sessionID,
                    source: source,
                    workspace: workspace,
                    createdAt: request.createdAt,
                    prompts: [],
                    requiresLocalResponse: true,
                    actionToken: nil,
                    actionExpiresAt: nil
                )
            }

            let prompts: [RemoteQuestionPrompt]
            if let items, !items.isEmpty {
                prompts = items.map { item in
                    RemoteQuestionPrompt(
                        id: item.answerKey,
                        header: item.payload.header,
                        question: String(item.payload.question.prefix(1_000)),
                        options: Array((item.payload.options ?? []).prefix(20)).map { String($0.prefix(300)) },
                        descriptions: Array((item.payload.descriptions ?? []).prefix(20)).map { String($0.prefix(500)) },
                        allowsMultipleSelection: item.multiSelect
                    )
                }
            } else {
                prompts = [RemoteQuestionPrompt(
                    id: request.question.header ?? "answer",
                    header: request.question.header,
                    question: String(request.question.question.prefix(1_000)),
                    options: Array((request.question.options ?? []).prefix(20)).map { String($0.prefix(300)) },
                    descriptions: Array((request.question.descriptions ?? []).prefix(20)).map { String($0.prefix(500)) },
                    allowsMultipleSelection: false
                )]
            }
            let action = actionTokens.issue(requestID: request.id, deviceID: deviceID, now: now)
            return RemoteQuestionItem(
                id: request.id,
                sessionId: sessionID,
                source: source,
                workspace: workspace,
                createdAt: request.createdAt,
                prompts: prompts,
                requiresLocalResponse: false,
                actionToken: action.rawValue,
                actionExpiresAt: action.expiresAt
            )
        }
        return RemoteApprovalSnapshot(
            serverName: Host.current().localizedName ?? "CodeIsland Mac",
            companionSequence: companionSequence,
            deviceId: deviceID,
            approvals: approvals,
            questions: questions
        )
    }

    func resolve(
        appState: AppState,
        requestID: String,
        actionToken: String,
        deviceID: String,
        deviceName: String,
        decision: RemoteApprovalDecision
    ) -> ResolutionResult {
        switch actionTokens.consume(
            requestID: requestID,
            deviceID: deviceID,
            token: actionToken
        ) {
        case .invalid:
            appendAudit(AuditEvent(
                timestamp: Date(), event: "decision", requestID: requestID,
                sessionID: nil, deviceID: deviceID, deviceName: deviceName,
                decision: decision.rawValue, outcome: "invalid-token", source: nil, tool: nil
            ))
            return .unauthorized
        case .expired:
            appendAudit(AuditEvent(
                timestamp: Date(), event: "decision", requestID: requestID,
                sessionID: nil, deviceID: deviceID, deviceName: deviceName,
                decision: decision.rawValue, outcome: "expired", source: nil, tool: nil
            ))
            return .expired
        case .accepted:
            break
        }
        guard let pending = appState.permissionQueue.first(where: { $0.id == requestID }) else {
            appendAudit(AuditEvent(
                timestamp: Date(), event: "decision", requestID: requestID,
                sessionID: nil, deviceID: deviceID, deviceName: deviceName,
                decision: decision.rawValue, outcome: "stale", source: nil, tool: nil
            ))
            return .stale
        }
        let sessionID = pending.event.sessionId ?? "default"
        let source = AppState.sourceLabel(for: pending.event)
        let tool = pending.event.toolName
        guard appState.resolveRemotePermission(requestID: requestID, decision: decision) else {
            return .stale
        }
        actionTokens.removeAll(forRequestID: requestID)
        appendAudit(AuditEvent(
            timestamp: Date(), event: "decision", requestID: requestID,
            sessionID: sessionID, deviceID: deviceID, deviceName: deviceName,
            decision: decision.rawValue, outcome: "resolved", source: source, tool: tool
        ))
        return .resolved
    }

    func resolveQuestion(
        appState: AppState,
        requestID: String,
        answers: [String],
        actionToken: String,
        deviceID: String,
        deviceName: String
    ) -> ResolutionResult {
        switch actionTokens.consume(
            requestID: requestID,
            deviceID: deviceID,
            token: actionToken
        ) {
        case .invalid:
            appendAudit(AuditEvent(
                timestamp: Date(), event: "question-answer", requestID: requestID,
                sessionID: nil, deviceID: deviceID, deviceName: deviceName,
                decision: nil, outcome: "invalid-token", source: nil, tool: nil
            ))
            return .unauthorized
        case .expired:
            appendAudit(AuditEvent(
                timestamp: Date(), event: "question-answer", requestID: requestID,
                sessionID: nil, deviceID: deviceID, deviceName: deviceName,
                decision: nil, outcome: "expired", source: nil, tool: nil
            ))
            return .expired
        case .accepted:
            break
        }

        guard let pending = appState.questionQueue.first(where: { $0.id == requestID }) else {
            return .stale
        }
        let sessionID = pending.event.sessionId ?? "default"
        let source = AppState.sourceLabel(for: pending.event)
        guard appState.resolveRemoteQuestion(requestID: requestID, answers: answers) else {
            appendAudit(AuditEvent(
                timestamp: Date(), event: "question-answer", requestID: requestID,
                sessionID: sessionID, deviceID: deviceID, deviceName: deviceName,
                decision: nil, outcome: "rejected", source: source, tool: "Question"
            ))
            return .invalid
        }
        actionTokens.removeAll(forRequestID: requestID)
        appendAudit(AuditEvent(
            timestamp: Date(), event: "question-answer", requestID: requestID,
            sessionID: sessionID, deviceID: deviceID, deviceName: deviceName,
            decision: "answer", outcome: "resolved", source: source, tool: "Question"
        ))
        return .resolved
    }

    func recordPairFailure(deviceName: String) {
        appendAudit(AuditEvent(
            timestamp: Date(), event: "pair", requestID: nil, sessionID: nil,
            deviceID: nil, deviceName: String(deviceName.prefix(80)), decision: nil,
            outcome: "invalid-code", source: nil, tool: nil
        ))
    }

    func recordPairSuccess(deviceID: String, deviceName: String) {
        appendAudit(AuditEvent(
            timestamp: Date(), event: "pair", requestID: nil, sessionID: nil,
            deviceID: deviceID, deviceName: String(deviceName.prefix(80)), decision: nil,
            outcome: "paired", source: nil, tool: nil
        ))
    }

    func recordLiveActivityReceipts(
        _ receipts: [RemoteLiveActivityReceipt],
        deviceID: String,
        deviceName: String
    ) {
        for receipt in receipts {
            appendAudit(LiveActivityReceiptAuditEvent(
                timestamp: Date(),
                event: "live-activity-receipt",
                receiptEventID: receipt.eventId,
                requestID: receipt.requestId,
                deviceID: deviceID,
                deviceName: String(deviceName.prefix(80)),
                outcome: "observed",
                source: receipt.source.rawValue,
                attentionKind: receipt.kind?.rawValue,
                attentionState: receipt.state?.rawValue,
                activityState: receipt.activityState?.rawValue,
                observedAt: receipt.observedAt,
                activitiesEnabled: receipt.activitiesEnabled,
                activeActivityCount: receipt.activeActivityCount,
                activeRequestIDs: receipt.activeRequestIds
            ))
        }
    }

    private func appendAudit<Event: Encodable>(_ event: Event) {
        guard var data = try? JSONEncoder.remoteApproval.encode(event) else { return }
        data.append(0x0A)
        let directory = auditURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: auditURL.path) {
            FileManager.default.createFile(atPath: auditURL.path, contents: nil)
        }
        do {
            let handle = try FileHandle(forWritingTo: auditURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: auditURL.path)
        } catch {
            remoteApprovalLog.error("audit append failed: \(error.localizedDescription, privacy: .public)")
        }
    }

}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension JSONEncoder {
    fileprivate static var remoteApproval: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    fileprivate static var remoteApproval: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
