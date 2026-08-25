import CryptoKit
import Foundation

enum LiveActivityPairingIdentity: Equatable {
    case unpaired
    case credentialPresentButIdentityMissing
    case paired(String)

    static func resolve(
        credential: String?,
        pairingDeviceID: String?
    ) -> LiveActivityPairingIdentity {
        guard credential != nil else { return .unpaired }
        guard let pairingDeviceID = LiveActivityPairingScope.normalized(pairingDeviceID) else {
            return .credentialPresentButIdentityMissing
        }
        return .paired(pairingDeviceID)
    }

    var pairingDeviceID: String? {
        guard case .paired(let pairingDeviceID) = self else { return nil }
        return LiveActivityPairingScope.normalized(pairingDeviceID)
    }

    var canRegisterHostScopedArtifacts: Bool {
        pairingDeviceID != nil
    }

    var canCreateOwnedActivity: Bool {
        switch self {
        case .unpaired:
            return true
        case .credentialPresentButIdentityMissing:
            return false
        case .paired:
            return pairingDeviceID != nil
        }
    }
}

enum RemotePairingIdentityStore {
    static let pairingDeviceIDKey = "codeisland.remote.pairingDeviceID.v1"
    private static let credentialFingerprintKey = "codeisland.remote.pairingCredentialFingerprint.v1"
    static let runtimeIdentityRecordKey = "codeisland.remote.runtimePairingIdentity.v2"
    private static let processNonce = UUID().uuidString
    private static let ownershipLock = NSLock()

    private struct RuntimeIdentityRecord: Codable {
        let processNonce: String
        let state: String
        let pairingDeviceID: String?
    }

    static func current(
        forCredential credential: String,
        defaults: UserDefaults = .standard
    ) -> String? {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        return currentUnlocked(forCredential: credential, defaults: defaults)
    }

    private static func currentUnlocked(
        forCredential credential: String,
        defaults: UserDefaults
    ) -> String? {
        guard defaults.string(forKey: credentialFingerprintKey) == fingerprint(credential) else {
            return nil
        }
        return LiveActivityPairingScope.normalized(defaults.string(forKey: pairingDeviceIDKey))
    }

    static func store(
        _ pairingDeviceID: String?,
        forCredential credential: String?,
        defaults: UserDefaults = .standard
    ) {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        storeUnlocked(pairingDeviceID, forCredential: credential, defaults: defaults)
    }

    private static func storeUnlocked(
        _ pairingDeviceID: String?,
        forCredential credential: String?,
        defaults: UserDefaults
    ) {
        guard let credential,
              let pairingDeviceID = LiveActivityPairingScope.normalized(pairingDeviceID)
        else {
            defaults.removeObject(forKey: pairingDeviceIDKey)
            defaults.removeObject(forKey: credentialFingerprintKey)
            return
        }
        defaults.set(pairingDeviceID, forKey: pairingDeviceIDKey)
        defaults.set(fingerprint(credential), forKey: credentialFingerprintKey)
    }

    /// A pairing replacement is a trust-boundary transition. Persisted state
    /// owned by the old Mac must be gone before the new credential fingerprint
    /// can become recoverable after a crash.
    static func replace(
        _ pairingDeviceID: String?,
        forCredential credential: String?,
        defaults: UserDefaults = .standard
    ) {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        RemoteHostScopedArtifactStore.clear(defaults: defaults)
        storeUnlocked(pairingDeviceID, forCredential: credential, defaults: defaults)
    }

    /// Atomically crosses the pairing trust boundary for process-local push
    /// callbacks: an APNs callback can observe either the old identity and
    /// finish before quarantine, or the fully persisted new identity after it.
    /// No asynchronous work or NotificationCenter delivery occurs while held.
    static func replaceAndPublish(
        _ pairingDeviceID: String?,
        forCredential credential: String?,
        runtimeIdentity: LiveActivityPairingIdentity,
        defaults: UserDefaults = .standard
    ) {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        RemoteHostScopedArtifactStore.clear(defaults: defaults)
        storeUnlocked(pairingDeviceID, forCredential: credential, defaults: defaults)
        publishRuntimeIdentityUnlocked(runtimeIdentity, defaults: defaults)
    }

