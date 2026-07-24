import Foundation

enum CompanionAttentionSelection {
    static func resolve(previousID: String?, currentIDs: [String]) -> String? {
        resolve(previousID: previousID, preferredID: nil, currentIDs: currentIDs)
    }

    static func resolve(previousID: String?, preferredID: String?, currentIDs: [String]) -> String? {
        if let preferredID, currentIDs.contains(preferredID) {
            return preferredID
        }
        if let previousID, currentIDs.contains(previousID) {
            return previousID
        }
        return currentIDs.first
    }
}

struct CompanionAttentionSummary: Equatable {
    let needsAttention: Bool
    let title: String
    let subtitle: String

    static func resolve(
        approvalCount: Int,
        questionCount: Int,
        fallbackPendingAction: CompanionPendingAction?,
        fallbackWeather: String?
    ) -> CompanionAttentionSummary {
        let safeApprovalCount = max(0, approvalCount)
        let safeQuestionCount = max(0, questionCount)
        let total = safeApprovalCount + safeQuestionCount

        if total > 0 {
            return CompanionAttentionSummary(
                needsAttention: true,
                title: "Needs you",
                subtitle: attentionCopy(approvals: safeApprovalCount, questions: safeQuestionCount)
            )
        }

        if let fallbackPendingAction {
            return CompanionAttentionSummary(
                needsAttention: true,
                title: "Needs you",
                subtitle: fallbackPendingAction == .approval
                    ? "An agent is waiting for approval"
                    : "An agent is waiting for an answer"
            )
        }

        return CompanionAttentionSummary(
            needsAttention: false,
            title: "Today",
            subtitle: fallbackWeather ?? "Nothing else needs your attention"
        )
    }

    private static func attentionCopy(approvals: Int, questions: Int) -> String {
        switch (approvals, questions) {
        case (1, 0): return "1 approval needs a decision"
        case let (count, 0): return "\(count) approvals need decisions"
        case (0, 1): return "1 question needs an answer"
        case let (0, count): return "\(count) questions need answers"
        case (1, 1): return "1 approval and 1 question need you"
        case let (approvals, 1): return "\(approvals) approvals and 1 question need you"
        case let (1, questions): return "1 approval and \(questions) questions need you"
        case let (approvals, questions): return "\(approvals) approvals and \(questions) questions need you"
        }
    }
}

enum CompanionAgentAttention {
    static func needsAttention(flag: Bool?, title: String, subtitle: String?, detail: String?) -> Bool {
        // Newer Mac payloads provide the authoritative state, so copy text is ignored.
        if let flag {
            return flag
        }

        // Older Mac payloads omit the flag; preserve the legacy text heuristic.
        let signal = [title, subtitle ?? "", detail ?? ""]
            .joined(separator: " ")
            .lowercased()
        return ["approval", "question", "needs", "waiting"].contains { signal.contains($0) }
    }
}

extension CompanionMotionPolicy {
    static let animatesRoutinePoll = false

    static func shouldAnimateNewAttention(
        previousIDs: [String],
        currentIDs: [String],
        reduceMotion: Bool
    ) -> Bool {
        guard !reduceMotion else { return false }
        return !Set(currentIDs).subtracting(previousIDs).isEmpty
    }
}
