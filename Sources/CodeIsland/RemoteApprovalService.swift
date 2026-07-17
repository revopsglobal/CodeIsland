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

    private weak var appState: AppState?
    private var server: RemoteApprovalHTTPServer?
    private let deviceStore: RemoteApprovalDeviceStore
    private let coordinator: RemoteApprovalCoordinator
    private let personalHub: PersonalHubService
    private let localPortOverride: UInt16?
    private let enabledOverride: Bool?
    private let tailscaleConfigurator: @Sendable (Int, Int) throws -> String
    private var pairAttemptLimiter = RemotePairAttemptLimiter()
    private var lastPendingIDs: Set<String> = []
    private var lastPendingQuestionIDs: Set<String> = []
    private var sleepActivity: NSObjectProtocol?

    init(
        deviceStore: RemoteApprovalDeviceStore? = nil,
        coordinator: RemoteApprovalCoordinator? = nil,
        personalHub: PersonalHubService? = nil,
        localPortOverride: UInt16? = nil,
        enabledOverride: Bool? = nil,
        tailscaleConfigurator: @escaping @Sendable (Int, Int) throws -> String = { localPort, tailscalePort in
            try TailscaleServeManager.configure(localPort: localPort, httpsPort: tailscalePort)
        }
    ) {
        self.deviceStore = deviceStore ?? RemoteApprovalDeviceStore()
        self.coordinator = coordinator ?? RemoteApprovalCoordinator()
        self.personalHub = personalHub ?? .shared
        self.localPortOverride = localPortOverride
        self.enabledOverride = enabledOverride
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
                        self.configureTailscaleServe()
                    case .failure(let error):
                        self.running = false
                        self.lastError = error.localizedDescription
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
        server?.stop()
        server = nil
        running = false
        endSleepActivity()
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
    /// Pushes only newly observed permission IDs and holds a power assertion only
    /// while a decision is actually waiting.
    func stateDidChange() {
        guard let appState else { return }
        let currentIDs = Set(appState.permissionQueue.map(\.id))
        let currentQuestionIDs = Set(appState.questionQueue.map(\.id))
        updateSleepActivity(hasPending: !currentIDs.isEmpty || !currentQuestionIDs.isEmpty)

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

    private func updateSleepActivity(hasPending: Bool) {
        let preventSleep = UserDefaults.standard.object(forKey: SettingsKey.remoteApprovalPreventSleep) == nil
            ? SettingsDefaults.remoteApprovalPreventSleep
            : UserDefaults.standard.bool(forKey: SettingsKey.remoteApprovalPreventSleep)
        if hasPending, preventSleep, sleepActivity == nil {
            sleepActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated],
                reason: "CodeIsland is waiting for a remote approval"
            )
        } else if (!hasPending || !preventSleep), sleepActivity != nil {
            endSleepActivity()
        }
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
            let status = RemoteServiceStatus(
                running: running,
                pendingCount: appState.permissionQueue.count,
                serverName: Host.current().localizedName ?? "CodeIsland Mac"
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
                  registration.token.count >= 32
            else {
                return .json(status: 400, object: ["error": "invalid push token"])
            }
            deviceStore.registerPushToken(registration, deviceID: authenticated.id)
            syncPublishedState()
            return .json(status: 200, object: ["registered": true])
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
            pushEnvironment: nil
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

    func registerPushToken(_ registration: RemotePushRegistrationRequest, deviceID: String) {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return }
        devices[index].pushToken = registration.token.lowercased()
        devices[index].pushEnvironment = registration.environment.lowercased()
        devices[index].lastSeenAt = Date()
        save()
    }

    func revoke(deviceID: String) {
        devices.removeAll { $0.id == deviceID }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder.remoteApproval.decode(PersistedState.self, from: data)
        else { return }
        devices = state.devices
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
                actionExpiresAt: action.expiresAt
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

    private func appendAudit(_ event: AuditEvent) {
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
