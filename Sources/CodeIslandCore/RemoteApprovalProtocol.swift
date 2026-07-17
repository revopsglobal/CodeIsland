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

    public init(
        version: Int = 1,
        serverName: String,
        generatedAt: Date = Date(),
        approvals: [RemoteApprovalItem]
    ) {
        self.version = version
        self.serverName = serverName
        self.generatedAt = generatedAt
        self.approvals = approvals
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
