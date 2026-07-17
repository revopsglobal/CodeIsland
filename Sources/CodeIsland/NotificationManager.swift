import AppKit
import UserNotifications
import os.log
import CodeIslandCore

/// Posts a native macOS notification when an agent needs an approval or answer.
///
/// This is the Crest-parity "impossible to miss" signal: the notch chime + card
/// only help when you're looking at that display. A local notification reaches you
/// on another Space, over a fullscreen app, or from the Notification Center, for
/// BOTH Claude Code and Codex in one place. Clicking it opens the notch to the
/// pending card.
///
/// Gated by `SettingsKey.notifyOnApproval` (default on). Authorization is requested
/// once at launch; if the user declines, this silently no-ops.
@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private let log = Logger(subsystem: "com.codeisland", category: "NotificationManager")
    private var authorized = false
    /// Opens the notch to a session's pending card when a notification is clicked.
    var onOpenSession: ((String) -> Void)?

    private static let categoryId = "codeisland.approval"
    private static let sessionKey = "sessionId"

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // A single category so clicking the banner activates our default action.
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryId,
                actions: [],
                intentIdentifiers: [],
                options: []
            )
        ])
        center.requestAuthorization(options: [.alert, .badge]) { [weak self] granted, error in
            Task { @MainActor in
                self?.authorized = granted
                if let error {
                    self?.log.error("notification auth error: \(error.localizedDescription, privacy: .public)")
                } else {
                    self?.log.info("notification auth granted=\(granted)")
                }
            }
        }
    }

    /// Post an approval/question notification. `title` is the human tool label,
    /// `subtitle` the command/detail. Deduped per session so a re-fired hook
    /// (replay) doesn't stack duplicate banners.
    func notifyPending(sessionId: String, sourceLabel: String, tool: String?, detail: String?) {
        guard SettingsManager.shared.notifyOnApproval else { return }
        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(sourceLabel) needs your approval"
        if let tool, !tool.isEmpty {
            content.subtitle = tool
        }
        if let detail, !detail.isEmpty {
            content.body = String(detail.prefix(180))
        }
        content.categoryIdentifier = Self.categoryId
        content.userInfo = [Self.sessionKey: sessionId]
        // Interruptive so it surfaces over a fullscreen app / another Space.
        content.interruptionLevel = .timeSensitive

        // Stable identifier per session → a replayed hook updates in place
        // instead of stacking a second banner.
        let request = UNNotificationRequest(
            identifier: "approval-\(sessionId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.log.error("notify add failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Clear a session's pending notification once it's answered/gone.
    func clearPending(sessionId: String) {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["approval-\(sessionId)"])
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    // Show the banner even while CodeIsland is the active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    // Clicking the banner opens the notch to the pending card.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let sessionId = response.notification.request.content.userInfo[Self.sessionKey] as? String
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            if let sessionId { self.onOpenSession?(sessionId) }
        }
        completionHandler()
    }
}
