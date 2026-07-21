import Combine
import Foundation
import Security
import UIKit

enum RemoteTaskDeepLinkDestination: Equatable, Sendable {
    case detail(UUID)
    case composer(text: String?, provider: RemoteTaskProvider?)
    case needsYou
    case sessions

    init?(route: PersonalHubDeepLink) {
        switch route {
        case .task(let id):
            self = .detail(id)
        case .newTask(let text, let provider):
            self = .composer(text: text, provider: provider)
        case .needsYou:
            self = .needsYou
        case .sessions:
            self = .sessions
        case .pendingApproval, .pendingQuestion, .module, .quickJot:
            return nil
        }
    }
}

@MainActor
final class RemoteApprovalClient: ObservableObject {
    enum ConnectionState: Equatable {
        case unpaired
        case connecting
        case connected
        case offline(String)

        var label: String {
            switch self {
            case .unpaired: return "Pairing required"
            case .connecting: return "Connecting"
            case .connected: return "Connected"
            case .offline: return "Mac offline"
            }
        }
    }

    @Published private(set) var approvals: [RemoteApprovalItem] = []
    @Published private(set) var questions: [RemoteQuestionItem] = []
    @Published private(set) var state: ConnectionState = .unpaired
    @Published private(set) var serverName: String?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var busyRequestIDs: Set<String> = []
    @Published private(set) var highlightedApprovalID: String?
    @Published private(set) var highlightedQuestionID: String?
    @Published private(set) var highlightedHubModuleID: PersonalHubModuleID?
    @Published private(set) var hubSnapshot: PersonalHubSnapshot?
    @Published private(set) var sessionsModule: PersonalHubModuleSnapshot?
    @Published private(set) var sessionsError: String?
    private var calendarReferenceDate: Date?
    private var calendarSelectedDate: Date?
    @Published private(set) var hubError: String?
    @Published private(set) var hubActionInFlight = false
    @Published private(set) var hubActionMessage: String?
    @Published var preparedAction: PersonalHubPreparedAction?
    @Published var quickJotDestination: BuddyQuickJotDestination?
    @Published var quickJotSeedText: String?
    @Published private(set) var remoteTaskDeepLinkDestination: RemoteTaskDeepLinkDestination?
    @Published private(set) var remoteTasks: [RemoteTaskSummary] = []
    @Published private(set) var remoteTaskWorkspaces: [RemoteWorkspaceSummary] = []
    @Published private(set) var remoteTaskDrafts: [RemoteTaskDraft] = []
    @Published private(set) var remoteTaskError: String?
    @Published var selectedMode: PersonalHubMode {
        didSet {
            UserDefaults.standard.set(selectedMode.rawValue, forKey: Self.selectedModeKey)
#if DEBUG
            if usesMockHub {
                hubSnapshot = Self.mockHubSnapshot(requestedMode: selectedMode)
                return
            }
#endif
            Task { await refreshHub() }
        }
    }
    @Published var serverURLText: String

    private static let defaultServerURL = "https://gregs-macbook-air.tail62f27c.ts.net:9443"
    private static let serverURLKey = "codeisland.remote.serverURL.v1"
    private static let tokenService = "com.revopsglobal.codeisland.buddy.remote"
    private static let tokenAccount = "device-token"
    private static let pendingPushTokenKey = "codeisland.remote.pendingPushToken"
    private static let pendingApprovalIDKey = "codeisland.remote.pendingApprovalID"
    private static let pendingQuestionIDKey = "codeisland.remote.pendingQuestionID"
    private static let selectedModeKey = "codeisland.hub.selectedMode.v1"
    static let invalidServerURLMessage = "Check the Mac connection URL in Connection settings"

    private let usesMockHub: Bool
    private let usesMockPairing: Bool
    private var deviceToken: String?
    private var pollTask: Task<Void, Never>?
    private var isActive = true
    private var clientMetadataRegisteredThisLaunch = false
    private var consecutiveApprovalRefreshFailures = 0
    private var notificationObservers: [NSObjectProtocol] = []
    private var pendingGenericDeepLink: RemoteAttentionKind?
    private let remoteTaskClient = RemoteTaskClient()
    private var remoteTaskCancellables: Set<AnyCancellable> = []
    var onSnapshotReceived: ((RemoteApprovalSnapshot) -> Void)?
    var onRemoteTasksReceived: (([RemoteTaskSummary]) -> Void)?

    var hasPairingCredential: Bool {
        deviceToken != nil
    }

    /// A foreground poll should only present the blocking connection state
    /// before the first authenticated snapshot. Once content has loaded, keep
    /// that stable presentation in place while subsequent polls run.
    nonisolated static func refreshStartState(hasCompletedSnapshot: Bool) -> ConnectionState? {
        hasCompletedSnapshot ? nil : .connecting
    }

    nonisolated static func refreshFailureState(
        hasCompletedSnapshot: Bool,
        consecutiveFailures: Int,
        message: String
    ) -> ConnectionState? {
        guard hasCompletedSnapshot else { return .offline(message) }
        return consecutiveFailures >= 3 ? .offline(message) : nil
    }

    nonisolated static func genericPendingDeepLinkTarget(
        kind: RemoteAttentionKind,
        approvalIDs: [String],
        questionIDs: [String]
    ) -> String? {
        switch kind {
        case .approval:
            return approvalIDs.first
        case .question:
            return questionIDs.first
        case .task:
            return nil
        }
    }

