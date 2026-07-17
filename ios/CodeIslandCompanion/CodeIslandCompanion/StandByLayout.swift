import CoreGraphics

/// Estimated height of one session row: identity row + up to 3 message lines + work-indicator row + padding.
/// Used to decide how many sessions fit fully in the board's available height.
let standbySessionRowStride: CGFloat = 100

/// Reserved height for the board's title area + top padding.
let standbySessionBoardHeaderHeight: CGFloat = 44

/// Fixed max number of message lines shown per session (up to 3 lines on iPad).
let standbyMaxMessageLines = 3

/// Board layout: how many sessions can be shown in full, and the line limit per message.
struct StandBySessionBoardLayout: Equatable {
    let visibleCount: Int
    let messageLineLimit: Int
}

/// Based on the board's available height and total session count, decide how many sessions to show; messages are capped at 3 lines.
/// Sessions that don't fit are shown by the caller as "N more" (or scrolled in grouped mode).
func standbySessionBoardLayout(boardHeight: CGFloat, sessionCount: Int) -> StandBySessionBoardLayout {
    let usable = max(0, boardHeight - standbySessionBoardHeaderHeight)
    let maxRows = max(1, Int(usable / standbySessionRowStride))
    let visible = max(1, min(sessionCount, maxRows))
    return StandBySessionBoardLayout(visibleCount: visible, messageLineLimit: standbyMaxMessageLines)
}
