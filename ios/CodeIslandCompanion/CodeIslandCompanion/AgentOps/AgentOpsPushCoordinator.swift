import CryptoKit
import Foundation
import UIKit
import UserNotifications

enum AgentOpsMobileEventType: String, Codable, Sendable {
    case taskNeedsYou = "task.needs_you"
    case taskWorking = "task.working"
    case taskBlocked = "task.blocked"
    case taskVerified = "task.verified"
    case taskFailed = "task.failed"
    case approvalRequired = "approval.required"
    case approvalResolved = "approval.resolved"

    var isVisible: Bool {
        switch self {
        case .taskNeedsYou, .taskBlocked, .taskVerified, .taskFailed,
                .approvalRequired:
            return true
        case .taskWorking, .approvalResolved:
            return false
        }
    }

    var isApproval: Bool {
        self == .approvalRequired || self == .approvalResolved
    }
}

enum AgentOpsNavigationTarget: Equatable, Sendable {
    case task(UUID)
    case approval(UUID)

    init?(url: URL) {
        guard
            url.scheme?.lowercased() == "codeisland",
            url.host?.lowercased() == "agentops"
        else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2, let id = UUID(uuidString: components[1])
        else { return nil }
        switch components[0] {
        case "tasks":
            self = .task(id)
        case "approvals":
            self = .approval(id)
        default:
            return nil
        }
    }
}

struct AgentOpsPushEnvelope: Equatable, Sendable {
    private static let allowedKeys: Set<String> = [
        "aps",
        "taskId",
        "approvalId",
        "eventType",
        "version",
        "deepLink",
    ]

    let taskID: UUID
    let approvalID: UUID?
    let eventType: AgentOpsMobileEventType
    let version: Int
    let deepLink: URL

    init(
        taskID: UUID,
        approvalID: UUID?,
        eventType: AgentOpsMobileEventType,
        version: Int,
        deepLink: URL
    ) {
        self.taskID = taskID
        self.approvalID = approvalID
        self.eventType = eventType
        self.version = version
        self.deepLink = deepLink
    }

    init?(payloadFields: [String: Any]) {
        guard
            Set(payloadFields.keys).isSubset(of: Self.allowedKeys),
            payloadFields["aps"] is [String: Any],
            let taskText = payloadFields["taskId"] as? String,
            let taskID = UUID(uuidString: taskText),
            taskText == taskText.lowercased(),
            let eventText = payloadFields["eventType"] as? String,
            let eventType = AgentOpsMobileEventType(rawValue: eventText),
            let version = payloadFields["version"] as? Int,
            version > 0,
            let deepLinkText = payloadFields["deepLink"] as? String,
            let deepLink = URL(string: deepLinkText),
            let navigation = AgentOpsNavigationTarget(url: deepLink)
        else { return nil }

        let approvalID: UUID?
        if let approvalText = payloadFields["approvalId"] as? String {
            guard
                approvalText == approvalText.lowercased(),
                let parsed = UUID(uuidString: approvalText)
            else { return nil }
            approvalID = parsed
        } else {
            approvalID = nil
        }
        guard eventType.isApproval == (approvalID != nil) else { return nil }

        switch navigation {
        case .task(let deepLinkTaskID):
            guard !eventType.isApproval, deepLinkTaskID == taskID else {
                return nil
            }
        case .approval(let deepLinkApprovalID):
            guard
                eventType.isApproval,
                deepLinkApprovalID == approvalID,
                URLComponents(
                    url: deepLink,
                    resolvingAgainstBaseURL: false
                )?
                .queryItems?
                .first(where: { $0.name == "taskId" })?
                .value == taskText
            else { return nil }
        }

        self.init(
            taskID: taskID,
            approvalID: approvalID,
            eventType: eventType,
            version: version,
            deepLink: deepLink
        )
    }

    var customPayloadIsContentFree: Bool { true }
}

struct AgentOpsDeviceRegistrationRequest: Codable, Equatable, Sendable {
    let deviceId: String
    let apnsToken: String?
    let apnsEnvironment: AgentOpsAPNsEnvironment
    let pushToStartToken: String?
    let liveActivityTokens: [String: String]
}

enum AgentOpsAPNsEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}

struct AgentOpsDeviceRegistration: Codable, Equatable, Sendable {
    let id: UUID
    let deviceId: String
    let lastSeenAt: Date
}

struct AgentOpsDeviceRegistrationEnvelope: Codable, Equatable, Sendable {
    let device: AgentOpsDeviceRegistration
}

struct AgentOpsPushTokenSnapshot: Equatable, Sendable {
    let deviceID: String
    let apnsToken: String?
    let pushToStartToken: String?
    let liveActivityTokens: [String: String]

