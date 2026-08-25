import Foundation

public enum RemoteAttentionKind: String, Codable, Equatable, Sendable {
    case approval
    case question
    case task
}

public enum RemoteAttentionState: String, Codable, Equatable, Sendable {
    case pending
    case resolved
    case expired
}

/// Privacy-preserving notification metadata. The push never includes a prompt,
/// command, workspace, agent transcript, or action token. Buddy must perform an
/// authenticated refresh before it can render or act on the request.
public struct RemoteAttentionPushEnvelope: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let eventID: String
    public let kind: RemoteAttentionKind
    public let state: RemoteAttentionState
    public let requestID: String
    public let taskState: RemoteTaskState?
    /// The exact paired-device record this APNs payload was routed to. Older
    /// Buddy/Mac builds omit it, so it remains optional on the wire.
    public let pairingDeviceID: String?
    public let issuedAt: Date
    public let expiresAt: Date

    public init(
        version: Int = Self.currentVersion,
        eventID: String = UUID().uuidString.lowercased(),
        kind: RemoteAttentionKind,
        state: RemoteAttentionState,
        requestID: String,
        taskState: RemoteTaskState? = nil,
        pairingDeviceID: String? = nil,
        issuedAt: Date = Date(),
        expiresAt: Date
    ) {
        self.version = version
        self.eventID = eventID
        self.kind = kind
        self.state = state
        self.requestID = requestID
        self.taskState = taskState
        self.pairingDeviceID = pairingDeviceID
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    public var payloadFields: [String: Any] {
        var fields: [String: Any] = [
            "ciVersion": version,
            "ciEventId": eventID,
            "ciAttentionKind": kind.rawValue,
            "ciAttentionState": state.rawValue,
            "ciRequestId": requestID,
            "ciIssuedAt": issuedAt.timeIntervalSince1970,
            "ciExpiresAt": expiresAt.timeIntervalSince1970,
        ]
        if let taskState { fields["ciTaskState"] = taskState.rawValue }
        if let pairingDeviceID { fields["ciPairingDeviceId"] = pairingDeviceID }
        return fields
    }

    public init?(payloadFields: [String: Any]) {
        guard let versionValue = Self.number(payloadFields["ciVersion"]),
              let version = Int(exactly: versionValue),
              version == Self.currentVersion,
              let eventID = payloadFields["ciEventId"] as? String,
              !eventID.isEmpty,
              let kindValue = payloadFields["ciAttentionKind"] as? String,
              let kind = RemoteAttentionKind(rawValue: kindValue),
              let stateValue = payloadFields["ciAttentionState"] as? String,
              let state = RemoteAttentionState(rawValue: stateValue),
              let requestID = payloadFields["ciRequestId"] as? String,
              !requestID.isEmpty,
              let issuedAtValue = Self.number(payloadFields["ciIssuedAt"]),
              let expiresAtValue = Self.number(payloadFields["ciExpiresAt"])
        else { return nil }

        let taskState = (payloadFields["ciTaskState"] as? String).flatMap(RemoteTaskState.init(rawValue:))
        let pairingDeviceID = (payloadFields["ciPairingDeviceId"] as? String)?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard (kind == .task && UUID(uuidString: requestID) != nil && taskState != nil)
                || (kind != .task && taskState == nil)
        else { return nil }

        self.init(
            version: version,
            eventID: eventID,
            kind: kind,
            state: state,
            requestID: requestID,
            taskState: taskState,
            pairingDeviceID: pairingDeviceID?.isEmpty == false ? pairingDeviceID : nil,
            issuedAt: Date(timeIntervalSince1970: issuedAtValue),
            expiresAt: Date(timeIntervalSince1970: expiresAtValue)
        )
    }

    /// A transition is accepted only once per request and only inside its
    /// validity window. A resolved event arriving before an older pending push
    /// therefore prevents that old push from reopening the request.
    public func isFresh(lastIssuedAt: Date?, now: Date = Date()) -> Bool {
        guard issuedAt <= now.addingTimeInterval(60),
              expiresAt > now,
              issuedAt > (lastIssuedAt ?? .distantPast)
        else { return false }
        return true
    }

    public var requestKey: String {
        "\(kind.rawValue):\(requestID)"
    }

    private static func number(_ value: Any?) -> TimeInterval? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }
}

