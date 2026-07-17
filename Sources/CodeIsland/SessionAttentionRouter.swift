import Foundation
import CodeIslandCore

struct SessionAttentionCandidate {
    let id: String
    let status: AgentStatus
    let lastActivity: Date
}

/// Selects one stable, high-signal session for compact Mac and Buddy surfaces.
/// Interactive requests preempt background work; equal-priority work never
/// advances on a timer, so Auto behaves like an attention router rather than a
/// carousel.
enum SessionAttentionRouter {
    static func preferredSessionID(
        candidates: [SessionAttentionCandidate],
        currentSessionID: String?,
        selectedSessionID: String?
    ) -> String? {
        let ordered = orderedCandidates(candidates)
        guard let best = ordered.first else { return nil }

        if let current = ordered.first(where: { $0.id == currentSessionID }) {
            return priority(best.status) > priority(current.status) ? best.id : current.id
        }

        if let selected = ordered.first(where: { $0.id == selectedSessionID }) {
            return priority(best.status) > priority(selected.status) ? best.id : selected.id
        }

        return best.id
    }

    static func orderedSessionIDs(_ candidates: [SessionAttentionCandidate]) -> [String] {
        orderedCandidates(candidates).map(\.id)
    }

    private static func orderedCandidates(
        _ candidates: [SessionAttentionCandidate]
    ) -> [SessionAttentionCandidate] {
        candidates
            .filter { priority($0.status) > 0 }
            .sorted { lhs, rhs in
                let leftPriority = priority(lhs.status)
                let rightPriority = priority(rhs.status)
                if leftPriority != rightPriority { return leftPriority > rightPriority }
                if lhs.lastActivity != rhs.lastActivity { return lhs.lastActivity > rhs.lastActivity }
                return lhs.id < rhs.id
            }
    }

    /// Approvals and questions are both explicit decisions; background running
    /// and processing states share one lower tier so they cannot preempt each
    /// other merely because another heartbeat arrived.
    private static func priority(_ status: AgentStatus) -> Int {
        switch status {
        case .waitingApproval, .waitingQuestion: return 2
        case .running, .processing: return 1
        case .idle: return 0
        }
    }
}
