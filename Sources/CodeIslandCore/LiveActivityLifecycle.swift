import Foundation

public struct LiveActivityLifecycleCursor: Equatable, Sendable {
    public let sequence: UInt64
    public let updatedAt: Date

    public init(sequence: UInt64, updatedAt: Date) {
        self.sequence = sequence
        self.updatedAt = updatedAt
    }
}

public enum LiveActivityLifecycleDecision: Equatable, Sendable {
    case ignore
    case create
    case update
    case end
}

public struct LiveActivityLifecycleTransition: Equatable, Sendable {
    public let decision: LiveActivityLifecycleDecision
    public let cursor: LiveActivityLifecycleCursor

    public init(decision: LiveActivityLifecycleDecision, cursor: LiveActivityLifecycleCursor) {
        self.decision = decision
        self.cursor = cursor
    }
}

/// Pure ordering policy shared by the iPhone lifecycle controller and tests.
/// Sequence orders one Mac process lifetime; timestamp safely recognizes a
/// newer process lifetime after the Mac restarts its sequence at zero.
public enum LiveActivityLifecycle {
    public static func transition(
        current: LiveActivityLifecycleCursor?,
        incoming: LiveActivityLifecycleCursor,
        hasActivity: Bool,
        hasActiveContent: Bool,
        createIfNeeded: Bool,
        allowIdleCreation: Bool = false
    ) -> LiveActivityLifecycleTransition {
        if let current {
            let sequenceReset = incoming.sequence < current.sequence
                && incoming.updatedAt > current.updatedAt.addingTimeInterval(2)
            let stale = (incoming.sequence < current.sequence && !sequenceReset)
                || (incoming.sequence == current.sequence && incoming.updatedAt <= current.updatedAt)
            if stale {
                return LiveActivityLifecycleTransition(decision: .ignore, cursor: current)
            }
        }

        let decision: LiveActivityLifecycleDecision
        if hasActivity {
            decision = hasActiveContent ? .update : .end
        } else if createIfNeeded, hasActiveContent || allowIdleCreation {
            decision = .create
        } else {
            decision = .ignore
        }
        return LiveActivityLifecycleTransition(decision: decision, cursor: incoming)
    }
}