    static func publishRuntimeIdentity(
        _ identity: LiveActivityPairingIdentity,
        defaults: UserDefaults = .standard
    ) {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        publishRuntimeIdentityUnlocked(identity, defaults: defaults)
    }

    private static func publishRuntimeIdentityUnlocked(
        _ identity: LiveActivityPairingIdentity,
        defaults: UserDefaults
    ) {
        let state: String
        let pairingDeviceID: String?
        switch identity {
        case .unpaired:
            state = "unpaired"
            pairingDeviceID = nil
        case .credentialPresentButIdentityMissing:
            state = "pending"
            pairingDeviceID = nil
        case .paired(let rawPairingDeviceID):
            if let normalized = LiveActivityPairingScope.normalized(rawPairingDeviceID) {
                state = "paired"
                pairingDeviceID = normalized
            } else {
                state = "pending"
                pairingDeviceID = nil
            }
        }
        let record = RuntimeIdentityRecord(
            processNonce: processNonce,
            state: state,
            pairingDeviceID: pairingDeviceID
        )
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: runtimeIdentityRecordKey)
        } else {
            defaults.removeObject(forKey: runtimeIdentityRecordKey)
        }
    }

    static func runtimeIdentity(defaults: UserDefaults = .standard) -> LiveActivityPairingIdentity {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        return runtimeIdentityUnlocked(defaults: defaults)
    }

    /// Serializes the full APNs ownership check and all host-scoped writes with
    /// pairing replacement. The body must remain synchronous and must not post
    /// notifications that could re-enter this boundary.
    static func withRuntimeIdentityTransaction<T>(
        defaults: UserDefaults = .standard,
        _ body: (LiveActivityPairingIdentity) -> T
    ) -> T {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        return body(runtimeIdentityUnlocked(defaults: defaults))
    }

    private static func runtimeIdentityUnlocked(
        defaults: UserDefaults
    ) -> LiveActivityPairingIdentity {
        guard let data = defaults.data(forKey: runtimeIdentityRecordKey),
              let record = try? JSONDecoder().decode(RuntimeIdentityRecord.self, from: data),
              record.processNonce == processNonce
        else { return .credentialPresentButIdentityMissing }
        switch record.state {
        case "unpaired":
            guard record.pairingDeviceID == nil else {
                return .credentialPresentButIdentityMissing
            }
            return .unpaired
        case "pending":
            guard record.pairingDeviceID == nil else {
                return .credentialPresentButIdentityMissing
            }
            return .credentialPresentButIdentityMissing
        case "paired":
            guard let pairingDeviceID = LiveActivityPairingScope.normalized(
                record.pairingDeviceID
            ) else { return .credentialPresentButIdentityMissing }
            return .paired(pairingDeviceID)
        default:
            return .credentialPresentButIdentityMissing
        }
    }

    private static func fingerprint(_ credential: String) -> String {
        SHA256.hash(data: Data(credential.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Persisted state whose request IDs and ActivityKit routes belong to one Mac.
/// Global APNs and push-to-start tokens are intentionally excluded because the
/// same iPhone route is republished to a newly paired device record.
enum RemoteHostScopedArtifactStore {
    static let pendingApprovalIDKey = "codeisland.remote.pendingApprovalID"
    static let pendingQuestionIDKey = "codeisland.remote.pendingQuestionID"
    static let liveActivityUpdateTokensKey = "codeisland.remote.liveActivity.updateTokens"
    static let liveActivityReceiptsKey = "codeisland.remote.liveActivity.receipts.v1"
    static let followedTaskIDKey = "codeisland.liveActivity.followedTask.v1"

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingApprovalIDKey)
        defaults.removeObject(forKey: pendingQuestionIDKey)
        defaults.removeObject(forKey: liveActivityUpdateTokensKey)
        defaults.removeObject(forKey: liveActivityReceiptsKey)
        defaults.removeObject(forKey: followedTaskIDKey)
    }

    /// A cold launch without a proven exact pairing owner must not adopt state
    /// left by a prior credential or by an interrupted transition.
    @discardableResult
    static func quarantineIfUnowned(
        by identity: LiveActivityPairingIdentity,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard identity.pairingDeviceID == nil else { return false }
        clear(defaults: defaults)
        return true
    }
}

enum LiveActivityPairingScope {
    static func normalized(_ pairingDeviceID: String?) -> String? {
        guard let value = pairingDeviceID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    /// Existing TestFlight activities predate pairing-scoped attributes. They
    /// remain recoverable only while this install also has no persisted pairing
    /// identity. Once Buddy knows the current device record, exact identity is
    /// required and legacy or other-Mac activities must be retired.
    static func accepts(
        activityPairingDeviceID: String?,
        identity: LiveActivityPairingIdentity
    ) -> Bool {
        switch identity {
        case .unpaired:
            return normalized(activityPairingDeviceID) == nil
        case .credentialPresentButIdentityMissing:
            return false
        case .paired(let current):
            guard let activityPairingDeviceID = normalized(activityPairingDeviceID),
                  let current = normalized(current)
            else { return false }
            return activityPairingDeviceID == current
        }
    }
}

/// Normal APNs metadata is host-scoped just like ActivityKit update tokens.
/// Presentation remains backward compatible, but a receipt or in-app route is
/// trusted only when the Mac named the exact paired device record.
enum RemoteAttentionPushPairingScope {
    static func acceptsHostScopedArtifacts(
        payloadPairingDeviceID: String?,
        identity: LiveActivityPairingIdentity
    ) -> Bool {
        guard case .paired(let currentPairingDeviceID) = identity,
              let payloadPairingDeviceID = LiveActivityPairingScope.normalized(
                payloadPairingDeviceID
              ),
              let currentPairingDeviceID = LiveActivityPairingScope.normalized(
                currentPairingDeviceID
              )
        else { return false }
        return payloadPairingDeviceID == currentPairingDeviceID
    }
}

enum ScopedRemoteAttentionRoute: Equatable {
    case pendingApproval(String?)
    case pendingQuestion(String?)
    case resolvedApproval(String?)
    case resolvedQuestion(String?)
    case task(UUID)

    static func resolve(
        requestID: String?,
        kind: RemoteAttentionKind?,
        state: RemoteAttentionState?,
        eventPairingDeviceID: String?,
        currentIdentity: LiveActivityPairingIdentity
    ) -> ScopedRemoteAttentionRoute? {
        guard RemoteAttentionPushPairingScope.acceptsHostScopedArtifacts(
            payloadPairingDeviceID: eventPairingDeviceID,
            identity: currentIdentity
        ), let kind, let state else { return nil }

        switch (kind, state) {
        case (.approval, .pending): return .pendingApproval(requestID)
        case (.question, .pending): return .pendingQuestion(requestID)
        case (.approval, _): return .resolvedApproval(requestID)
        case (.question, _): return .resolvedQuestion(requestID)
        case (.task, _):
            guard let requestID, let id = UUID(uuidString: requestID) else { return nil }
            return .task(id)
        }
    }
}

enum RemoteDeepLinkPairingScope {
    static func accepts(
        url: URL,
        route: PersonalHubDeepLink,
        currentIdentity: LiveActivityPairingIdentity
    ) -> Bool {
        let routedPairingDeviceID = LiveActivityPairingScope.normalized(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "pairingDeviceID" })?
                .value
        )
        switch route {
        case .task:
            return LiveActivityPairingScope.accepts(
                activityPairingDeviceID: routedPairingDeviceID,
                identity: currentIdentity
            )
        case .pendingApproval(let id), .pendingQuestion(let id):
            // Generic user-initiated shortcuts intentionally have no request ID
            // and no owner. Any request-specific ActivityKit link must prove its
            // exact immutable pairing owner.
            if id == nil, routedPairingDeviceID == nil { return true }
            return LiveActivityPairingScope.accepts(
                activityPairingDeviceID: routedPairingDeviceID,
                identity: currentIdentity
            )
        case .module, .quickJot, .newTask, .needsYou, .sessions:
            return true
        }
    }
}