    init() {
        remoteTaskDrafts = remoteTaskClient.localDrafts
#if DEBUG
        usesMockHub = ProcessInfo.processInfo.arguments.contains("-CodeIslandCompanionMockHub")
        usesMockPairing = ProcessInfo.processInfo.arguments.contains("-CodeIslandCompanionMockPairing")
        let launchMode = Self.mockHubModeFromLaunchArguments()
        let mockAttention = Self.mockAttentionFromLaunchArguments()
#else
        usesMockHub = false
        usesMockPairing = false
        let launchMode: PersonalHubMode? = nil
#endif
        serverURLText = UserDefaults.standard.string(forKey: Self.serverURLKey) ?? Self.defaultServerURL
        selectedMode = launchMode ?? PersonalHubMode(
            rawValue: UserDefaults.standard.string(forKey: Self.selectedModeKey) ?? ""
        ) ?? (CompanionFirst.isEnabled ? .code : .auto)
        bindRemoteTaskClient()

#if DEBUG
        if usesMockPairing {
            deviceToken = nil
            state = .unpaired
            return
        }
        if usesMockHub {
            deviceToken = "ui-test-device-token"
            state = .connected
            serverName = "Code Island UI Test Mac"
            lastUpdatedAt = Date()
            hubSnapshot = Self.mockHubSnapshot(requestedMode: selectedMode).companionFiltered
            sessionsModule = Self.mockHubModule(.agents)
            approvals = mockAttention.approvals
            questions = mockAttention.questions
            let remoteTaskFixture = Self.mockRemoteTasksFromLaunchArguments()
            remoteTaskWorkspaces = remoteTaskFixture.workspaces
            remoteTasks = remoteTaskFixture.tasks
            if let url = Self.mockDeepLinkFromLaunchArguments() {
                openDeepLink(url)
            }
            return
        }
#endif

        deviceToken = Self.readKeychainToken()
        state = deviceToken == nil ? .unpaired : .connecting

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .codeIslandPushTokenAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.registerPendingPushToken() }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .codeIslandLiveActivityTokenAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.registerPendingPushToken() }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .codeIslandLiveActivityReceiptAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.registerPendingPushToken() }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .codeIslandRemoteAttentionChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                let requestID = notification.userInfo?["requestId"] as? String
                let kind = (notification.userInfo?["kind"] as? String).flatMap(RemoteAttentionKind.init(rawValue:))
                let attentionState = (notification.userInfo?["state"] as? String).flatMap(RemoteAttentionState.init(rawValue:))
                if attentionState == .pending, kind == .approval {
                    self.highlightedApprovalID = requestID
                } else if attentionState == .pending, kind == .question {
                    self.highlightedQuestionID = requestID
                } else if kind == .approval, self.highlightedApprovalID == requestID {
                    self.highlightedApprovalID = nil
                } else if kind == .question, self.highlightedQuestionID == requestID {
                    self.highlightedQuestionID = nil
                } else if kind == .task, let requestID, let id = UUID(uuidString: requestID) {
                    self.remoteTaskDeepLinkDestination = .detail(id)
                }
                await self.refresh()
            }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .codeIslandIntentRouteAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.consumePendingIntentRoute() }
        })
    }

    deinit {
        pollTask?.cancel()
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
        consumePendingIntentRoute()
#if DEBUG
        if usesMockPairing {
            state = .unpaired
            return
        }
        if usesMockHub {
            state = .connected
            hubSnapshot = Self.mockHubSnapshot(requestedMode: selectedMode)
            return
        }
#endif
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.isActive, self.deviceToken != nil {
                    await self.refresh()
                }
                try? await Task.sleep(for: .seconds(4))
            }
        }
        Task {
            if let pendingID = UserDefaults.standard.string(forKey: Self.pendingApprovalIDKey) {
                highlightedApprovalID = pendingID
                UserDefaults.standard.removeObject(forKey: Self.pendingApprovalIDKey)
            }
            if let pendingID = UserDefaults.standard.string(forKey: Self.pendingQuestionIDKey) {
                highlightedQuestionID = pendingID
                UserDefaults.standard.removeObject(forKey: Self.pendingQuestionIDKey)
            }
            await refresh()
            await registerPendingPushToken()
        }
    }

    func setActive(_ active: Bool) {
#if DEBUG
        if usesMockHub { return }
#endif
        isActive = active
        if active {
            consumePendingIntentRoute()
            remoteTaskClient.resetForActivation()
            Task { await refresh() }
        }
    }

    @discardableResult
    func pair(code: String, deviceName: String? = nil) async -> Bool {
        let trimmedCode = code.filter(\.isNumber)
        guard trimmedCode.count == 6 else {
            state = .offline("Enter the six-digit code from the Mac")
            return false
        }
        guard let requestURL = endpoint("/api/pair") else {
            state = .offline(Self.invalidServerURLMessage)
            return false
        }
        state = .connecting
#if DEBUG
        if usesMockPairing {
            state = .offline(Self.expiredPairingCodeMessage)
            return false
        }
#endif
        do {
            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(
                RemotePairRequest(code: trimmedCode, deviceName: deviceName ?? UIDevice.current.name)
            )
            let response: RemotePairResponse = try await perform(request, authenticated: false)
            try Self.saveKeychainToken(response.deviceToken)
            deviceToken = response.deviceToken
            serverName = response.serverName
            consecutiveApprovalRefreshFailures = 0
            UserDefaults.standard.set(normalizedServerURL?.absoluteString, forKey: Self.serverURLKey)
            state = .connected
            await registerPendingPushToken()
            await refresh()
            return true
        } catch {
            let message = error.localizedDescription
            state = .offline(
                message == "pairing code is invalid or expired"
                    ? Self.expiredPairingCodeMessage
                    : message
            )
            return false
        }
    }

    private static let expiredPairingCodeMessage =
        "That code expired. Open Code Island Settings → Buddy on your Mac for the current code."

    func unpair() {
        Self.deleteKeychainToken()
        deviceToken = nil
        remoteTaskClient.clearConnection()
        approvals = []
        questions = []
        serverName = nil
        hubSnapshot = nil
        sessionsModule = nil
        sessionsError = nil
        hubError = nil
        preparedAction = nil
        consecutiveApprovalRefreshFailures = 0
        remoteTasks = []
        remoteTaskDrafts = remoteTaskClient.localDrafts
        state = .unpaired
    }

    private func bindRemoteTaskClient() {
        remoteTaskClient.$tasks
            .sink { [weak self] tasks in
                self?.remoteTasks = tasks
                self?.onRemoteTasksReceived?(tasks)
            }
            .store(in: &remoteTaskCancellables)
        remoteTaskClient.$localDrafts
            .sink { [weak self] in self?.remoteTaskDrafts = $0 }
            .store(in: &remoteTaskCancellables)
        remoteTaskClient.$workspaces
            .sink { [weak self] in self?.remoteTaskWorkspaces = $0 }
            .store(in: &remoteTaskCancellables)
        remoteTaskClient.$lastError
            .sink { [weak self] in self?.remoteTaskError = $0 }
            .store(in: &remoteTaskCancellables)
    }

    func resolve(_ approval: RemoteApprovalItem, decision: RemoteApprovalDecision) async {
        guard !busyRequestIDs.contains(approval.id),
              let url = endpoint("/api/approvals/\(approval.id)/decision")
        else { return }
        busyRequestIDs.insert(approval.id)
        defer { busyRequestIDs.remove(approval.id) }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(
                RemoteDecisionRequest(decision: decision, actionToken: approval.actionToken)
            )
            let _: RemoteDecisionResponse = try await perform(request, authenticated: true)
            highlightedApprovalID = nil
            await refresh()
        } catch {
            state = .offline(error.localizedDescription)
            await refresh()
        }
    }

    func answer(_ question: RemoteQuestionItem, answers: [String]) async {
        guard !busyRequestIDs.contains(question.id),
              let actionToken = question.actionToken,
              let url = endpoint("/api/questions/\(question.id)/answer")
        else { return }
        busyRequestIDs.insert(question.id)
        defer { busyRequestIDs.remove(question.id) }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(
                RemoteQuestionAnswerRequest(answers: answers, actionToken: actionToken)
            )
            let _: RemoteQuestionAnswerResponse = try await perform(request, authenticated: true)
            highlightedQuestionID = nil
            await refresh()
        } catch {
            state = .offline(error.localizedDescription)
            await refresh()
        }
    }

    func refresh() async {
#if DEBUG
        if usesMockHub {
            state = .connected
            lastUpdatedAt = Date()
            hubSnapshot = Self.mockHubSnapshot(requestedMode: selectedMode)
            return
        }
#endif
        guard deviceToken != nil else {
            state = .unpaired
            approvals = []
            questions = []
            consecutiveApprovalRefreshFailures = 0
            return
        }
        guard let url = endpoint("/api/approvals") else {
            state = .offline(Self.invalidServerURLMessage)
            return
        }
        if let refreshStartState = Self.refreshStartState(
            hasCompletedSnapshot: lastUpdatedAt != nil
        ) {
            state = refreshStartState
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let snapshot: RemoteApprovalSnapshot = try await perform(request, authenticated: true)
            consecutiveApprovalRefreshFailures = 0
            approvals = snapshot.approvals
            questions = snapshot.questions
            consumePendingGenericDeepLink()
            if let highlightedApprovalID,
               !approvals.contains(where: { $0.id == highlightedApprovalID }) {
                self.highlightedApprovalID = nil
            }
            if let highlightedQuestionID,
               !questions.contains(where: { $0.id == highlightedQuestionID }) {
                self.highlightedQuestionID = nil
            }
            serverName = snapshot.serverName
            lastUpdatedAt = Date()
            state = .connected
            onSnapshotReceived?(snapshot)
            await refreshHub()
            await refreshRemoteTasks()
        } catch RemoteClientError.unauthorized {
            unpair()
        } catch {
            consecutiveApprovalRefreshFailures += 1
            if let failureState = Self.refreshFailureState(
                hasCompletedSnapshot: lastUpdatedAt != nil,
                consecutiveFailures: consecutiveApprovalRefreshFailures,
                message: error.localizedDescription
            ) {
                state = failureState
            }
        }
    }

    @discardableResult
    func enqueueRemoteTask(_ input: RemoteTaskDraftInput) async throws -> RemoteTaskDraft {
        let draft = try remoteTaskClient.enqueue(input)
        remoteTaskDrafts = remoteTaskClient.localDrafts
        await refreshRemoteTasks(force: true)
        return draft
    }

    func refreshRemoteTasks(force: Bool = false) async {
#if DEBUG
        if usesMockHub { return }
#endif
        guard let deviceToken, let baseURL = normalizedServerURL else {
            remoteTaskDrafts = remoteTaskClient.localDrafts
            return
        }
        let result = await remoteTaskClient.sync(
            baseURL: baseURL,
            bearerToken: deviceToken,
            force: force
        )
        remoteTasks = remoteTaskClient.tasks
        remoteTaskDrafts = remoteTaskClient.localDrafts
        remoteTaskError = remoteTaskClient.lastError
        if remoteTaskClient.workspaces.isEmpty {
            _ = await remoteTaskClient.refreshWorkspaces(baseURL: baseURL, bearerToken: deviceToken)
        }
        switch result {
        case .pairingRequired:
            unpair()
        case .offline:
            if lastUpdatedAt == nil {
                state = .offline(remoteTaskClient.lastError ?? "Mac offline")
            }
        case .success, .conflict, .deferred:
            break
        }
    }

    func followUpRemoteTask(taskID: UUID, text: String) async {
        guard let deviceToken, let baseURL = normalizedServerURL else { return }
        let result = await remoteTaskClient.followUp(
            taskID: taskID,
            text: text,
            baseURL: baseURL,
            bearerToken: deviceToken
        )
        if result == .pairingRequired { unpair() }
    }

    func cancelRemoteTask(taskID: UUID) async {
        guard let deviceToken, let baseURL = normalizedServerURL else { return }
        let result = await remoteTaskClient.cancel(
            taskID: taskID,
            baseURL: baseURL,
            bearerToken: deviceToken
        )
        if result == .pairingRequired { unpair() }
    }

    func consumeRemoteTaskDeepLinkDestination() {
        remoteTaskDeepLinkDestination = nil
    }

    func refreshHub() async {
#if DEBUG
        if usesMockHub {
            hubSnapshot = Self.mockHubSnapshot(
                requestedMode: selectedMode,
                calendarReferenceDate: calendarReferenceDate,
                calendarSelectedDate: calendarSelectedDate
            )
            hubError = nil
            return
        }
#endif
        guard deviceToken != nil else {
            hubSnapshot = nil
            return
        }
        guard let url = endpoint("/api/hub/snapshot") else {
            hubError = Self.invalidServerURLMessage
            return
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(
                PersonalHubSnapshotRequest(
                    requestedMode: selectedMode,
                    calendarReferenceDate: calendarReferenceDate,
                    calendarSelectedDate: calendarSelectedDate
                )
            )
            let snapshot: PersonalHubSnapshot = try await perform(request, authenticated: true)
            hubSnapshot = snapshot.companionFiltered
            hubError = nil
        } catch RemoteClientError.unauthorized {
            unpair()
        } catch {
            hubError = error.localizedDescription
        }
    }

    /// The Sessions destination is transport-independent. Fetch the Code rack's
    /// agent snapshot directly so choosing Home or Work never falls back to the
    /// nearby Bluetooth discovery UI while Tailscale is authenticated.
    func refreshSessions() async {
#if DEBUG
        if usesMockHub {
            sessionsModule = Self.mockHubModule(.agents)
            sessionsError = nil
            return
        }
#endif
        guard deviceToken != nil else {
            sessionsModule = nil
            return
        }
        guard let url = endpoint("/api/hub/snapshot") else {
            sessionsError = Self.invalidServerURLMessage
            return
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(
                PersonalHubSnapshotRequest(requestedMode: .code)
            )
            let snapshot: PersonalHubSnapshot = try await perform(request, authenticated: true)
            sessionsModule = snapshot.modules.first(where: { $0.id == .agents })
            sessionsError = sessionsModule == nil ? "The Mac did not return session status" : nil
        } catch RemoteClientError.unauthorized {
            unpair()
        } catch {
            sessionsError = error.localizedDescription
        }
    }

    func refreshCalendar(referenceDate: Date, selectedDate: Date) async {
        calendarReferenceDate = referenceDate
        calendarSelectedDate = selectedDate
        await refreshHub()
    }

    func prepareHubAction(_ intent: PersonalHubActionIntent) async {
#if DEBUG
        if usesMockHub {
            preparedAction = PersonalHubPreparedAction(
                intent: intent,
                preview: Self.mockHubPreview(for: intent),
                actionToken: "ui-test-action-token",
                actionExpiresAt: Date().addingTimeInterval(120)
            )
            hubActionMessage = nil
            return
        }
#endif
        guard !hubActionInFlight,
              let url = endpoint("/api/hub/actions/prepare")
        else { return }
        hubActionInFlight = true
        defer { hubActionInFlight = false }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(
                PersonalHubPrepareActionRequest(intent: intent)
            )
            preparedAction = try await perform(request, authenticated: true)
            hubActionMessage = nil
        } catch RemoteClientError.unauthorized {
            unpair()
        } catch {
            hubActionMessage = error.localizedDescription
        }
    }

    func reportHubClientAction(_ message: String) {
        hubActionMessage = message
    }

    func dismissHubActionMessage() {
        hubActionMessage = nil
    }

    func openDeepLink(_ url: URL) {
        guard let route = PersonalHubDeepLink(url: url) else { return }
        switch route {
        case .pendingApproval(let id):
            if let id {
                pendingGenericDeepLink = nil
                highlightedApprovalID = id
            } else if let firstID = approvals.first?.id {
                pendingGenericDeepLink = nil
                highlightedApprovalID = firstID
            } else {
                pendingGenericDeepLink = .approval
                highlightedApprovalID = nil
            }
            Task { await refresh() }
        case .pendingQuestion(let id):
            if let id {
                pendingGenericDeepLink = nil
                highlightedQuestionID = id
            } else if let firstID = questions.first?.id {
                pendingGenericDeepLink = nil
                highlightedQuestionID = firstID
            } else {
                pendingGenericDeepLink = .question
                highlightedQuestionID = nil
            }
            Task { await refresh() }
        case .module(let module):
            pendingGenericDeepLink = nil
            highlightedHubModuleID = module
            selectedMode = PersonalHubCatalog.preferredMode(for: module)
        case .quickJot(let destination, let text):
            pendingGenericDeepLink = nil
            quickJotSeedText = text
            quickJotDestination = BuddyQuickJotDestination(rawValue: destination.rawValue)
        case .task, .newTask, .needsYou, .sessions:
            pendingGenericDeepLink = nil
            remoteTaskDeepLinkDestination = RemoteTaskDeepLinkDestination(route: route)
        }
    }

    private func consumePendingGenericDeepLink() {
        guard let pendingGenericDeepLink else { return }
        switch pendingGenericDeepLink {
        case .approval:
            highlightedApprovalID = Self.genericPendingDeepLinkTarget(
                kind: .approval,
                approvalIDs: approvals.map(\.id),
                questionIDs: questions.map(\.id)
            )
        case .question:
            highlightedQuestionID = Self.genericPendingDeepLinkTarget(
                kind: .question,
                approvalIDs: approvals.map(\.id),
                questionIDs: questions.map(\.id)
            )
        case .task:
            break
        }
        self.pendingGenericDeepLink = nil
    }

    var connectionDetail: String {
        Self.connectionDetail(serverName: serverName)
    }

    nonisolated static func connectionDetail(serverName: String?) -> String {
        guard let serverName = serverName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serverName.isEmpty
        else {
            return "Connected to Greg's Mac"
        }
        return "Connected to \(serverName)"
    }

    func clearQuickJotSeed() {
        quickJotSeedText = nil
    }

    private func consumePendingIntentRoute() {
        guard let raw = UserDefaults.standard.string(forKey: CodeIslandIntentBridge.pendingRouteKey),
              let url = URL(string: raw)
        else { return }
        UserDefaults.standard.removeObject(forKey: CodeIslandIntentBridge.pendingRouteKey)
        openDeepLink(url)
    }

    func downloadHubFile(moduleID: PersonalHubModuleID, id: String, filename: String) async -> URL? {
#if DEBUG
        if usesMockHub {
            do {
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                let fileURL = destination.appendingPathComponent(filename.isEmpty ? "CodeIsland-file" : filename)
                try Data("CodeIsland simulator file transfer".utf8).write(to: fileURL, options: [.atomic])
                hubActionMessage = "Downloaded \(fileURL.lastPathComponent)"
                return fileURL
            } catch {
                hubActionMessage = error.localizedDescription
                return nil
            }
        }
#endif
        var pathAllowed = CharacterSet.urlPathAllowed
        pathAllowed.remove(charactersIn: "/")
        guard let encodedID = id.addingPercentEncoding(withAllowedCharacters: pathAllowed) else { return nil }
        let route = moduleID == .downloads ? "downloads" : "shelf"
        guard let url = endpoint("/api/hub/\(route)/\(encodedID)/file"), let deviceToken else { return nil }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 45
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw RemoteClientError.server("Mac could not transfer the file")
            }
            let safeName = filename.replacingOccurrences(of: "/", with: "-")
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let fileURL = destination.appendingPathComponent(safeName.isEmpty ? "CodeIsland-file" : safeName)
            try data.write(to: fileURL, options: [.atomic])
            hubActionMessage = "Downloaded \(fileURL.lastPathComponent)"
            return fileURL
        } catch {
            hubActionMessage = error.localizedDescription
            return nil
        }
    }

    func executeHubAction(_ prepared: PersonalHubPreparedAction) async {
#if DEBUG
        if usesMockHub {
            preparedAction = nil
            hubActionMessage = "Executed \(prepared.intent.moduleID.rawValue).\(prepared.intent.actionID)"
            hubSnapshot = Self.mockHubSnapshot(requestedMode: selectedMode)
            return
        }
#endif
        guard !hubActionInFlight,
              let url = endpoint("/api/hub/actions/execute")
        else { return }
        hubActionInFlight = true
        defer { hubActionInFlight = false }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(
                PersonalHubExecuteActionRequest(
                    intent: prepared.intent,
                    actionToken: prepared.actionToken
                )
            )
            let response: PersonalHubActionResponse = try await perform(request, authenticated: true)
            preparedAction = nil
            hubActionMessage = response.message
            await refreshHub()
        } catch RemoteClientError.unauthorized {
            unpair()
        } catch {
            preparedAction = nil
            hubActionMessage = error.localizedDescription
            await refreshHub()
        }
    }

    private func registerPendingPushToken() async {
#if DEBUG
        if usesMockHub { return }
#endif
        guard deviceToken != nil, let url = endpoint("/api/push-token") else { return }
        let pushToken = UserDefaults.standard.string(forKey: Self.pendingPushTokenKey)
        let pushToStartToken = UserDefaults.standard.string(
            forKey: LiveActivityTokenMailbox.pushToStartTokenKey
        )
        let updateTokens = UserDefaults.standard.dictionary(
            forKey: LiveActivityTokenMailbox.updateTokensKey
        ) as? [String: String]
        let receipts = LiveActivityTokenMailbox.pendingReceipts()
        let clientVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let clientBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let shouldRegisterClientMetadata = !clientMetadataRegisteredThisLaunch
            && clientVersion?.isEmpty == false
            && clientBuild?.isEmpty == false
        guard pushToken != nil || pushToStartToken != nil || updateTokens?.isEmpty == false
                || !receipts.isEmpty || shouldRegisterClientMetadata
        else { return }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
#if DEBUG
            let environment = "development"
#else
            let environment = "production"
#endif
            request.httpBody = try Self.encoder.encode(
                RemotePushRegistrationRequest(
                    token: pushToken,
                    environment: environment,
                    liveActivityPushToStartToken: pushToStartToken,
                    liveActivityUpdateTokens: updateTokens,
                    liveActivityReceipts: Array(receipts.prefix(16)),
                    clientVersion: clientVersion,
                    clientBuild: clientBuild
                )
            )
            let _: RegistrationResponse = try await perform(request, authenticated: true)
            if clientVersion?.isEmpty == false, clientBuild?.isEmpty == false {
                clientMetadataRegisteredThisLaunch = true
            }
            if UserDefaults.standard.string(forKey: Self.pendingPushTokenKey) == pushToken {
                UserDefaults.standard.removeObject(forKey: Self.pendingPushTokenKey)
            }
            if UserDefaults.standard.string(forKey: LiveActivityTokenMailbox.pushToStartTokenKey) == pushToStartToken {
                UserDefaults.standard.removeObject(forKey: LiveActivityTokenMailbox.pushToStartTokenKey)
            }
            if let updateTokens,
               UserDefaults.standard.dictionary(forKey: LiveActivityTokenMailbox.updateTokensKey) as? [String: String] == updateTokens {
                UserDefaults.standard.removeObject(forKey: LiveActivityTokenMailbox.updateTokensKey)
            }
            LiveActivityTokenMailbox.clearReceipts(
                eventIDs: Set(receipts.prefix(16).map(\.eventId))
            )
            let remainingReceipts = LiveActivityTokenMailbox.pendingReceipts()
            if !remainingReceipts.isEmpty, remainingReceipts.count < receipts.count {
                await registerPendingPushToken()
            }
        } catch {
            // Keep the token queued; foreground polling still works and registration
            // retries on the next launch / APNs callback.
        }
    }

    private var normalizedServerURL: URL? {
        var raw = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "https://\(raw)" }
        guard var components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false
        else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func endpoint(_ path: String) -> URL? {
        guard let base = normalizedServerURL else { return nil }
        let components = path.split(separator: "/").map(String.init)
        return components.reduce(base) { partial, component in
            partial.appendingPathComponent(component)
        }
    }

    private func perform<T: Decodable>(_ request: URLRequest, authenticated: Bool) async throws -> T {
        var request = request
        request.timeoutInterval = 12
        if authenticated {
            guard let deviceToken else { throw RemoteClientError.unauthorized }
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RemoteClientError.invalidResponse }
        if http.statusCode == 401 { throw RemoteClientError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? Self.decoder.decode(ErrorResponse.self, from: data)
            throw RemoteClientError.server(error?.error ?? "Mac returned HTTP \(http.statusCode)")
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    private enum RemoteClientError: LocalizedError {
        case unauthorized
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Pairing expired"
            case .invalidResponse: return "Mac returned an invalid response"
            case .server(let message): return message
            }
        }
    }

    private struct ErrorResponse: Decodable { let error: String }
    private struct RegistrationResponse: Decodable { let registered: Bool }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

