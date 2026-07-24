import Foundation

enum AgentOpsRoutingMode: String, Codable, Sendable {
    case auto
    case prefer
    case locked
}

enum AgentOpsWorkerRuntime: String, Codable, Sendable {
    case codex
    case claude
    case ringer
    case orgo
    case mac
}

enum AgentOpsApprovalStatus: String, Codable, Sendable {
    case pending
    case approved
    case rejected
}

enum AgentOpsApprovalInteraction: String, Codable, Sendable {
    case onScreenTap = "on_screen_tap"
}

struct AgentOpsSourceHandle: Codable, Equatable, Sendable {
    let kind: String
    let label: String
    let url: URL
}

struct AgentOpsWorkLifecycle: Codable, Equatable, Sendable {
    let status: String
    let updatedAt: Date
    let completedAt: Date?
}

struct AgentOpsRouting: Codable, Equatable, Sendable {
    let mode: AgentOpsRoutingMode
    let implementer: AgentOpsWorkerRuntime?
    let reviewer: String?
    let allowFallback: Bool
    let fallbackRuntime: AgentOpsWorkerRuntime?
}

struct AgentOpsBlocker: Codable, Equatable, Sendable {
    let blockedBy: [String]
    let needsPersonQuestion: String?
    let needsPersonContext: String?
}

struct AgentOpsProof: Codable, Equatable, Sendable {
    let state: String
    let handles: [AgentOpsSourceHandle]
}

struct AgentOpsWorkSource: Codable, Equatable, Sendable {
    let system: String?
    let key: String?
    let url: URL?
    let threadRef: [String: AgentOpsJSONValue]?
}

struct AgentOpsWorkSummary: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let lifecycle: AgentOpsWorkLifecycle
    let routing: AgentOpsRouting
    let blocker: AgentOpsBlocker?
    let proof: AgentOpsProof
    let source: AgentOpsWorkSource
}

struct AgentOpsWorkListResponse: Codable, Equatable, Sendable {
    let tasks: [AgentOpsWorkSummary]
    let nextCursor: String?
}

struct AgentOpsApprovalCard: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let taskId: UUID
    let type: String
    let status: AgentOpsApprovalStatus
    let target: String
    let consequence: String
    let expiresAt: Date
    let actionDigest: String
    let requiresExplicitTap: Bool
}

struct AgentOpsApprovalListResponse: Codable, Equatable, Sendable {
    let approvals: [AgentOpsApprovalCard]
    let nextCursor: String?
}

struct AgentOpsApprovalResolutionRequest: Codable, Equatable, Sendable {
    let actionDigest: String
    let resolution: AgentOpsApprovalStatus
    let interaction: AgentOpsApprovalInteraction
    let decisionNote: String?
}

struct AgentOpsApprovalResolutionResponse: Codable, Equatable, Sendable {
    let approvalId: UUID
    let status: AgentOpsApprovalStatus
    let resolved: Bool
}

struct AgentOpsEvent: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let taskId: UUID
    let eventType: String
    let version: Int
    let createdAt: Date
    let payload: [String: AgentOpsJSONValue]
}

enum AgentOpsJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AgentOpsJSONValue])
    case array([AgentOpsJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: AgentOpsJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([AgentOpsJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct AgentOpsAPIError: Codable, Error, Equatable, Sendable {
    let error: String
    let retryable: Bool?
}

extension AgentOpsWorkSummary {
    var hasVerifiedProof: Bool {
        lifecycle.status.lowercased() == "verified"
            && proof.state.lowercased() == "verified"
    }
}