/// The high-signal task notification contract. Routine progress remains quiet;
/// only an actionable or failed task interrupts, while completion is sent only
/// for the one task the user explicitly follows.
public enum RemoteTaskAttentionPolicy {
    public static func shouldNotifyImmediately(
        state: RemoteTaskState,
        isFollowed: Bool
    ) -> Bool {
        switch state {
        case .needsYou, .failed:
            return true
        case .verified, .waitingForMac:
            return isFollowed
        case .queued, .working, .cancelled:
            return false
        }
    }

    public static func accepts(
        previousState: RemoteTaskState?,
        incomingState: RemoteTaskState
    ) -> Bool {
        guard let previousState else { return true }
        if previousState.isTerminal {
            return incomingState == previousState
        }
        return true
    }
}

public enum RemoteApprovalDecision: String, Codable, Equatable, Sendable {
    case approve
    case deny
}

public struct RemoteApprovalItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionId: String
    public let source: String
    public let tool: String
    public let detail: String?
    public let workspace: String?
    public let createdAt: Date
    public let actionToken: String
    public let actionExpiresAt: Date
    /// How much damage approving this would do. Optional so a payload from an
    /// older Mac still decodes on a newer phone and vice versa; `nil` means
    /// "unclassified", which the UI treats as no emphasis rather than as safe.
    public let risk: CommandRisk?

    public init(
        id: String,
        sessionId: String,
        source: String,
        tool: String,
        detail: String?,
        workspace: String?,
        createdAt: Date,
        actionToken: String,
        actionExpiresAt: Date,
        risk: CommandRisk? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.source = source
        self.tool = tool
        self.detail = detail
        self.workspace = workspace
        self.createdAt = createdAt
        self.actionToken = actionToken
        self.actionExpiresAt = actionExpiresAt
        self.risk = risk
    }
}

public struct RemoteApprovalSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let serverName: String
    public let generatedAt: Date
    public let companionSequence: UInt64?
    public let deviceId: String?
    public let approvals: [RemoteApprovalItem]
    public let questions: [RemoteQuestionItem]

    public init(
        version: Int = 1,
        serverName: String,
        generatedAt: Date = Date(),
        companionSequence: UInt64? = nil,
        deviceId: String? = nil,
        approvals: [RemoteApprovalItem],
        questions: [RemoteQuestionItem] = []
    ) {
        self.version = version
        self.serverName = serverName
        self.generatedAt = generatedAt
        self.companionSequence = companionSequence
        self.deviceId = deviceId
        self.approvals = approvals
        self.questions = questions
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case serverName
        case generatedAt
        case companionSequence
        case deviceId
        case approvals
        case questions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        serverName = try container.decode(String.self, forKey: .serverName)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        companionSequence = try container.decodeIfPresent(UInt64.self, forKey: .companionSequence)
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId)
        approvals = try container.decode([RemoteApprovalItem].self, forKey: .approvals)
        questions = try container.decodeIfPresent([RemoteQuestionItem].self, forKey: .questions) ?? []
    }
}

public struct RemoteQuestionPrompt: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let header: String?
    public let question: String
    public let options: [String]
    public let descriptions: [String]
    public let allowsMultipleSelection: Bool

    public init(
        id: String,
        header: String?,
        question: String,
        options: [String],
        descriptions: [String],
        allowsMultipleSelection: Bool
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.options = options
        self.descriptions = descriptions
        self.allowsMultipleSelection = allowsMultipleSelection
    }
}