    var isEmpty: Bool {
        apnsToken == nil
            && pushToStartToken == nil
            && liveActivityTokens.isEmpty
    }
}

@MainActor
final class AgentOpsPushTokenStore {
    static let shared = AgentOpsPushTokenStore()

    private static let deviceIDKey = "agentops.native.push.device-id.v1"
    private static let apnsTokenKey = "agentops.native.push.apns-token.v1"
    private static let pushToStartTokenKey =
        "agentops.native.push.activity-start-token.v1"
    private static let liveActivityTokensKey =
        "agentops.native.push.activity-update-tokens.v1"
    private static let versionsKey = "agentops.native.push.versions.v1"
    private static let statesKey = "agentops.native.push.states.v1"
    private static let registeredFingerprintKey =
        "agentops.native.push.registered-fingerprint.v1"

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let deviceIDProvider: () -> String

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        deviceID: @escaping () -> String = {
            UUID().uuidString.lowercased()
        }
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        deviceIDProvider = deviceID
    }

    func storeAPNsToken(_ token: Data) {
        defaults.set(token.hexString, forKey: Self.apnsTokenKey)
        notify()
    }

    func storePushToStartToken(_ token: Data) {
        defaults.set(token.hexString, forKey: Self.pushToStartTokenKey)
        notify()
    }

    func storeLiveActivityToken(_ token: Data, taskID: UUID) {
        var values = liveActivityTokens()
        let key = taskID.uuidString.lowercased()
        let encoded = token.hexString
        guard values[key] != encoded else { return }
        values[key] = encoded
        defaults.set(values, forKey: Self.liveActivityTokensKey)
        notify()
    }

    func snapshot() -> AgentOpsPushTokenSnapshot {
        AgentOpsPushTokenSnapshot(
            deviceID: deviceID(),
            apnsToken: defaults.string(forKey: Self.apnsTokenKey),
            pushToStartToken: defaults.string(
                forKey: Self.pushToStartTokenKey
            ),
            liveActivityTokens: liveActivityTokens()
        )
    }

    func removeLiveActivityToken(taskID: UUID) {
        var values = liveActivityTokens()
        guard values.removeValue(
            forKey: taskID.uuidString.lowercased()
        ) != nil else { return }
        defaults.set(values, forKey: Self.liveActivityTokensKey)
        notify()
    }

    func needsRegistration(_ snapshot: AgentOpsPushTokenSnapshot) -> Bool {
        guard !snapshot.isEmpty else { return false }
        return defaults.string(forKey: Self.registeredFingerprintKey)
            != fingerprint(snapshot)
    }

    func markRegistered(_ snapshot: AgentOpsPushTokenSnapshot) {
        guard snapshot == self.snapshot() else { return }
        defaults.set(
            fingerprint(snapshot),
            forKey: Self.registeredFingerprintKey
        )
    }

    func invalidateRegistration() {
        defaults.removeObject(forKey: Self.registeredFingerprintKey)
    }

    func acceptedVersion(taskID: UUID) -> Int? {
        let key = taskID.uuidString.lowercased()
        return (defaults.dictionary(forKey: Self.versionsKey) as? [String: Int])?[
            key
        ]
    }

    func acceptedState(taskID: UUID) -> AgentOpsPushTaskState? {
        let key = taskID.uuidString.lowercased()
        let raw = (
            defaults.dictionary(forKey: Self.statesKey) as? [String: String]
        )?[key]
        return raw.flatMap(AgentOpsPushTaskState.init(rawValue:))
    }

    func record(
        taskID: UUID,
        version: Int,
        state: AgentOpsPushTaskState
    ) {
        let key = taskID.uuidString.lowercased()
        var versions =
            defaults.dictionary(forKey: Self.versionsKey) as? [String: Int]
                ?? [:]
        var states =
            defaults.dictionary(forKey: Self.statesKey) as? [String: String]
                ?? [:]
        versions[key] = version
        states[key] = state.rawValue
        trim(&versions, keeping: key)
        trim(&states, keeping: key)
        defaults.set(versions, forKey: Self.versionsKey)
        defaults.set(states, forKey: Self.statesKey)
    }

    private func deviceID() -> String {
        if let existing = defaults.string(forKey: Self.deviceIDKey) {
            return existing
        }
        let generated = deviceIDProvider()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = generated.isEmpty
            ? UUID().uuidString.lowercased()
            : String(generated.prefix(200))
        defaults.set(safe, forKey: Self.deviceIDKey)
        return safe
    }

    private func liveActivityTokens() -> [String: String] {
        defaults.dictionary(
            forKey: Self.liveActivityTokensKey
        ) as? [String: String] ?? [:]
    }

    private func notify() {
        notificationCenter.post(
            name: .agentOpsPushTokenAvailable,
            object: nil
        )
    }

    private func fingerprint(_ snapshot: AgentOpsPushTokenSnapshot) -> String {
        let material = [
            snapshot.deviceID,
            snapshot.apnsToken ?? "-",
            snapshot.pushToStartToken ?? "-",
            snapshot.liveActivityTokens
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&"),
        ].joined(separator: "|")
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func trim<Value>(
        _ dictionary: inout [String: Value],
        keeping key: String
    ) {
        guard dictionary.count > 128 else { return }
        dictionary = [key: dictionary[key]].compactMapValues { $0 }
    }
}

