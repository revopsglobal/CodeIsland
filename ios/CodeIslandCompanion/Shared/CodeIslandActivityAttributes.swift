import ActivityKit
import Foundation

struct CodeIslandSessionActivityPreview: Codable, Hashable, Identifiable {
    var sessionId: String?
    var source: String
    var status: String
    var toolName: String?
    var workspaceName: String?
    var message: String?
    var updatedAt: Date

    var id: String {
        sessionId ?? "\(source)-\(workspaceName ?? "session")-\(updatedAt.timeIntervalSince1970)"
    }

    var statusLabel: String {
        switch status {
        case "processing": return "Processing"
        case "running": return "Running"
        case "waitingApproval": return "Waiting for approval"
        case "waitingQuestion": return "Waiting for answer"
        default: return "Idle"
        }
    }

    var sourceLabel: String {
        source.isEmpty ? "CodeIsland" : source.uppercased()
    }

    var isActionRequired: Bool {
        status == "waitingApproval" || status == "waitingQuestion"
    }

    var displayPriority: Int {
        switch status {
        case "waitingApproval": return 5
        case "waitingQuestion": return 4
        case "running": return 3
        case "processing": return 2
        default: return 0
        }
    }

    var stableSortKey: String {
        [
            sessionId,
            source,
            workspaceName,
            toolName,
            message,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
        .joined(separator: "|")
    }
}

struct CodeIslandActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var sequence: UInt64
        var source: String
        var status: String
        var toolName: String?
        var workspaceName: String?
        var message: String?
        var pendingAction: String?
        var taskID: String? = nil
        var taskState: String? = nil
        var questionText: String?
        var questionHeader: String?
        var questionProgress: String?
        var sessions: [CodeIslandSessionActivityPreview]
        var updatedAt: Date

        var statusLabel: String {
            if let taskState {
                switch taskState {
                case "waiting-for-mac": return "Waiting for Mac"
                case "queued": return "Queued"
                case "working": return "Working"
                case "needs-you": return "Needs You"
                case "verified": return "Verified"
                case "failed": return "Failed"
                case "cancelled": return "Cancelled"
                default: break
                }
            }
            switch status {
            case "processing": return "Processing"
            case "running": return "Running"
            case "waitingApproval": return "Waiting for approval"
            case "waitingQuestion": return "Waiting for answer"
            default: return "Idle"
            }
        }

        var sourceLabel: String {
            source.isEmpty ? "CodeIsland" : source.uppercased()
        }

        var compactStatusLabel: String {
            if let taskState {
                switch taskState {
                case "waiting-for-mac": return "Mac offline"
                case "queued": return "Queued"
                case "working": return "Working"
                case "needs-you": return "Needs You"
                case "verified": return "Verified"
                case "failed": return "Failed"
                case "cancelled": return "Cancelled"
                default: break
                }
            }
            switch status {
            case "waitingApproval": return "Approve?"
            case "waitingQuestion": return "Answer?"
            case "processing": return "Processing"
            case "running": return "Running"
            default: return "Idle"
            }
        }

        var activeSessionCount: Int {
            sessions.filter { $0.status != "idle" }.count
        }

        var actionRequiredSessionCount: Int {
            orderedSessions.filter(\.isActionRequired).count
        }

        var orderedSessions: [CodeIslandSessionActivityPreview] {
            Self.orderedSessions(sessions)
        }

        var isTaskActivity: Bool { taskID != nil }

        static func orderedSessions(_ sessions: [CodeIslandSessionActivityPreview]) -> [CodeIslandSessionActivityPreview] {
            sessions.sorted { lhs, rhs in
                if lhs.displayPriority != rhs.displayPriority {
                    return lhs.displayPriority > rhs.displayPriority
                }
                if lhs.stableSortKey != rhs.stableSortKey {
                    return lhs.stableSortKey < rhs.stableSortKey
                }
                return lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    var sessionId: String?
    /// Exact `RemoteApprovalDevice.id` that owns this activity. Optional so an
    /// already-running activity created by an older Buddy build still decodes.
    var pairingDeviceID: String? = nil
}

enum CodeIslandActivityAttentionLink {
    static let pairingDeviceIDQueryName = "pairingDeviceID"

    static func url(
        host: String,
        path: String,
        pairingDeviceID: String?
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "codeisland"
        components.host = host
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        if let pairingDeviceID = normalized(pairingDeviceID) {
            components.queryItems = [
                URLQueryItem(name: pairingDeviceIDQueryName, value: pairingDeviceID),
            ]
        }
        return components.url
    }

    static func url(
        attributes: CodeIslandActivityAttributes,
        state: CodeIslandActivityAttributes.ContentState
    ) -> URL? {
        if let taskID = state.taskID, UUID(uuidString: taskID) != nil {
            return url(
                host: "tasks",
                path: taskID,
                pairingDeviceID: attributes.pairingDeviceID
            )
        }
        guard state.pendingAction == "approval" || state.pendingAction == "question" else {
            return nil
        }
        return url(
            host: state.pendingAction == "question" ? "questions" : "approvals",
            path: attributes.sessionId ?? state.sessions.first?.sessionId ?? "pending",
            pairingDeviceID: attributes.pairingDeviceID
        )
    }

    static func pairingDeviceID(from url: URL) -> String? {
        normalized(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == pairingDeviceIDQueryName })?
            .value)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }
}