public struct RemoteQuestionItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionId: String
    public let source: String
    public let workspace: String?
    public let createdAt: Date
    public let prompts: [RemoteQuestionPrompt]
    public let requiresLocalResponse: Bool
    public let actionToken: String?
    public let actionExpiresAt: Date?

    public init(
        id: String,
        sessionId: String,
        source: String,
        workspace: String?,
        createdAt: Date,
        prompts: [RemoteQuestionPrompt],
        requiresLocalResponse: Bool,
        actionToken: String?,
        actionExpiresAt: Date?
    ) {
        self.id = id
        self.sessionId = sessionId
        self.source = source
        self.workspace = workspace
        self.createdAt = createdAt
        self.prompts = prompts
        self.requiresLocalResponse = requiresLocalResponse
        self.actionToken = actionToken
        self.actionExpiresAt = actionExpiresAt
    }
}

public struct RemoteQuestionAnswerRequest: Codable, Equatable, Sendable {
    public let answers: [String]
    public let actionToken: String

    public init(answers: [String], actionToken: String) {
        self.answers = answers
        self.actionToken = actionToken
    }
}

public struct RemoteQuestionAnswerResponse: Codable, Equatable, Sendable {
    public let answered: Bool
    public let requestId: String

    public init(answered: Bool, requestId: String) {
        self.answered = answered
        self.requestId = requestId
    }
}

public struct RemotePairRequest: Codable, Equatable, Sendable {
    public let code: String
    public let deviceName: String

    public init(code: String, deviceName: String) {
        self.code = code
        self.deviceName = deviceName
    }
}

public struct RemotePairResponse: Codable, Equatable, Sendable {
    /// Empty only when decoding a response from a pre-device-ID Mac. Buddy
    /// normalizes that legacy sentinel to an unresolved pairing identity and
    /// backfills it from the first authenticated vNext response.
    public let deviceId: String
    public let deviceToken: String
    public let serverName: String

    public init(deviceId: String, deviceToken: String, serverName: String) {
        self.deviceId = deviceId
        self.deviceToken = deviceToken
        self.serverName = serverName
    }

    private enum CodingKeys: String, CodingKey {
        case deviceId
        case deviceToken
        case serverName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
        deviceToken = try container.decode(String.self, forKey: .deviceToken)
        serverName = try container.decode(String.self, forKey: .serverName)
    }
}

public struct RemoteDecisionRequest: Codable, Equatable, Sendable {
    public let decision: RemoteApprovalDecision
    public let actionToken: String

    public init(decision: RemoteApprovalDecision, actionToken: String) {
        self.decision = decision
        self.actionToken = actionToken
    }
}

public struct RemoteDecisionResponse: Codable, Equatable, Sendable {
    public let resolved: Bool
    public let requestId: String
    public let decision: RemoteApprovalDecision

    public init(resolved: Bool, requestId: String, decision: RemoteApprovalDecision) {
        self.resolved = resolved
        self.requestId = requestId
        self.decision = decision
    }
}

/// An authenticated, privacy-preserving observation of the iPhone's remote
/// attention lifecycle. Receipts deliberately contain no prompt, workspace,
/// command, transcript, action token, or APNs token.
public struct RemoteLiveActivityReceipt: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Equatable, Sendable {
        case notification
        case activityStarted
        case activityStateChanged
        case snapshot
    }

    public enum ActivityState: String, Codable, Equatable, Sendable {
        case pending
        case active
        case stale
        case ended
        case dismissed
    }

    public let eventId: String
    public let source: Source
    public let requestId: String?
    public let kind: RemoteAttentionKind?
    public let state: RemoteAttentionState?
    public let activityState: ActivityState?
    public let observedAt: Date
    public let activitiesEnabled: Bool
    public let activeActivityCount: Int
    public let activeRequestIds: [String]

    public init(
        eventId: String = UUID().uuidString.lowercased(),
        source: Source,
        requestId: String? = nil,
        kind: RemoteAttentionKind? = nil,
        state: RemoteAttentionState? = nil,
        activityState: ActivityState? = nil,
        observedAt: Date = Date(),
        activitiesEnabled: Bool,
        activeActivityCount: Int,
        activeRequestIds: [String]
    ) {
        self.eventId = eventId
        self.source = source
        self.requestId = requestId
        self.kind = kind
        self.state = state
        self.activityState = activityState
        self.observedAt = observedAt
        self.activitiesEnabled = activitiesEnabled
        self.activeActivityCount = activeActivityCount
        self.activeRequestIds = activeRequestIds
    }

    public var isStructurallyValid: Bool {
        guard !eventId.isEmpty, eventId.count <= 100,
              requestId.map({ !$0.isEmpty && $0.count <= 200 }) ?? true,
              activeActivityCount >= 0, activeActivityCount <= 32,
              activeRequestIds.count <= 32,
              activeRequestIds.allSatisfy({ !$0.isEmpty && $0.count <= 200 }),
              Set(activeRequestIds).count == activeRequestIds.count,
              activeActivityCount >= activeRequestIds.count
        else { return false }

        switch source {
        case .notification:
            return requestId != nil && kind != nil && state != nil
        case .activityStarted:
            return requestId != nil && kind != nil && state == .pending && activityState == .active
        case .activityStateChanged:
            return requestId != nil && activityState != nil
        case .snapshot:
            return true
        }
    }
}