protocol AgentOpsNotificationAuthorizing: Sendable {
    func authorizationGranted() async -> Bool?
    func requestAuthorization() async throws -> Bool
    func registerForRemoteNotifications() async
    func openNotificationSettings() async
}

struct SystemAgentOpsNotificationAuthorizer:
    AgentOpsNotificationAuthorizing,
    @unchecked Sendable
{
    func authorizationGranted() async -> Bool? {
        let status = await UNUserNotificationCenter.current()
            .notificationSettings()
            .authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return nil
        @unknown default:
            return nil
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        )
    }

    func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func openNotificationSettings() async {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString)
        else { return }
        await MainActor.run {
            UIApplication.shared.open(url)
        }
    }
}

enum AgentOpsPushProcessingOutcome: Equatable, Sendable {
    case acceptedVisible
    case acceptedSilent
    case rejectedStale
    case rejectedRegressive
    case unavailable
}

enum AgentOpsPushTaskState: String, Sendable {
    case queued
    case working
    case needsYou
    case verified
    case failed
    case cancelled

    var isTerminal: Bool {
        self == .verified || self == .failed || self == .cancelled
    }

    static func authoritative(
        _ task: AgentOpsWorkSummary
    ) -> AgentOpsPushTaskState {
        if task.hasVerifiedProof { return .verified }
        switch task.lifecycle.status.lowercased() {
        case "queued", "pending", "created":
            return .queued
        case "blocked", "needs_person", "needs_approval":
            return .needsYou
        case "failed":
            return .failed
        case "cancelled", "canceled":
            return .cancelled
        default:
            return .working
        }
    }

    static func accepts(
        previous: AgentOpsPushTaskState?,
        incoming: AgentOpsPushTaskState
    ) -> Bool {
        guard let previous else { return true }
        return !previous.isTerminal || incoming == previous
    }
}

@MainActor
final class AgentOpsPushCoordinator: ObservableObject {
    @Published private(set) var permissionGranted: Bool?
    @Published private(set) var registrationError: String?

    private let client: AgentOpsClient
    private let tokenStore: AgentOpsPushTokenStore
    private let environment: AgentOpsAPNsEnvironment
    private let notificationAuthorizer: any AgentOpsNotificationAuthorizing
    private let notificationCenter: NotificationCenter
    private let onWork: @MainActor (AgentOpsWorkSummary) -> Void
    private let onApproval: @MainActor (AgentOpsApprovalCard) -> Void
    private let onOpen: @MainActor (AgentOpsNavigationTarget) -> Void
    private var observers: [NSObjectProtocol] = []
    private var registering = false

    init(
        client: AgentOpsClient,
        tokenStore: AgentOpsPushTokenStore,
        environment: AgentOpsAPNsEnvironment = {
#if DEBUG
            .sandbox
#else
            .production
#endif
        }(),
        notificationAuthorizer: any AgentOpsNotificationAuthorizing =
            SystemAgentOpsNotificationAuthorizer(),
        notificationCenter: NotificationCenter = .default,
        onWork: @escaping @MainActor (AgentOpsWorkSummary) -> Void = { _ in },
        onApproval: @escaping @MainActor (AgentOpsApprovalCard) -> Void = {
            _ in
        },
        onOpen: @escaping @MainActor (AgentOpsNavigationTarget) -> Void = {
            _ in
        }
    ) {
        self.client = client
        self.tokenStore = tokenStore
        self.environment = environment
        self.notificationAuthorizer = notificationAuthorizer
        self.notificationCenter = notificationCenter
        self.onWork = onWork
        self.onApproval = onApproval
        self.onOpen = onOpen
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    func start() {
        guard observers.isEmpty else {
            Task { await registerPendingTokens() }
            return
        }
        observers.append(
            notificationCenter.addObserver(
                forName: .agentOpsPushTokenAvailable,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.registerPendingTokens()
                }
            }
        )
        Task {
            permissionGranted = await notificationAuthorizer
                .authorizationGranted()
            await registerPendingTokens()
        }
    }