struct PairingIdentityGenerationScope: Equatable {
    let generation: UInt64
    let identity: LiveActivityPairingIdentity

    func isCurrent(
        generation currentGeneration: UInt64,
        identity currentIdentity: LiveActivityPairingIdentity
    ) -> Bool {
        generation == currentGeneration && identity == currentIdentity
    }
}

/// Nearby Multipeer/BLE payloads do not carry the authenticated remote device
/// record ID. They may drive local, nil-owned activities only while Buddy is
/// unpaired; once a remote credential exists, authenticated snapshots are the
/// sole authority for Live Activity content.
enum LocalTransportLiveActivityScope {
    static func capture(
        generation: UInt64,
        identity: LiveActivityPairingIdentity
    ) -> PairingIdentityGenerationScope? {
        guard identity == .unpaired else { return nil }
        return PairingIdentityGenerationScope(generation: generation, identity: identity)
    }
}

struct AuthenticatedConnectionScope: Equatable {
    let generation: UInt64
    let credential: String
    let baseURL: String

    func isCurrent(
        generation currentGeneration: UInt64,
        credential currentCredential: String?,
        baseURL currentBaseURL: String?
    ) -> Bool {
        generation == currentGeneration
            && credential == currentCredential
            && baseURL == currentBaseURL
    }
}