public struct RemotePushRegistrationRequest: Codable, Equatable, Sendable {
    public let token: String?
    public let environment: String
    public let liveActivityPushToStartToken: String?
    public let liveActivityUpdateTokens: [String: String]?
    public let liveActivityReceipts: [RemoteLiveActivityReceipt]?
    public let clientVersion: String?
    public let clientBuild: String?

    public init(
        token: String? = nil,
        environment: String,
        liveActivityPushToStartToken: String? = nil,
        liveActivityUpdateTokens: [String: String]? = nil,
        liveActivityReceipts: [RemoteLiveActivityReceipt]? = nil,
        clientVersion: String? = nil,
        clientBuild: String? = nil
    ) {
        self.token = token
        self.environment = environment
        self.liveActivityPushToStartToken = liveActivityPushToStartToken
        self.liveActivityUpdateTokens = liveActivityUpdateTokens
        self.liveActivityReceipts = liveActivityReceipts
        self.clientVersion = clientVersion
        self.clientBuild = clientBuild
    }
}

public struct RemotePushRegistrationResponse: Codable, Equatable, Sendable {
    public let registered: Bool
    public let deviceId: String?

    public init(registered: Bool, deviceId: String? = nil) {
        self.registered = registered
        self.deviceId = deviceId
    }
}

public struct RemoteServiceStatus: Codable, Equatable, Sendable {
    public let running: Bool
    public let pendingCount: Int
    public let serverName: String
    public let hostVersion: String?
    public let launchAtLoginStatus: String?
    public let launchAtLoginError: String?
    public let calendarAuthorizationStatus: String?
    public let remindersAuthorizationStatus: String?
    public let locationAuthorizationStatus: String?
    public let manualWeatherLocationConfigured: Bool?
    public let reminderListSelectionConfigured: Bool?
    public let version: Int

    public init(
        running: Bool,
        pendingCount: Int,
        serverName: String,
        hostVersion: String? = nil,
        launchAtLoginStatus: String? = nil,
        launchAtLoginError: String? = nil,
        calendarAuthorizationStatus: String? = nil,
        remindersAuthorizationStatus: String? = nil,
        locationAuthorizationStatus: String? = nil,
        manualWeatherLocationConfigured: Bool? = nil,
        reminderListSelectionConfigured: Bool? = nil,
        version: Int = 1
    ) {
        self.running = running
        self.pendingCount = pendingCount
        self.serverName = serverName
        self.hostVersion = hostVersion
        self.launchAtLoginStatus = launchAtLoginStatus
        self.launchAtLoginError = launchAtLoginError
        self.calendarAuthorizationStatus = calendarAuthorizationStatus
        self.remindersAuthorizationStatus = remindersAuthorizationStatus
        self.locationAuthorizationStatus = locationAuthorizationStatus
        self.manualWeatherLocationConfigured = manualWeatherLocationConfigured
        self.reminderListSelectionConfigured = reminderListSelectionConfigured
        self.version = version
    }
}
