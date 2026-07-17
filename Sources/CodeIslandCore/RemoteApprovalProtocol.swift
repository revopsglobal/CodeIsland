import Foundation

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

    public init(
        id: String,
        sessionId: String,
        source: String,
        tool: String,
        detail: String?,
        workspace: String?,
        createdAt: Date,
        actionToken: String,
        actionExpiresAt: Date
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
    }
}

public struct RemoteApprovalSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let serverName: String
    public let generatedAt: Date
    public let approvals: [RemoteApprovalItem]
    public let questions: [RemoteQuestionItem]

    public init(
        version: Int = 1,
        serverName: String,
        generatedAt: Date = Date(),
        approvals: [RemoteApprovalItem],
        questions: [RemoteQuestionItem] = []
    ) {
        self.version = version
        self.serverName = serverName
        self.generatedAt = generatedAt
        self.approvals = approvals
        self.questions = questions
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case serverName
        case generatedAt
        case approvals
        case questions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        serverName = try container.decode(String.self, forKey: .serverName)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
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
    public let deviceId: String
    public let deviceToken: String
    public let serverName: String

    public init(deviceId: String, deviceToken: String, serverName: String) {
        self.deviceId = deviceId
        self.deviceToken = deviceToken
        self.serverName = serverName
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

public struct RemotePushRegistrationRequest: Codable, Equatable, Sendable {
    public let token: String
    public let environment: String

    public init(token: String, environment: String) {
        self.token = token
        self.environment = environment
    }
}

public struct RemoteServiceStatus: Codable, Equatable, Sendable {
    public let running: Bool
    public let pendingCount: Int
    public let serverName: String
    public let version: Int

    public init(running: Bool, pendingCount: Int, serverName: String, version: Int = 1) {
        self.running = running
        self.pendingCount = pendingCount
        self.serverName = serverName
        self.version = version
    }
}