struct RemotePushRegistrationState {
    enum CredentialEvent {
        case restored
        case changed
    }

    private var clientMetadataRegistered = false

    var needsCredentialRegistration: Bool {
        !clientMetadataRegistered
    }

    func shouldRegisterClientMetadata(hasClientMetadata: Bool) -> Bool {
        needsCredentialRegistration && hasClientMetadata
    }

    mutating func pairingCredentialDidChange() {
        clientMetadataRegistered = false
    }

    mutating func markClientMetadataRegistered() {
        clientMetadataRegistered = true
    }

    static func shouldRequeueHostScopedLiveActivityTokens(for event: CredentialEvent) -> Bool {
        event == .restored
    }
}

enum RemotePushTokenMailbox {
    private static let pendingKey = "codeisland.remote.pendingPushToken"
    private static let currentKey = "codeisland.remote.currentPushToken.v1"

    static func store(_ token: String, defaults: UserDefaults = .standard) {
        guard !token.isEmpty else { return }
        defaults.set(token, forKey: pendingKey)
        defaults.set(token, forKey: currentKey)
    }

    static func registrationToken(
        republishCurrent: Bool,
        defaults: UserDefaults = .standard
    ) -> String? {
        if let pending = defaults.string(forKey: pendingKey), !pending.isEmpty {
            return pending
        }
        guard republishCurrent,
              let current = defaults.string(forKey: currentKey),
              !current.isEmpty
        else { return nil }
        return current
    }

    static func acknowledge(_ token: String?, defaults: UserDefaults = .standard) {
        guard let token,
              defaults.string(forKey: pendingKey) == token
        else { return }
        // The pending copy is delivery state; the current copy is retained so a
        // newly paired Mac record can receive the same APNs route immediately.
        defaults.removeObject(forKey: pendingKey)
    }
}

enum CompanionStatus: String, Codable, Hashable {
    case idle
    case processing
    case running
    case waitingApproval
    case waitingQuestion

    /// Tolerant decoding: a newer Mac app may ship status values this build has
    /// never heard of. Falling back to .idle keeps the payload renderable instead
    /// of failing the whole decode (and, on watchOS, re-crashing on the persisted
    /// application context at every launch — #246).
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CompanionStatus(rawValue: raw) ?? .idle
    }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .processing: return "Processing"
        case .running: return "Running"
        case .waitingApproval: return "Waiting for approval"
        case .waitingQuestion: return "Waiting for answer"
        }
    }

    var shortLabel: String {
        switch self {
        case .idle: return "Idle"
        case .processing: return "Processing"
        case .running: return "Running"
        case .waitingApproval: return "Approve"
        case .waitingQuestion: return "Question"
        }
    }

    /// Display priority matching the Mac notch: approval > question > running > processing > idle.
    var priority: Int {
        switch self {
        case .waitingApproval: return 5
        case .waitingQuestion: return 4
        case .running: return 3
        case .processing: return 2
        case .idle: return 0
        }
    }
}

enum CompanionPendingAction: String, Codable {
    case approval
    case question
}

enum CompanionMessageRole: String, Codable {
    case user
    case assistant

