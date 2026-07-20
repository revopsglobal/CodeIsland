import Foundation
import CodeIslandCore

struct SessionAttentionCandidate {
    let id: String
    let status: AgentStatus
    let lastActivity: Date
}

/// The three bands the expanded session list renders, in display order.
/// Grouping by state answers "who needs me"; grouping by vendor answered
/// "what am I running", which is not why the panel gets opened.
enum SessionAttentionBand: String, CaseIterable {
    case needsYou
    case working
    case idle

    func contains(_ status: AgentStatus) -> Bool {
        switch self {
        case .needsYou: return status == .waitingApproval || status == .waitingQuestion
        case .working: return status == .running || status == .processing
        case .idle: return status == .idle
        }
    }

    var localizedLabel: String {
        switch self {
        case .needsYou: return L10n.shared["band_needs_you"]
        case .working: return L10n.shared["band_working"]
        case .idle: return L10n.shared["band_idle"]
        }
    }
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

    /// Full roster split into the three bands the panel renders, idle included.
    /// `orderedSessionIDs` deliberately drops idle sessions because it feeds the
    /// single-session compact surfaces; the expanded list needs all of them.
    static func bandedSessionIDs(
        _ candidates: [SessionAttentionCandidate]
    ) -> [(band: SessionAttentionBand, ids: [String])] {
        SessionAttentionBand.allCases.compactMap { band in
            let ids = candidates
                .filter { band.contains($0.status) }
                .sorted(by: order)
                .map(\.id)
            return ids.isEmpty ? nil : (band, ids)
        }
    }

    private static func orderedCandidates(
        _ candidates: [SessionAttentionCandidate]
    ) -> [SessionAttentionCandidate] {
        candidates
            .filter { priority($0.status) > 0 }
            .sorted(by: order)
    }

    /// Higher priority first. Within a tier, waiting work sorts *oldest first* —
    /// the request that has been blocked longest is the one at risk of being
    /// forgotten, so it must not sink below a decision that arrived seconds ago.
    /// Routine and idle work stay most-recent-first, where freshness is the
    /// useful signal.
    private static func order(
        _ lhs: SessionAttentionCandidate,
        _ rhs: SessionAttentionCandidate
    ) -> Bool {
        let leftPriority = priority(lhs.status)
        let rightPriority = priority(rhs.status)
        if leftPriority != rightPriority { return leftPriority > rightPriority }
        if lhs.lastActivity != rhs.lastActivity {
            return leftPriority == 2
                ? lhs.lastActivity < rhs.lastActivity
                : lhs.lastActivity > rhs.lastActivity
        }
        return lhs.id < rhs.id
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
