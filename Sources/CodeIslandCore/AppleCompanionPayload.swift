import Foundation

public enum AppleCompanionStatus: String, Codable, Equatable, Sendable {
    case idle
    case processing
    case running
    case waitingApproval
    case waitingQuestion

    public init(_ status: AgentStatus) {
        switch status {
        case .idle: self = .idle
        case .processing: self = .processing
        case .running: self = .running
        case .waitingApproval: self = .waitingApproval
        case .waitingQuestion: self = .waitingQuestion
        }
    }
}

public enum AppleCompanionPendingAction: String, Codable, Equatable, Sendable {
    case approval
    case question
}

public enum AppleCompanionMessageRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
}

public struct AppleCompanionMessagePreview: Codable, Equatable, Sendable {
    public let role: AppleCompanionMessageRole
    public let text: String

    public init(role: AppleCompanionMessageRole, text: String) {
        self.role = role
        self.text = text
    }
}

public struct AppleCompanionQuestionPayload: Codable, Equatable, Sendable {
    public let header: String?
    public let question: String
    public let options: [String]
    public let descriptions: [String]
    public let index: Int
    public let total: Int
    public let allowsMultipleSelection: Bool

    public init(
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
}

public struct AppleCompanionSessionPreview: Codable, Equatable, Sendable {
    public let sessionId: String?
    public let source: String
    public let status: AppleCompanionStatus
    public let toolName: String?
    public let workspaceName: String?
    public let message: String?
    /// 该会话最近若干条消息（含角色），用于在伴侣端逐会话显示多轮转写。
    /// 向后兼容：旧客户端无此字段时按空数组处理。
    public let messages: [AppleCompanionMessagePreview]
    public let updatedAt: Date

    public init(
        sessionId: String?,
        source: String,
        status: AppleCompanionStatus,
        toolName: String?,
        workspaceName: String?,
        message: String?,
        messages: [AppleCompanionMessagePreview] = [],
        updatedAt: Date = Date()
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        source = try c.decode(String.self, forKey: .source)
        status = try c.decode(AppleCompanionStatus.self, forKey: .status)
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        workspaceName = try c.decodeIfPresent(String.self, forKey: .workspaceName)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        messages = try c.decodeIfPresent([AppleCompanionMessagePreview].self, forKey: .messages) ?? []
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

/// Small, privacy-safe personal signals sent to Greg's iPhone companion.
///
/// The Mac deliberately sends only display names and progress/battery values—
/// never a local filesystem path. Every field is optional at the top-level so
/// shipped companion builds can continue decoding the established agent state.
public struct AppleCompanionDownloadStatus: Codable, Equatable, Sendable {
    public let name: String
    public let bytesReceived: Int64
    public let totalBytes: Int64?

    public init(name: String, bytesReceived: Int64, totalBytes: Int64?) {
        self.name = name
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
    }
}

public struct AppleCompanionDeviceBatteryStatus: Codable, Equatable, Sendable {
    public let name: String
    public let percent: Int
    public let detail: String?

    public init(name: String, percent: Int, detail: String? = nil) {
        self.name = name
        self.percent = min(max(percent, 0), 100)
        self.detail = detail
    }
}

public struct AppleCompanionPersonalStatus: Codable, Equatable, Sendable {
    public let download: AppleCompanionDownloadStatus?
    public let recentDownloadCompleted: String?
    public let devices: [AppleCompanionDeviceBatteryStatus]

    public init(
        download: AppleCompanionDownloadStatus? = nil,
        recentDownloadCompleted: String? = nil,
        devices: [AppleCompanionDeviceBatteryStatus] = []
    ) {
        self.download = download
        self.recentDownloadCompleted = recentDownloadCompleted
        self.devices = devices
    }
}

public struct AppleCompanionStatePayload: Codable, Equatable, Sendable {
    public let version: Int
    public let sequence: UInt64
    public let sessionId: String?
    public let source: String
    public let status: AppleCompanionStatus
    public let toolName: String?
    public let workspaceName: String?
    public let messages: [AppleCompanionMessagePreview]
    public let pendingAction: AppleCompanionPendingAction?
    public let question: AppleCompanionQuestionPayload?
    public let sessions: [AppleCompanionSessionPreview]
    public let personalStatus: AppleCompanionPersonalStatus?
    public let updatedAt: Date

    public init(
        version: Int = 1,
        sequence: UInt64,
        sessionId: String?,
        source: String,
        status: AppleCompanionStatus,
        toolName: String?,
        workspaceName: String?,
        messages: [AppleCompanionMessagePreview],
        pendingAction: AppleCompanionPendingAction?,
        question: AppleCompanionQuestionPayload? = nil,
        sessions: [AppleCompanionSessionPreview] = [],
        personalStatus: AppleCompanionPersonalStatus? = nil,
        updatedAt: Date = Date()
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        source = try container.decode(String.self, forKey: .source)
        status = try container.decode(AppleCompanionStatus.self, forKey: .status)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        workspaceName = try container.decodeIfPresent(String.self, forKey: .workspaceName)
        messages = try container.decode([AppleCompanionMessagePreview].self, forKey: .messages)
        pendingAction = try container.decodeIfPresent(AppleCompanionPendingAction.self, forKey: .pendingAction)
        question = try container.decodeIfPresent(AppleCompanionQuestionPayload.self, forKey: .question)
        sessions = try container.decodeIfPresent([AppleCompanionSessionPreview].self, forKey: .sessions) ?? []
        personalStatus = try? container.decodeIfPresent(AppleCompanionPersonalStatus.self, forKey: .personalStatus)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public enum AppleCompanionCommandType: String, Codable, Equatable, Sendable {
    case requestCurrentState
    case approveCurrentPermission
    case denyCurrentPermission
    case skipCurrentQuestion
    case answerQuestion
    case focus
}

public struct AppleCompanionCommandPayload: Codable, Equatable, Sendable {
    public let version: Int
    public let type: AppleCompanionCommandType
    public let sessionId: String?
    public let source: String?
    public let answer: String?

    public init(version: Int = 1, type: AppleCompanionCommandType, sessionId: String? = nil, source: String? = nil, answer: String? = nil) {
        self.version = version
        self.type = type
        self.sessionId = sessionId
        self.source = source
        self.answer = answer
    }
}
