import Foundation

enum CompanionAttentionSelection {
    static func resolve(previousID: String?, currentIDs: [String]) -> String? {
        if let previousID, currentIDs.contains(previousID) {
            return previousID
        }
        return currentIDs.first
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