    /// Tolerant decoding — unknown roles from a newer Mac app read as assistant (#246).
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CompanionMessageRole(rawValue: raw) ?? .assistant
    }

    var label: String {
        switch self {
        case .user: return "You"
        case .assistant: return "Assistant"
        }
    }
}

struct CompanionMessagePreview: Codable, Identifiable, Hashable {
    let id = UUID()
    let role: CompanionMessageRole
    let text: String

    init(role: CompanionMessageRole, text: String) {
        self.role = role
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case text
    }
}

struct CompanionQuestionPayload: Codable {
    let header: String?
    let question: String
    let options: [String]
    let descriptions: [String]
    let index: Int
    let total: Int
    let allowsMultipleSelection: Bool

    init(
        header: String?,
        question: String,
        options: [String],
        descriptions: [String],
        index: Int,
        total: Int,
        allowsMultipleSelection: Bool
    ) {
        self.header = header
        self.question = question
        self.options = options
        self.descriptions = descriptions
        self.index = index
        self.total = total
        self.allowsMultipleSelection = allowsMultipleSelection
    }

    private enum CodingKeys: String, CodingKey {
        case header, question, options, descriptions, index, total, allowsMultipleSelection
    }

    /// Tolerant decoding: only `question` is required. Everything else falls back to
    /// safe defaults so a payload from a newer/older Mac app never fails the decode (#246).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        header = try? c.decodeIfPresent(String.self, forKey: .header)
        question = try c.decode(String.self, forKey: .question)
        options = (try? c.decodeIfPresent([String].self, forKey: .options)) ?? []
        descriptions = (try? c.decodeIfPresent([String].self, forKey: .descriptions)) ?? []
        index = max(0, (try? c.decodeIfPresent(Int.self, forKey: .index)) ?? 0)
        total = max(1, (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? 1)
        allowsMultipleSelection = (try? c.decodeIfPresent(Bool.self, forKey: .allowsMultipleSelection)) ?? false
    }
}

struct CompanionSessionPreview: Codable, Identifiable, Hashable {
    let sessionId: String?
    let source: String
    let status: CompanionStatus
    let toolName: String?
    let workspaceName: String?
    let message: String?
    /// The session's most recent messages (with roles), for showing multi-turn transcripts per session.
    let messages: [CompanionMessagePreview]
    let updatedAt: Date

    var id: String {
        sessionId ?? "\(source)-\(workspaceName ?? "session")-\(updatedAt.timeIntervalSince1970)"
    }