#if DEBUG
    private static func mockDeepLinkFromLaunchArguments() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-CodeIslandCompanionMockDeepLink"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return URL(string: arguments[index + 1])
    }

    private static func mockHubModeFromLaunchArguments() -> PersonalHubMode? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-CodeIslandCompanionMockHubMode"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return PersonalHubMode(rawValue: arguments[index + 1].lowercased())
    }

    private static func mockAttentionFromLaunchArguments() -> (
        approvals: [RemoteApprovalItem],
        questions: [RemoteQuestionItem]
    ) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-CodeIslandCompanionMockAttention"),
              arguments.indices.contains(index + 1)
        else { return ([], []) }

        let now = Date()
        let approval = RemoteApprovalItem(
            id: "approval-a",
            sessionId: "codex-release-session",
            source: "Codex",
            tool: "Run release build",
            detail: "xcodebuild -scheme CodeIslandCompanion archive",
            workspace: "CodeIsland",
            createdAt: now.addingTimeInterval(-90),
            actionToken: "ui-test-approval-token",
            actionExpiresAt: now.addingTimeInterval(600)
        )
        let question = RemoteQuestionItem(
            id: "question-b",
            sessionId: "codex-release-session",
            source: "Codex",
            workspace: "CodeIsland",
            createdAt: now.addingTimeInterval(-60),
            prompts: [
                RemoteQuestionPrompt(
                    id: "ship-timing",
                    header: "Release",
                    question: "Ship the signed build tonight?",
                    options: ["Ship tonight", "Hold for review"],
                    descriptions: [
                        "Archive, upload, and keep the release internal.",
                        "Leave the current TestFlight build in place."
                    ],
                    allowsMultipleSelection: false
                )
            ],
            requiresLocalResponse: false,
            actionToken: "ui-test-question-token",
            actionExpiresAt: now.addingTimeInterval(600)
        )

        switch arguments[index + 1].lowercased() {
        case "approval": return ([approval], [])
        case "question": return ([], [question])
        case "multiple": return ([approval], [question])
        default: return ([], [])
        }
    }

    private static func mockRemoteTasksFromLaunchArguments() -> (
        workspaces: [RemoteWorkspaceSummary],
        tasks: [RemoteTaskSummary]
    ) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-CodeIslandCompanionMockRemoteTasks"),
              arguments.indices.contains(index + 1)
        else { return ([], []) }

        let workspace = RemoteWorkspaceSummary(id: "ui-test-codeisland", name: "CodeIsland")
        let now = Date()
        func task(_ id: String, state: RemoteTaskState, title: String, summary: String) -> RemoteTaskSummary {
            let uuid = UUID(uuidString: id)!
            return RemoteTaskSummary(
                id: uuid,
                clientTaskID: uuid,
                idempotencyKey: UUID(),
                title: title,
                workspaceID: workspace.id,
                workspaceName: workspace.name,
                provider: .codex,
                authority: .editAndTest,
                state: state,
                createdAt: now.addingTimeInterval(-600),
                updatedAt: now,
                lastReceiptSequence: 2,
                latestSummary: summary
            )
        }

        switch arguments[index + 1].lowercased() {
        case "needs-you":
            return ([workspace], [task(
                "20000000-0000-0000-0000-000000000001",
                state: .needsYou,
                title: "Finish Buddy end-to-end testing",
                summary: "Choose whether to upload the internal build"
            )])
        case "failed":
            return ([workspace], [task(
                "20000000-0000-0000-0000-000000000004",
                state: .failed,
                title: "Recover the interrupted build",
                summary: "Codex app-server failed"
            )])
        case "portfolio":
            return ([workspace], [
                task("20000000-0000-0000-0000-000000000001", state: .needsYou, title: "Finish Buddy end-to-end testing", summary: "Choose whether to upload the internal build"),
                task("20000000-0000-0000-0000-000000000002", state: .working, title: "Polish the Mac task portfolio", summary: "Running focused UI checks"),
                task("20000000-0000-0000-0000-000000000003", state: .verified, title: "Keep notch text in English", summary: "English-boundary checks passed"),
            ])
        default:
            return ([workspace], [task(
                "20000000-0000-0000-0000-000000000002",
                state: .working,
                title: "Polish the Mac task portfolio",
                summary: "Running focused UI checks"
            )])
        }
    }

    private static func mockHubSnapshot(
        requestedMode: PersonalHubMode,
        calendarReferenceDate: Date? = nil,
        calendarSelectedDate: Date? = nil
    ) -> PersonalHubSnapshot {
        let resolvedMode: PersonalHubMode = requestedMode == .auto ? .home : requestedMode
        return PersonalHubSnapshot(
            serverName: "Code Island UI Test Mac",
            requestedMode: requestedMode,
            resolvedMode: resolvedMode,
            modules: PersonalHubCatalog.modules(for: resolvedMode).map {
                mockHubModule(
                    $0,
                    calendarReferenceDate: calendarReferenceDate,
                    calendarSelectedDate: calendarSelectedDate
                )
            },
            configuration: .default,
            dayProgress: 0.5
        )
    }

    static func mockHubParityViolations(
        requestedMode: PersonalHubMode,
        calendarReferenceDate: Date? = nil,
        calendarSelectedDate: Date? = nil
    ) -> [PersonalHubBuddyParityViolation] {
        PersonalHubBuddyParity.validate(snapshot: mockHubSnapshot(
            requestedMode: requestedMode,
            calendarReferenceDate: calendarReferenceDate,
            calendarSelectedDate: calendarSelectedDate
        ))
    }

    private static func mockHubModule(
        _ id: PersonalHubModuleID,
        calendarReferenceDate: Date? = nil,
        calendarSelectedDate: Date? = nil
    ) -> PersonalHubModuleSnapshot {
        let ready = PersonalHubAvailability.ready
        switch id {
        case .nowPlaying:
            return .init(
                id: id,
                availability: ready,
                summary: "North Star — Demo Artist",
                detail: "1:42 / 4:06 · Apple Music",
                items: [
                    .init(
                        id: "current",
                        title: "North Star",
                        subtitle: "Demo Artist",
                        progress: 102.0 / 246.0,
                        mediaPosition: 102,
                        mediaDuration: 246
                    ),
                    .init(
                        id: "queue:1",
                        title: "Next: Signal Fire",
                        subtitle: "Demo Artist",
                        actions: [.init(id: "playQueueItem", label: "Play now", targetID: "1")]
                    )
                ],
                actions: [
                    .init(id: "previous", label: "Previous", symbol: "backward.fill"),
                    .init(id: "seekBack", label: "-15", symbol: "gobackward.15"),
                    .init(id: "playPause", label: "Pause", symbol: "pause.fill"),
                    .init(id: "seekForward", label: "+15", symbol: "goforward.15"),
                    .init(id: "next", label: "Next", symbol: "forward.fill"),
                ]
            )
        case .shelf:
            return .init(
                id: id,
                availability: ready,
                summary: "2 recent items",
                items: [
                    .init(
                        id: "shelf:launch-reel",
                        title: "launch-reel.mp4",
                        subtitle: "12.4 MB",
                        actions: [
                            .init(
                                id: "downloadToDevice",
                                label: "Download",
                                role: .primary,
                                targetID: "shelf:launch-reel"
                            ),
                            .init(id: "remove", label: "Remove", role: .destructive, targetID: "shelf:launch-reel"),
                        ]
                    )
                ]
            )
        case .calendar:
            let start = Date().addingTimeInterval(3_600)
            let draft = PersonalHubCalendarDraft(
                title: "Design review",
                start: start,
                end: start.addingTimeInterval(1_800),
                joinURL: URL(string: "https://meet.google.com/test-room")
            )
            let eventItem = PersonalHubItem(
                id: "event:design-review",
                title: "Design review",
                subtitle: "Today at 2:00 PM",
                date: start,
                actions: [
                    .init(id: "join", label: "Join", deepLink: draft.joinURL),
                    .init(id: "edit", label: "Edit", targetID: "event:design-review", value: draft.encodedActionValue()),
                    .init(id: "delete", label: "Delete", role: .destructive, targetID: "event:design-review"),
                ]
            )
            let month = PersonalHubCalendarMonth.make(
                referenceDate: calendarReferenceDate ?? Date(),
                selectedDate: calendarSelectedDate ?? calendarReferenceDate ?? Date(),
                eventDates: [start],
                selectedEvents: Calendar.current.isDate(
                    calendarSelectedDate ?? calendarReferenceDate ?? Date(),
                    inSameDayAs: start
                ) ? [eventItem] : []
            )
            return .init(
                id: id,
                availability: ready,
                summary: "3 upcoming events",
                items: [eventItem],
                actions: [.init(id: "add", label: "Add event", symbol: "plus")],
                calendarMonth: month
            )
        case .reminders:
            return .init(
                id: id,
                availability: ready,
                summary: "2 open tasks · Personal",
                items: [
                    .init(id: "list:mock-list", title: "Personal", detail: "mock-list"),
                    .init(
                        id: "task:finish-deck",
                        title: "Finish the deck",
                        subtitle: "Due today",
                        detail: "Finish the deck",
                        actions: [
                            .init(id: "copyToDevice", label: "Copy", targetID: "task:finish-deck"),
                            .init(id: "complete", label: "Complete", targetID: "task:finish-deck"),
                            .init(id: "moveDown", label: "Move down", targetID: "task:finish-deck"),
                            .init(id: "delete", label: "Delete", role: .destructive, targetID: "task:finish-deck"),
                        ]
                    ),
                    .init(
                        id: "task:book-flights",
                        title: "Book flights",
                        subtitle: "Personal",
                        detail: "Book flights",
                        actions: [
                            .init(id: "copyToDevice", label: "Copy", targetID: "task:book-flights"),
                            .init(id: "complete", label: "Complete", targetID: "task:book-flights"),
                            .init(id: "moveUp", label: "Move up", targetID: "task:book-flights"),
                            .init(id: "moveTop", label: "Top", targetID: "task:book-flights"),
                            .init(id: "delete", label: "Delete", role: .destructive, targetID: "task:book-flights"),
                        ]
                    ),
                    .init(
                        id: "task:send-recap",
                        title: "Send recap",
                        subtitle: "Completed",
                        detail: "Send recap",
                        actions: [
                            .init(id: "copyToDevice", label: "Copy", targetID: "task:send-recap"),
                            .init(id: "restore", label: "Restore", targetID: "task:send-recap"),
                            .init(id: "delete", label: "Delete", role: .destructive, targetID: "task:send-recap"),
                        ]
                    ),
                ],
                actions: [
                    .init(id: "add", label: "Add task", symbol: "plus"),
                    .init(id: "addList", label: "Add list", symbol: "folder.badge.plus"),
                ]
            )
        case .notes:
            let note = PersonalHubNoteDraft(
                text: "Launch checklist\n- [ ] Record demo\n- [x] Prepare outline",
                category: "Work",
                baseRevision: 4
            )
            return .init(
                id: id,
                availability: ready,
                summary: "1 note · Work",
                items: [
                    .init(
                        id: "note:launch",
                        title: "Launch checklist",
                        subtitle: "Work · revision 4",
                        detail: note.text,
                        actions: [
                            .init(id: "replace", label: "Edit", targetID: "note:launch", value: note.encodedActionValue()),
                            .init(id: "append", label: "Append", targetID: "note:launch", value: note.encodedActionValue()),
                            .init(id: "setCategory", label: "Category", targetID: "note:launch", value: note.encodedActionValue()),
                            .init(id: "copyToDevice", label: "Copy", targetID: "note:launch"),
                            .init(
                                id: "toggleChecklist",
                                label: "Toggle task",
                                targetID: "note:launch",
                                value: PersonalHubChecklistMutation(lineIndex: 1, baseRevision: 4).encodedActionValue()
                            ),
                            .init(id: "undo", label: "Undo", targetID: "note:launch"),
                            .init(id: "delete", label: "Delete", role: .destructive, targetID: "note:launch"),
                        ]
                    )
                ],
                actions: [
                    .init(id: "add", label: "Add note", symbol: "plus"),
                ]
            )
        case .system:
            return .init(id: id, availability: ready, summary: "CPU 18% · Memory 61%", detail: "Thermal state nominal", actions: [.init(id: "refresh", label: "Refresh")])
        case .weather:
            return .init(id: id, availability: ready, summary: "68° · Mostly clear", detail: "Los Angeles, CA", actions: [.init(id: "refresh", label: "Refresh")])
        case .notifications:
            return .init(
                id: id,
                availability: .partial,
                summary: "1 CodeIsland alert needs attention",
                detail: "macOS does not expose other apps’ Notification Center history through a public API. CodeIsland never reads private notification databases or asks for Full Disk Access.",
                items: [
                    .init(
                        id: "alert:approval",
                        title: "Shell approval",
                        subtitle: "Codex · Action required",
                        detail: "Review the exact command in the approval card.",
                        symbol: "exclamationmark.circle.fill"
                    )
                ]
            )
        case .claude:
            return .init(
                id: id,
                availability: ready,
                summary: "Your Claude Code subscription · tools disabled",
                items: [
                    .init(
                        id: "latest",
                        title: "What CodeIsland version is running on my Mac?",
                        subtitle: "Claude Code · read-only",
                        detail: "CodeIsland 1.0.49 is running on your Mac.",
                        symbol: "sparkles",
                        actions: [.init(id: "copyToDevice", label: "Copy", symbol: "doc.on.doc")]
                    )
                ],
                actions: [
                    .init(id: "ask", label: "Ask", symbol: "questionmark.bubble"),
                    .init(id: "plan", label: "Do", symbol: "checkmark.circle"),
                ]
            )
        case .agents:
            return .init(
                id: id,
                availability: ready,
                summary: "2 active sessions",
                items: [.init(id: "agent:codex", title: "Codex", subtitle: "Running in ob1-app")],
                actions: [.init(id: "refresh", label: "Refresh")]
            )
        case .github:
            return .init(id: id, availability: ready, summary: "1 pull request", items: [.init(id: "pr:8", title: "#8 Crest parity", subtitle: "Merged", actions: [.init(id: "open", label: "Open", deepLink: URL(string: "https://github.com/revopsglobal/CodeIsland/pull/8"))])], actions: [.init(id: "refresh", label: "Refresh")])
        case .audio:
            return .init(
                id: id,
                availability: ready,
                summary: "MacBook Air Speakers · 42%",
                items: [.init(id: "audio:output", title: "MacBook Air Speakers", subtitle: "Default output")],
                actions: [
                    .init(id: "volumeDown", label: "-10", symbol: "speaker.minus"),
                    .init(id: "setVolume", label: "Volume", symbol: "slider.horizontal.3", value: "42"),
                    .init(id: "volumeUp", label: "+10", symbol: "speaker.plus"),
                    .init(id: "openSettings", label: "Sound Settings", symbol: "gearshape"),
                ]
            )
        case .bluetooth:
            return .init(id: id, availability: ready, summary: "AirPods Pro · 76%", items: [.init(id: "bluetooth:airpods", title: "AirPods Pro", subtitle: "Connected · 76%", actions: [.init(id: "disconnect", label: "Disconnect", targetID: "bluetooth:airpods")])], actions: [.init(id: "refresh", label: "Refresh")])
        case .battery:
            return .init(id: id, availability: ready, summary: "84% · Normal", detail: "112 cycles", actions: [.init(id: "refresh", label: "Refresh")])
        case .quickToggles:
            return .init(id: id, availability: ready, summary: "Appearance and Mac controls", actions: [.init(id: "darkMode", label: "Dark / Light"), .init(id: "mute", label: "Mute"), .init(id: "displaySleep", label: "Sleep display"), .init(id: "lockMac", label: "Lock Mac")])
        case .downloads:
            return .init(
                id: id,
                availability: ready,
                summary: "1 recent download",
                items: [
                    .init(
                        id: "download:1",
                        title: "CodeIsland.dmg",
                        subtitle: "Completed · 8.4 MB",
                        actions: [
                            .init(
                                id: "downloadToDevice",
                                label: "Download",
                                role: .primary,
                                targetID: "download:1"
                            )
                        ]
                    )
                ],
                actions: [.init(id: "refresh", label: "Refresh")]
            )
        case .camera:
            return .init(
                id: id,
                availability: ready,
                summary: "Private camera and microphone pre-check",
                actions: [.init(id: "previewLocal", label: "Preview", symbol: "camera.fill")]
            )
        case .teleprompter:
            return .init(
                id: id,
                availability: ready,
                summary: "Ready · 140 WPM",
                detail: "Launch remarks",
                items: [
                    .init(
                        id: "teleprompter:launch",
                        title: "Launch remarks",
                        detail: "Welcome to Code Island",
                        actions: [
                            .init(id: "presentOnDevice", label: "Present", targetID: "teleprompter:launch"),
                            .init(id: "copyToDevice", label: "Copy", targetID: "teleprompter:launch"),
                        ]
                    )
                ],
                actions: [.init(id: "set", label: "Edit script", value: "Welcome to Code Island")]
            )
        case .windowManager:
            return .init(id: id, availability: ready, summary: "Finder", actions: [.init(id: "left", label: "Left"), .init(id: "right", label: "Right"), .init(id: "maximize", label: "Maximize")])
        }
    }

    private static func mockHubPreview(for intent: PersonalHubActionIntent) -> String {
        let title = PersonalHubCatalog.definition(for: intent.moduleID).title
        let value = intent.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty
            ? "\(title): \(intent.actionID)"
            : "\(title): \(intent.actionID) — \(value)"
    }
#endif

    private static func saveKeychainToken(_ token: String) throws {
        deleteKeychainToken()
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw RemoteClientError.server("Couldn't save pairing token (\(status))")
        }
    }

    private static func readKeychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychainToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: tokenAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension Notification.Name {
    static let codeIslandPushTokenAvailable = Notification.Name("codeisland.push-token-available")
    static let codeIslandLiveActivityTokenAvailable = Notification.Name("codeisland.live-activity-token-available")
    static let codeIslandLiveActivityReceiptAvailable = Notification.Name("codeisland.live-activity-receipt-available")
    static let codeIslandRemoteAttentionChanged = Notification.Name("codeisland.remote-attention-changed")
}