    func invalidateRegistrationScope() {
        tokenStore.invalidateRegistration()
    }

    func requestNotificationAccess() async {
        if permissionGranted == false {
            await notificationAuthorizer.openNotificationSettings()
            return
        }
        do {
            let granted = try await notificationAuthorizer
                .requestAuthorization()
            permissionGranted = granted
            guard granted else { return }
            await notificationAuthorizer.registerForRemoteNotifications()
        } catch {
            permissionGranted = false
        }
    }

    func registerPendingTokens() async {
        guard !registering else { return }
        let snapshot = tokenStore.snapshot()
        guard tokenStore.needsRegistration(snapshot) else { return }
        registering = true
        defer { registering = false }
        do {
            _ = try await client.registerDevice(
                AgentOpsDeviceRegistrationRequest(
                    deviceId: snapshot.deviceID,
                    apnsToken: snapshot.apnsToken,
                    apnsEnvironment: environment,
                    pushToStartToken: snapshot.pushToStartToken,
                    liveActivityTokens: snapshot.liveActivityTokens
                )
            )
            tokenStore.markRegistered(snapshot)
            registrationError = nil
        } catch is CancellationError {
            return
        } catch {
            registrationError =
                "AgentOps alerts will retry registration automatically."
        }
    }

    func process(
        _ envelope: AgentOpsPushEnvelope,
        userTapped: Bool
    ) async -> AgentOpsPushProcessingOutcome {
        if let accepted = tokenStore.acceptedVersion(taskID: envelope.taskID),
           envelope.version <= accepted
        {
            if userTapped {
                await openCurrentDetail(for: envelope)
            }
            return .rejectedStale
        }

        do {
            let work = try await client.work(id: envelope.taskID)
            guard work.id == envelope.taskID else { return .unavailable }
            let state = AgentOpsPushTaskState.authoritative(work)
            guard AgentOpsPushTaskState.accepts(
                previous: tokenStore.acceptedState(taskID: envelope.taskID),
                incoming: state
            ) else {
                return .rejectedRegressive
            }
            guard eventIsConsistent(envelope.eventType, state: state) else {
                return .unavailable
            }

            if let approvalID = envelope.approvalID {
                let approval = try await client.approval(id: approvalID)
                guard
                    approval.id == approvalID,
                    approval.taskId == envelope.taskID,
                    approvalIsConsistent(
                        approval,
                        eventType: envelope.eventType
                    )
                else { return .unavailable }
                onApproval(approval)
            }

            tokenStore.record(
                taskID: envelope.taskID,
                version: envelope.version,
                state: state
            )
            onWork(work)
            if userTapped, let target = AgentOpsNavigationTarget(
                url: envelope.deepLink
            ) {
                onOpen(target)
            }
            return envelope.eventType.isVisible
                ? .acceptedVisible
                : .acceptedSilent
        } catch is CancellationError {
            return .unavailable
        } catch {
            return .unavailable
        }
    }

    static func notificationActions(
        for eventType: AgentOpsMobileEventType
    ) -> [UNNotificationAction] {
        // Notifications only open the private card. No APNs action identifier
        // can ever resolve an approval.
        []
    }

    private func eventIsConsistent(
        _ eventType: AgentOpsMobileEventType,
        state: AgentOpsPushTaskState
    ) -> Bool {
        switch eventType {
        case .taskVerified:
            return state == .verified
        case .taskFailed:
            return state == .failed
        default:
            return true
        }
    }

    private func openCurrentDetail(for envelope: AgentOpsPushEnvelope) async {
        do {
            let work = try await client.work(id: envelope.taskID)
            guard work.id == envelope.taskID else { return }
            onWork(work)
            if let approvalID = envelope.approvalID {
                let approval = try await client.approval(id: approvalID)
                guard
                    approval.id == approvalID,
                    approval.taskId == envelope.taskID
                else { return }
                onApproval(approval)
            }
            guard let target = AgentOpsNavigationTarget(
                url: envelope.deepLink
            ) else { return }
            onOpen(target)
        } catch {
            // Keep the existing card state; the screen will retry privately.
        }
    }

    private func approvalIsConsistent(
        _ approval: AgentOpsApprovalCard,
        eventType: AgentOpsMobileEventType
    ) -> Bool {
        switch eventType {
        case .approvalRequired:
            return approval.status == .pending
        case .approvalResolved:
            return approval.status != .pending
        default:
            return false
        }
    }
}

extension Notification.Name {
    static let agentOpsPushTokenAvailable = Notification.Name(
        "agentops.native.push-token-available"
    )
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
