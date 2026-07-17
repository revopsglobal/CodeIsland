import Foundation
import Security
import UIKit

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
    @Published private(set) var hubSnapshot: PersonalHubSnapshot?
    private var calendarReferenceDate: Date?
    private var calendarSelectedDate: Date?
    @Published private(set) var hubError: String?
    @Published private(set) var hubActionInFlight = false
    @Published private(set) var hubActionMessage: String?
    @Published var preparedAction: PersonalHubPreparedAction?
    @Published var quickJotDestination: BuddyQuickJotDestination?
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
    private static let selectedModeKey = "codeisland.hub.selectedMode.v1"

    private let usesMockHub: Bool
    private let usesMockPairing: Bool
    private var deviceToken: String?
    private var pollTask: Task<Void, Never>?
    private var isActive = true
    private var notificationObservers: [NSObjectProtocol] = []

    var hasPairingCredential: Bool {
        deviceToken != nil
    }

    init() {
#if DEBUG
        usesMockHub = ProcessInfo.processInfo.arguments.contains("-CodeIslandCompanionMockHub")
        usesMockPairing = ProcessInfo.processInfo.arguments.contains("-CodeIslandCompanionMockPairing")
        let launchMode = Self.mockHubModeFromLaunchArguments()
#else
        usesMockHub = false
        usesMockPairing = false
        let launchMode: PersonalHubMode? = nil
#endif
        serverURLText = UserDefaults.standard.string(forKey: Self.serverURLKey) ?? Self.defaultServerURL
        selectedMode = launchMode ?? PersonalHubMode(
            rawValue: UserDefaults.standard.string(forKey: Self.selectedModeKey) ?? ""
        ) ?? .auto

#if DEBUG
        if usesMockPairing {
            deviceToken = nil
            state = .unpaired
            return
        }
        if usesMockHub {
            deviceToken = "ui-test-device-token"
            state = .connected
            serverName = "CodeIsland UI Test Mac"
            lastUpdatedAt = Date()
            hubSnapshot = Self.mockHubSnapshot(requestedMode: selectedMode)
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
            forName: .codeIslandRemoteApprovalOpened,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.highlightedApprovalID = notification.userInfo?["approvalId"] as? String
                await self?.refresh()
            }
        })
    }

    deinit {
        pollTask?.cancel()
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
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
            state = .offline("Enter a valid Tailscale HTTPS URL")
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
        "That code expired. Open CodeIsland Settings → Buddy on your Mac for the current code."

    func unpair() {
        Self.deleteKeychainToken()
        deviceToken = nil
        approvals = []
        questions = []
        serverName = nil
        hubSnapshot = nil
        hubError = nil
        preparedAction = nil
        state = .unpaired
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
            return
        }
        guard let url = endpoint("/api/approvals") else {
            state = .offline("Enter a valid Tailscale HTTPS URL")
            return
        }
        if approvals.isEmpty { state = .connecting }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let snapshot: RemoteApprovalSnapshot = try await perform(request, authenticated: true)
            approvals = snapshot.approvals
            questions = snapshot.questions
            serverName = snapshot.serverName
            lastUpdatedAt = Date()
            state = .connected
            await refreshHub()
        } catch RemoteClientError.unauthorized {
            unpair()
        } catch {
            state = .offline(error.localizedDescription)
        }
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
            hubError = "Enter a valid Tailscale HTTPS URL"
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
            hubSnapshot = snapshot
            hubError = nil
        } catch RemoteClientError.unauthorized {
            unpair()
        } catch {
            hubError = error.localizedDescription
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
        guard url.scheme?.lowercased() == "codeisland",
              url.host?.lowercased() == "quick-jot",
              let destination = url.pathComponents.dropFirst().first,
              let destination = BuddyQuickJotDestination(rawValue: destination.lowercased())
        else { return }
        quickJotDestination = destination
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
        guard deviceToken != nil,
              let pushToken = UserDefaults.standard.string(forKey: Self.pendingPushTokenKey),
              let url = endpoint("/api/push-token")
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
                RemotePushRegistrationRequest(token: pushToken, environment: environment)
            )
            let _: RegistrationResponse = try await perform(request, authenticated: true)
            UserDefaults.standard.removeObject(forKey: Self.pendingPushTokenKey)
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
    private static func mockHubModeFromLaunchArguments() -> PersonalHubMode? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-CodeIslandCompanionMockHubMode"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return PersonalHubMode(rawValue: arguments[index + 1].lowercased())
    }

    private static func mockHubSnapshot(
        requestedMode: PersonalHubMode,
        calendarReferenceDate: Date? = nil,
        calendarSelectedDate: Date? = nil
    ) -> PersonalHubSnapshot {
        let resolvedMode: PersonalHubMode = requestedMode == .auto ? .home : requestedMode
        return PersonalHubSnapshot(
            serverName: "CodeIsland UI Test Mac",
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
                        id: "queue:1",
                        title: "Next: Signal Fire",
                        subtitle: "Demo Artist",
                        actions: [.init(id: "playFromQueue", label: "Play now", targetID: "queue:1")]
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
            let task = PersonalHubReminderDraft(
                title: "Finish the deck",
                due: Date().addingTimeInterval(7_200),
                calendarID: "mock-list"
            )
            return .init(
                id: id,
                availability: ready,
                summary: "1 open task · Personal",
                items: [
                    .init(id: "list:mock-list", title: "Personal", detail: "mock-list"),
                    .init(
                        id: "task:finish-deck",
                        title: "Finish the deck",
                        subtitle: "Due today",
                        actions: [
                            .init(id: "edit", label: "Edit", targetID: "task:finish-deck", value: task.encodedActionValue()),
                            .init(id: "complete", label: "Complete", targetID: "task:finish-deck"),
                            .init(id: "down", label: "Move down", targetID: "task:finish-deck"),
                            .init(id: "delete", label: "Delete", role: .destructive, targetID: "task:finish-deck"),
                        ]
                    ),
                ],
                actions: [
                    .init(id: "add", label: "Add task", symbol: "plus"),
                    .init(id: "addList", label: "Add list", symbol: "folder.badge.plus"),
                    .init(id: "showCompleted", label: "Completed", symbol: "archivebox"),
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
                        actions: [
                            .init(id: "edit", label: "Edit", targetID: "note:launch", value: note.encodedActionValue()),
                            .init(id: "append", label: "Append", targetID: "note:launch", value: note.encodedActionValue()),
                            .init(id: "copy", label: "Copy", targetID: "note:launch", value: note.text),
                            .init(
                                id: "toggleChecklist",
                                label: "Toggle task",
                                targetID: "note:launch",
                                value: PersonalHubChecklistMutation(lineIndex: 1, baseRevision: 4).encodedActionValue()
                            ),
                            .init(id: "delete", label: "Delete", role: .destructive, targetID: "note:launch"),
                        ]
                    )
                ],
                actions: [
                    .init(id: "add", label: "Add note", symbol: "plus"),
                    .init(id: "undo", label: "Undo", symbol: "arrow.uturn.backward"),
                ]
            )
        case .system:
            return .init(id: id, availability: ready, summary: "CPU 18% · Memory 61%", detail: "Thermal state nominal", actions: [.init(id: "refresh", label: "Refresh")])
        case .weather:
            return .init(id: id, availability: ready, summary: "68° · Mostly clear", detail: "Los Angeles, CA", actions: [.init(id: "refresh", label: "Refresh")])
        case .notifications:
            return .init(id: id, availability: ready, summary: "Push and Live Activity ready", actions: [.init(id: "test", label: "Test notification")])
        case .claude:
            return .init(
                id: id,
                availability: ready,
                summary: "Your Claude Code subscription · tools disabled",
                actions: [
                    .init(id: "ask", label: "Ask", symbol: "questionmark.bubble"),
                    .init(id: "plan", label: "Do", symbol: "checkmark.circle"),
                ]
            )
        case .agents:
            return .init(id: id, availability: ready, summary: "2 active sessions", items: [.init(id: "agent:codex", title: "Codex", subtitle: "Waiting for approval")], actions: [.init(id: "refresh", label: "Refresh")])
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
                    .init(id: "mute", label: "Mute", symbol: "speaker.slash"),
                ]
            )
        case .bluetooth:
            return .init(id: id, availability: ready, summary: "AirPods Pro · 76%", items: [.init(id: "bluetooth:airpods", title: "AirPods Pro", subtitle: "Connected · 76%", actions: [.init(id: "disconnect", label: "Disconnect", targetID: "bluetooth:airpods")])], actions: [.init(id: "refresh", label: "Refresh")])
        case .battery:
            return .init(id: id, availability: ready, summary: "84% · Normal", detail: "112 cycles", actions: [.init(id: "refresh", label: "Refresh")])
        case .quickToggles:
            return .init(id: id, availability: ready, summary: "Appearance and Mac controls", actions: [.init(id: "toggleAppearance", label: "Dark / Light"), .init(id: "mute", label: "Mute"), .init(id: "lock", label: "Lock Mac")])
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
            return .init(id: id, availability: ready, summary: "Front camera preview", actions: [.init(id: "previewOnDevice", label: "Preview", symbol: "camera.fill")])
        case .teleprompter:
            return .init(id: id, availability: ready, summary: "Ready · 140 WPM", detail: "Launch remarks", actions: [.init(id: "set", label: "Edit script", value: "Welcome to CodeIsland"), .init(id: "playPause", label: "Play"), .init(id: "slower", label: "Slower"), .init(id: "faster", label: "Faster")])
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
    static let codeIslandRemoteApprovalOpened = Notification.Name("codeisland.remote-approval-opened")
}