    init(
        sessionId: String?,
        source: String,
        status: CompanionStatus,
        toolName: String?,
        workspaceName: String?,
        message: String?,
        messages: [CompanionMessagePreview] = [],
        updatedAt: Date
    ) {
        self.sessionId = sessionId
        self.source = source
        self.status = status
        self.toolName = toolName
        self.workspaceName = workspaceName
        self.message = message
        self.messages = messages
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId, source, status, toolName, workspaceName, message, messages, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        source = try c.decode(String.self, forKey: .source)
        status = try c.decode(CompanionStatus.self, forKey: .status)
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        workspaceName = try c.decodeIfPresent(String.self, forKey: .workspaceName)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        messages = try c.decodeIfPresent([CompanionMessagePreview].self, forKey: .messages) ?? []
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

enum CompanionSessionOrdering {
    static func ordered(_ sessions: [CompanionSessionPreview]) -> [CompanionSessionPreview] {
        sessions.sorted { lhs, rhs in
            if lhs.status.priority != rhs.status.priority {
                return lhs.status.priority > rhs.status.priority
            }

            let leftKey = stableKey(for: lhs)
            let rightKey = stableKey(for: rhs)
            if leftKey != rightKey {
                return leftKey < rightKey
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private static func stableKey(for session: CompanionSessionPreview) -> String {
        [
            session.sessionId,
            session.source,
            session.workspaceName,
            session.toolName,
            session.message,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
        .joined(separator: "|")
    }
}

struct CompanionDownloadStatus: Codable, Hashable {
    let name: String
    let bytesReceived: Int64
    let totalBytes: Int64?

    var progress: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(max(Double(bytesReceived) / Double(totalBytes), 0), 1)
    }
}

struct CompanionDeviceBatteryStatus: Codable, Identifiable, Hashable {
    let name: String
    let percent: Int
    let detail: String?

    var id: String { name.lowercased() }
}

struct CompanionPersonalStatus: Codable, Hashable {
    let download: CompanionDownloadStatus?
    let recentDownloadCompleted: String?
    let devices: [CompanionDeviceBatteryStatus]

    var isEmpty: Bool {
        download == nil && recentDownloadCompleted == nil && devices.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case download, recentDownloadCompleted, devices
    }

    init(
        download: CompanionDownloadStatus? = nil,
        recentDownloadCompleted: String? = nil,
        devices: [CompanionDeviceBatteryStatus] = []
    ) {
        self.download = download
        self.recentDownloadCompleted = recentDownloadCompleted
        self.devices = devices
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        download = try? c.decodeIfPresent(CompanionDownloadStatus.self, forKey: .download)
        recentDownloadCompleted = try? c.decodeIfPresent(String.self, forKey: .recentDownloadCompleted)
        devices = (try? c.decodeIfPresent([CompanionDeviceBatteryStatus].self, forKey: .devices)) ?? []
    }
}

struct CompanionStatePayload: Codable {
    let version: Int
    let sequence: UInt64
    let sessionId: String?
    let source: String
    let status: CompanionStatus
    let toolName: String?
    let workspaceName: String?
    let messages: [CompanionMessagePreview]
    let pendingAction: CompanionPendingAction?
    let question: CompanionQuestionPayload?
    let sessions: [CompanionSessionPreview]
    let personalStatus: CompanionPersonalStatus?
    let updatedAt: Date

    init(
        version: Int,
        sequence: UInt64,
        sessionId: String?,
        source: String,
        status: CompanionStatus,
        toolName: String?,
        workspaceName: String?,
        messages: [CompanionMessagePreview],
        pendingAction: CompanionPendingAction?,
        question: CompanionQuestionPayload?,
        sessions: [CompanionSessionPreview] = [],
        personalStatus: CompanionPersonalStatus? = nil,
        updatedAt: Date
    ) {
        self.version = version
        self.sequence = sequence
        self.sessionId = sessionId
        self.source = source
        self.status = status
        self.toolName = toolName
        self.workspaceName = workspaceName
        self.messages = messages
        self.pendingAction = pendingAction
        self.question = question
        self.sessions = sessions
        self.personalStatus = personalStatus
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case sequence
        case sessionId
        case source
        case status
        case toolName
        case workspaceName
        case messages
        case pendingAction
        case question
        case sessions
        case personalStatus
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        source = try container.decode(String.self, forKey: .source)
        status = try container.decode(CompanionStatus.self, forKey: .status)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        workspaceName = try container.decodeIfPresent(String.self, forKey: .workspaceName)
        messages = (try? container.decodeIfPresent([CompanionMessagePreview].self, forKey: .messages)) ?? []
        // Unknown pending actions / malformed question payloads from a different app
        // version degrade to nil instead of failing the whole state decode (#246).
        pendingAction = (try? container.decodeIfPresent(CompanionPendingAction.self, forKey: .pendingAction)) ?? nil
        question = (try? container.decodeIfPresent(CompanionQuestionPayload.self, forKey: .question)) ?? nil
        sessions = (try? container.decodeIfPresent([CompanionSessionPreview].self, forKey: .sessions)) ?? []
        personalStatus = (try? container.decodeIfPresent(CompanionPersonalStatus.self, forKey: .personalStatus)) ?? nil
        updatedAt = (try? container.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? Date()
    }
}

enum CompanionCommandType: String, Codable {
    case requestCurrentState
    case approveCurrentPermission
    case denyCurrentPermission
    case skipCurrentQuestion
    case answerQuestion
    case focus
}

struct CompanionCommandPayload: Codable {
    let version: Int
    let type: CompanionCommandType
    let sessionId: String?
    let source: String?
    let answer: String?

    init(version: Int = 1, type: CompanionCommandType, sessionId: String? = nil, source: String? = nil, answer: String? = nil) {
        self.version = version
        self.type = type
        self.sessionId = sessionId
        self.source = source
        self.answer = answer
    }
}
